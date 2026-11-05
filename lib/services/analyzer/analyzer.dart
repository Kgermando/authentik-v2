import 'dart:async';
import 'dart:isolate';
import 'dart:math' as math;
import '../../core/i18n.dart';
import '../../core/models.dart';
import '../../core/page_scale.dart';
import '../../core/scoring.dart';
import '../../core/scoring_params.dart';
import '../reference/ref_image.dart';
import '../reference/reference_checks.dart';
import '../reference/reference_context.dart';
import 'copy_move.dart';
import 'cv_adapter.dart' as cvx;
import 'grid_checks.dart';
import 'metadata_check.dart';
import 'overlay_check.dart';
import 'page_context.dart';
import 'text_check.dart';

/// Une page à analyser : soit déjà rendue en BGRA (PDF), soit encodée (image).
class PageInput {
  PageInput({
    required this.index,
    required this.width,
    required this.height,
    required this.kind,
    required this.data,
    this.declaredDpi,
    this.pageWidthPt,
    this.pageHeightPt,
  });

  final int index;
  final int width;
  final int height;

  /// "bgra" ou "encoded".
  final String kind;
  final TransferableTypedData data;

  /// Résolution lue dans l'en-tête de l'image (null si absente).
  final DeclaredDpi? declaredDpi;

  /// Taille de la page PDF en points (null pour une image).
  final double? pageWidthPt;
  final double? pageHeightPt;
}

class AnalysisJob {
  AnalysisJob({
    required this.id,
    required this.fileName,
    required this.source,
    required this.sha256,
    required this.pages,
    required this.profile,
    required this.meta,
    required this.warnings,
    this.acquisition = Acquisition.fichier,
    this.texts = const {},
    this.reference,
    this.identicalOriginal,
  });

  /// Même tâche avec le référentiel chargé et l'original identique trouvé.
  AnalysisJob withReference(
    ReferenceContext? reference, {
    KnownOriginal? identicalOriginal,
  }) => AnalysisJob(
    id: id,
    fileName: fileName,
    source: source,
    sha256: sha256,
    pages: pages,
    profile: profile,
    meta: meta,
    warnings: warnings,
    acquisition: acquisition,
    texts: texts,
    reference: reference,
    identicalOriginal: identicalOriginal,
  );

  final String id;
  final String fileName;
  final String source;
  final String sha256;
  final List<PageInput> pages;
  final Map<String, dynamic> profile;
  final FileMeta meta;
  final List<String> warnings;

  /// Voie d'acquisition (fichier, dossier surveillé, scanner).
  final String acquisition;

  /// Textes d'interface (l'isolat d'analyse ne lit pas les assets).
  final Map<String, String> texts;

  /// Référentiel de l'année d'émission choisie (null : aucune année).
  final ReferenceContext? reference;

  /// Original du référentiel dont le fichier analysé est la copie exacte
  /// (même SHA-256), pour l'année chargée.
  final KnownOriginal? identicalOriginal;
}

/// Original enregistré reconnu (fichier identique).
class KnownOriginal {
  const KnownOriginal({
    required this.specimenId,
    required this.label,
    required this.year,
  });

  final String specimenId;
  final String label;
  final int year;
}

/// Contrôles du référentiel qui concluent à une copie ou une modification
/// d'un original.
const _copyChecks = {
  CheckId.sealCopy,
  CheckId.signatureCopy,
  CheckId.originalModified,
};

/// Le document est un original du référentiel (fichier identique, ou rescan
/// sans aucune différence locale au-delà du bruit de scan) :
/// - fichier identique : les contrôles de copie ne peuvent pas conclure à une
///   copie frauduleuse de lui-même ;
/// - les indices génériques (métadonnées, encre, grain, compression…) sont
///   aussi présents sur l'original validé : ils ne peuvent pas signaler une
///   falsification et ne pèsent plus, mesure conservée pour la traçabilité.
List<CheckResult> neutralizeForOriginal(
  List<CheckResult> results, {
  required String label,
  required bool identicalFile,
}) => [
  for (final r in results)
    if (identicalFile &&
        _copyChecks.contains(r.id) &&
        (r.status == CheckStatus.failed || r.status == CheckStatus.warning))
      CheckResult(
        id: r.id,
        score: 0,
        status: CheckStatus.passed,
        confidence: r.confidence,
        summary: tr('ref.fichier_identique', {'original': label}),
        version: r.version,
        durationMs: r.durationMs,
        critical: r.critical,
        details: {...r.details, 'fichier_identique': true},
      )
    else if (r.status == null && !r.skipped && r.score > 0)
      CheckResult(
        id: r.id,
        score: r.score,
        status: CheckStatus.notApplicable,
        summary: tr('ref.indice_original', {
          'original': label,
          'mesure': r.summary,
        }),
        version: r.version,
        durationMs: r.durationMs,
        details: {
          ...r.details,
          'neutralise_original': label,
          'score_mesure': r.score,
        },
      )
    else
      r,
];

