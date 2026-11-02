import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

/// Décision automatique du moteur.
enum Verdict { authentic, review, suspect }

extension VerdictX on Verdict {
  String get label => switch (this) {
        Verdict.authentic => 'Aucune anomalie majeure',
        Verdict.review => 'À examiner',
        Verdict.suspect => 'Suspect',
      };

  String get short => switch (this) {
        Verdict.authentic => 'Conforme',
        Verdict.review => 'À examiner',
        Verdict.suspect => 'Suspect',
      };

  static Verdict parse(String? v) => Verdict.values.firstWhere(
        (e) => e.name == v,
        orElse: () => Verdict.review,
      );
}

/// Contrôles disponibles dans un profil de vérification.
enum CheckId {
  copyMove,
  sealOverlay,
  signatureOverlay,
  textConsistency,
  noiseConsistency,
  ela,
  metadata,
}

extension CheckIdX on CheckId {
  String get label => switch (this) {
        CheckId.copyMove => 'Éléments dupliqués (copier-coller)',
        CheckId.sealOverlay => 'Sceau superposé',
        CheckId.signatureOverlay => 'Signature superposée',
        CheckId.textConsistency => 'Texte et dates modifiés',
        CheckId.noiseConsistency => 'Cohérence du grain du papier',
        CheckId.ela => 'Niveaux de compression (ELA)',
        CheckId.metadata => 'Métadonnées du fichier',
      };

  String get description => switch (this) {
        CheckId.copyMove =>
          'Détecte un sceau, une signature ou un bloc copié et collé ailleurs dans le même document.',
        CheckId.sealOverlay =>
          'Cherche les tampons collés : bord rectangulaire, fond de papier différent, grain différent.',
        CheckId.signatureOverlay =>
          'Cherche les signatures ajoutées : fond de papier et grain incohérents autour du tracé.',
        CheckId.textConsistency =>
          'Compare l’encre, l’épaisseur de trait et la netteté de chaque mot (dates, noms, numéros).',
        CheckId.noiseConsistency =>
          'Repère les zones dont le grain diffère du reste de la feuille (collage, retouche).',
        CheckId.ela =>
          'Analyse les écarts de recompression JPEG. Signal faible seul, utile en renfort.',
        CheckId.metadata =>
          'Recherche un logiciel de retouche (Photoshop, GIMP…) ou une date de modification suspecte.',
      };

  /// Famille affichée dans les profils (sceau, signature, date, général).
  String get group => switch (this) {
        CheckId.sealOverlay => 'Sceau',
        CheckId.signatureOverlay => 'Signature',
        CheckId.textConsistency => 'Date et texte',
        CheckId.copyMove => 'Général',
        CheckId.noiseConsistency => 'Général',
        CheckId.ela => 'Général',
        CheckId.metadata => 'Fichier',
      };

  static CheckId? parse(String? v) {
    for (final e in CheckId.values) {
      if (e.name == v) return e;
    }
    return null;
  }
}

/// Zone suspecte, en coordonnées normalisées (0..1) sur la page.
class Region {
  const Region({
    required this.page,
    required this.check,
    required this.left,
    required this.top,
    required this.width,
    required this.height,
    required this.score,
    required this.label,
  });

  final int page;
  final CheckId check;
  final double left;
  final double top;
  final double width;
  final double height;
  final double score;
  final String label;

  Map<String, dynamic> toJson() => {
        'page': page,
        'check': check.name,
        'l': _r(left),
        't': _r(top),
        'w': _r(width),
        'h': _r(height),
        's': _r(score),
        'label': label,
      };

  factory Region.fromJson(Map<String, dynamic> j) => Region(
        page: (j['page'] as num?)?.toInt() ?? 0,
        check: CheckIdX.parse(j['check'] as String?) ?? CheckId.ela,
        left: (j['l'] as num).toDouble(),
        top: (j['t'] as num).toDouble(),
        width: (j['w'] as num).toDouble(),
        height: (j['h'] as num).toDouble(),
        score: (j['s'] as num?)?.toDouble() ?? 0,
        label: (j['label'] as String?) ?? '',
      );
}

