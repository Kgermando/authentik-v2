import 'dart:typed_data';

import 'package:authentik_v2/services/analyzer/image_ops.dart';
import 'package:authentik_v2/services/analyzer/overlay_check.dart';
import 'package:authentik_v2/services/analyzer/page_context.dart';
import 'package:flutter_test/flutter_test.dart';

/// Page A4 synthétique (BGR) : papier clair légèrement bruité.
Uint8List _paper(int w, int h, {int base = 235, int seed = 1}) {
  final out = Uint8List(w * h * 3);
  var s = seed;
  for (var i = 0; i < w * h; i++) {
    s = (s * 1103515245 + 12345) & 0x7fffffff;
    final n = (s >> 16) % 5 - 2; // bruit ±2
    final v = (base + n).clamp(0, 255).toInt();
    out[i * 3] = v;
    out[i * 3 + 1] = v;
    out[i * 3 + 2] = v;
  }
  return out;
}

void _fillRect(
  Uint8List bgr,
  int w,
  IRect r,
  int b,
  int g,
  int rr,
) {
  for (var y = r.y; y < r.bottom; y++) {
    for (var x = r.x; x < r.right; x++) {
      final i = (y * w + x) * 3;
      bgr[i] = b;
      bgr[i + 1] = g;
      bgr[i + 2] = rr;
    }
  }
}

/// Anneau rouge (tampon) de rayon donné.
void _stamp(Uint8List bgr, int w, int cx, int cy, int radius) {
  for (var y = cy - radius; y <= cy + radius; y++) {
    for (var x = cx - radius; x <= cx + radius; x++) {
      final d = ((x - cx) * (x - cx) + (y - cy) * (y - cy)).toDouble();
      if (d <= radius * radius && d >= (radius - 6) * (radius - 6)) {
        final i = (y * w + x) * 3;
        bgr[i] = 40;
        bgr[i + 1] = 40;
        bgr[i + 2] = 200;
      }
    }
  }
}

void main() {
  test('dilatation puis érosion : fermeture d’un trou', () {
    const w = 20, h = 20;
    final m = Uint8List(w * h);
    for (var x = 2; x < 18; x++) {
      m[10 * w + x] = 1;
    }
    m[10 * w + 9] = 0;
    m[10 * w + 10] = 0; // trou de 2 px
    final c = closeMask(m, w, h, 2);
    expect(c[10 * w + 9], 1);
    expect(c[10 * w + 10], 1);
  });

  test('composantes connexes : deux blocs séparés', () {
    const w = 30, h = 10;
    final m = Uint8List(w * h);
    for (var y = 2; y < 6; y++) {
      for (var x = 2; x < 6; x++) {
        m[y * w + x] = 1;
      }
      for (var x = 20; x < 26; x++) {
        m[y * w + x] = 1;
      }
    }
    final lab = labelComponents(m, w, h);
    expect(lab.comps.length, 2);
    expect(lab.comps.map((c) => c.area).toSet(), {16, 24});
  });

  test('image intégrale : somme de rectangle', () {
    final v = Uint8List.fromList(List.filled(100, 2));
    final ig = Integral.bytes(v, 10, 10);
    expect(ig.sum(0, 0, 10, 10), 200);
    expect(ig.sum(2, 2, 5, 4), 12);
  });

  test('tampon sur papier continu : rupture de fond faible', () {
    const w = 1000, h = 1400;
    final bgr = _paper(w, h);
    _stamp(bgr, w, 500, 1000, 90);
    final ctx = PageContext(0, w, h, bgr);
    final res = detectOverlays(ctx);
    expect(res.seals, isNotEmpty);
    expect(res.seals.first.score, lessThan(0.3));
  });

  test('tampon collé avec un fond de papier différent : rupture détectée', () {
    const w = 1000, h = 1400;
    final bgr = _paper(w, h, base: 235);
    // Le « collage » apporte son propre papier, plus foncé et plus jaune.
    _fillRect(bgr, w, const IRect(380, 880, 240, 240), 205, 222, 228);
    _stamp(bgr, w, 500, 1000, 90);
    final ctx = PageContext(0, w, h, bgr);
    final res = detectOverlays(ctx);
    expect(res.seals, isNotEmpty);
    expect(res.seals.first.score, greaterThan(0.5));
  });
}