typedef ProgressCallback = void Function(double fraction, String stage);

/// Lance l'analyse dans un isolat séparé : l'interface reste fluide.
Future<AnalysisResult> runAnalysis(
  AnalysisJob job,
  ProgressCallback onProgress,
) async {
  final port = ReceivePort();
  final done = Completer<AnalysisResult>();
  final sub = port.listen((m) {
    if (m == null) {
      // L'isolat s'est arrêté sans résultat (plantage natif, mémoire).
      if (!done.isCompleted) {
        done.completeError('Analyse interrompue (mémoire insuffisante ?).');
      }
      return;
    }
    if (m is List && m.isNotEmpty) {
      switch (m[0]) {
        case 'progress':
          onProgress((m[1] as num).toDouble(), m[2] as String);
        case 'done':
          if (!done.isCompleted) done.complete(m[1] as AnalysisResult);
        case 'error':
          if (!done.isCompleted) done.completeError(m[1] as String);
        default:
          // Erreur non rattrapée : [message, trace].
          if (!done.isCompleted) done.completeError('${m[0]}');
      }
    }
  });
  Isolate? iso;
  try {
    iso = await Isolate.spawn<List<Object>>(
      _entry,
      [port.sendPort, job],
      onError: port.sendPort,
      onExit: port.sendPort,
      errorsAreFatal: true,
    );
    return await done.future;
  } finally {
    await sub.cancel();
    port.close();
    iso?.kill(priority: Isolate.immediate);
  }
}

void _entry(List<Object> args) {
  final send = args[0] as SendPort;
  final job = args[1] as AnalysisJob;
  try {
    final r = analyzeSync(job, (f, s) => send.send(['progress', f, s]));
    send.send(['done', r]);
  } catch (e, st) {
    send.send(['error', '$e\n$st']);
  }
}

