import 'dart:math' as math;
import 'dart:typed_data';

import '../../core/models.dart';
import 'image_ops.dart';
import 'page_context.dart';

/// Cohérence du grain du papier : un collage ou une retouche locale change
/// presque toujours le bruit haute fréquence du fond.
CheckResult noiseConsistency(List<PageContext> pages) {
  var best = 0.0;
  var anyValid = false;
  final regions = <Region>[];
  for (final c in pages) {
    const cell = 24;
    final gw = c.w ~/ cell;
    final gh = c.h ~/ cell;
    if (gw < 8 || gh < 8) continue;
    final values = Float64List(gw * gh);
    final valid = Uint8List(gw * gh);
    for (var gy = 0; gy < gh; gy++) {
      for (var gx = 0; gx < gw; gx++) {
        final fx = (gx + 0.5) / gw;
        final fy = (gy + 0.5) / gh;
        if (fx < 0.03 || fx > 0.97 || fy < 0.03 || fy > 0.97) continue;
        final r = IRect(gx * cell, gy * cell, cell, cell);
        final cnt = c.flatCount.sumRect(r);
        if (cnt < 0.4 * cell * cell) continue;
        final mean = c.flatNoise.sumRect(r) / cnt;
        values[gy * gw + gx] = math.log(mean + 0.5);
        valid[gy * gw + gx] = 1;
      }
    }
    final res = analyzeGrid(
      values: values,
      valid: valid,
      gw: gw,
      gh: gh,
      cell: cell,
      imgW: c.w,
      imgH: c.h,
      zThreshold: 4.0,
      madFloor: 0.12,
    );
    if (res.valid >= 40) anyValid = true;
    if (res.score > best) best = res.score;
    for (final cl in res.clusters) {
      regions.add(
        Region(
          page: c.index,
          check: CheckId.noiseConsistency,
          left: cl.rect.x / c.w,
          top: cl.rect.y / c.h,
          width: cl.rect.w / c.w,
          height: cl.rect.h / c.h,
          score: clamp01(0.25 + 0.05 * (cl.meanZ - 4)),
          label: 'Grain du papier différent du reste de la page',
        ),
      );
    }
  }
  if (!anyValid) {
    return const CheckResult(
      id: CheckId.noiseConsistency,
      score: 0,
      skipped: true,
      summary:
          'Fond trop chargé (motifs, filigrane) pour comparer le grain du papier.',
    );
  }
  final summary = best < 0.2
      ? 'Grain du papier homogène sur la page.'
      : 'Zone(s) dont le grain diffère du reste du papier.';
  return CheckResult(
    id: CheckId.noiseConsistency,
    score: best,
    summary: summary,
    regions: regions.where((r) => best >= 0.2).take(8).toList(),
  );
}

/// Analyse des niveaux d'erreur (ELA) : on recompresse l'image en JPEG et on
/// regarde où l'écart est anormalement fort ou faible par rapport au papier
/// voisin. Signal faible : il sert surtout en renfort des autres contrôles.
CheckResult errorLevelAnalysis(
  List<PageContext> pages,
  List<Uint8List?> recompressed,
) {
  var best = 0.0;
  var anyValid = false;
  final regions = <Region>[];
  for (var p = 0; p < pages.length; p++) {
    final c = pages[p];
    final re = recompressed[p];
    if (re == null || re.length != c.gray.length) continue;
    final ela = Uint8List(c.gray.length);
    for (var i = 0; i < ela.length; i++) {
      ela[i] = (c.gray[i] - re[i]).abs();
    }
    final elaInt = Integral.masked(ela, c.flat, c.w, c.h);
    const cell = 32;
    final gw = c.w ~/ cell;
    final gh = c.h ~/ cell;
    if (gw < 8 || gh < 8) continue;
    final values = Float64List(gw * gh);
    final valid = Uint8List(gw * gh);
    for (var gy = 0; gy < gh; gy++) {
      for (var gx = 0; gx < gw; gx++) {
        final fx = (gx + 0.5) / gw;
        final fy = (gy + 0.5) / gh;
        if (fx < 0.03 || fx > 0.97 || fy < 0.03 || fy > 0.97) continue;
        final r = IRect(gx * cell, gy * cell, cell, cell);
        final cnt = c.flatCount.sumRect(r);
        if (cnt < 0.4 * cell * cell) continue;
        values[gy * gw + gx] = math.log(elaInt.sumRect(r) / cnt + 0.3);
        valid[gy * gw + gx] = 1;
      }
    }
    final res = analyzeGrid(
      values: values,
      valid: valid,
      gw: gw,
      gh: gh,
      cell: cell,
      imgW: c.w,
      imgH: c.h,
      zThreshold: 4.5,
      madFloor: 0.2,
      minCells: 4,
    );
    if (res.valid >= 40) anyValid = true;
    if (res.score > best) best = res.score;
    for (final cl in res.clusters) {
      regions.add(
        Region(
          page: c.index,
          check: CheckId.ela,
          left: cl.rect.x / c.w,
          top: cl.rect.y / c.h,
          width: cl.rect.w / c.w,
          height: cl.rect.h / c.h,
          score: clamp01(0.25 + 0.05 * (cl.meanZ - 4.5)),
          label: 'Niveau de recompression différent du papier voisin',
        ),
      );
    }
  }
  if (!anyValid) {
    return const CheckResult(
      id: CheckId.ela,
      score: 0,
      skipped: true,
      summary: 'Analyse ELA indisponible pour ce document.',
    );
  }
  return CheckResult(
    id: CheckId.ela,
    score: best,
    summary: best < 0.2
        ? 'Recompression homogène.'
        : 'Zone(s) à recompression différente.',
    regions: regions.where((r) => best >= 0.2).take(6).toList(),
  );
}
