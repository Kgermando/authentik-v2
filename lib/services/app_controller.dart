import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../core/models.dart';
import 'analyzer/analyzer.dart';
import 'database.dart';
import 'document_loader.dart';
import 'settings_store.dart';

enum TaskStatus { queued, running, done, failed }

class AnalysisTask {
  AnalysisTask({
    required this.id,
    required this.path,
    required this.name,
    this.fromWatcher = false,
  }) : added = DateTime.now();

  final String id;
  final String path;
  final String name;
  final bool fromWatcher;
  final DateTime added;
  TaskStatus status = TaskStatus.queued;
  double progress = 0;
  String stage = 'En attente';
  AnalysisResult? result;
  String? error;
}

enum DbState { disconnected, connecting, connected, failed }

/// État global de l'application : réglages, file d'analyses, historique,
/// base de données et dossier surveillé.
class AppController extends ChangeNotifier {
  AppController({SettingsStore? store, AuthentikDb? db})
      : _store = store ?? SettingsStore(),
        db = db ?? AuthentikDb();

  final SettingsStore _store;
  final AuthentikDb db;

  AppSettings settings = AppSettings();
  bool ready = false;

  DbState dbState = DbState.disconnected;
  String? dbError;
  DbStats? stats;
  List<HistoryEntry> history = [];
  String historySearch = '';
  Verdict? historyFilter;

  /// Résultats de la session, utilisés si la base est indisponible.
  final List<AnalysisResult> sessionResults = [];
  final List<AnalysisTask> tasks = [];
  AnalysisResult? selected;

  bool _running = false;
  StreamSubscription<FileSystemEvent>? _watchSub;
  final Map<String, String> _seen = {};
  String? watchError;

  VerificationProfile get profile => settings.activeProfile;
  bool get busy => tasks.any(
        (t) => t.status == TaskStatus.running || t.status == TaskStatus.queued,
      );

  Future<void> init() async {
    settings = await _store.load();
    ready = true;
    notifyListeners();
    unawaited(connectDb());
    if (settings.watchEnabled && settings.watchFolder.isNotEmpty) {
      await startWatching();
    }
  }

  // ------------------------------------------------------------- Base ------

  Future<void> connectDb() async {
    dbState = DbState.connecting;
    dbError = null;
    notifyListeners();
    try {
      await db.connect(
        path: settings.dbPath.isEmpty ? null : settings.dbPath,
      );
      dbState = DbState.connected;
      await refreshHistory();
    } catch (e) {
      dbState = DbState.failed;
      dbError = _short(e);
    }
    notifyListeners();
  }

  Future<void> refreshHistory() async {
    if (dbState != DbState.connected) {
      history = [for (final r in sessionResults.reversed) r.toEntry()];
      stats = null;
      notifyListeners();
      return;
    }
    try {
      history = await db.list(verdict: historyFilter, search: historySearch);
      stats = await db.stats();
    } catch (e) {
      dbState = DbState.failed;
      dbError = _short(e);
    }
    notifyListeners();
  }

  void setHistoryQuery({String? search, Verdict? filter, bool clearFilter = false}) {
    if (search != null) historySearch = search;
    if (filter != null) historyFilter = filter;
    if (clearFilter) historyFilter = null;
    unawaited(refreshHistory());
  }

  Future<void> setDecision(
    String id,
    Decision d, {
    String note = '',
  }) async {
    for (final r in sessionResults) {
      if (r.id == id) {
        r.decision = d;
        r.note = note;
      }
    }
    for (final h in history) {
      if (h.id == id) {
        h.decision = d;
        h.note = note;
      }
    }
    notifyListeners();
    if (dbState == DbState.connected) {
      try {
        await db.setDecision(id, d, note);
        stats = await db.stats();
      } catch (e) {
        dbError = _short(e);
      }
      notifyListeners();
    }
  }

  Future<void> deleteEntry(String id) async {
    sessionResults.removeWhere((r) => r.id == id);
    history.removeWhere((h) => h.id == id);
    if (selected?.id == id) selected = null;
    notifyListeners();
    if (dbState == DbState.connected) {
      try {
        await db.delete(id);
        stats = await db.stats();
      } catch (e) {
        dbError = _short(e);
      }
      notifyListeners();
    }
  }

  // --------------------------------------------------------- Réglages ------

  Future<void> saveSettings() async {
    await _store.save(settings);
    notifyListeners();
  }

  void setActiveProfile(String id) {
    settings.activeProfileId = id;
    unawaited(saveSettings());
  }

  /// Remet Standard, Certificats et Rapide à leurs réglages d'origine.
  Future<void> restoreDefaultProfiles() async {
    settings.profiles =
        VerificationProfile.withRestoredDefaults(settings.profiles);
    if (!settings.profiles.any((p) => p.id == settings.activeProfileId)) {
      settings.activeProfileId = 'certificats';
    }
    await saveSettings();
  }

