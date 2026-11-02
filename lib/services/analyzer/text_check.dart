import 'dart:math' as math;
import 'dart:typed_data';

import '../../core/models.dart';
import 'image_ops.dart';
import 'page_context.dart';

class _Glyph {
  _Glyph(this.comp);

  final Component comp;
  double get cy => (comp.y0 + comp.y1) / 2;
}

class _Line {
  _Line(_Glyph g)
      : glyphs = [g],
        cySum = g.cy,
        hSum = g.comp.h.toDouble();

  final List<_Glyph> glyphs;
  double cySum;
  double hSum;

  double get cy => cySum / glyphs.length;
  double get h => hSum / glyphs.length;

  void add(_Glyph g) {
    glyphs.add(g);
    cySum += g.cy;
    hSum += g.comp.h;
  }
}

class _Word {
  _Word(this.glyphs, this.lineH, this.page);

  final List<_Glyph> glyphs;
  final double lineH;
  final int page;
  late IRect rect;
  double darkness = 0;
  double stroke = 0;
  double sharp = 0;
  int ink = 0;
  double z = 0;
}

/// Compare chaque mot du document aux autres mots de même corps : encre
/// (niveau de gris), épaisseur de trait et netteté des bords. Un mot, un
/// nom ou une date retapé / retouché après coup se distingue souvent par une
/// encre plus foncée ou plus claire, ou un trait plus fin ou plus épais.
CheckResult textConsistency(
  List<PageContext> pages,
  List<List<IRect>> excluded,
) {
  final words = <_Word>[];
  for (var p = 0; p < pages.length; p++) {
    words.addAll(_extractWords(pages[p], excluded[p], p));
  }
  final usable = words.where((w) => w.ink >= 30).toList();
  if (usable.length < 20) {
    return const CheckResult(
      id: CheckId.textConsistency,
      score: 0,
      skipped: true,
      summary:
          'Pas assez de texte imprimé lisible pour comparer les mots entre eux.',
    );
  }

  // Regroupement par corps de texte (bandes de hauteur de ligne ~18 %).
  final buckets = <int, List<_Word>>{};
  for (final w in usable) {
    final k = (math.log(math.max(4.0, w.lineH)) / math.log(1.18)).round();
    buckets.putIfAbsent(k, () => []).add(w);
  }

  var compared = 0;
  for (final list in buckets.values) {
    if (list.length < 12) continue;
    compared += list.length;
    final d = [for (final w in list) w.darkness];
    final s = [for (final w in list) w.stroke];
    final f = [for (final w in list) w.sharp];
    final md = median(d);
    final ms = median(s);
    final mf = median(f);
    final sd = 1.4826 * math.max(mad(d, md), 5.0);
    final ss = 1.4826 * math.max(mad(s, ms), 0.25);
    final sf = 1.4826 * math.max(mad(f, mf), 0.12 * mf);
    for (final w in list) {
      final zd = (w.darkness - md).abs() / sd;
      final zs = (w.stroke - ms).abs() / ss;
      final zf = (w.sharp - mf).abs() / sf;
      w.z = math.max(zd, math.max(zs, zf * 0.7));
    }
  }
  if (compared < 20) {
    return const CheckResult(
      id: CheckId.textConsistency,
      score: 0,
      skipped: true,
      summary: 'Texte trop varié pour une comparaison fiable.',
    );
  }

  final flagged = usable.where((w) => w.z >= 4.5).toList()
    ..sort((a, b) => b.z.compareTo(a.z));
  var score = 0.0;
  if (flagged.isNotEmpty) {
    score = clamp01((flagged.first.z - 4.0) / 6.0);
    // Plusieurs mots voisins sur la même ligne : indice plus fort.
    final byLine = <int, int>{};
    for (final w in flagged) {
      final key = w.page * 100000 + (w.rect.cy / 8).round();
      byLine[key] = (byLine[key] ?? 0) + 1;
    }
    if (byLine.values.any((n) => n >= 2)) score = math.min(1.0, score + 0.15);
    // Document très hétérogène (gras, titres, polices mélangées) : prudence.
    if (flagged.length / compared > 0.12) score *= 0.4;
  }

  final regions = <Region>[
    for (final w in flagged.take(8))
      Region(
        page: pages[w.page].index,
        check: CheckId.textConsistency,
        left: w.rect.x / pages[w.page].w,
        top: w.rect.y / pages[w.page].h,
        width: w.rect.w / pages[w.page].w,
        height: w.rect.h / pages[w.page].h,
        score: clamp01((w.z - 4.0) / 6.0),
        label: 'Mot dont l’encre ou le trait diffère du reste du texte',
      ),
  ];
  final summary = flagged.isEmpty
      ? 'Encre et trait homogènes sur $compared mots comparés.'
      : '${flagged.length} mot(s) dont l’encre ou le trait diffère nettement '
          '(sur $compared mots comparés).';
  return CheckResult(
    id: CheckId.textConsistency,
    score: score,
    summary: summary,
    regions: regions,
  );
}

