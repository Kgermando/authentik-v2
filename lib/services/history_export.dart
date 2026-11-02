import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../core/models.dart';

/// Génère un classeur Excel (.xlsx) à partir de l'historique.
Uint8List buildHistoryXlsx(List<HistoryEntry> entries) {
  final rows = <List<String>>[
    [
      'Date',
      'Fichier',
      'Empreinte SHA-256',
      'Type',
      'Pages',
      'Suspicion (%)',
      'Verdict',
      'Seuil (%)',
      'Profil',
      'Durée (s)',
      'Décision humaine',
      'Note',
      'Avertissements',
      'Contrôles (résumé)',
    ],
    for (final h in entries)
      [
        _formatDate(h.createdAt),
        h.fileName,
        h.sha256,
        h.source.toUpperCase(),
        '${h.pageCount}',
        '${(h.probability * 100).round()}',
        h.verdict.short,
        '${(h.threshold * 100).round()}',
        h.profileName,
        (h.elapsedMs / 1000).toStringAsFixed(1),
        h.decision == Decision.none ? '' : h.decision.label,
        h.note,
        h.warnings.join(' · '),
        h.checks
            .where((c) => !c.skipped)
            .map((c) => '${c.id.label}: ${(c.score * 100).round()} %')
            .join(' · '),
      ],
  ];
  return _packXlsx(rows);
}

String _formatDate(DateTime d) {
  final l = d.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(l.day)}/${two(l.month)}/${l.year} ${two(l.hour)}:${two(l.minute)}';
}

String _col(int index) {
  var dividend = index + 1;
  var name = '';
  while (dividend > 0) {
    final mod = (dividend - 1) % 26;
    name = String.fromCharCode(65 + mod) + name;
    dividend = (dividend - mod) ~/ 26;
  }
  return name;
}

String _escapeXml(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');

Uint8List _packXlsx(List<List<String>> rows) {
  final sheet = StringBuffer()
    ..writeln('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
    ..writeln(
      '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">',
    )
    ..writeln('<sheetData>');
  for (var r = 0; r < rows.length; r++) {
    final rowNum = r + 1;
    sheet.writeln('<row r="$rowNum">');
    final line = rows[r];
    for (var c = 0; c < line.length; c++) {
      final ref = '${_col(c)}$rowNum';
      final text = _escapeXml(line[c]);
      sheet.writeln(
        '<c r="$ref" t="inlineStr"><is><t>$text</t></is></c>',
      );
    }
    sheet.writeln('</row>');
  }
  sheet.writeln('</sheetData></worksheet>');

  const contentTypes = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
  <Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
</Types>''';

  const rels = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
</Relationships>''';

  const workbook = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
  <sheets>
    <sheet name="Historique" sheetId="1" r:id="rId1"/>
  </sheets>
</workbook>''';

  const workbookRels = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>
</Relationships>''';

  final archive = Archive()
    ..addFile(ArchiveFile('[Content_Types].xml', contentTypes.length, utf8.encode(contentTypes)))
    ..addFile(ArchiveFile('_rels/.rels', rels.length, utf8.encode(rels)))
    ..addFile(ArchiveFile('xl/workbook.xml', workbook.length, utf8.encode(workbook)))
    ..addFile(ArchiveFile('xl/_rels/workbook.xml.rels', workbookRels.length, utf8.encode(workbookRels)))
    ..addFile(ArchiveFile('xl/worksheets/sheet1.xml', sheet.length, utf8.encode(sheet.toString())));

  return Uint8List.fromList(ZipEncoder().encode(archive));
}
