import 'dart:math' as math;

import '../../core/models.dart';
import 'image_ops.dart';

/// Deux points de la même image décrits de façon quasi identique.
class MatchPair {
  const MatchPair(this.x1, this.y1, this.x2, this.y2);

  final double x1;
  final double y1;
  final double x2;
  final double y2;
}

class _Cluster {
  _Cluster(this.dx, this.dy);

  double dx;
  double dy;
  final List<MatchPair> pairs = [];

  void add(MatchPair p, double pdx, double pdy) {
    pairs.add(p);
    final n = pairs.length;
    dx += (pdx - dx) / n;
    dy += (pdy - dy) / n;
  }
}

/// Regroupe les paires de points similaires par vecteur de déplacement. Un
/// élément copié-collé (sceau, signature, bloc) produit de nombreuses paires
/// qui partagent le même déplacement.
CheckResult copyMoveFromPairs(
  List<List<MatchPair>> perPage,
  List<int> pageIndex,
  List<int> widths,
  List<int> heights,
) {
  var best = 0.0;
  final regions = <Region>[];
  var anyPairs = false;
  for (var p = 0; p < perPage.length; p++) {
    final w = widths[p];
    final h = heights[p];
    final clusters = <_Cluster>[];
    for (final m in perPage[p]) {
      anyPairs = true;
      var a = m;
      var dx = m.x2 - m.x1;
      var dy = m.y2 - m.y1;
      // Direction canonique : (i, j) et (j, i) donnent le même vecteur.
      if (dy < 0 || (dy == 0 && dx < 0)) {
        a = MatchPair(m.x2, m.y2, m.x1, m.y1);
        dx = -dx;
        dy = -dy;
      }
      if (math.sqrt(dx * dx + dy * dy) < w * 0.04) continue;
      _Cluster? found;
      for (final c in clusters) {
        if ((c.dx - dx).abs() <= 6 && (c.dy - dy).abs() <= 6) {
          found = c;
          break;
        }
      }
      if (found == null) {
        found = _Cluster(dx, dy);
        clusters.add(found);
      }
      found.add(a, dx, dy);
    }
    for (final c in clusters) {
      final n = c.pairs.length;
      if (n < 8) continue;
      double minX1 = 1e9, minY1 = 1e9, maxX1 = 0, maxY1 = 0;
      double minX2 = 1e9, minY2 = 1e9, maxX2 = 0, maxY2 = 0;
      for (final m in c.pairs) {
        minX1 = math.min(minX1, m.x1);
        minY1 = math.min(minY1, m.y1);
        maxX1 = math.max(maxX1, m.x1);
        maxY1 = math.max(maxY1, m.y1);
        minX2 = math.min(minX2, m.x2);
        minY2 = math.min(minY2, m.y2);
        maxX2 = math.max(maxX2, m.x2);
        maxY2 = math.max(maxY2, m.y2);
      }
      final bw = maxX1 - minX1;
      final bh = maxY1 - minY1;
      if (bw < w * 0.02 && bh < h * 0.02) continue; // amas ponctuel
      var s = clamp01((n - 8) / 24 + 0.3);
      final axis = c.dx.abs() < 4 || c.dy.abs() < 4;
      if (axis) s *= 0.5; // lignes de tableau répétées : prudence
      if (bw > w * 0.35 || bh > h * 0.35) s *= 0.3;
      if (s > best) best = s;
      if (s >= 0.3) {
        void add(double x0, double y0, double x1, double y1, String label) {
          final pad = 0.01;
          regions.add(
            Region(
              page: pageIndex[p],
              check: CheckId.copyMove,
              left: math.max(0.0, x0 / w - pad),
              top: math.max(0.0, y0 / h - pad),
              width: math.min(1.0, (x1 - x0) / w + 2 * pad),
              height: math.min(1.0, (y1 - y0) / h + 2 * pad),
              score: s,
              label: label,
            ),
          );
        }

        add(minX1, minY1, maxX1, maxY1, 'Élément dupliqué (original)');
        add(minX2, minY2, maxX2, maxY2, 'Élément dupliqué (copie)');
      }
    }
  }
  if (!anyPairs) {
    return CheckResult(
      id: CheckId.copyMove,
      score: 0,
      summary: 'Aucun élément répété détecté.',
    );
  }
  return CheckResult(
    id: CheckId.copyMove,
    score: best,
    summary: best >= 0.3
        ? 'Un même élément apparaît deux fois à des endroits différents.'
        : 'Aucun élément dupliqué détecté.',
    regions: regions.take(8).toList(),
  );
}
