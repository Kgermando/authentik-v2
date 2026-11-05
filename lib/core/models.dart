import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'i18n.dart';
import 'page_scale.dart';

/// Décision automatique du moteur.
///
/// `inconclusive` : qualité insuffisante, ou année de référence choisie sans
/// référentiel utilisable. Le pourcentage reste calculé mais n'est qu'indicatif.
enum Verdict { authentic, review, suspect, inconclusive }

extension VerdictX on Verdict {
  String get label => switch (this) {
    Verdict.authentic => 'Aucune anomalie majeure',
    Verdict.review => 'À examiner',
    Verdict.suspect => 'Suspect',
    Verdict.inconclusive => tr('verdict.non_concluant'),
  };

  String get short => switch (this) {
    Verdict.authentic => 'Conforme',
    Verdict.review => 'À examiner',
    Verdict.suspect => 'Suspect',
    Verdict.inconclusive => tr('verdict.non_concluant.court'),
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
  // --- Référentiel annuel d'originaux ---------------------------------
  sealComparison,
  sealCopy,
  originalModified,
  signatureComparison,
  signatureCopy,
  layoutComparison,
  sealSignaturePosition,
  textYear,
  paperComparison,
  yearConsistency,
}

/// Contrôles du référentiel annuel : non applicables sans année choisie.
const Set<CheckId> kReferenceChecks = {
  CheckId.sealComparison,
  CheckId.sealCopy,
  CheckId.originalModified,
  CheckId.signatureComparison,
  CheckId.signatureCopy,
  CheckId.layoutComparison,
  CheckId.sealSignaturePosition,
  CheckId.textYear,
  CheckId.paperComparison,
  CheckId.yearConsistency,
};

/// Version du format de profil qui a introduit chaque contrôle du
/// référentiel : un profil enregistré avant les active automatiquement.
const Map<CheckId, int> kCheckSinceSchema = {
  CheckId.sealComparison: 2,
  CheckId.sealCopy: 2,
  CheckId.originalModified: 2,
  CheckId.signatureComparison: 3,
  CheckId.signatureCopy: 3,
  CheckId.layoutComparison: 4,
  CheckId.sealSignaturePosition: 4,
  CheckId.textYear: 4,
  CheckId.paperComparison: 5,
  CheckId.yearConsistency: 5,
};

/// Contrôles critiques par défaut (un échec avec une confiance suffisante
/// force « suspect »).
const Set<CheckId> kCriticalChecks = {
  CheckId.sealComparison,
  CheckId.sealCopy,
  CheckId.originalModified,
  CheckId.signatureCopy,
  CheckId.yearConsistency,
};

extension CheckIdX on CheckId {
  String get label => switch (this) {
    CheckId.copyMove => 'Éléments dupliqués (copier-coller)',
    CheckId.sealOverlay => 'Sceau superposé',
    CheckId.signatureOverlay => 'Signature superposée',
    CheckId.textConsistency => 'Texte et dates modifiés',
    CheckId.noiseConsistency => 'Cohérence du grain du papier',
    CheckId.ela => 'Niveaux de compression (ELA)',
    CheckId.metadata => 'Métadonnées du fichier',
    CheckId.sealComparison => tr('controle.comparaison_sceau'),
    CheckId.sealCopy => tr('controle.sceau_copie_original'),
    CheckId.originalModified => tr('controle.original_modifie'),
    CheckId.signatureComparison => tr('controle.comparaison_signature'),
    CheckId.signatureCopy => tr('controle.signature_copie_original'),
    CheckId.layoutComparison => tr('controle.comparaison_mise_en_page'),
    CheckId.sealSignaturePosition => tr('controle.position_sceau_signature'),
    CheckId.textYear => tr('controle.coherence_texte_annee'),
    CheckId.paperComparison => tr('controle.comparaison_papier'),
    CheckId.yearConsistency => tr('controle.coherence_annee'),
  };

