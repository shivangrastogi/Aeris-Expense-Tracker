import 'dart:math' as math;
import 'package:flutter/material.dart';

/// An animated circular progress ring with rounded caps and a center slot.
/// Used on Home to show "budget used" at a glance. Colour shifts from the
/// given [color] toward red as it approaches/exceeds 100%.
class BudgetRing extends StatelessWidget {
  final double progress; // 0..1+ (may exceed 1 when over budget)
  final double size;
  final double strokeWidth;
  final Color color;
  final Widget? center;
  final Duration duration;

  const BudgetRing({
    super.key,
    required this.progress,
    this.size = 132,
    this.strokeWidth = 12,
    this.color = const Color(0xFF0EA5A4),
    this.center,
    this.duration = const Duration(milliseconds: 900),
  });

  @override
  Widget build(BuildContext context) {
    final track = Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5);
    return SizedBox(
      width: size,
      height: size,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: progress.clamp(0.0, 1.0)),
        duration: duration,
        curve: Curves.easeOutCubic,
        builder: (_, v, __) {
          // Blend toward red as the ring fills past 80%.
          final over = ((progress - 0.8) / 0.2).clamp(0.0, 1.0);
          final ringColor = Color.lerp(color, const Color(0xFFEF4444), over)!;
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
      ..shader = SweepGradient(
        startAngle: -math.pi / 2,
        endAngle: 3 * math.pi / 2,
        colors: [color.withValues(alpha: 0.65), color],
      ).createShader(Rect.fromCircle(center: center, radius: radius))
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
