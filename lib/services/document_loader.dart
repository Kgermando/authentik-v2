import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';

import '../core/models.dart';
import 'analyzer/analyzer.dart';
import 'analyzer/metadata_check.dart';

const supportedExtensions = <String>{
  'pdf',
  'png',
  'jpg',
  'jpeg',
  'bmp',
  'tif',
  'tiff',
  'webp',
};

bool isSupportedFile(String path) {
  final ext = p.extension(path).replaceFirst('.', '').toLowerCase();
  return supportedExtensions.contains(ext);
}

/// Lit le fichier, calcule son empreinte, rend les pages d'un PDF (sur le fil
/// principal : PDFium) et prépare le travail pour l'isolat d'analyse.
///
/// Le document n'est jamais copié ni enregistré : il vit en mémoire le temps
/// de l'analyse.
Future<AnalysisJob> prepareJob(String path, VerificationProfile profile) async {
  final file = File(path);
  if (!await file.exists()) {
    throw FileSystemException('Fichier introuvable', path);
  }
  if (!isSupportedFile(path)) {
    throw FormatException(
      'Format non pris en charge. Formats acceptés : PDF, PNG, JPG, TIFF, BMP, WEBP.',
    );
  }
  final bytes = await file.readAsBytes();
  if (bytes.isEmpty) throw const FormatException('Le fichier est vide.');
  final sha = sha256.convert(bytes).toString();
  final meta = readFileMeta(bytes);
  final isPdf = bytes.length > 4 &&
      bytes[0] == 0x25 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x44 &&
      bytes[3] == 0x46;
  final warnings = <String>[];
  final pages = <PageInput>[];

  if (isPdf) {
    final doc = await PdfDocument.openData(bytes);
    try {
      final total = doc.pages.length;
      final n = math.min(total, profile.maxPages);
      if (total > n) {
        warnings.add(
          'Seules les $n premières pages sur $total sont analysées '
          '(réglable dans le profil de vérification).',
        );
      }
      for (var i = 0; i < n; i++) {
        final page = doc.pages[i];
        var scale = profile.renderDpi / 72.0;
        final longSide = math.max(page.width, page.height) * scale;
        if (longSide > 4200) scale *= 4200 / longSide;
        final w = (page.width * scale).round();
        final h = (page.height * scale).round();
        final img = await page.render(
          fullWidth: w.toDouble(),
          fullHeight: h.toDouble(),
          backgroundColor: 0xFFFFFFFF,
        );
        if (img == null) {
          throw StateError('Rendu de la page ${i + 1} impossible.');
        }
        final px = Uint8List.fromList(img.pixels);
        final iw = img.width;
        final ih = img.height;
        img.dispose();
        pages.add(
          PageInput(
            index: i,
            width: iw,
            height: ih,
            kind: 'bgra',
            data: TransferableTypedData.fromList([px]),
          ),
        );
      }
    } finally {
      await doc.dispose();
    }
  } else {
    pages.add(
      PageInput(
        index: 0,
        width: 0,
        height: 0,
        kind: 'encoded',
        data: TransferableTypedData.fromList([bytes]),
      ),
    );
  }

  return AnalysisJob(
    id: newId(),
    fileName: p.basename(path),
    source: isPdf ? 'pdf' : 'image',
    sha256: sha,
    pages: pages,
    profile: profile.toJson(),
    meta: meta,
    warnings: warnings,
  );
}
