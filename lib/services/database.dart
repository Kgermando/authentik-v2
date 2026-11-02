import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../core/models.dart';

class DbStats {
  const DbStats({
    this.total = 0,
    this.suspect = 0,
    this.review = 0,
    this.authentic = 0,
    this.avgProbability = 0,
    this.pendingReview = 0,
  });

  final int total;
  final int suspect;
  final int review;
  final int authentic;
  final double avgProbability;

  /// Documents suspects ou à examiner sans décision humaine.
  final int pendingReview;
}

/// Initialise SQLite pour Windows, macOS et Linux (FFI).
Future<void> initSqlite() async {
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }
}

/// Historique des analyses dans SQLite (fichier local).
///
/// Seules les métadonnées et les résultats sont enregistrés : le document
/// analysé et ses images ne sont jamais écrits sur disque ni en base.
class AuthentikDb {
  Database? _db;
  String? _path;

  bool get connected => _db != null;

  String? get path => _path;

  Future<void> connect({String? path}) async {
    await close();
    final file = await _resolvePath(path);
    _path = file;
    _db = await openDatabase(
      file,
      version: 1,
      onCreate: (db, _) => _migrate(db),
      onUpgrade: (db, _, _) => _migrate(db),
    );
    await _migrate(_db!);
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
    if (db != null) await db.close();
  }

  Database get _c {
    final db = _db;
    if (db == null) {
      throw StateError('Base de données non ouverte');
    }
    return db;
  }

  Future<void> _migrate(Database db) async {
    await db.execute('''
CREATE TABLE IF NOT EXISTS analyses (
  id            TEXT PRIMARY KEY,
  created_at    TEXT NOT NULL,
  file_name     TEXT NOT NULL,
  sha256        TEXT NOT NULL,
  source        TEXT NOT NULL,
  page_count    INTEGER NOT NULL DEFAULT 1,
  probability   REAL NOT NULL,
  verdict       TEXT NOT NULL,
  threshold     REAL NOT NULL,
  profile_name  TEXT NOT NULL,
  elapsed_ms    INTEGER NOT NULL,
  checks_json   TEXT NOT NULL,
  regions_json  TEXT NOT NULL,
  warnings_json TEXT NOT NULL,
  decision      TEXT NOT NULL DEFAULT 'none',
  decision_at   TEXT,
  note          TEXT NOT NULL DEFAULT ''
)''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS analyses_created_idx ON analyses (created_at DESC)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS analyses_sha_idx ON analyses (sha256)',
    );
  }

  Future<void> insert(AnalysisResult r) async {
    await _c.insert(
      'analyses',
      {
        'id': r.id,
        'created_at': r.createdAt.toUtc().toIso8601String(),
        'file_name': r.fileName,
        'sha256': r.sha256,
        'source': r.source,
        'page_count': r.pageCount,
        'probability': r.probability,
        'verdict': r.verdict.name,
        'threshold': r.threshold,
        'profile_name': r.profileName,
        'elapsed_ms': r.elapsedMs,
        'checks_json': jsonEncode(r.checks.map((c) => c.toJson()).toList()),
        'regions_json': jsonEncode(r.regions.map((e) => e.toJson()).toList()),
        'warnings_json': jsonEncode(r.warnings),
        'decision': r.decision.name,
        'note': r.note,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<List<HistoryEntry>> list({
    int limit = 200,
    Verdict? verdict,
    String search = '',
  }) async {
    final where = <String>[];
    final args = <Object?>[];
    if (verdict != null) {
      where.add('verdict = ?');
      args.add(verdict.name);
    }
    if (search.trim().isNotEmpty) {
      where.add('(file_name LIKE ? COLLATE NOCASE OR sha256 LIKE ? COLLATE NOCASE)');
      final q = '%${search.trim()}%';
      args.addAll([q, q]);
    }
    final sql = StringBuffer('SELECT * FROM analyses');
    if (where.isNotEmpty) sql.write(' WHERE ${where.join(' AND ')}');
    sql.write(' ORDER BY created_at DESC LIMIT ?');
    args.add(limit);
    final rows = await _c.rawQuery(sql.toString(), args);
    return [for (final row in rows) _entry(row)];
  }

  HistoryEntry _entry(Map<String, Object?> m) {
    List<Region> regions = const [];
    try {
      regions = [
        for (final e in jsonDecode(m['regions_json']! as String) as List)
          Region.fromJson(Map<String, dynamic>.from(e as Map)),
      ];
    } catch (_) {}
    var checks = <CheckResult>[];
    try {
      checks = [
        for (final e in jsonDecode(m['checks_json']! as String) as List)
          CheckResult.fromJson(Map<String, dynamic>.from(e as Map), regions),
      ];
    } catch (_) {}
    var warnings = <String>[];
    try {
      warnings = [
        for (final e in jsonDecode(m['warnings_json']! as String) as List)
          e as String,
      ];
    } catch (_) {}
    return HistoryEntry(
      id: m['id']! as String,
      fileName: m['file_name']! as String,
      sha256: m['sha256']! as String,
      source: m['source']! as String,
      pageCount: (m['page_count'] as num).toInt(),
      createdAt: DateTime.parse(m['created_at']! as String).toLocal(),
      elapsedMs: (m['elapsed_ms'] as num).toInt(),
      probability: (m['probability'] as num).toDouble(),
      verdict: VerdictX.parse(m['verdict'] as String?),
      threshold: (m['threshold'] as num).toDouble(),
      profileName: m['profile_name']! as String,
      checks: checks,
      warnings: warnings,
      decision: DecisionX.parse(m['decision'] as String?),
      note: (m['note'] as String?) ?? '',
    );
  }

  Future<DbStats> stats() async {
    final rows = await _c.rawQuery('''
SELECT
  COUNT(*) AS total,
  SUM(CASE WHEN verdict = 'suspect' THEN 1 ELSE 0 END) AS suspect,
  SUM(CASE WHEN verdict = 'review' THEN 1 ELSE 0 END) AS review,
  SUM(CASE WHEN verdict = 'authentic' THEN 1 ELSE 0 END) AS authentic,
  IFNULL(AVG(probability), 0) AS avg_p,
  SUM(CASE WHEN verdict <> 'authentic' AND decision = 'none' THEN 1 ELSE 0 END) AS pending
FROM analyses''');
    final m = rows.first;
    return DbStats(
      total: (m['total'] as num?)?.toInt() ?? 0,
      suspect: (m['suspect'] as num?)?.toInt() ?? 0,
      review: (m['review'] as num?)?.toInt() ?? 0,
      authentic: (m['authentic'] as num?)?.toInt() ?? 0,
      avgProbability: (m['avg_p'] as num?)?.toDouble() ?? 0,
      pendingReview: (m['pending'] as num?)?.toInt() ?? 0,
    );
  }

  Future<void> setDecision(String id, Decision d, String note) async {
    await _c.update(
      'analyses',
      {
        'decision': d.name,
        'decision_at': d == Decision.none
            ? null
            : DateTime.now().toUtc().toIso8601String(),
        'note': note,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> delete(String id) async {
    await _c.delete('analyses', where: 'id = ?', whereArgs: [id]);
  }
}
