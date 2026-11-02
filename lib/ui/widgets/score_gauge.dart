import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../core/theme.dart';

const double _start = 3 * math.pi / 4; // 135°
const double _sweep = 3 * math.pi / 2; // 270°

/// Jauge animée du score de suspicion, avec le repère du seuil du profil.
class ScoreGauge extends StatelessWidget {
  const ScoreGauge({
    super.key,
    required this.probability,
    required this.threshold,
    required this.verdict,
    this.size = 240,
  });

  final double probability;
  final double threshold;
  final Verdict verdict;
  final double size;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final color = p.verdictColor(verdict);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: probability),
      duration: const Duration(milliseconds: 1400),
      curve: Curves.easeOutCubic,
      builder: (context, v, _) {
        return SizedBox(
          width: size,
          height: size,
          child: CustomPaint(
            painter: _GaugePainter(
              value: v,
              threshold: threshold,
              color: color,
              track: p.line,
              tick: p.ink,
              bg: p.surface,
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${(v * 100).round()}',
                    style: TextStyle(
                      fontFamilyFallback: kSerif,
                      fontSize: size * 0.30,
                      fontWeight: FontWeight.w600,
                      height: 1,
                      color: color,
                    ),
                  ),
                  Text(
                    '% de suspicion',
                    style: TextStyle(color: p.muted, fontSize: size * 0.055),
                  ),
                  SizedBox(height: size * 0.03),
                  Text(
                    'seuil ${(threshold * 100).round()} %',
                    style: TextStyle(
                      color: p.muted,
                      fontSize: size * 0.05,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _GaugePainter extends CustomPainter {
  _GaugePainter({
    required this.value,
    required this.threshold,
    required this.color,
    required this.track,
    required this.tick,
    required this.bg,
  });

  final double value;
  final double threshold;
  final Color color;
  final Color track;
  final Color tick;
  final Color bg;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * 0.075;
    final rect = Rect.fromLTWH(
      stroke,
      stroke,
      size.width - 2 * stroke,
      size.height - 2 * stroke,
    );
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = track;
    canvas.drawArc(rect, _start, _sweep, false, base);

    if (value > 0.002) {
      final sweep = _sweep * value.clamp(0.0, 1.0);
      final shader = SweepGradient(
        startAngle: _start,
        endAngle: _start + _sweep,
        colors: [color.withValues(alpha: 0.35), color],
        transform: const GradientRotation(0),
      ).createShader(rect);
      final arc = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..shader = shader;
      canvas.drawArc(rect, _start, sweep, false, arc);
    }

    // Repère du seuil : trait radial qui traverse l'anneau.
    final a = _start + _sweep * threshold.clamp(0.0, 1.0);
    final c = rect.center;
    final r = rect.width / 2;
    final p1 = Offset(c.dx + (r - stroke * 0.85) * math.cos(a),
        c.dy + (r - stroke * 0.85) * math.sin(a));
    final p2 = Offset(c.dx + (r + stroke * 0.85) * math.cos(a),
        c.dy + (r + stroke * 0.85) * math.sin(a));
    canvas.drawLine(
      p1,
      p2,
      Paint()
        ..color = bg
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.butt,
    );
    canvas.drawLine(
      p1,
      p2,
      Paint()
        ..color = tick
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.butt,
    );
  }

  @override
  bool shouldRepaint(_GaugePainter o) =>
      o.value != value ||
      o.threshold != threshold ||
      o.color != color ||
      o.track != track;
}

/// Anneau de progression pendant l'analyse : arc de progression et reflet
/// qui balaie le cercle, pour montrer que le moteur travaille.
class ScanRing extends StatefulWidget {
  const ScanRing({super.key, required this.progress, this.size = 150});

  final double progress;
  final double size;

  @override
  State<ScanRing> createState() => _ScanRingState();
}

class _ScanRingState extends State<ScanRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: widget.progress),
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeOut,
        builder: (context, v, _) => AnimatedBuilder(
          animation: _c,
          builder: (context, _) => CustomPaint(
            painter: _RingPainter(
              progress: v,
              spin: _c.value,
              color: p.accent,
              track: p.line,
            ),
            child: Center(
              child: Text(
                '${(v * 100).round()}%',
                style: TextStyle(
                  fontFamilyFallback: kSerif,
                  fontSize: widget.size * 0.24,
                  fontWeight: FontWeight.w600,
                  color: p.ink,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.progress,
    required this.spin,
    required this.color,
    required this.track,
  });

  final double progress;
  final double spin;
  final Color color;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * 0.07;
    final rect = Rect.fromLTWH(
      stroke,
      stroke,
      size.width - 2 * stroke,
      size.height - 2 * stroke,
    );
    canvas.drawArc(
      rect,
      0,
      2 * math.pi,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = track,
    );
    canvas.drawArc(
      rect,
      -math.pi / 2,
      2 * math.pi * progress.clamp(0.0, 1.0),
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..color = color,
    );
    // Reflet qui tourne.
    final a = spin * 2 * math.pi;
    canvas.drawArc(
      rect,
      a,
      0.55,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke * 0.45
        ..strokeCap = StrokeCap.round
        ..color = color.withValues(alpha: 0.45),
    );
  }

  @override
  bool shouldRepaint(_RingPainter o) =>
      o.progress != progress || o.spin != spin || o.color != color;
}
