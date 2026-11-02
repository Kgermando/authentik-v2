import 'dart:math' as math;
import 'dart:typed_data';

import '../../core/models.dart';
import 'image_ops.dart';
import 'page_context.dart';

/// Élément (sceau ou signature) candidat à une superposition.
class OverlayCandidate {
  OverlayCandidate({
    required this.rect,
    required this.kind,
    required this.score,
    required this.grayStep,
    required this.tintStep,
    required this.noiseStep,
  });

  final IRect rect;

  /// "seal" ou "signature".
  final String kind;

  /// 0..1 — indice qu'il s'agit d'un élément collé.
  final double score;

  /// Plus forte marche de niveau de gris autour de l'élément (niveaux 0..255).
  final double grayStep;

  /// Plus forte marche de teinte du papier.
  final double tintStep;

  /// Plus forte marche de grain (rapport logarithmique).
  final double noiseStep;
}

class OverlayResult {
  OverlayResult(this.seals, this.signatures);

  final List<OverlayCandidate> seals;
  final List<OverlayCandidate> signatures;
}

/// Détecte les sceaux (encre colorée) et les signatures (grand tracé continu
/// sombre) puis mesure, autour de chacun, les ruptures de fond de papier.
///
/// Principe : sur un vrai document, le papier autour d'un tampon est continu.
/// Quand un tampon ou une signature est copié depuis un autre document puis
/// collé, la découpe laisse une rupture (niveau de gris, teinte, grain) à la
/// frontière du collage. On mesure cette rupture sur des anneaux successifs
/// autour de l'élément et on garde la plus forte marche, corrigée de la
/// variation naturelle du fond.
OverlayResult detectOverlays(PageContext c) {
  final seals = _sealCandidates(c);
  final sigs = _signatureCandidates(c, seals);
  return OverlayResult(
    [for (final r in seals) _evaluate(c, r, 'seal')],
    [for (final r in sigs) _evaluate(c, r, 'signature')],
  );
}

List<IRect> _sealCandidates(PageContext c) {
  final satThr = math.max(60.0, c.paperSat + 40).toInt();
  final mask = Uint8List(c.w * c.h);
  for (var i = 0; i < mask.length; i++) {
    if (c.sat[i] > satThr && c.gray[i] > 35) mask[i] = 1;
  }
  final r = math.max(2, (c.w * 0.006).round());
  final closed = closeMask(mask, c.w, c.h, r);
  final lab = labelComponents(closed, c.w, c.h, minArea: 200);
  final minSide = c.w * 0.035;
  final maxSide = c.w * 0.6;
  final out = <IRect>[];
  for (final comp in lab.comps) {
    if (comp.w < minSide || comp.h < minSide) continue;
    if (comp.w > maxSide || comp.h > maxSide) continue;
    if (comp.fill < 0.05) continue;
    out.add(comp.rect);
  }
  out.sort((a, b) => b.area.compareTo(a.area));
  return out.take(6).toList();
}

List<IRect> _signatureCandidates(PageContext c, List<IRect> sealRects) {
  final thr = c.paperGray * 0.62;
  final mask = Uint8List(c.w * c.h);
  for (var i = 0; i < mask.length; i++) {
    if (c.gray[i] < thr) mask[i] = 1;
  }
  final lab = labelComponents(mask, c.w, c.h, minArea: 120);
  final out = <IRect>[];
  for (final comp in lab.comps) {
    final w = comp.w;
    final h = comp.h;
    if (w < c.w * 0.05 || h < c.h * 0.012) continue;
    if (w > c.w * 0.45 || h > c.h * 0.2) continue;
    final aspect = w / h;
    if (aspect < 1.1 || aspect > 12) continue;
    if (comp.fill > 0.45 || comp.fill < 0.02) continue;
    final rect = comp.rect;
    if (sealRects.any((s) => rect.overlapRatio(s) > 0.5)) continue;
    out.add(rect);
  }
  out.sort((a, b) => b.area.compareTo(a.area));
  return out.take(6).toList();
}

OverlayCandidate _evaluate(PageContext c, IRect box, String kind) {
  final unit = math.max(6, (math.max(box.w, box.h) * 0.05).round());
  final rects = <IRect>[
    for (var k = 0; k <= 6; k++) box.expand(3 + k * unit, c.w, c.h),
  ];
  final rings = <FlatStats?>[
    for (var k = 0; k < 6; k++) c.ringStats(rects[k], rects[k + 1]),
  ];

  final gSteps = <double>[];
  final tSteps = <double>[];
  final nSteps = <double>[];
  for (var k = 0; k < rings.length - 1; k++) {
    final a = rings[k];
    final b = rings[k + 1];
    if (a == null || b == null) continue;
    gSteps.add((a.gray - b.gray).abs());
    tSteps.add((a.tint - b.tint).abs());
    nSteps.add((math.log(a.noise + 0.5) - math.log(b.noise + 0.5)).abs());
  }
  if (gSteps.length < 2) {
    return OverlayCandidate(
      rect: box,
      kind: kind,
      score: 0,
      grayStep: 0,
      tintStep: 0,
      noiseStep: 0,
    );
  }
  double eff(List<double> s) {
    final m = median(s);
    return math.max(0.0, s.reduce(math.max) - m);
  }

  final g = eff(gSteps);
  final t = eff(tSteps);
  final n = eff(nSteps);
  final halo = math.max(clamp01((g - 2.0) / 8.0), clamp01((t - 2.5) / 10.0));
  final noise = clamp01((n - 0.35) / 0.8);
  final score = clamp01(1 - (1 - 0.9 * halo) * (1 - 0.55 * noise));
  return OverlayCandidate(
    rect: box,
    kind: kind,
    score: score,
    grayStep: g,
    tintStep: t,
    noiseStep: n,
  );
}

/// Transforme les candidats d'une page en résultat de contrôle.
CheckResult overlayCheckResult(
  CheckId id,
  List<List<OverlayCandidate>> perPage,
  List<PageContext> pages,
) {
  var best = 0.0;
  final regions = <Region>[];
  var found = 0;
  for (var p = 0; p < perPage.length; p++) {
    final ctx = pages[p];
    for (final cand in perPage[p]) {
      found++;
      if (cand.score > best) best = cand.score;
      if (cand.score >= 0.30) {
        regions.add(
          Region(
            page: ctx.index,
            check: id,
            left: cand.rect.x / ctx.w,
            top: cand.rect.y / ctx.h,
            width: cand.rect.w / ctx.w,
            height: cand.rect.h / ctx.h,
            score: cand.score,
            label: id == CheckId.sealOverlay
                ? 'Sceau : rupture de fond autour du tampon'
                : 'Signature : rupture de fond autour du tracé',
          ),
        );
      }
    }
  }
  final what = id == CheckId.sealOverlay ? 'sceau' : 'signature';
  final summary = found == 0
      ? 'Aucun $what détecté sur les pages analysées.'
      : best >= 0.30
          ? '$found $what(x) détecté(s), rupture de fond suspecte (${(best * 100).round()} %).'
          : '$found $what(x) détecté(s), fond continu autour de chacun.';
  return CheckResult(id: id, score: best, summary: summary, regions: regions);
}