  void toggleDark(bool v) {
    settings.darkMode = v;
    unawaited(saveSettings());
  }

  // --------------------------------------------------------- Analyses ------

  void analyzePaths(Iterable<String> paths, {bool fromWatcher = false}) {
    for (final path in paths) {
      final t = AnalysisTask(
        id: newId(),
        path: path,
        name: path.split(RegExp(r'[\\/]')).last,
        fromWatcher: fromWatcher,
      );
      if (!isSupportedFile(path)) {
        t.status = TaskStatus.failed;
        t.error =
            'Format non pris en charge. Formats acceptés : PDF, PNG, JPG, TIFF, BMP, WEBP.';
      }
      tasks.insert(0, t);
    }
    notifyListeners();
    unawaited(_drain());
  }

  Future<void> _drain() async {
    if (_running) return;
    _running = true;
    try {
      while (true) {
        final next = tasks.reversed
            .cast<AnalysisTask?>()
            .firstWhere((t) => t!.status == TaskStatus.queued, orElse: () => null);
        if (next == null) break;
        await _runTask(next);
      }
    } finally {
      _running = false;
    }
  }

  Future<void> _runTask(AnalysisTask t) async {
    t.status = TaskStatus.running;
    t.stage = 'Lecture du document';
    t.progress = 0.01;
    notifyListeners();
    try {
      final job = await prepareJob(t.path, profile);
      final result = await runAnalysis(job, (f, s) {
        t.progress = f;
        t.stage = s;
        notifyListeners();
      });
      t.result = result;
      t.status = TaskStatus.done;
      t.progress = 1;
      t.stage = 'Terminé';
      sessionResults.add(result);
      selected = result;
      if (dbState == DbState.connected) {
        try {
          await db.insert(result);
        } catch (e) {
          dbError = 'Enregistrement impossible : ${_short(e)}';
        }
      }
      await refreshHistory();
    } catch (e) {
      t.status = TaskStatus.failed;
      t.error = _short(e);
    }
    notifyListeners();
  }

  void clearFinishedTasks() {
    tasks.removeWhere(
      (t) => t.status == TaskStatus.done || t.status == TaskStatus.failed,
    );
    notifyListeners();
  }

  void dismissTask(AnalysisTask t) {
    tasks.remove(t);
    notifyListeners();
  }

  void select(AnalysisResult? r) {
    selected = r;
    notifyListeners();
  }

  /// Lignes visibles dans l'historique (filtres et recherche appliqués).
  List<HistoryEntry> visibleHistory() {
    if (dbState == DbState.connected) return history;
    return [
      for (final h in history)
        if ((historyFilter == null || h.verdict == historyFilter) &&
            (historySearch.isEmpty ||
                h.fileName.toLowerCase().contains(historySearch.toLowerCase()) ||
                h.sha256.toLowerCase().contains(historySearch.toLowerCase())))
          h,
    ];
  }

  // ------------------------------------------------ Dossier surveillé ------

  Future<void> startWatching() async {
    await stopWatching(notify: false);
    final dir = Directory(settings.watchFolder);
    if (!await dir.exists()) {
      watchError = 'Dossier introuvable : ${settings.watchFolder}';
      notifyListeners();
      return;
    }
    watchError = null;
    // Les fichiers déjà présents ne sont pas analysés : seuls les nouveaux le sont.
    await for (final e in dir.list(followLinks: false).handleError((_) {})) {
      if (e is File) {
        _seen[e.path] = '${e.lengthSync()}';
      }
    }
    try {
      _watchSub = dir
          .watch(events: FileSystemEvent.create | FileSystemEvent.modify)
          .listen(_onFsEvent, onError: (Object e) {
        watchError = _short(e);
        notifyListeners();
      });
    } catch (e) {
      watchError = _short(e);
    }
    notifyListeners();
  }

  Future<void> stopWatching({bool notify = true}) async {
    await _watchSub?.cancel();
    _watchSub = null;
    if (notify) notifyListeners();
  }

  bool get watching => _watchSub != null;

  Future<void> _onFsEvent(FileSystemEvent e) async {
    if (e.isDirectory || !isSupportedFile(e.path)) return;
    // On attend que le scanner ait fini d'écrire (taille stable).
    final f = File(e.path);
    var last = -1;
    for (var i = 0; i < 40; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 600));
      if (!await f.exists()) return;
      final len = await f.length();
      if (len > 0 && len == last) break;
      last = len;
    }
    final sig = '$last';
    if (_seen[e.path] == sig) return;
    _seen[e.path] = sig;
    analyzePaths([e.path], fromWatcher: true);
  }

  @override
  void dispose() {
    _watchSub?.cancel();
    db.close();
    super.dispose();
  }

  String _short(Object e) {
    final s = e.toString().replaceFirst(RegExp(r'^(Exception|StateError): '), '');
    return s.length > 300 ? '${s.substring(0, 300)}…' : s;
  }
}