  /// Identifiant stable du contrôle dans les rapports (spécification).
  String get code => switch (this) {
    CheckId.sealComparison => 'comparaison_sceau',
    CheckId.sealCopy => 'sceau_copie_original',
    CheckId.originalModified => 'original_modifie',
    CheckId.signatureComparison => 'comparaison_signature',
    CheckId.signatureCopy => 'signature_copie_original',
    CheckId.layoutComparison => 'comparaison_mise_en_page',
    CheckId.sealSignaturePosition => 'position_sceau_signature',
    CheckId.textYear => 'coherence_texte_annee',
    CheckId.paperComparison => 'comparaison_papier',
    CheckId.yearConsistency => 'coherence_annee',
    _ => name,
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
    CheckId.sealComparison => tr('controle.comparaison_sceau.description'),
    CheckId.sealCopy => tr('controle.sceau_copie_original.description'),
    CheckId.originalModified => tr('controle.original_modifie.description'),
    CheckId.signatureComparison => tr(
      'controle.comparaison_signature.description',
    ),
    CheckId.signatureCopy => tr(
      'controle.signature_copie_original.description',
    ),
    CheckId.layoutComparison => tr(
      'controle.comparaison_mise_en_page.description',
    ),
    CheckId.sealSignaturePosition => tr(
      'controle.position_sceau_signature.description',
    ),
    CheckId.textYear => tr('controle.coherence_texte_annee.description'),
    CheckId.paperComparison => tr('controle.comparaison_papier.description'),
    CheckId.yearConsistency => tr('controle.coherence_annee.description'),
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
    CheckId.sealComparison ||
    CheckId.sealCopy ||
    CheckId.originalModified ||
    CheckId.signatureComparison ||
    CheckId.signatureCopy ||
    CheckId.layoutComparison ||
    CheckId.sealSignaturePosition ||
    CheckId.textYear ||
    CheckId.paperComparison ||
    CheckId.yearConsistency => tr('controle.groupe.referentiel'),
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

/// Statut d'un contrôle (nouveaux contrôles uniquement).
///
/// Les contrôles d'origine n'ont pas de statut (`null`) : ils contribuent à la
/// fusion exactement comme avant.
enum CheckStatus { passed, warning, failed, skipped, notApplicable }

extension CheckStatusX on CheckStatus {
  String get code => switch (this) {
    CheckStatus.passed => 'PASSED',
    CheckStatus.warning => 'WARNING',
    CheckStatus.failed => 'FAILED',
    CheckStatus.skipped => 'SKIPPED',
    CheckStatus.notApplicable => 'NOT_APPLICABLE',
  };

  /// Seuls WARNING et FAILED pèsent dans la fusion.
  bool get contributes =>
      this == CheckStatus.warning || this == CheckStatus.failed;

  static CheckStatus? parse(String? v) {
    for (final e in CheckStatus.values) {
      if (e.code == v) return e;
    }
    return null;
  }
}

/// Résultat d'un contrôle sur l'ensemble du document.
class CheckResult {
  const CheckResult({
    required this.id,
    required this.score,
    this.summary = '',
    this.regions = const [],
    bool skipped = false,
    this.status,
    this.confidence,
    this.version = legacyVersion,
    this.durationMs = 0,
    this.details = const {},
    this.critical = false,
    // Le paramètre nommé `skipped` est conservé pour les appels existants ;
    // un paramètre nommé ne peut pas être privé.
    // ignore: prefer_initializing_formals
  }) : _skipped = skipped;

  /// Version attribuée aux détecteurs d'origine.
  static const String legacyVersion = '1.0.0';

  final CheckId id;

  /// 0 = rien d'anormal, 1 = indice très fort.
  final double score;
  final String summary;
  final List<Region> regions;
  final bool _skipped;

  /// `null` pour les détecteurs d'origine.
  final CheckStatus? status;

  /// 0..1 ; `null` si le détecteur ne l'estime pas.
  final double? confidence;
  final String version;
  final int durationMs;

  /// Détail chiffré (sous-distances, originaux les plus proches…), JSON.
  final Map<String, dynamic> details;

  /// Contrôle critique selon le profil au moment de l'analyse.
  final bool critical;

  /// Non évalué : ignoré, non applicable ou marqué comme sauté.
  bool get skipped =>
      _skipped ||
      status == CheckStatus.skipped ||
      status == CheckStatus.notApplicable;

  /// Copie avec la version et la durée mesurée du détecteur.
  CheckResult timed(int ms, {String? version}) => CheckResult(
    id: id,
    score: score,
    summary: summary,
    regions: regions,
    skipped: _skipped,
    status: status,
    confidence: confidence,
    version: version ?? this.version,
    durationMs: ms,
    details: details,
    critical: critical,
  );

  Map<String, dynamic> toJson() => {
    'id': id.name,
    'score': _r(score),
    'summary': summary,
    'skipped': skipped,
    'version': version,
    'durationMs': durationMs,
    if (status != null) 'status': status!.code,
    if (confidence != null) 'confidence': _r(confidence!),
    if (critical) 'critical': true,
    if (details.isNotEmpty) 'details': details,
  };

  /// Lit aussi les enregistrements d'origine (sans statut ni version).
  factory CheckResult.fromJson(Map<String, dynamic> j, List<Region> regions) =>
      CheckResult(
        id: CheckIdX.parse(j['id'] as String?) ?? CheckId.ela,
        score: (j['score'] as num?)?.toDouble() ?? 0,
        summary: (j['summary'] as String?) ?? '',
        skipped: (j['skipped'] as bool?) ?? false,
        status: CheckStatusX.parse(j['status'] as String?),
        confidence: (j['confidence'] as num?)?.toDouble(),
        version: (j['version'] as String?) ?? legacyVersion,
        durationMs: (j['durationMs'] as num?)?.toInt() ?? 0,
        details: j['details'] is Map
            ? Map<String, dynamic>.from(j['details'] as Map)
            : const {},
        critical: (j['critical'] as bool?) ?? false,
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
    this.acquisition = Acquisition.fichier,
    this.pageScales = const [],
    this.forcedByCritical = false,
    this.qualityInsufficient = false,
    this.referenceYearId,
    this.claimedYear,
    this.calibrationIds = const [],
    this.scanner = '',
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

  /// Voie d'acquisition (fichier, dossier surveillé, scanner).
  final String acquisition;

  /// Échelle physique de chaque page analysée.
  final List<PageScale> pageScales;

  /// Verdict imposé par un contrôle critique en échec.
  final bool forcedByCritical;

  /// Qualité insuffisante : verdict « non concluant ».
  final bool qualityInsufficient;

  /// Année de référence choisie (module référentiels) ; null sans année.
  final String? referenceYearId;
  final int? claimedYear;

  /// Calibrages du référentiel utilisés par cette analyse.
  final List<String> calibrationIds;

  /// Champ libre « scanner ».
  final String scanner;

  /// Copie avec d'autres contrôles et une nouvelle décision (contrôle ajouté
  /// après l'analyse, par exemple la lecture de l'année par Tesseract).
  AnalysisResult withDecision({
    required List<CheckResult> checks,
    required double probability,
    required Verdict verdict,
    required bool forcedByCritical,
    required List<String> warnings,
  }) => AnalysisResult(
    id: id,
    fileName: fileName,
    sha256: sha256,
    source: source,
    createdAt: createdAt,
    elapsedMs: elapsedMs,
    probability: probability,
    verdict: verdict,
    threshold: threshold,
    profileName: profileName,
    checks: checks,
    warnings: warnings,
    previews: previews,
    decision: decision,
    note: note,
    acquisition: acquisition,
    pageScales: pageScales,
    forcedByCritical: forcedByCritical,
    qualityInsufficient: qualityInsufficient,
    referenceYearId: referenceYearId,
    claimedYear: claimedYear,
    calibrationIds: calibrationIds,
    scanner: scanner,
  );

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
    'acquisition': acquisition,
    'pageScales': pageScales.map((s) => s.toJson()).toList(),
    'forcedByCritical': forcedByCritical,
    'qualityInsufficient': qualityInsufficient,
    if (referenceYearId != null) 'referenceYearId': referenceYearId,
    if (claimedYear != null) 'claimedYear': claimedYear,
    if (calibrationIds.isNotEmpty) 'calibrationIds': calibrationIds,
    if (scanner.isNotEmpty) 'scanner': scanner,
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
    acquisition: acquisition,
    pageScales: pageScales,
    forcedByCritical: forcedByCritical,
    referenceYearId: referenceYearId,
    claimedYear: claimedYear,
    scanner: scanner,
  );
}

/// Voies d'acquisition enregistrées.
abstract final class Acquisition {
  static const String fichier = 'fichier';
  static const String dossierSurveille = 'dossier_surveille';
  static const String scan = 'scan';

  /// Analyses enregistrées avant le schéma 2.
  static const String inconnue = '';

  static String label(String code) => switch (code) {
    fichier => tr('acquisition.fichier'),
    dossierSurveille => tr('acquisition.dossier_surveille'),
    scan => tr('acquisition.scan'),
    _ => tr('acquisition.inconnue'),
  };
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
    this.acquisition = Acquisition.fichier,
    this.pageScales = const [],
    this.forcedByCritical = false,
    this.referenceYearId,
    this.claimedYear,
    this.scanner = '',
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
  final String acquisition;

  /// Vide pour les analyses enregistrées avant le schéma 2.
  final List<PageScale> pageScales;
  final bool forcedByCritical;
  final String? referenceYearId;
  final int? claimedYear;
  final String scanner;

  /// Échelle de la première page (null pour les anciennes analyses).
  PageScale? get firstScale => pageScales.isEmpty ? null : pageScales.first;
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
    'schema': schemaVersion,
  };

  /// Version du format de profil. 2 : contrôles du sceau ; 3 : signature ;
  /// 4 : mise en page, position, texte ; 5 : papier, cohérence d'année.
  static const int schemaVersion = 5;

  factory VerificationProfile.fromJson(Map<String, dynamic> j) {
    final en = <CheckId>{};
    for (final n in (j['enabled'] as List? ?? const [])) {
      final c = CheckIdX.parse(n as String?);
      if (c != null) en.add(c);
    }
    // Profil enregistré avant un contrôle du référentiel : ce contrôle est
    // activé (sans année choisie, il est non applicable et ne pèse pas).
    final schema = (j['schema'] as num?)?.toInt() ?? 1;
    if (en.isNotEmpty) {
      for (final e in kCheckSinceSchema.entries) {
        if (schema < e.value) en.add(e.key);
      }
    }
    return VerificationProfile(
      id: (j['id'] as String?) ?? newId(),
      name: (j['name'] as String?) ?? 'Profil',
      enabled: en.isEmpty ? {...CheckId.values} : en,
      threshold: ((j['threshold'] as num?)?.toDouble() ?? 0.70)
          .clamp(0.4, 0.98)
          .toDouble(),
      sensitivity: ((j['sensitivity'] as num?)?.toDouble() ?? 1.0)
          .clamp(0.5, 1.5)
          .toDouble(),
      maxPages: ((j['maxPages'] as num?)?.toInt() ?? 3).clamp(1, 6).toInt(),
      renderDpi: ((j['renderDpi'] as num?)?.toInt() ?? 300)
          .clamp(100, 400)
          .toInt(),
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
        ...kReferenceChecks,
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
        ...kReferenceChecks,
      },
      maxPages: 1,
      renderDpi: 200,
    ),
  ];

  /// Réinitialise Standard, Certificats et Rapide ; conserve les profils personnalisés.
  static List<VerificationProfile> withRestoredDefaults(
    List<VerificationProfile> current,
  ) {
    final custom = current
        .where((p) => !builtInIds.contains(p.id))
        .toList(growable: false);
    return [...defaults(), ...custom];
  }
}

final _rng = Random();

String newId() {
  final t = DateTime.now().microsecondsSinceEpoch.toRadixString(16);
  final r = List.generate(
    4,
    (_) => _rng.nextInt(1 << 16).toRadixString(16),
  ).join();
  return '$t$r';
}