/// Analyse complète, synchrone (appelée dans l'isolat, ou directement en test).
AnalysisResult analyzeSync(AnalysisJob job, ProgressCallback progress) {
  final sw = Stopwatch()..start();
  if (job.texts.isNotEmpty && !Textes.loaded) Textes.load(job.texts);
  final profile = VerificationProfile.fromJson(job.profile);
  final on = profile.enabled;
  final warnings = [...job.warnings];

  progress(0.02, 'Préparation des pages');
  final pages = <PageContext>[];
  final previews = <PagePreview>[];
  final scales = <PageScale>[];
  final qualityNotes = <String>[];
  // Page pleine résolution pour le référentiel (sceau, empreinte de page) :
  // première page seulement, et seulement si une année est choisie.
  RefImage? refPage;
  for (var i = 0; i < job.pages.length; i++) {
    final p = job.pages[i];
    final bytes = p.data.materialize().asUint8List();
    final cvx.BgrImage img;
    if (i == 0 && job.reference != null) {
      final full = p.kind == 'bgra'
          ? cvx.bgraToBgr(bytes, p.width, p.height, maxSide: cvx.kFullSide)
          : cvx.decodeImage(bytes, maxSide: cvx.kFullSide);
      refPage = RefImage(full.w, full.h, full.bgr);
      img = cvx.shrink(full);
    } else {
      img = p.kind == 'bgra'
          ? cvx.bgraToBgr(bytes, p.width, p.height)
          : cvx.decodeImage(bytes);
    }
    final ctx = PageContext(p.index, img.w, img.h, img.bgr);
    pages.add(ctx);
    previews.add(
      PagePreview(
        index: p.index,
        width: img.w,
        height: img.h,
        jpeg: cvx.encodePreview(img),
      ),
    );
    final multi = job.pages.length > 1;
    _pageWarnings(ctx, img, p.index, multi, warnings);
    final scale = _pageScale(p, img);
    scales.add(scale);
    _scaleWarning(scale, p.index, multi, warnings);
    _pageQuality(ctx, img, p.index, multi, qualityNotes);
    progress(0.02 + 0.2 * (i + 1) / job.pages.length, 'Préparation des pages');
  }

  // Étapes réellement actives, pour un pourcentage de progression honnête.
  final steps = <String>[
    if (on.contains(CheckId.metadata)) 'metadata',
    if (on.contains(CheckId.sealOverlay) ||
        on.contains(CheckId.signatureOverlay) ||
        on.contains(CheckId.textConsistency))
      'overlay',
    if (on.contains(CheckId.textConsistency)) 'text',
    if (on.contains(CheckId.noiseConsistency)) 'noise',
    if (on.contains(CheckId.ela)) 'ela',
    if (on.contains(CheckId.copyMove)) 'copy',
  ];
  var done = 0;
  void tick(String label) {
    done++;
    progress(0.25 + 0.7 * done / math.max(1, steps.length), label);
  }

  final results = <CheckResult>[];
  final t = Stopwatch();
  void add(CheckResult r) => results.add(r.timed(t.elapsedMilliseconds));

  if (on.contains(CheckId.metadata)) {
    progress(0.25, 'Lecture des métadonnées');
    t
      ..reset()
      ..start();
    add(metadataCheck(job.meta));
    tick('Métadonnées vérifiées');
  }

  List<OverlayResult>? perPage;
  if (steps.contains('overlay')) {
    progress(0.3, 'Recherche des sceaux et signatures');
    // La détection est commune au sceau et à la signature : sa durée est
    // comptée dans chacun des deux contrôles.
    t
      ..reset()
      ..start();
    perPage = [for (final c in pages) detectOverlays(c)];
    final shared = t.elapsedMilliseconds;
    if (on.contains(CheckId.sealOverlay)) {
      t
        ..reset()
        ..start();
      final r = overlayCheckResult(CheckId.sealOverlay, [
        for (final o in perPage) o.seals,
      ], pages);
      results.add(r.timed(shared + t.elapsedMilliseconds));
    }
    if (on.contains(CheckId.signatureOverlay)) {
      t
        ..reset()
        ..start();
      final r = overlayCheckResult(CheckId.signatureOverlay, [
        for (final o in perPage) o.signatures,
      ], pages);
      results.add(r.timed(shared + t.elapsedMilliseconds));
    }
    tick('Sceaux et signatures analysés');
  }

  if (on.contains(CheckId.textConsistency)) {
    progress(0.5, 'Comparaison de l’encre et des dates');
    t
      ..reset()
      ..start();
    final excl = [
      for (var i = 0; i < pages.length; i++)
        [
          ...?perPage?[i].seals.map((e) => e.rect),
          ...?perPage?[i].signatures.map((e) => e.rect),
        ],
    ];
    add(textConsistency(pages, excl));
    tick('Texte et dates analysés');
  }

  if (on.contains(CheckId.noiseConsistency)) {
    progress(0.65, 'Cohérence du grain du papier');
    t
      ..reset()
      ..start();
    add(noiseConsistency(pages));
    tick('Grain du papier analysé');
  }

  if (on.contains(CheckId.ela)) {
    progress(0.75, 'Niveaux de compression');
    t
      ..reset()
      ..start();
    final re = [for (final c in pages) cvx.recompressGray(c.gray, c.w, c.h)];
    add(errorLevelAnalysis(pages, re));
    tick('Compression analysée');
  }

  if (on.contains(CheckId.copyMove)) {
    progress(0.85, 'Recherche d’éléments dupliqués');
    t
      ..reset()
      ..start();
    final pairs = [for (final c in pages) cvx.orbSelfMatches(c.gray, c.w, c.h)];
    add(
      copyMoveFromPairs(
        pairs,
        [for (final c in pages) c.index],
        [for (final c in pages) c.w],
        [for (final c in pages) c.h],
      ),
    );
    tick('Duplications recherchées');
  }

  // Référentiel annuel : non applicable sans année choisie.
  var referenceUnusable = false;
  if (on.any(kReferenceChecks.contains)) {
    progress(0.9, 'Comparaison au référentiel de l’année');
    final outcome = runReferenceChecks(
      ctx: job.reference,
      page: refPage,
      scale: scales.isEmpty ? null : scales.first,
      acquisition: job.acquisition,
    );
    for (final r in outcome.results) {
      if (on.contains(r.id)) results.add(r);
    }
    // Fichier identique à un original : c'est cet original lui-même, ce qui
    // ne dépend pas du nombre d'originaux de l'année (pas de « non
    // concluant » pour référentiel insuffisant).
    final identical = job.identicalOriginal;
    final ctx = job.reference;
    final insufficient = {
      if (ctx != null) ...[
        tr('ref.non_concluant', {'annee': ctx.claimedYear}),
        tr('ref.non_concluant', {'annee': ctx.yearLabel}),
      ],
    };
    referenceUnusable = outcome.unusable && identical == null;
    warnings.addAll(
      identical == null
          ? outcome.notes
          : outcome.notes.where((n) => !insufficient.contains(n)),
    );

    // Document reconnu comme un original du référentiel.
    String? originalLabel = identical?.label;
    if (originalLabel == null && outcome.rescanOf != null) {
      for (final p in job.reference?.prints ?? const <SpecimenPrint>[]) {
        if (p.specimenId == outcome.rescanOf) originalLabel = p.label;
      }
    }
    if (originalLabel != null) {
      final neutral = neutralizeForOriginal(
        results,
        label: originalLabel,
        identicalFile: identical != null,
      );
      results
        ..clear()
        ..addAll(neutral);
      warnings.add(
        tr(
          identical != null ? 'ref.note_fichier_identique' : 'ref.note_rescan',
          {'original': originalLabel},
        ),
      );
    }
  }

  progress(0.97, 'Calcul du score');
  final decision = Scoring.decide(
    results,
    profile,
    qualityInsufficient: qualityNotes.isNotEmpty || referenceUnusable,
  );
  warnings
    ..addAll(qualityNotes)
    ..addAll(decision.notes);
  sw.stop();
  progress(1.0, 'Terminé');

  return AnalysisResult(
    id: job.id,
    fileName: job.fileName,
    sha256: job.sha256,
    source: job.source,
    createdAt: DateTime.now(),
    elapsedMs: sw.elapsedMilliseconds,
    probability: decision.probability,
    verdict: decision.verdict,
    threshold: profile.threshold,
    profileName: profile.name,
    checks: results,
    warnings: warnings,
    previews: previews,
    acquisition: job.acquisition,
    pageScales: scales,
    forcedByCritical: decision.forcedByCritical,
    qualityInsufficient: qualityNotes.isNotEmpty,
    referenceYearId: job.reference?.yearId,
    claimedYear: job.reference?.claimedYear,
    calibrationIds: job.reference?.calibrationIds ?? const [],
  );
}

