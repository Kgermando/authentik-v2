import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/models.dart';

class AppSettings {
  AppSettings({
    List<VerificationProfile>? profiles,
    this.activeProfileId = 'certificats',
    this.dbPath = '',
    this.watchFolder = '',
    this.watchEnabled = false,
    this.darkMode = false,
  }) : profiles = profiles ?? VerificationProfile.defaults();

  List<VerificationProfile> profiles;
  String activeProfileId;

  /// Chemin optionnel du fichier SQLite (vide = dossier support de l'app).
  String dbPath;
  String watchFolder;
  bool watchEnabled;
  bool darkMode;

  VerificationProfile get activeProfile => profiles.firstWhere(
        (e) => e.id == activeProfileId,
        orElse: () => profiles.first,
      );

  Map<String, dynamic> toJson() => {
        'profiles': profiles.map((e) => e.toJson()).toList(),
        'activeProfileId': activeProfileId,
        if (dbPath.isNotEmpty) 'dbPath': dbPath,
        'watchFolder': watchFolder,
        'watchEnabled': watchEnabled,
        'darkMode': darkMode,
      };

  factory AppSettings.fromJson(Map<String, dynamic> j) {
    final profiles = <VerificationProfile>[
      for (final e in (j['profiles'] as List? ?? const []))
        VerificationProfile.fromJson(Map<String, dynamic>.from(e as Map)),
    ];
    return AppSettings(
      profiles: profiles.isEmpty ? null : profiles,
      activeProfileId: (j['activeProfileId'] as String?) ?? 'certificats',
      dbPath: (j['dbPath'] as String?) ?? '',
      watchFolder: (j['watchFolder'] as String?) ?? '',
      watchEnabled: (j['watchEnabled'] as bool?) ?? false,
      darkMode: (j['darkMode'] as bool?) ?? false,
    );
  }
}

/// Lecture / écriture des réglages dans un fichier JSON local.
/// La variable d'environnement AUTHENTIK_DB_PATH, si elle existe, remplace le
/// chemin SQLite enregistré.
class SettingsStore {
  Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    final d = Directory(p.join(dir.path, 'authentik-v2'));
    if (!await d.exists()) await d.create(recursive: true);
    return File(p.join(d.path, 'settings.json'));
  }

  Future<AppSettings> load() async {
    AppSettings s;
    try {
      final f = await _file();
      if (await f.exists()) {
        s = AppSettings.fromJson(
          jsonDecode(await f.readAsString()) as Map<String, dynamic>,
        );
      } else {
        s = AppSettings();
      }
    } catch (_) {
      s = AppSettings();
    }
    final env = Platform.environment['AUTHENTIK_DB_PATH']?.trim();
    if (env != null && env.isNotEmpty) s.dbPath = env;
    return s;
  }

  Future<void> save(AppSettings s) async {
    try {
      final f = await _file();
      await f.writeAsString(
        const JsonEncoder.withIndent('  ').convert(s.toJson()),
      );
    } catch (_) {
      // Les réglages sont un confort : on ne bloque jamais l'application.
    }
  }
}
