// Primitives d'image en Dart pur (sans OpenCV), pour pouvoir tester les
// algorithmes sans bibliothèque native : images intégrales, morphologie
// binaire, composantes connexes, statistiques robustes.
import 'dart:math' as math;
import 'dart:typed_data';

/// Rectangle d'entiers [x, x+w) × [y, y+h).
class IRect {
  const IRect(this.x, this.y, this.w, this.h);

  final int x;
  final int y;
  final int w;
  final int h;

  int get right => x + w;
  int get bottom => y + h;
  int get area => w * h;
  double get cx => x + w / 2;
  double get cy => y + h / 2;

  IRect expand(int d, int maxW, int maxH) {
    final x0 = math.max(0, x - d);
    final y0 = math.max(0, y - d);
    final x1 = math.min(maxW, right + d);
    final y1 = math.min(maxH, bottom + d);
    return IRect(x0, y0, math.max(0, x1 - x0), math.max(0, y1 - y0));
  }

  int intersectionArea(IRect o) {
    final x0 = math.max(x, o.x);
    final y0 = math.max(y, o.y);
    final x1 = math.min(right, o.right);
    final y1 = math.min(bottom, o.bottom);
    if (x1 <= x0 || y1 <= y0) return 0;
    return (x1 - x0) * (y1 - y0);
  }

  double overlapRatio(IRect o) {
    final i = intersectionArea(o);
    if (i == 0) return 0;
    return i / math.min(area, o.area);
  }

  @override
  String toString() => 'IRect($x,$y,$w,$h)';
}

/// Image intégrale en double précision : somme de n'importe quel rectangle en O(1).
class Integral {
  Integral._(this.w, this.h, this._s);

  factory Integral.bytes(Uint8List v, int w, int h) {
    final s = Float64List((w + 1) * (h + 1));
    for (var y = 0; y < h; y++) {
      var row = 0.0;
      final o = (y + 1) * (w + 1);
      final p = y * (w + 1);
      for (var x = 0; x < w; x++) {
        row += v[y * w + x];
        s[o + x + 1] = s[p + x + 1] + row;
      }
    }
    return Integral._(w, h, s);
  }

  factory Integral.floats(Float32List v, int w, int h) {
    final s = Float64List((w + 1) * (h + 1));
    for (var y = 0; y < h; y++) {
      var row = 0.0;
      final o = (y + 1) * (w + 1);
      final p = y * (w + 1);
      for (var x = 0; x < w; x++) {
        row += v[y * w + x];
        s[o + x + 1] = s[p + x + 1] + row;
      }
    }
    return Integral._(w, h, s);
  }

  /// Somme de `v` sur les pixels où `mask != 0`.
  factory Integral.masked(Uint8List v, Uint8List mask, int w, int h) {
    final s = Float64List((w + 1) * (h + 1));
    for (var y = 0; y < h; y++) {
      var row = 0.0;
      final o = (y + 1) * (w + 1);
      final p = y * (w + 1);
      for (var x = 0; x < w; x++) {
        final i = y * w + x;
        if (mask[i] != 0) row += v[i];
        s[o + x + 1] = s[p + x + 1] + row;
      }
    }
    return Integral._(w, h, s);
  }

  factory Integral.maskedFloats(
    Float32List v,
    Uint8List mask,
    int w,
    int h,
  ) {
    final s = Float64List((w + 1) * (h + 1));
    for (var y = 0; y < h; y++) {
      var row = 0.0;
      final o = (y + 1) * (w + 1);
      final p = y * (w + 1);
      for (var x = 0; x < w; x++) {
        final i = y * w + x;
        if (mask[i] != 0) row += v[i];
        s[o + x + 1] = s[p + x + 1] + row;
      }
    }
    return Integral._(w, h, s);
  }

  final int w;
  final int h;
  final Float64List _s;

  /// Somme sur [x0, x1) × [y0, y1), bornée à l'image.
  double sum(int x0, int y0, int x1, int y1) {
    x0 = x0.clamp(0, w).toInt();
    x1 = x1.clamp(0, w).toInt();
    y0 = y0.clamp(0, h).toInt();
    y1 = y1.clamp(0, h).toInt();
    if (x1 <= x0 || y1 <= y0) return 0;
    final W = w + 1;
    return _s[y1 * W + x1] - _s[y0 * W + x1] - _s[y1 * W + x0] + _s[y0 * W + x0];
  }

