import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../core/theme.dart';

/// Aperçu de la page analysée avec les zones suspectes surlignées.
/// L'image reste en mémoire : elle n'est jamais écrite sur disque.
class PageViewer extends StatefulWidget {
  const PageViewer({
    super.key,
    required this.result,
    required this.visible,
    this.focus,
  });

  final AnalysisResult result;

  /// Contrôles dont les zones sont affichées.
  final Set<CheckId> visible;

  /// Zone mise en avant (clic dans la liste).
  final Region? focus;

  @override
  State<PageViewer> createState() => _PageViewerState();
}

class _PageViewerState extends State<PageViewer>
    with SingleTickerProviderStateMixin {
  int _page = 0;
  final _tc = TransformationController();
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void didUpdateWidget(PageViewer old) {
    super.didUpdateWidget(old);
    if (old.result.id != widget.result.id) {
      _page = 0;
      _tc.value = Matrix4.identity();
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    _tc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final previews = widget.result.previews;
    if (previews.isEmpty) {
      return Center(
        child: Text(
          'Aperçu indisponible',
          style: TextStyle(color: p.muted),
        ),
      );
    }
    final page = previews[_page.clamp(0, previews.length - 1).toInt()];
    final regions = [
      for (final r in widget.result.regions)
        if (r.page == page.index && widget.visible.contains(r.check)) r,
    ];
    return Column(
      children: [
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: p.surfaceAlt,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: p.line),
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              children: [
                InteractiveViewer(
                  transformationController: _tc,
                  minScale: 1,
                  maxScale: 6,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: AspectRatio(
                        aspectRatio: page.width / page.height,
                        child: Container(
                          decoration: BoxDecoration(
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.18),
                                blurRadius: 18,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              Image.memory(
                                page.jpeg,
                                fit: BoxFit.fill,
                                gaplessPlayback: true,
                                filterQuality: FilterQuality.medium,
                              ),
                              AnimatedBuilder(
                                animation: _pulse,
                                builder: (context, _) => CustomPaint(
                                  painter: _RegionPainter(
                                    regions: regions,
                                    palette: p,
                                    focus: widget.focus,
                                    pulse: _pulse.value,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  right: 10,
                  top: 10,
                  child: IconButton.filledTonal(
                    tooltip: 'Recentrer',
                    onPressed: () => _tc.value = Matrix4.identity(),
                    icon: const Icon(Icons.center_focus_strong_outlined),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (previews.length > 1)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  onPressed: _page > 0 ? () => setState(() => _page--) : null,
                  icon: const Icon(Icons.chevron_left_rounded),
                ),
                Text('Page ${_page + 1} / ${previews.length}'),
                IconButton(
                  onPressed: _page < previews.length - 1
                      ? () => setState(() => _page++)
                      : null,
                  icon: const Icon(Icons.chevron_right_rounded),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _RegionPainter extends CustomPainter {
  _RegionPainter({
    required this.regions,
    required this.palette,
    required this.focus,
    required this.pulse,
  });

  final List<Region> regions;
  final Palette palette;
  final Region? focus;
  final double pulse;

  @override
  void paint(Canvas canvas, Size size) {
    for (final r in regions) {
      final color = palette.checkColor(r.check);
      final isFocus = focus != null &&
          focus!.check == r.check &&
          focus!.left == r.left &&
          focus!.top == r.top;
      final rect = Rect.fromLTWH(
        r.left * size.width,
        r.top * size.height,
        r.width * size.width,
        r.height * size.height,
      ).inflate(3);
      final rr = RRect.fromRectAndRadius(rect, const Radius.circular(6));
      final fillA = isFocus ? 0.16 + 0.14 * pulse : 0.12;
      canvas.drawRRect(
        rr,
        Paint()..color = color.withValues(alpha: fillA),
      );
      canvas.drawRRect(
        rr,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = isFocus ? 3.2 : 2
          ..color = color,
      );
      // Pastille du score.
      final tp = TextPainter(
        text: TextSpan(
          text: '${(r.score * 100).round()} %',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final tag = Rect.fromLTWH(
        rect.left,
        rect.top - tp.height - 6 < 0 ? rect.top + 2 : rect.top - tp.height - 6,
        tp.width + 10,
        tp.height + 4,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(tag, const Radius.circular(5)),
        Paint()..color = color,
      );
      tp.paint(canvas, Offset(tag.left + 5, tag.top + 2));
    }
  }

  @override
  bool shouldRepaint(_RegionPainter o) =>
      o.regions != regions || o.focus != focus || o.pulse != pulse;
}
