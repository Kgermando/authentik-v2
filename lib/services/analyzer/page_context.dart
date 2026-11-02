import 'dart:math' as math;
import 'dart:typed_data';

import 'image_ops.dart';

/// Image d'une page prête pour l'analyse, avec les plans et statistiques
/// partagés par tous les contrôles. Tout est calculé une seule fois.
class PageContext {
  PageContext(this.index, this.w, this.h, this.bgr) {
    _build();
  }

  final int index;
  final int w;
  final int h;

  /// Pixels BGR entrelacés (w*h*3).
  final Uint8List bgr;

  late final Uint8List gray;

  /// Saturation 0..255.
  late final Uint8List sat;

  /// Teinte du papier : R − B + 128 (détecte un papier plus jaune ou plus bleu).
  late final Uint8List tint;

  /// Gradient (|dx| + |dy|), 0..255.
  late final Uint8List grad;

  /// Résidu haute fréquence au carré (énergie du grain / bruit).
  late final Float32List resid2;

  late final double paperGray;
  late final double paperSat;

  /// 1 là où le pixel est du papier plat (clair, sans contour) : base de toutes
  /// les comparaisons de fond.
  late final Uint8List flat;

  late final double flatFraction;

  late final Integral grayInt;
  late final Integral flatCount;
  late final Integral flatGray;
  late final Integral flatTint;
  late final Integral flatNoise;

  void _build() {
    final n = w * h;
    gray = Uint8List(n);
    sat = Uint8List(n);
    tint = Uint8List(n);
    for (var i = 0, j = 0; i < n; i++, j += 3) {
      final b = bgr[j];
      final g = bgr[j + 1];
      final r = bgr[j + 2];
      gray[i] = (0.114 * b + 0.587 * g + 0.299 * r).round();
      final mx = math.max(b, math.max(g, r));
      final mn = math.min(b, math.min(g, r));
      sat[i] = mx == 0 ? 0 : ((mx - mn) * 255 ~/ mx);
      tint[i] = (r - b + 128).clamp(0, 255).toInt();
    }

    grayInt = Integral.bytes(gray, w, h);

    // Niveau de papier : 75e centile des moyennes de blocs de 32 px.
    const cell = 32;
    final gw = math.max(1, w ~/ cell);
    final gh = math.max(1, h ~/ cell);
    final blockMeans = <double>[];
    final blockSats = <double>[];
    final satInt = Integral.bytes(sat, w, h);
    for (var by = 0; by < gh; by++) {
      for (var bx = 0; bx < gw; bx++) {
        final a = (cell * cell).toDouble();
        blockMeans.add(
          grayInt.sum(bx * cell, by * cell, (bx + 1) * cell, (by + 1) * cell) / a,
        );
        blockSats.add(
          satInt.sum(bx * cell, by * cell, (bx + 1) * cell, (by + 1) * cell) / a,
        );
      }
    }
    paperGray = quantile(blockMeans, 0.75);
    final paperSats = <double>[
      for (var i = 0; i < blockMeans.length; i++)
        if (blockMeans[i] >= paperGray * 0.92) blockSats[i],
    ];
    paperSat = paperSats.isEmpty ? 0 : median(paperSats);

    // Gradient et résidu haute fréquence.
    grad = Uint8List(n);
    resid2 = Float32List(n);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final i = y * w + x;
        final xl = x > 0 ? gray[i - 1] : gray[i];
        final xr = x < w - 1 ? gray[i + 1] : gray[i];
        final yu = y > 0 ? gray[i - w] : gray[i];
        final yd = y < h - 1 ? gray[i + w] : gray[i];
        grad[i] = math.min(255, (xr - xl).abs() + (yd - yu).abs());
        final mean3 = grayInt.sum(x - 1, y - 1, x + 2, y + 2) /
            (((math.min(w, x + 2) - math.max(0, x - 1))) *
                ((math.min(h, y + 2) - math.max(0, y - 1))));
        final d = gray[i] - mean3;
        resid2[i] = (d * d).toDouble();
      }
    }

    flat = Uint8List(n);
    var flatN = 0;
    final lightThr = paperGray * 0.86;
    for (var i = 0; i < n; i++) {
      if (gray[i] >= lightThr && grad[i] <= 10) {
        flat[i] = 1;
        flatN++;
      }
    }
    flatFraction = flatN / n;

    flatCount = Integral.bytes(flat, w, h);
    flatGray = Integral.masked(gray, flat, w, h);
    flatTint = Integral.masked(tint, flat, w, h);
    flatNoise = Integral.maskedFloats(resid2, flat, w, h);
  }

  /// Moyenne de gray / tint / bruit sur le papier plat d'un rectangle
  /// (null si trop peu de pixels exploitables).
  FlatStats? flatStats(IRect r, {int minPixels = 150}) {
    final c = flatCount.sumRect(r);
    if (c < minPixels) return null;
    return FlatStats(
      flatGray.sumRect(r) / c,
      flatTint.sumRect(r) / c,
      flatNoise.sumRect(r) / c,
      c,
    );
  }

  /// Statistiques de l'anneau compris entre `inner` et `outer` (rectangles
  /// imbriqués), sur le papier plat uniquement.
  FlatStats? ringStats(IRect inner, IRect outer, {int minPixels = 150}) {
    final c = flatCount.sumRect(outer) - flatCount.sumRect(inner);
    if (c < minPixels) return null;
    return FlatStats(
      (flatGray.sumRect(outer) - flatGray.sumRect(inner)) / c,
      (flatTint.sumRect(outer) - flatTint.sumRect(inner)) / c,
      (flatNoise.sumRect(outer) - flatNoise.sumRect(inner)) / c,
      c,
    );
  }
}

class FlatStats {
  const FlatStats(this.gray, this.tint, this.noise, this.count);

  final double gray;
  final double tint;
  final double noise;
  final double count;
}
