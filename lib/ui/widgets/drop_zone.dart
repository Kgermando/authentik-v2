import 'dart:math' as math;

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../services/document_loader.dart';

/// Zone de dépôt : glisser un PDF / une image, ou cliquer pour choisir.
class DropZone extends StatefulWidget {
  const DropZone({
    super.key,
    required this.onFiles,
    this.compact = false,
    this.disabled = false,
  });

  final void Function(List<String> paths) onFiles;
  final bool compact;
  final bool disabled;

  @override
  State<DropZone> createState() => _DropZoneState();
}

class _DropZoneState extends State<DropZone> {
  bool _hover = false;
  bool _over = false;

  Future<void> _pick() async {
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: supportedExtensions.toList(),
    );
    if (picked.isEmpty) return;
    final paths = [for (final f in picked) if (f.path != null) f.path!];
    if (paths.isNotEmpty) widget.onFiles(paths);
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final active = _over || _hover;
    final h = widget.compact ? 108.0 : 250.0;
    return DropTarget(
      enable: !widget.disabled,
      onDragEntered: (_) => setState(() => _over = true),
      onDragExited: (_) => setState(() => _over = false),
      onDragDone: (d) {
        setState(() => _over = false);
        final paths = [for (final f in d.files) f.path];
        if (paths.isNotEmpty) widget.onFiles(paths);
      },
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.disabled ? null : _pick,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            height: h,
            decoration: BoxDecoration(
              color: active ? p.accentSoft : p.surface,
              borderRadius: BorderRadius.circular(22),
            ),
            child: CustomPaint(
              painter: _DashedBorder(
                color: active ? p.accent : p.muted.withValues(alpha: 0.45),
                radius: 22,
                width: active ? 2.2 : 1.5,
              ),
              child: Center(
                child: widget.compact ? _compact(p) : _full(p, active),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _full(Palette p, bool active) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedScale(
            scale: active ? 1.12 : 1,
            duration: const Duration(milliseconds: 220),
            child: Container(
              width: 68,
              height: 68,
              decoration: BoxDecoration(
                color: p.accent.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.upload_file_rounded, size: 32, color: p.accent),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            _over ? 'Relâchez pour analyser' : 'Déposez un certificat ici',
            style: TextStyle(
              fontFamilyFallback: kSerif,
              fontSize: 22,
              fontWeight: FontWeight.w600,
              color: p.ink,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'PDF, PNG, JPG, TIFF, BMP ou WEBP · ou cliquez pour parcourir',
            style: TextStyle(color: p.muted, fontSize: 13.5),
          ),
          const SizedBox(height: 4),
          Text(
            'Le document n’est jamais enregistré, seul le résultat est conservé.',
            style: TextStyle(color: p.muted, fontSize: 12),
          ),
        ],
      );

  Widget _compact(Palette p) => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.upload_file_rounded, color: p.accent),
          const SizedBox(width: 12),
          Text(
            _over ? 'Relâchez pour analyser' : 'Analyser un autre document',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: p.ink,
              fontSize: 15,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            'glisser-déposer ou cliquer',
            style: TextStyle(color: p.muted, fontSize: 13),
          ),
        ],
      );
}

class _DashedBorder extends CustomPainter {
  _DashedBorder({required this.color, required this.radius, required this.width});

  final Color color;
  final double radius;
  final double width;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );
    final path = Path()..addRRect(rrect);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = width;
    for (final m in path.computeMetrics()) {
      var d = 0.0;
      while (d < m.length) {
        final len = math.min(9.0, m.length - d);
        canvas.drawPath(m.extractPath(d, d + len), paint);
        d += 15;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorder o) =>
      o.color != color || o.width != width || o.radius != radius;
}
