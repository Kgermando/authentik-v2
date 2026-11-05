// Seul fichier qui touche OpenCV : décodage, redimensionnement, recompression
// JPEG (ELA), ORB (copier-coller) et encodage de l'aperçu. Tous les
// algorithmes d'analyse restent en Dart pur (voir les autres fichiers).
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:opencv_dart/opencv_dart.dart' as cv;

import 'copy_move.dart';

/// Image BGR entrelacée.
class BgrImage {
  const BgrImage(this.w, this.h, this.bgr, this.srcW, this.srcH);

  final int w;
  final int h;
  final Uint8List bgr;

  /// Dimensions de l'image d'origine avant réduction.
  final int srcW;
  final int srcH;
}

/// Taille maximale du grand côté pour l'analyse (compromis précision / mémoire).
const int kWorkSide = 2200;

BgrImage _finish(cv.Mat src, int maxSide) {
  final srcW = src.cols;
  final srcH = src.rows;
  final scale = math.min(1.0, maxSide / math.max(srcW, srcH));
  cv.Mat m = src;
  if (scale < 1.0) {
    m = cv.resize(src, (
      (srcW * scale).round(),
      (srcH * scale).round(),
    ), interpolation: cv.INTER_AREA);
  }
  final out = BgrImage(m.cols, m.rows, Uint8List.fromList(m.data), srcW, srcH);
  if (!identical(m, src)) m.dispose();
  return out;
}

/// Décode une image (PNG, JPEG, TIFF, BMP…).
BgrImage decodeImage(Uint8List encoded, {int maxSide = kWorkSide}) {
  final m = cv.imdecode(encoded, cv.IMREAD_COLOR);
  if (m.isEmpty) {
    m.dispose();
    throw const FormatException(
      'Image illisible ou format non pris en charge.',
    );
  }
  final out = _finish(m, maxSide);
  m.dispose();
  return out;
}

/// Convertit une page PDF rendue (BGRA) en BGR de travail.
BgrImage bgraToBgr(Uint8List bgra, int w, int h, {int maxSide = kWorkSide}) {
  final raw = cv.Mat.fromList(h, w, cv.MatType.CV_8UC4, bgra);
  final bgr = cv.cvtColor(raw, cv.COLOR_BGRA2BGR);
  raw.dispose();
  final out = _finish(bgr, maxSide);
  bgr.dispose();
  return out;
}

/// Pas de réduction : image à pleine résolution (module référentiels).
const int kFullSide = 1 << 30;

/// Image de travail obtenue d'une image pleine résolution : même opération
/// (`INTER_AREA`) que `decodeImage`, donc pixels identiques.
BgrImage shrink(BgrImage full, {int maxSide = kWorkSide}) {
  final m = cv.Mat.fromList(full.h, full.w, cv.MatType.CV_8UC3, full.bgr);
  final out = _finish(m, maxSide);
  m.dispose();
  return out;
}

/// Aperçu JPEG réduit (jamais écrit sur disque).
Uint8List encodePreview(BgrImage img, {int maxSide = 1600, int quality = 82}) {
  final m = cv.Mat.fromList(img.h, img.w, cv.MatType.CV_8UC3, img.bgr);
  final scale = math.min(1.0, maxSide / math.max(img.w, img.h));
  final r = scale < 1.0
      ? cv.resize(m, (
          (img.w * scale).round(),
          (img.h * scale).round(),
        ), interpolation: cv.INTER_AREA)
      : m;
  final (ok, jpg) = cv.imencode(
    '.jpg',
    r,
    params: cv.VecI32.fromList([cv.IMWRITE_JPEG_QUALITY, quality]),
  );
  if (!identical(r, m)) r.dispose();
  m.dispose();
  if (!ok) throw StateError('Encodage de l’aperçu impossible');
  return Uint8List.fromList(jpg);
}

/// Image en niveaux de gris recompressée en JPEG (pour l'ELA).
Uint8List? recompressGray(Uint8List gray, int w, int h, {int quality = 90}) {
  try {
    final m = cv.Mat.fromList(h, w, cv.MatType.CV_8UC1, gray);
    final (ok, jpg) = cv.imencode(
      '.jpg',
      m,
      params: cv.VecI32.fromList([cv.IMWRITE_JPEG_QUALITY, quality]),
    );
    m.dispose();
    if (!ok) return null;
    final back = cv.imdecode(Uint8List.fromList(jpg), cv.IMREAD_GRAYSCALE);
    if (back.isEmpty || back.cols != w || back.rows != h) {
      back.dispose();
      return null;
    }
    final out = Uint8List.fromList(back.data);
    back.dispose();
    return out;
  } catch (_) {
    return null;
  }
}

/// Paires de points ORB quasi identiques à l'intérieur de la même image.
List<MatchPair> orbSelfMatches(Uint8List gray, int w, int h) {
  try {
    final m = cv.Mat.fromList(h, w, cv.MatType.CV_8UC1, gray);
    final orb = cv.ORB.create(nFeatures: 4000);
    final (kps, desc) = orb.detectAndCompute(m, cv.Mat.empty());
    m.dispose();
    if (kps.length < 20 || desc.isEmpty) return const [];
    final bf = cv.BFMatcher.create(type: cv.NORM_HAMMING);
    // k = 3 : le premier voisin est le point lui-même.
    final knn = bf.knnMatch(desc, desc, 3);
    final pairs = <MatchPair>[];
    for (var i = 0; i < knn.length; i++) {
      final row = knn[i];
      if (row.length < 3) continue;
      final nn1 = row[1];
      final nn2 = row[2];
      if (nn1.distance > 0.6 * nn2.distance) continue; // test du ratio
      if (nn1.distance > 48) continue; // descripteurs vraiment proches
      final a = kps[nn1.queryIdx];
      final b = kps[nn1.trainIdx];
      pairs.add(MatchPair(a.x, a.y, b.x, b.y));
    }
    return pairs;
  } catch (_) {
    return const [];
  }
}