  double sumRect(IRect r) => sum(r.x, r.y, r.right, r.bottom);
}

/// Dilatation binaire par fenêtre carrée de côté 2r+1 (O(n)).
Uint8List dilate(Uint8List m, int w, int h, int r) {
  if (r <= 0) return Uint8List.fromList(m);
  final tmp = Uint8List(w * h);
  for (var y = 0; y < h; y++) {
    final o = y * w;
    var cnt = 0;
    for (var x = 0; x <= math.min(r, w - 1); x++) {
      cnt += m[o + x];
    }
    for (var x = 0; x < w; x++) {
      tmp[o + x] = cnt > 0 ? 1 : 0;
      final add = x + r + 1;
      if (add < w) cnt += m[o + add];
      final rem = x - r;
      if (rem >= 0) cnt -= m[o + rem];
    }
  }
  final out = Uint8List(w * h);
  final acc = Int32List(w);
  for (var y = 0; y <= math.min(r, h - 1); y++) {
    final o = y * w;
    for (var x = 0; x < w; x++) {
      acc[x] += tmp[o + x];
    }
  }
  for (var y = 0; y < h; y++) {
    final o = y * w;
    for (var x = 0; x < w; x++) {
      out[o + x] = acc[x] > 0 ? 1 : 0;
    }
    final add = y + r + 1;
    if (add < h) {
      final a = add * w;
      for (var x = 0; x < w; x++) {
        acc[x] += tmp[a + x];
      }
    }
    final rem = y - r;
    if (rem >= 0) {
      final a = rem * w;
      for (var x = 0; x < w; x++) {
        acc[x] -= tmp[a + x];
      }
    }
  }
  return out;
}

Uint8List _invert(Uint8List m) {
  final o = Uint8List(m.length);
  for (var i = 0; i < m.length; i++) {
    o[i] = m[i] == 0 ? 1 : 0;
  }
  return o;
}

Uint8List erode(Uint8List m, int w, int h, int r) =>
    _invert(dilate(_invert(m), w, h, r));

Uint8List closeMask(Uint8List m, int w, int h, int r) =>
    erode(dilate(m, w, h, r), w, h, r);

class Component {
  Component(this.id, this.x0, this.y0)
      : x1 = x0,
        y1 = y0;

  final int id;
  int x0;
  int y0;
  int x1;
  int y1;
  int area = 0;

  int get w => x1 - x0 + 1;
  int get h => y1 - y0 + 1;
  IRect get rect => IRect(x0, y0, w, h);
  double get fill => area / (w * h);
}

class Labeling {
  Labeling(this.labels, this.comps);

  /// 0 = fond, sinon id de composante + 1.
  final Int32List labels;
  final List<Component> comps;
}

/// Composantes connexes (8-connexité par défaut), remplissage itératif.
Labeling labelComponents(
  Uint8List mask,
  int w,
  int h, {
  bool eight = true,
  int minArea = 1,
}) {
  final labels = Int32List(w * h);
  final comps = <Component>[];
  final stack = Int32List(w * h);
  var next = 1;
  for (var start = 0; start < w * h; start++) {
    if (mask[start] == 0 || labels[start] != 0) continue;
    final c = Component(next - 1, start % w, start ~/ w);
    var sp = 0;
    stack[sp++] = start;
    labels[start] = next;
    while (sp > 0) {
      final p = stack[--sp];
      final px = p % w;
      final py = p ~/ w;
      c.area++;
      if (px < c.x0) c.x0 = px;
      if (px > c.x1) c.x1 = px;
      if (py < c.y0) c.y0 = py;
      if (py > c.y1) c.y1 = py;
      for (var dy = -1; dy <= 1; dy++) {
        final ny = py + dy;
        if (ny < 0 || ny >= h) continue;
        for (var dx = -1; dx <= 1; dx++) {
          if (dx == 0 && dy == 0) continue;
          if (!eight && dx != 0 && dy != 0) continue;
          final nx = px + dx;
          if (nx < 0 || nx >= w) continue;
          final q = ny * w + nx;
          if (mask[q] != 0 && labels[q] == 0) {
            labels[q] = next;
            stack[sp++] = q;
          }
        }
      }
    }
    if (c.area >= minArea) {
      comps.add(c);
      next++;
    } else {
      // Composante trop petite : marquée -1 pour ne pas être reparcourue.
      for (var yy = c.y0; yy <= c.y1; yy++) {
        for (var xx = c.x0; xx <= c.x1; xx++) {
          if (labels[yy * w + xx] == next) labels[yy * w + xx] = -1;
        }
      }
    }
  }
  for (var i = 0; i < labels.length; i++) {
    if (labels[i] < 0) labels[i] = 0;
  }
  return Labeling(labels, comps);
}