double _r(double v) => (v * 10000).roundToDouble() / 10000;

/// Résultat d'un contrôle sur l'ensemble du document.
class CheckResult {
  const CheckResult({
    required this.id,
    required this.score,
    this.summary = '',
    this.regions = const [],
    this.skipped = false,
  });

  final CheckId id;

  /// 0 = rien d'anormal, 1 = indice très fort.
  final double score;
  final String summary;
  final List<Region> regions;
  final bool skipped;

  Map<String, dynamic> toJson() => {
        'id': id.name,
        'score': _r(score),
        'summary': summary,
        'skipped': skipped,
      };

  factory CheckResult.fromJson(Map<String, dynamic> j, List<Region> regions) =>
      CheckResult(
        id: CheckIdX.parse(j['id'] as String?) ?? CheckId.ela,
        score: (j['score'] as num?)?.toDouble() ?? 0,
        summary: (j['summary'] as String?) ?? '',
        skipped: (j['skipped'] as bool?) ?? false,
        regions: regions.where((r) => r.check.name == j['id']).toList(),
      );
}

/// Image d'une page telle qu'analysée (pour l'aperçu, jamais écrite sur disque).
class PagePreview {
  const PagePreview({
    required this.index,
    required this.width,
    required this.height,
    required this.jpeg,
  });

  final int index;
  final int width;
  final int height;
  final Uint8List jpeg;
}

/// Décision humaine après vérification manuelle.
enum Decision { none, authentic, fraud }

extension DecisionX on Decision {
  String get label => switch (this) {
        Decision.none => 'En attente',
        Decision.authentic => 'Confirmé authentique',
        Decision.fraud => 'Confirmé falsifié',
      };

  static Decision parse(String? v) => Decision.values.firstWhere(
        (e) => e.name == v,
        orElse: () => Decision.none,
      );
}

class AnalysisResult {
  AnalysisResult({
    required this.id,
    required this.fileName,
    required this.sha256,
    required this.source,
    required this.createdAt,
    required this.elapsedMs,
    required this.probability,
    required this.verdict,
    required this.threshold,
    required this.profileName,
    required this.checks,
    required this.warnings,
    required this.previews,
    this.decision = Decision.none,
    this.note = '',
  });

  final String id;
  final String fileName;
  final String sha256;

  /// "pdf" ou "image".
  final String source;
  final DateTime createdAt;
  final int elapsedMs;

  /// 0..1 — probabilité estimée que le document ait été falsifié.
  final double probability;
  final Verdict verdict;
  final double threshold;
  final String profileName;
  final List<CheckResult> checks;
  final List<String> warnings;
  final List<PagePreview> previews;
  Decision decision;
  String note;

  int get pageCount => previews.length;

  List<Region> get regions => [for (final c in checks) ...c.regions];

  Map<String, dynamic> toJson() => {
        'id': id,
        'fileName': fileName,
        'sha256': sha256,
        'source': source,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'elapsedMs': elapsedMs,
        'probability': _r(probability),
        'verdict': verdict.name,
        'threshold': threshold,
        'profileName': profileName,
        'checks': checks.map((c) => c.toJson()).toList(),
        'regions': regions.map((r) => r.toJson()).toList(),
        'warnings': warnings,
        'decision': decision.name,
        'note': note,
      };

  String toPrettyJson() => const JsonEncoder.withIndent('  ').convert(toJson());

  HistoryEntry toEntry() => HistoryEntry(
        id: id,
        fileName: fileName,
        sha256: sha256,
        source: source,
        pageCount: pageCount,
        createdAt: createdAt,
        elapsedMs: elapsedMs,
        probability: probability,
        verdict: verdict,
        threshold: threshold,
        profileName: profileName,
        checks: checks,
        warnings: warnings,
        decision: decision,
        note: note,
      );
}

/// Ligne d'historique (base de données ou session).
class HistoryEntry {
  HistoryEntry({
    required this.id,
    required this.fileName,
    required this.sha256,
    required this.source,
    required this.pageCount,
    required this.createdAt,
    required this.elapsedMs,
    required this.probability,
    required this.verdict,
    required this.threshold,
    required this.profileName,
    required this.checks,
    required this.warnings,
    required this.decision,
    required this.note,
  });

