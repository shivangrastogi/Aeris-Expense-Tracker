import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../models/avatar_skin.dart';

enum AvatarMood { sad, neutral, happy, excited }

/// A "2.5D" Aeris avatar: layered custom paint with parallax tilt (drag it, or
/// it eases back), an idle float, orbiting aura particles, rotating rays and
/// stage-based accessories. Reads as 3D, stays light, fully offline.
class AerisAvatar extends StatefulWidget {
  final AvatarSkin skin;
  final int stage; // 1..5 evolution
  final AvatarMood mood;
  final double size;

  /// When false, renders a single static frame (no controller, no repaint loop,
  /// no drag-tilt) — use for small decorative instances on busy screens.
  final bool animate;

  const AerisAvatar({
    super.key,
    required this.skin,
    this.stage = 1,
    this.mood = AvatarMood.happy,
    this.size = 200,
    this.animate = true,
  });

  @override
  State<AerisAvatar> createState() => _AerisAvatarState();
}

class _AerisAvatarState extends State<AerisAvatar>
    with SingleTickerProviderStateMixin {
  AnimationController? _c;
  Offset _tilt = Offset.zero;
  Offset _target = Offset.zero;

  @override
  void initState() {
    super.initState();
    if (widget.animate) {
      _c = AnimationController(vsync: this, duration: const Duration(seconds: 6))
        ..addListener(() {
          // Smoothly follow the drag target and ease back to centre.
          final next = Offset.lerp(_tilt, _target, 0.15)!;
          if ((next - _tilt).distance > 0.05) setState(() => _tilt = next);
        })
        ..repeat();
    }
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  void _onPan(DragUpdateDetails d) {
    const max = 26.0;
    _target = Offset(
      (_target.dx + d.delta.dx).clamp(-max, max),
      (_target.dy + d.delta.dy).clamp(-max, max),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Static instance — one paint, no controller, no gestures.
    if (!widget.animate || _c == null) {
      return RepaintBoundary(
        child: CustomPaint(
          size: Size.square(widget.size),
          painter: _AvatarPainter(
            t: 0,
            tilt: Offset.zero,
            skin: widget.skin,
            stage: widget.stage,
            mood: widget.mood,
          ),
        ),
      );
    }
    return GestureDetector(
      onPanUpdate: _onPan,
      onPanEnd: (_) => _target = Offset.zero,
      onPanCancel: () => _target = Offset.zero,
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: _c!,
          builder: (_, __) => CustomPaint(
            size: Size.square(widget.size),
            painter: _AvatarPainter(
              t: _c!.value,
              tilt: _tilt,
              skin: widget.skin,
              stage: widget.stage,
              mood: widget.mood,
            ),
          ),
        ),
      ),
    );
  }
}

class _AvatarPainter extends CustomPainter {
  final double t;
  final Offset tilt;
  final AvatarSkin skin;
  final int stage;
  final AvatarMood mood;

  _AvatarPainter({
    required this.t,
    required this.tilt,
    required this.skin,
    required this.stage,
    required this.mood,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final c0 = Offset(size.width / 2, size.height / 2);
    final r = math.min(size.width, size.height) * 0.30;
    final bob = math.sin(t * 2 * math.pi) * (size.height * 0.02);
    final base = c0 + Offset(0, bob);

    // ── Back glow (parallax: moves least) ──
    final glowC = base + tilt * 0.3;
    canvas.drawCircle(
      glowC,
      r * 1.9,
      Paint()
        ..shader = RadialGradient(colors: [
          skin.aura.withValues(alpha: 0.40),
          skin.aura.withValues(alpha: 0.0),
        ]).createShader(Rect.fromCircle(center: glowC, radius: r * 1.9)),
    );

    // ── Rotating rays (stage 2+) ──
    if (stage >= 2) {
      final rayPaint = Paint()
        ..color = skin.aura.withValues(alpha: 0.55)
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round;
      final n = 4 + stage * 2;
      final rot = t * 2 * math.pi;
      final rc = base + tilt * 0.5;
      for (var i = 0; i < n; i++) {
        final a = rot + i * 2 * math.pi / n;
        final dir = Offset(math.cos(a), math.sin(a));
        canvas.drawLine(rc + dir * (r * 1.25), rc + dir * (r * 1.5), rayPaint);
      }
    }

    // ── Orbiting aura particles (front: moves most) ──
    final pc = base + tilt * 1.3;
    final particles = 5 + stage * 3;
    for (var i = 0; i < particles; i++) {
      final a = -t * 2 * math.pi + i * 2 * math.pi / particles;
      final orbit = r * (1.45 + 0.12 * math.sin(t * 2 * math.pi + i));
      final pos = pc + Offset(math.cos(a), math.sin(a)) * orbit;
      canvas.drawCircle(
          pos,
          1.6 + (i % 3),
          Paint()..color = (i.isEven ? skin.accent : skin.aura).withValues(alpha: 0.85));
    }

    // ── Body (mid parallax) with soft 3D shading ──
    final bodyC = base + tilt * 0.8;
    canvas.drawCircle(
      bodyC,
      r,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.4, -0.5),
          colors: [
            Color.lerp(skin.core, Colors.white, 0.35)!,
            skin.core,
            Color.lerp(skin.core, Colors.black, 0.28)!,
          ],
          stops: const [0.0, 0.55, 1.0],
        ).createShader(Rect.fromCircle(center: bodyC, radius: r)),
    );
    // Rim highlight
    canvas.drawCircle(
      bodyC,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = skin.accent.withValues(alpha: 0.5),
    );
    // Glossy top reflection
    canvas.drawOval(
      Rect.fromCenter(
          center: bodyC + Offset(-r * 0.32, -r * 0.42),
          width: r * 0.7,
          height: r * 0.4),
      Paint()..color = Colors.white.withValues(alpha: 0.25),
    );

