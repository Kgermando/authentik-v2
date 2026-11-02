import 'dart:convert';
import 'dart:typed_data';

import '../../core/models.dart';

/// Métadonnées lues directement dans les octets du fichier (PDF ou image).
class FileMeta {
  const FileMeta({
    this.producer,
    this.creator,
    this.created,
    this.modified,
    this.editors = const [],
  });

  final String? producer;
  final String? creator;
  final DateTime? created;
  final DateTime? modified;

  /// Logiciels de retouche repérés dans le fichier.
  final List<String> editors;
}

const _editorTokens = <String>[
  'Photoshop',
  'GIMP',
  'Paint.NET',
  'Pixelmator',
  'Affinity',
  'Illustrator',
  'CorelDRAW',
  'Canva',
  'Inkscape',
  'PicsArt',
  'Snapseed',
  'Photopea',
  'Fotor',
  'PhotoScape',
  'iLovePDF',
  'Sejda',
  'Smallpdf',
  'PDFescape',
];

FileMeta readFileMeta(Uint8List bytes) {
  final text = latin1.decode(bytes, allowInvalid: true);

  String? grab(RegExp re) {
    final m = re.firstMatch(text);
    final v = m?.group(1)?.trim();
    return (v == null || v.isEmpty) ? null : v;
  }

  final producer = grab(RegExp(r'/Producer\s*\(([^)]{1,200})\)')) ??
      grab(RegExp(r'<pdf:Producer>([^<]{1,200})<'));
  final creator = grab(RegExp(r'/Creator\s*\(([^)]{1,200})\)')) ??
      grab(RegExp(r'CreatorTool>([^<]{1,200})<'));
  final created = _parsePdfDate(grab(RegExp(r'/CreationDate\s*\(([^)]{1,40})\)')));
  final modified = _parsePdfDate(grab(RegExp(r'/ModDate\s*\(([^)]{1,40})\)')));

  // On cherche les logiciels de retouche dans l'ensemble du fichier : pour les
  // images, ils figurent dans les blocs EXIF / XMP / Photoshop.
  final head = text.length > 400000 ? text.substring(0, 400000) : text;
  final tail = text.length > 400000
      ? text.substring(text.length - 200000)
      : '';
  final scan = '$head$tail';
  final editors = <String>[
    for (final t in _editorTokens)
      if (scan.contains(t)) t,
  ];
  return FileMeta(
    producer: producer,
    creator: creator,
    created: created,
    modified: modified,
    editors: editors,
  );
}

DateTime? _parsePdfDate(String? s) {
  if (s == null) return null;
  final m = RegExp(r'D:(\d{4})(\d{2})?(\d{2})?(\d{2})?(\d{2})?(\d{2})?')
      .firstMatch(s);
  if (m == null) return null;
  int g(int i, int def) => int.tryParse(m.group(i) ?? '') ?? def;
  try {
    return DateTime.utc(g(1, 1970), g(2, 1), g(3, 1), g(4, 0), g(5, 0), g(6, 0));
  } catch (_) {
    return null;
  }
}

CheckResult metadataCheck(FileMeta m) {
  final notes = <String>[];
  var score = 0.0;
  if (m.editors.isNotEmpty) {
    score = 0.9;
    notes.add('Logiciel de retouche détecté : ${m.editors.join(', ')}.');
  }
  if (m.created != null && m.modified != null) {
    final d = m.modified!.difference(m.created!);
    if (d.inDays >= 1) {
      score = score < 0.5 ? 0.5 : score;
      notes.add('Fichier modifié ${d.inDays} jour(s) après sa création.');
    } else if (d.inSeconds > 60) {
      score = score < 0.3 ? 0.3 : score;
      notes.add('Fichier modifié après sa création.');
    }
  }
  if (notes.isEmpty) {
    final who = m.producer ?? m.creator;
    notes.add(
      who == null
          ? 'Aucune métadonnée exploitable (neutre).'
          : 'Produit par « $who », aucun signe de retouche.',
    );
  }
  return CheckResult(
    id: CheckId.metadata,
    score: score,
    summary: notes.join(' '),
  );
}
