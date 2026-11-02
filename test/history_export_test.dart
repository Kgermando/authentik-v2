import 'package:authentik_v2/core/models.dart';
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
}