    // ── Face (front parallax) ──
    _face(canvas, base + tilt * 0.95, r);

    // ── Stage accessories ──
    if (stage >= 3) {
      // halo ring
      canvas.drawCircle(
        base + tilt * 0.6 - Offset(0, r * 1.05),
        r * 0.5,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = skin.accent.withValues(alpha: 0.9),
      );
    }
    if (stage >= 5) {
      // sparkle crown
      final crownC = base + tilt * 0.6 - Offset(0, r * 1.05);
      for (var i = 0; i < 5; i++) {
        final a = -math.pi / 2 + (i - 2) * 0.4;
        final p = crownC + Offset(math.cos(a), math.sin(a)) * r * 0.5;
        _sparkle(canvas, p, 4, skin.accent);
      }
    }
  }

  void _face(Canvas canvas, Offset c, double r) {
    final eyeY = c.dy - r * 0.1;
    final dx = r * 0.34;
    final eyePaint = Paint()..color = const Color(0xFF06231F);

    if (mood == AvatarMood.excited) {
      // star eyes
      _sparkle(canvas, Offset(c.dx - dx, eyeY), r * 0.16, const Color(0xFF06231F));
      _sparkle(canvas, Offset(c.dx + dx, eyeY), r * 0.16, const Color(0xFF06231F));
    } else if (mood == AvatarMood.sad) {
      canvas.drawCircle(Offset(c.dx - dx, eyeY), r * 0.1, eyePaint);
      canvas.drawCircle(Offset(c.dx + dx, eyeY), r * 0.1, eyePaint);
    } else {
      canvas.drawCircle(Offset(c.dx - dx, eyeY), r * 0.12, eyePaint);
      canvas.drawCircle(Offset(c.dx + dx, eyeY), r * 0.12, eyePaint);
      // little glints
      final glint = Paint()..color = Colors.white;
      canvas.drawCircle(Offset(c.dx - dx + r * 0.04, eyeY - r * 0.04), r * 0.04, glint);
      canvas.drawCircle(Offset(c.dx + dx + r * 0.04, eyeY - r * 0.04), r * 0.04, glint);
    }

    // mouth
    final mouth = Paint()
      ..color = const Color(0xFF06231F)
      ..style = PaintingStyle.stroke
      ..strokeWidth = r * 0.07
      ..strokeCap = StrokeCap.round;
    final my = c.dy + r * 0.32;
    final path = Path();
    switch (mood) {
      case AvatarMood.happy:
      case AvatarMood.excited:
        path.moveTo(c.dx - r * 0.22, my);
        path.quadraticBezierTo(c.dx, my + r * 0.28, c.dx + r * 0.22, my);
        break;
      case AvatarMood.neutral:
        path.moveTo(c.dx - r * 0.18, my + r * 0.05);
        path.lineTo(c.dx + r * 0.18, my + r * 0.05);
        break;
      case AvatarMood.sad:
        path.moveTo(c.dx - r * 0.22, my + r * 0.12);
        path.quadraticBezierTo(c.dx, my - r * 0.14, c.dx + r * 0.22, my + r * 0.12);
        break;
    }
    canvas.drawPath(path, mouth);
  }

  void _sparkle(Canvas canvas, Offset c, double s, Color color) {
    final p = Paint()..color = color;
    final path = Path();
    for (var i = 0; i < 4; i++) {
      final a = i * math.pi / 2;
      path.moveTo(c.dx, c.dy);
      path.lineTo(c.dx + math.cos(a - 0.3) * s * 0.4,
          c.dy + math.sin(a - 0.3) * s * 0.4);
      path.lineTo(c.dx + math.cos(a) * s, c.dy + math.sin(a) * s);
      path.lineTo(c.dx + math.cos(a + 0.3) * s * 0.4,
          c.dy + math.sin(a + 0.3) * s * 0.4);
      path.close();
    }
    canvas.drawPath(path, p);
  }

  @override
  bool shouldRepaint(_AvatarPainter old) =>
      old.t != t ||
      old.tilt != tilt ||
      old.skin.id != skin.id ||
      old.stage != stage ||
      old.mood != mood;
}
