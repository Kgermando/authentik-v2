import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:authentik_v2/core/i18n.dart';
import 'package:authentik_v2/core/models.dart';
import 'package:authentik_v2/core/page_scale.dart';
import 'package:authentik_v2/services/history_export.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('export Excel : fichier xlsx (zip) non vide', () {
    final bytes = buildHistoryXlsx([
      HistoryEntry(
        id: '1',
        fileName: 'certificat.pdf',
        sha256: 'abc',
        source: 'pdf',
        pageCount: 2,
        createdAt: DateTime(2026, 1, 15, 10, 30),
        elapsedMs: 4200,
        probability: 0.72,
        verdict: Verdict.suspect,
        threshold: 0.7,
        profileName: 'Certificats',
        checks: const [],
        warnings: const ['Scan un peu sombre'],
        decision: Decision.none,
        note: '',
      ),
    ]);
    expect(bytes.length, greaterThan(100));
    expect(bytes[0], 0x50); // PK..
    expect(bytes[1], 0x4B);
  });

  test('export Excel : verdict « non concluant », DPI et forçage', () {
    Textes.load(Textes.parse(File(Textes.assetPath).readAsStringSync()));
    final bytes = buildHistoryXlsx([
      HistoryEntry(
        id: '2',
        fileName: 'flou.jpg',
        sha256: 'def',
        source: 'image',
        pageCount: 1,
        createdAt: DateTime(2026, 11, 3, 9),
        elapsedMs: 1000,
        probability: 0.5,
        verdict: Verdict.inconclusive,
        threshold: 0.7,
        profileName: 'Standard',
        checks: const [],
        warnings: const [],
        decision: Decision.none,
        note: '',
        acquisition: Acquisition.dossierSurveille,
        pageScales: [PageScale.fromImage(pxW: 2480, pxH: 3508)],
        forcedByCritical: true,
      ),
    ]);
    final sheet = ZipDecoder()
        .decodeBytes(bytes)
        .files
        .firstWhere((f) => f.name.contains('sheet1'));
    final xml = utf8.decode(sheet.content as List<int>);
    expect(xml, contains('Non concluant'));
    expect(xml, contains('Dossier surveillé'));
    expect(xml, contains('DPI estimé'));
    expect(xml, contains('>300<'));
  });
}