/// Gradient moyen d'une page (un pixel sur sept), calcul d'origine.
double _meanGradient(PageContext c) {
  var sum = 0.0;
  for (var i = 0; i < c.grad.length; i += 7) {
    sum += c.grad[i];
  }
  return sum / (c.grad.length / 7);
}

void _pageWarnings(
  PageContext c,
  cvx.BgrImage img,
  int index,
  bool multi,
  List<String> out,
) {
  final label = multi ? 'Page ${index + 1} : ' : '';
  final shortSide = math.min(img.srcW, img.srcH);
  if (shortSide < ScoringParams.minShortSidePx) {
    out.add(
      '${label}résolution faible (${img.srcW}×${img.srcH}). '
      'Rescannez à 300 DPI minimum pour une analyse fiable.',
    );
  }
  if (c.flatFraction < 0.15) {
    out.add(
      '${label}fond très chargé (motifs, filigrane) : le contrôle du grain du '
      'papier et des ruptures de fond est moins fiable.',
    );
  }
  if (c.paperGray < 140) {
    out.add('${label}scan sombre ou peu contrasté : fiabilité réduite.');
  }
  if (_meanGradient(c) < ScoringParams.blurMeanGradient) {
    out.add('${label}image floue : fiabilité réduite.');
  }
}

/// Qualité insuffisante pour conclure : résolution trop basse, ou page floue
/// qui n'est pas blanche (un verso blanc n'a pas de contours, il n'est pas
/// « flou »).
void _pageQuality(
  PageContext c,
  cvx.BgrImage img,
  int index,
  bool multi,
  List<String> out,
) {
  final prefixe = multi ? tr('page.prefixe', {'n': index + 1}) : '';
  if (math.min(img.srcW, img.srcH) < ScoringParams.minShortSidePx) {
    out.add(
      tr('qualite.insuffisante.resolution', {
        'prefixe': prefixe,
        'w': img.srcW,
        'h': img.srcH,
      }),
    );
    return;
  }
  final blank = c.flatFraction >= ScoringParams.blankPageFlatFraction;
  if (!blank && _meanGradient(c) < ScoringParams.blurMeanGradient) {
    out.add(tr('qualite.insuffisante.floue', {'prefixe': prefixe}));
  }
}

/// Échelle physique de la page source (avant réduction pour l'analyse).
PageScale _pageScale(PageInput p, cvx.BgrImage img) {
  final wPt = p.pageWidthPt;
  final hPt = p.pageHeightPt;
  if (wPt != null && hPt != null && wPt > 0 && hPt > 0) {
    return PageScale.fromPdf(
      pxW: img.srcW,
      pxH: img.srcH,
      widthPt: wPt,
      heightPt: hPt,
    );
  }
  return PageScale.fromImage(
    pxW: img.srcW,
    pxH: img.srcH,
    declared: p.declaredDpi,
  );
}

void _scaleWarning(PageScale s, int index, bool multi, List<String> out) {
  if (s.reliability != ScaleReliability.incertain) return;
  out.add(
    tr('dpi.incertain', {
      'prefixe': multi ? tr('page.prefixe', {'n': index + 1}) : '',
      'wmm': s.widthMm.round(),
      'hmm': s.heightMm.round(),
      'dpi': s.dpi.round(),
    }),
  );
}
