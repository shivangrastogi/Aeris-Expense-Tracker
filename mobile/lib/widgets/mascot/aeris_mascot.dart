import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../core/theme.dart';

enum MascotMood { happy, neutral, worried, celebrate }

/// "Aeris" — a fully custom-painted, offline finance buddy. It idly bobs and
/// blinks, and its colour + expression react to the user's money situation.
/// No image/Lottie assets needed.
class AerisMascot extends StatefulWidget {
  final MascotMood mood;
  final double size;

  /// Bump this to replay the pop/shimmer reaction (e.g. on tap), even when
  /// the mood hasn't changed.
  final int reactKey;
  const AerisMascot(
      {super.key, required this.mood, this.size = 96, this.reactKey = 0});

  @override
  State<AerisMascot> createState() => _AerisMascotState();
}

class _AerisMascotState extends State<AerisMascot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Color get _color => switch (widget.mood) {
        MascotMood.happy => AerisColors.moodHappy,
        MascotMood.neutral => AerisColors.moodNeutral,
        MascotMood.worried => AerisColors.moodWorried,
        MascotMood.celebrate => AerisColors.seed,
      };

  @override
  Widget build(BuildContext context) {
    final painter = AnimatedBuilder(
      animation: _c,
      builder: (_, __) => CustomPaint(
        size: Size(widget.size, widget.size),
        painter: _MascotPainter(t: _c.value, mood: widget.mood, color: _color),
      ),
    );
    // Replay a little pop whenever the mood changes or on tap.
    // RepaintBoundary keeps the mascot's per-frame repaints from invalidating
    // the surrounding scroll view (was a big source of scroll jitter).
    return RepaintBoundary(
      child: painter
          .animate(key: ValueKey('${widget.mood}-${widget.reactKey}'))
          .scaleXY(
              begin: 0.86, end: 1, duration: 420.ms, curve: Curves.elasticOut),
    );
  }
}

class _MascotPainter extends CustomPainter {
  final double t; // 0..1 loop
  final MascotMood mood;
  final Color color;

