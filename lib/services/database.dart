import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../core/models.dart';
import 'db/analyses_repository.dart';
import 'db/errors.dart';
import 'db/references_repository.dart';
import 'db/schema.dart';
import 'db/security_repository.dart';

export 'db/analyses_repository.dart' show AnalysesRepository, DbStats;
export 'db/errors.dart' show DbRuleException, DbTooNewException;
export 'db/references_repository.dart';
export 'db/schema.dart' show kSchemaVersion;
export 'db/security_repository.dart' show SecurityRepository;

/// Initialise SQLite pour Windows, macOS et Linux (FFI).
Future<void> initSqlite() async {
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }
}

/// Base locale SQLite : historique des analyses et référentiels d'originaux.
///
/// - Schéma versionné (`PRAGMA user_version`, voir db/schema.dart).
/// - Avant toute mise à niveau, copie de sauvegarde du fichier (la base ne
///   contient ni document ni image de document).
/// - Une base créée par une version plus récente est refusée sans être
///   modifiée.
/// - Clés étrangères actives à chaque ouverture.
class AuthentikDb {
  /// [factory] : fabrique SQLite (tests) ; par défaut celle de sqflite.
  AuthentikDb({DatabaseFactory? factory, DateTime Function()? clock})
    // Un paramètre nommé ne peut pas être privé.
    // ignore: prefer_initializing_formals
    : _factory = factory,
      _clock = clock ?? DateTime.now;

  final DatabaseFactory? _factory;
  final DateTime Function() _clock;

  Database? _db;
  String? _path;
  AnalysesRepository? _analyses;
  ReferencesRepository? _references;
  SecurityRepository? _security;

  /// Copie de sauvegarde faite lors de la dernière ouverture (null si aucune
  /// mise à niveau n'a eu lieu).
  String? lastBackupPath;

  /// Version du schéma trouvée à l'ouverture (0 : base neuve).
  int openedFromVersion = 0;

  bool get connected => _db != null;

  String? get path => _path;

  Database get _c {
    final db = _db;
    if (db == null) throw StateError('Base de données non ouverte');
    return db;
  }

  AnalysesRepository get analyses =>
      _analyses ?? (throw StateError('Base de données non ouverte'));
  ReferencesRepository get references =>
      _references ?? (throw StateError('Base de données non ouverte'));
  SecurityRepository get security =>
      _security ?? (throw StateError('Base de données non ouverte'));

  Future<void> connect({String? path}) async {
    await close();
    final factory = _factory ?? databaseFactory;
    final file = await _resolvePath(path);
    final current = await _peekVersion(factory, file);
    if (current > kSchemaVersion) {
      throw DbTooNewException(current, kSchemaVersion);
    }
    openedFromVersion = current;
    lastBackupPath = null;
    if (current >= 1 && current < kSchemaVersion) {
      lastBackupPath = await _backup(file, current);
    }
    final db = await factory.openDatabase(
      file,
      options: OpenDatabaseOptions(
        version: kSchemaVersion,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, version) => _apply(db, 0, version),
        onUpgrade: _apply,
        onDowngrade: (db, from, to) => throw DbTooNewException(from, to),
      ),
    );
    _db = db;
    _path = file;
    _analyses = AnalysesRepository(db);
    _references = ReferencesRepository(db, clock: _clock);
    _security = SecurityRepository(db, clock: _clock);
  }

  /// Exécute les migrations `from+1 … to` (dans la transaction de sqflite).
  static Future<void> _apply(Database db, int from, int to) async {
    for (var v = from + 1; v <= to; v++) {
      for (final sql in kMigrations[v - 1]) {
        await db.execute(sql);
      }
    }
  }

  /// Version du schéma d'un fichier existant, sans le modifier (0 si absent).
  static Future<int> _peekVersion(DatabaseFactory f, String file) async {
    if (file == inMemoryDatabasePath || !await File(file).exists()) return 0;
    final db = await f.openDatabase(
      file,
      options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
    );
    try {
      final rows = await db.rawQuery('PRAGMA user_version');
      return (rows.first.values.first as num?)?.toInt() ?? 0;
    } finally {
      await db.close();
    }
  }

  /// Copie `history.db` en `history.v1-AAAAMMJJ-HHMMSS.bak` à côté du fichier.
  Future<String> _backup(String file, int version) async {
    final t = _clock().toUtc();
    String two(int n) => n.toString().padLeft(2, '0');
    final stamp =
        '${t.year}${two(t.month)}${two(t.day)}-'
        '${two(t.hour)}${two(t.minute)}${two(t.second)}';
    final base = p.basenameWithoutExtension(file);
    var target = p.join(p.dirname(file), '$base.v$version-$stamp.bak');
    var n = 1;
    while (await File(target).exists()) {
      target = p.join(p.dirname(file), '$base.v$version-$stamp-$n.bak');
      n++;
    }
    await File(file).copy(target);
    return target;
  }

  Future<String> _resolvePath(String? override) async {
    if (override != null && override.trim().isNotEmpty) {
      return override.trim();
    }
    final dir = await getApplicationSupportDirectory();
    final d = Directory(p.join(dir.path, 'authentik-v2'));
    if (!await d.exists()) await d.create(recursive: true);
    return p.join(d.path, 'history.db');
  }

  Future<void> close() async {
    final db = _db;
    _db = null;
    _analyses = null;
    _references = null;
    _security = null;
    if (db != null) await db.close();
  }

  /// Version du schéma de la base ouverte.
  Future<int> schemaVersion() async {
    final rows = await _c.rawQuery('PRAGMA user_version');
    return (rows.first.values.first as num).toInt();
  }

  // --- Façade historique (utilisée par l'interface) -----------------------

  Future<void> insert(AnalysisResult r) => analyses.insert(r);

  Future<List<HistoryEntry>> list({
    int limit = 200,
    Verdict? verdict,
    String search = '',
    bool pendingOnly = false,
  }) => analyses.list(
    limit: limit,
    verdict: verdict,
    search: search,
    pendingOnly: pendingOnly,
  );

  Future<DbStats> stats() => analyses.stats();

  Future<void> setDecision(String id, Decision d, String note) =>
      analyses.setDecision(id, d, note);

  Future<void> delete(String id) => analyses.delete(id);
}

/// Message clair pour une erreur d'ouverture (version trop récente, etc.).
String describeDbError(Object e) =>
    e is DbRuleException ? e.message : e.toString();