// ---------------------------------------------------------------------------
// Statistiques robustes
// ---------------------------------------------------------------------------

double median(List<double> v) {
  if (v.isEmpty) return 0;
  final s = List<double>.from(v)..sort();
  final n = s.length;
  return n.isOdd ? s[n ~/ 2] : (s[n ~/ 2 - 1] + s[n ~/ 2]) / 2;
}

double quantile(List<double> v, double q) {
  if (v.isEmpty) return 0;
  final s = List<double>.from(v)..sort();
  final i = q.clamp(0.0, 1.0).toDouble() * (s.length - 1);
  final lo = i.floor();
  final hi = i.ceil();
  return s[lo] + (s[hi] - s[lo]) * (i - lo);
}

/// Écart absolu médian (MAD), brut (non mis à l'échelle).
double mad(List<double> v, double med) =>
    median([for (final x in v) (x - med).abs()]);

double clamp01(double v) => v < 0 ? 0 : (v > 1 ? 1 : v);

// ---------------------------------------------------------------------------
// Anomalies sur une grille de blocs (bruit, ELA)
// ---------------------------------------------------------------------------

class GridCluster {
  GridCluster(this.rect, this.cells, this.meanZ);

  /// En pixels de l'image analysée.
  final IRect rect;
  final int cells;
  final double meanZ;
}

class GridAnomaly {
  GridAnomaly(this.score, this.clusters, this.outlierFraction, this.valid);

  final double score;
  final List<GridCluster> clusters;
  final double outlierFraction;
  final int valid;
}

/// Cherche des groupes de blocs dont la valeur s'écarte fortement de la
/// médiane de la page (z robuste via MAD).
GridAnomaly analyzeGrid({
  required Float64List values,
  required Uint8List valid,
  required int gw,
  required int gh,
  required int cell,
  required int imgW,
  required int imgH,
  double zThreshold = 4.0,
  double madFloor = 0.15,
  int minCells = 3,
  bool upperOnly = false,
}) {
  final vals = <double>[];
  for (var i = 0; i < values.length; i++) {
    if (valid[i] != 0) vals.add(values[i]);
  }
  if (vals.length < 40) return GridAnomaly(0, const [], 0, vals.length);
  final med = median(vals);
  final scale = 1.4826 * math.max(mad(vals, med), madFloor);

  final out = Uint8List(gw * gh);
  final z = Float64List(gw * gh);
  var outliers = 0;
  for (var i = 0; i < values.length; i++) {
    if (valid[i] == 0) continue;
    var zi = (values[i] - med) / scale;
    if (upperOnly && zi < 0) zi = 0;
    z[i] = zi.abs();
    if (z[i] >= zThreshold) {
      out[i] = 1;
      outliers++;
    }
  }
  final lab = labelComponents(out, gw, gh, minArea: minCells);
  final clusters = <GridCluster>[];
  var best = 0.0;
  for (final c in lab.comps) {
    var sumZ = 0.0;
    var n = 0;
    for (var y = c.y0; y <= c.y1; y++) {
      for (var x = c.x0; x <= c.x1; x++) {
        if (lab.labels[y * gw + x] == c.id + 1) {
          sumZ += z[y * gw + x];
          n++;
        }
      }
    }
    final meanZ = n == 0 ? 0.0 : sumZ / n;
    final rect = IRect(
      c.x0 * cell,
      c.y0 * cell,
      math.min(imgW - c.x0 * cell, c.w * cell),
      math.min(imgH - c.y0 * cell, c.h * cell),
    );
    clusters.add(GridCluster(rect, c.area, meanZ));
    final s = clamp01(0.25 + 0.05 * (c.area - minCells) + 0.05 * (meanZ - zThreshold));
    if (s > best) best = s;
  }
  final frac = outliers / vals.length;
  // Si une grande part de la page est « anormale », c'est de la variation
  // naturelle (scanner bruité, papier texturé) et non un collage local.
  if (frac > 0.25) best *= 0.4;
  clusters.sort((a, b) => b.cells.compareTo(a.cells));
  return GridAnomaly(best, clusters.take(8).toList(), frac, vals.length);
}