  final String id;
  final String fileName;
  final String sha256;
  final String source;
  final int pageCount;
  final DateTime createdAt;
  final int elapsedMs;
  final double probability;
  final Verdict verdict;
  final double threshold;
  final String profileName;
  final List<CheckResult> checks;
  final List<String> warnings;
  Decision decision;
  String note;
}

/// Profil de vérification : quels contrôles lancer et avec quelle sévérité.
class VerificationProfile {
  VerificationProfile({
    required this.id,
    required this.name,
    required this.enabled,
    this.threshold = 0.70,
    this.sensitivity = 1.0,
    this.maxPages = 3,
    this.renderDpi = 300,
  });

  final String id;
  String name;
  Set<CheckId> enabled;

  /// Seuil au-delà duquel un document est « suspect » (0.5..0.95).
  double threshold;

  /// Multiplicateur du poids des contrôles (0.6..1.4).
  double sensitivity;
  int maxPages;
  int renderDpi;

  VerificationProfile copy() => VerificationProfile(
        id: id,
        name: name,
        enabled: {...enabled},
        threshold: threshold,
        sensitivity: sensitivity,
        maxPages: maxPages,
        renderDpi: renderDpi,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'enabled': enabled.map((e) => e.name).toList(),
        'threshold': threshold,
        'sensitivity': sensitivity,
        'maxPages': maxPages,
        'renderDpi': renderDpi,
      };

  factory VerificationProfile.fromJson(Map<String, dynamic> j) {
    final en = <CheckId>{};
    for (final n in (j['enabled'] as List? ?? const [])) {
      final c = CheckIdX.parse(n as String?);
      if (c != null) en.add(c);
    }
    return VerificationProfile(
      id: (j['id'] as String?) ?? newId(),
      name: (j['name'] as String?) ?? 'Profil',
      enabled: en.isEmpty ? {...CheckId.values} : en,
      threshold:
          ((j['threshold'] as num?)?.toDouble() ?? 0.70).clamp(0.4, 0.98).toDouble(),
      sensitivity:
          ((j['sensitivity'] as num?)?.toDouble() ?? 1.0).clamp(0.5, 1.5).toDouble(),
      maxPages: ((j['maxPages'] as num?)?.toInt() ?? 3).clamp(1, 6).toInt(),
      renderDpi:
          ((j['renderDpi'] as num?)?.toInt() ?? 300).clamp(100, 400).toInt(),
    );
  }

  /// Identifiants des trois profils fournis avec l'application.
  static const builtInIds = {'standard', 'certificats', 'rapide'};

  static List<VerificationProfile> defaults() => [
        VerificationProfile(
          id: 'standard',
          name: 'Standard',
          enabled: {...CheckId.values},
        ),
        VerificationProfile(
          id: 'certificats',
          name: 'Certificats (sceau + signature + date)',
          enabled: {
            CheckId.sealOverlay,
            CheckId.signatureOverlay,
            CheckId.textConsistency,
            CheckId.copyMove,
            CheckId.noiseConsistency,
            CheckId.metadata,
          },
          threshold: 0.65,
        ),
        VerificationProfile(
          id: 'rapide',
          name: 'Rapide',
          enabled: {
            CheckId.sealOverlay,
            CheckId.signatureOverlay,
            CheckId.metadata,
          },
          maxPages: 1,
          renderDpi: 200,
        ),
      ];

  /// Réinitialise Standard, Certificats et Rapide ; conserve les profils personnalisés.
  static List<VerificationProfile> withRestoredDefaults(
    List<VerificationProfile> current,
  ) {
    final custom =
        current.where((p) => !builtInIds.contains(p.id)).toList(growable: false);
    return [...defaults(), ...custom];
  }
}

final _rng = Random();

String newId() {
  final t = DateTime.now().microsecondsSinceEpoch.toRadixString(16);
  final r = List.generate(4, (_) => _rng.nextInt(1 << 16).toRadixString(16))
      .join();
  return '$t$r';
}