  _MascotPainter({required this.t, required this.mood, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final bob = math.sin(t * 2 * math.pi) * h * 0.025;
    canvas.translate(0, bob);

    final cx = w / 2;
    final bodyW = w * 0.72, bodyH = h * 0.74;
    final bodyRect = Rect.fromCenter(
        center: Offset(cx, h * 0.56), width: bodyW, height: bodyH);
    final rrect = RRect.fromRectAndRadius(bodyRect, Radius.circular(w * 0.30));

    // Cheap solid offset "shadow" (no per-frame blur — that caused jank).
    canvas.drawRRect(
      rrect.shift(const Offset(0, 3)),
      Paint()..color = color.withValues(alpha: 0.18),
    );

    // Antenna
    final antPaint = Paint()
      ..color = color
      ..strokeWidth = w * 0.03
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
        Offset(cx, bodyRect.top), Offset(cx, bodyRect.top - h * 0.12), antPaint);
    canvas.drawCircle(Offset(cx, bodyRect.top - h * 0.13), w * 0.045,
        Paint()..color = color);

    // Body gradient
    final bodyPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color.lerp(color, Colors.white, 0.18)!, color],
      ).createShader(bodyRect);
    canvas.drawRRect(rrect, bodyPaint);

    // Face plate (lighter inset)
    final face = RRect.fromRectAndRadius(
      Rect.fromCenter(
          center: Offset(cx, h * 0.54), width: bodyW * 0.82, height: bodyH * 0.62),
      Radius.circular(w * 0.22),
    );
    canvas.drawRRect(face, Paint()..color = Colors.white.withValues(alpha: 0.92));

    // Eyes
    final eyeY = h * 0.50;
    final eyeDx = w * 0.13;
    final blink = (t < 0.06) ? 0.12 : 1.0; // quick blink each loop
    _drawEye(canvas, Offset(cx - eyeDx, eyeY), w * 0.06, blink);
    _drawEye(canvas, Offset(cx + eyeDx, eyeY), w * 0.06, blink);

    // Cheeks (happy / celebrate)
    if (mood == MascotMood.happy || mood == MascotMood.celebrate) {
      final cheek = Paint()..color = const Color(0xFFFB7185).withValues(alpha: 0.35);
      canvas.drawCircle(Offset(cx - eyeDx - w * 0.02, eyeY + h * 0.07), w * 0.04, cheek);
      canvas.drawCircle(Offset(cx + eyeDx + w * 0.02, eyeY + h * 0.07), w * 0.04, cheek);
    }

    // Mouth
    _drawMouth(canvas, cx, h * 0.64, w);

    // Worried: sweat drop
    if (mood == MascotMood.worried) {
      final drop = Paint()..color = const Color(0xFF38BDF8);
      final p = Path()
        ..moveTo(cx + eyeDx + w * 0.10, eyeY - h * 0.02)
        ..quadraticBezierTo(cx + eyeDx + w * 0.15, eyeY + h * 0.04,
            cx + eyeDx + w * 0.10, eyeY + h * 0.05)
        ..quadraticBezierTo(cx + eyeDx + w * 0.05, eyeY + h * 0.04,
            cx + eyeDx + w * 0.10, eyeY - h * 0.02);
      canvas.drawPath(p, drop);
    }

    // Celebrate: sparkles orbiting
    if (mood == MascotMood.celebrate) {
      final spark = Paint()..color = AerisColors.warning;
      for (var i = 0; i < 4; i++) {
        final a = t * 2 * math.pi + i * math.pi / 2;
        final r = w * 0.46;
        _star(canvas, Offset(cx + math.cos(a) * r, h * 0.5 + math.sin(a) * r * 0.7),
            w * 0.035, spark);
      }
    }
  }

  void _drawEye(Canvas canvas, Offset c, double r, double openFactor) {
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.scale(1, openFactor);
    canvas.drawCircle(Offset.zero, r, Paint()..color = const Color(0xFF1F2937));
    // little highlight
    canvas.drawCircle(Offset(-r * 0.3, -r * 0.3), r * 0.3,
        Paint()..color = Colors.white.withValues(alpha: 0.9));
    canvas.restore();
  }

  void _drawMouth(Canvas canvas, double cx, double y, double w) {
    final paint = Paint()
      ..color = const Color(0xFF1F2937)
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.035
      ..strokeCap = StrokeCap.round;
    final path = Path();
    switch (mood) {
      case MascotMood.happy:
        path.moveTo(cx - w * 0.10, y);
        path.quadraticBezierTo(cx, y + w * 0.10, cx + w * 0.10, y);
        canvas.drawPath(path, paint);
        break;
      case MascotMood.neutral:
        path.moveTo(cx - w * 0.07, y + w * 0.02);
        path.lineTo(cx + w * 0.07, y + w * 0.02);
        canvas.drawPath(path, paint);
        break;
      case MascotMood.worried:
        path.moveTo(cx - w * 0.09, y + w * 0.05);
        path.quadraticBezierTo(cx, y - w * 0.04, cx + w * 0.09, y + w * 0.05);
        canvas.drawPath(path, paint);
        break;
      case MascotMood.celebrate:
        // open happy mouth
        final fill = Paint()..color = const Color(0xFF1F2937);
        final mouth = Path()
          ..moveTo(cx - w * 0.10, y - w * 0.01)
          ..quadraticBezierTo(cx, y + w * 0.14, cx + w * 0.10, y - w * 0.01)
          ..close();
        canvas.drawPath(mouth, fill);
        break;
    }
  }

  void _star(Canvas canvas, Offset c, double r, Paint p) {
    final path = Path();
    for (var i = 0; i < 4; i++) {
      final a = i * math.pi / 2;
      path.moveTo(c.dx, c.dy);
      path.lineTo(c.dx + math.cos(a) * r, c.dy + math.sin(a) * r);
    }
    canvas.drawPath(
        path,
        p
          ..style = PaintingStyle.stroke
          ..strokeWidth = r * 0.5
          ..strokeCap = StrokeCap.round);
  }

  @override
  bool shouldRepaint(_MascotPainter old) =>
      old.t != t || old.mood != mood || old.color != color;
}