List<_Word> _extractWords(PageContext c, List<IRect> excluded, int page) {
  final thr = c.paperGray * 0.62;
  final mask = Uint8List(c.w * c.h);
  for (var i = 0; i < mask.length; i++) {
    if (c.gray[i] < thr) mask[i] = 1;
  }
  for (final r in excluded) {
    final e = r.expand(4, c.w, c.h);
    for (var y = e.y; y < e.bottom; y++) {
      mask.fillRange(y * c.w + e.x, y * c.w + e.right, 0);
    }
  }
  final lab = labelComponents(mask, c.w, c.h, minArea: 4);

  final glyphs = <_Glyph>[];
  for (final comp in lab.comps) {
    if (comp.h < 5 || comp.h > c.h * 0.07) continue;
    if (comp.w > c.w * 0.12) continue;
    glyphs.add(_Glyph(comp));
  }
  if (glyphs.length < 30) return const [];
  glyphs.sort((a, b) => a.cy.compareTo(b.cy));

  final lines = <_Line>[];
  for (final g in glyphs) {
    _Line? best;
    var bestD = double.infinity;
    for (var i = lines.length - 1; i >= 0 && i >= lines.length - 80; i--) {
      final l = lines[i];
      final d = (g.cy - l.cy).abs();
      if (d < 0.6 * math.max(l.h, g.comp.h.toDouble()) && d < bestD) {
        best = l;
        bestD = d;
      }
    }
    if (best == null) {
      lines.add(_Line(g));
    } else {
      best.add(g);
    }
  }

  final words = <_Word>[];
  for (final line in lines) {
    if (line.glyphs.length < 3) continue;
    final gs = [...line.glyphs]..sort((a, b) => a.comp.x0.compareTo(b.comp.x0));
    final lineH = line.h;
    var cur = <_Glyph>[gs.first];
    var right = gs.first.comp.x1;
    for (var i = 1; i < gs.length; i++) {
      final g = gs[i];
      if (g.comp.x0 - right > 0.35 * lineH) {
        words.add(_Word(cur, lineH, page));
        cur = [g];
      } else {
        cur.add(g);
      }
      right = math.max(right, g.comp.x1);
    }
    words.add(_Word(cur, lineH, page));
  }

  for (final w in words) {
    var x0 = c.w, y0 = c.h, x1 = 0, y1 = 0;
    var area = 0;
    var graySum = 0.0;
    var perim = 0;
    var gradSum = 0.0;
    for (final g in w.glyphs) {
      final comp = g.comp;
      x0 = math.min(x0, comp.x0);
      y0 = math.min(y0, comp.y0);
      x1 = math.max(x1, comp.x1);
      y1 = math.max(y1, comp.y1);
      final id = comp.id + 1;
      for (var y = comp.y0; y <= comp.y1; y++) {
        for (var x = comp.x0; x <= comp.x1; x++) {
          final i = y * c.w + x;
          if (lab.labels[i] != id) continue;
          area++;
          graySum += c.gray[i];
          final edge = x == 0 ||
              y == 0 ||
              x == c.w - 1 ||
              y == c.h - 1 ||
              mask[i - 1] == 0 ||
              mask[i + 1] == 0 ||
              mask[i - c.w] == 0 ||
              mask[i + c.w] == 0;
          if (edge) {
            perim++;
            gradSum += c.grad[i];
          }
        }
      }
    }
    w.rect = IRect(x0, y0, x1 - x0 + 1, y1 - y0 + 1);
    w.ink = area;
    if (area == 0 || perim == 0) continue;
    w.darkness = graySum / area;
    w.stroke = 2 * area / perim;
    w.sharp = gradSum / perim;
  }
  return words;
}
