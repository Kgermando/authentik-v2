import 'dart:async';
import 'dart:isolate';
import 'dart:math' as math;
import '../../core/models.dart';
import '../../core/scoring.dart';
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
  });

  final int index;
  final int width;
  final int height;

  /// "bgra" ou "encoded".
  final String kind;
  final TransferableTypedData data;
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
  });

  final String id;
  final String fileName;
  final String source;
  final String sha256;
  final List<PageInput> pages;
  final Map<String, dynamic> profile;
  final FileMeta meta;
  final List<String> warnings;
}

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
    final r = analyzeSync(
      job,
      (f, s) => send.send(['progress', f, s]),
    );
    send.send(['done', r]);
  } catch (e, st) {
    send.send(['error', '$e\n$st']);
  }
}

/// Analyse complète, synchrone (appelée dans l'isolat, ou directement en test).
AnalysisResult analyzeSync(AnalysisJob job, ProgressCallback progress) {
  final sw = Stopwatch()..start();
  final profile = VerificationProfile.fromJson(job.profile);
  final on = profile.enabled;
  final warnings = [...job.warnings];

  progress(0.02, 'Préparation des pages');
  final pages = <PageContext>[];
  final previews = <PagePreview>[];
  for (var i = 0; i < job.pages.length; i++) {
    final p = job.pages[i];
    final bytes = p.data.materialize().asUint8List();
    final img = p.kind == 'bgra'
        ? cvx.bgraToBgr(bytes, p.width, p.height)
        : cvx.decodeImage(bytes);
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
    _pageWarnings(ctx, img, p.index, job.pages.length > 1, warnings);
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

  if (on.contains(CheckId.metadata)) {
    progress(0.25, 'Lecture des métadonnées');
    results.add(metadataCheck(job.meta));
    tick('Métadonnées vérifiées');
  }

  List<OverlayResult>? perPage;
  if (steps.contains('overlay')) {
    progress(0.3, 'Recherche des sceaux et signatures');
    perPage = [for (final c in pages) detectOverlays(c)];
    if (on.contains(CheckId.sealOverlay)) {
      results.add(
        overlayCheckResult(
          CheckId.sealOverlay,
          [for (final o in perPage) o.seals],
          pages,
        ),
      );
    }
    if (on.contains(CheckId.signatureOverlay)) {
      results.add(
        overlayCheckResult(
          CheckId.signatureOverlay,
          [for (final o in perPage) o.signatures],
          pages,
        ),
      );
    }
    tick('Sceaux et signatures analysés');
  }

  if (on.contains(CheckId.textConsistency)) {
    progress(0.5, 'Comparaison de l’encre et des dates');
    final excl = [
      for (var i = 0; i < pages.length; i++)
        [
          ...?perPage?[i].seals.map((e) => e.rect),
          ...?perPage?[i].signatures.map((e) => e.rect),
        ],
    ];
    results.add(textConsistency(pages, excl));
    tick('Texte et dates analysés');
  }

  if (on.contains(CheckId.noiseConsistency)) {
    progress(0.65, 'Cohérence du grain du papier');
    results.add(noiseConsistency(pages));
    tick('Grain du papier analysé');
  }

  if (on.contains(CheckId.ela)) {
    progress(0.75, 'Niveaux de compression');
    final re = [
      for (final c in pages) cvx.recompressGray(c.gray, c.w, c.h),
    ];
    results.add(errorLevelAnalysis(pages, re));
    tick('Compression analysée');
  }

  if (on.contains(CheckId.copyMove)) {
    progress(0.85, 'Recherche d’éléments dupliqués');
    final pairs = [
      for (final c in pages) cvx.orbSelfMatches(c.gray, c.w, c.h),
    ];
    results.add(
      copyMoveFromPairs(
        pairs,
        [for (final c in pages) c.index],
        [for (final c in pages) c.w],
        [for (final c in pages) c.h],
      ),
    );
    tick('Duplications recherchées');
  }

  progress(0.97, 'Calcul du score');
  final p = Scoring.combine(results, profile);
  final verdict = Scoring.verdict(p, profile.threshold);
  sw.stop();
  progress(1.0, 'Terminé');

  return AnalysisResult(
    id: job.id,
    fileName: job.fileName,
    sha256: job.sha256,
    source: job.source,
    createdAt: DateTime.now(),
    elapsedMs: sw.elapsedMilliseconds,
    probability: p,
    verdict: verdict,
    threshold: profile.threshold,
    profileName: profile.name,
    checks: results,
    warnings: warnings,
    previews: previews,
  );
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
  if (shortSide < 1000) {
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
  var sum = 0.0;
  for (var i = 0; i < c.grad.length; i += 7) {
    sum += c.grad[i];
  }
  final meanGrad = sum / (c.grad.length / 7);
  if (meanGrad < 1.2) {
    out.add('${label}image floue : fiabilité réduite.');
  }
}
