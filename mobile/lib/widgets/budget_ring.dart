import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../core/theme.dart';

/// An animated circular progress ring with rounded caps and a center slot.
///
/// As a *budget* ring ([warnOverflow], the default) it turns red (the
/// design's danger token) once it goes over 100%. Rings that show a share
/// (e.g. "biggest category = full ring") pass `warnOverflow: false` — a full
/// share ring is not a warning.
class BudgetRing extends StatelessWidget {
  final double progress; // 0..1+ (may exceed 1 when over budget)
  final double size;
  final double strokeWidth;
  final Color color;
  final Widget? center;
  final Duration duration;
  final bool warnOverflow;

  const BudgetRing({
    super.key,
    required this.progress,
    this.size = 132,
    this.strokeWidth = 12,
    this.color = const Color(0xFF2A6F66),
    this.center,
    this.duration = Mo.fill,
    this.warnOverflow = true,
  });

  @override
  Widget build(BuildContext context) {
    final tk = context.tk;
    final track = tk.track;
    return SizedBox(
      width: size,
      height: size,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: progress.clamp(0.0, 1.0)),
        duration: duration,
        curve: Mo.curve,
        builder: (_, v, __) {
          // A budget ring turns red only once it is actually over the cap;
          // near the limit it stays in its own hue (callers add the words).
          final ringColor = warnOverflow && progress > 1 ? tk.bad : color;
          return CustomPaint(
            painter: _RingPainter(
              progress: v,
              color: ringColor,
              track: track,
              strokeWidth: strokeWidth,
            ),
            child: Center(child: center),
          );
        },
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double progress;
  final Color color;
  final Color track;
  final double strokeWidth;

  _RingPainter({
    required this.progress,
    required this.color,
    required this.track,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;
    final trackPaint = Paint()
      ..color = track
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, trackPaint);

    final progPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      2 * math.pi * progress,
      false,
      progPaint,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress || old.color != color;
}
