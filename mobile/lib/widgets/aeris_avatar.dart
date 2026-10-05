import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../models/avatar_skin.dart';

enum AvatarMood { sad, neutral, happy, excited }

/// Themed Aeris character — a faithful Flutter port of the new-GUI
/// `AvatarChar` (flow-avatars.jsx). Each avatar is the Aeris blob body plus a
/// per-id accessory layer, drawn in the GUI's `0 0 128 148` viewBox and scaled
/// to [size]. Animations mirror the GUI's CSS keyframes exactly:
///   • av-float  2.6s  — whole character gently bobs
///   • av-swing  1.4s  — warrior sword / ninja headband tail
///   • av-wing   0.9s  — dragon & phoenix wings flap
///   • av-flame  0.7s  — phoenix flame crown flickers
///   • av-spark  1.6s  — sprout/wizard/astro sparkles pulse
///   • av-glow   2.2s  — soft back-glow breathes
class AerisAvatar extends StatefulWidget {
  final AvatarSkin skin;

  /// Kept for API compatibility with existing call-sites; the GUI character is
  /// id-driven, so [stage]/[mood] no longer change the drawing.
  final int stage;
  final AvatarMood mood;
  final double size;

  /// When false, renders a single static frame (no ticker, no repaint loop).
  final bool animate;

  /// When false, the soft radial back-glow is omitted — for "logo" placements
  /// (app header, auth brand) where the mascot should read clean.
  final bool glow;

  const AerisAvatar({
    super.key,
    required this.skin,
    this.stage = 1,
    this.mood = AvatarMood.happy,
    this.size = 200,
    this.animate = true,
    this.glow = true,
  });

  @override
  State<AerisAvatar> createState() => _AerisAvatarState();
}

class _AerisAvatarState extends State<AerisAvatar>
    with SingleTickerProviderStateMixin {
  Ticker? _ticker;
  final ValueNotifier<double> _t = ValueNotifier<double>(0);
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    if (widget.animate) {
      // Ticker.elapsed is monotonic, so sin/cos phases never jump. TickerMode
      // (e.g. RootShell's per-tab guard) pauses it automatically off-screen.
      // Started in didChangeDependencies, once we know the motion setting.
      _ticker = createTicker((elapsed) {
        _t.value = elapsed.inMicroseconds / 1e6;
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // System "remove animations" → render the still pose, no ticking.
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    final t = _ticker;
    if (t == null) return;
    if (_reduceMotion && t.isActive) t.stop();
    if (!_reduceMotion && !t.isActive) t.start();
  }

  @override
  void dispose() {
    _ticker?.dispose();
    _t.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.animate || _reduceMotion) {
      return RepaintBoundary(
        child: CustomPaint(
          size: Size.square(widget.size),
          painter: _AvatarPainter(
            id: widget.skin.id,
            c1: widget.skin.core,
            c2: widget.skin.aura,
            time: 0,
            animate: false,
            glow: widget.glow,
          ),
        ),
      );
    }
    return RepaintBoundary(
      child: ValueListenableBuilder<double>(
        valueListenable: _t,
        builder: (_, t, __) => CustomPaint(
          size: Size.square(widget.size),
          painter: _AvatarPainter(
            id: widget.skin.id,
            c1: widget.skin.core,
            c2: widget.skin.aura,
            time: t,
            animate: true,
            glow: widget.glow,
          ),
        ),
      ),
    );
  }
}

// ── Character ids by face style (mirrors flow-avatars.jsx) ───────────────────
const _happyEyes = {'sprout', 'astro', 'king'};
const _fierceEyes = {'warrior', 'dragon', 'ninja', 'phoenix'};
const _flatMouth = {'warrior', 'dragon', 'ninja'};

const _ink = Color(0xFF0B0B0B);

class _AvatarPainter extends CustomPainter {
  final String id;
  final Color c1; // accent
  final Color c2; // accent2
  final double time;
  final bool animate;
  final bool glow;

  _AvatarPainter({
    required this.id,
    required this.c1,
    required this.c2,
    required this.time,
    required this.animate,
    required this.glow,
  });

  // 0→1→0 ease-in-out oscillation over [period] seconds.
  double _osc(double period) =>
      animate ? (1 - math.cos(2 * math.pi * (time / period))) / 2 : 0.0;

  @override
  void paint(Canvas canvas, Size size) {
    // Fit the 128×148 viewBox by height, centred horizontally.
    final s = size.height / 148.0;
    final ox = (size.width - 128 * s) / 2;
    canvas.save();
    canvas.translate(ox, 0);
    canvas.scale(s);

    // ── Back glow (sibling of the float group: does not bob) ──
    if (glow) {
      final gOpacity = animate ? 0.35 + 0.35 * _osc(2.2) : 0.4;
      canvas.drawOval(
        Rect.fromCenter(center: const Offset(64, 86), width: 104, height: 100),
        Paint()..color = c1.withValues(alpha: gOpacity),
      );
    }

    // ── Floating character group ──
    final floatDy = -6.5 * _osc(2.6);
    canvas.save();
    canvas.translate(0, floatDy);

    _behind(canvas);
    _body(canvas);
    _face(canvas);
    _front(canvas);

    canvas.restore(); // float
    canvas.restore(); // viewBox
  }

  // ── Shared blob body + face ─────────────────────────────────────────────
  void _body(Canvas canvas) {
    const rect = Rect.fromLTWH(32, 56, 64, 62);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(27)),
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.2, -0.4),
          radius: 0.95,
          colors: [c1, c2],
        ).createShader(rect),
    );
    // cheek shine
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(50, 74), width: 18, height: 14),
      Paint()..color = Colors.white.withValues(alpha: 0.22),
    );
  }

  void _face(Canvas canvas) {
    final stroke = Paint()
      ..color = _ink
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final fill = Paint()..color = _ink;

    if (_fierceEyes.contains(id)) {
      stroke.strokeWidth = 3.4;
      canvas.drawLine(const Offset(50, 80), const Offset(62, 84), stroke);
      canvas.drawLine(const Offset(78, 84), const Offset(66, 80), stroke);
      canvas.drawCircle(const Offset(55, 86), 2.6, fill);
      canvas.drawCircle(const Offset(73, 86), 2.6, fill);
    } else if (_happyEyes.contains(id)) {
      stroke.strokeWidth = 3.2;
      canvas.drawPath(
          (Path()
            ..moveTo(50, 84)
            ..quadraticBezierTo(55, 78, 60, 84)),
          stroke);
      canvas.drawPath(
          (Path()
            ..moveTo(68, 84)
            ..quadraticBezierTo(73, 78, 78, 84)),
          stroke);
    } else {
      canvas.drawCircle(const Offset(55, 84), 3.4, fill);
      canvas.drawCircle(const Offset(73, 84), 3.4, fill);
    }

    // mouth
    if (_flatMouth.contains(id)) {
      stroke.strokeWidth = 3.2;
      canvas.drawLine(const Offset(56, 98), const Offset(72, 98), stroke);
    } else if (id == 'phoenix') {
      canvas.drawPath(
          (Path()
            ..moveTo(57, 96)
            ..quadraticBezierTo(64, 104, 71, 96)
            ..close()),
          fill);
    } else {
      stroke.strokeWidth = 3.2;
      canvas.drawPath(
          (Path()
            ..moveTo(55, 96)
            ..quadraticBezierTo(64, 105, 73, 96)),
          stroke);
    }
  }

  // ── Layers BEHIND the body ──────────────────────────────────────────────
  void _behind(Canvas canvas) {
    switch (id) {
      case 'dragon':
        _wing(canvas,
            path: (Path()
              ..moveTo(92, 64)
              ..quadraticBezierTo(120, 50, 122, 78)
              ..quadraticBezierTo(108, 74, 96, 86)
              ..close()),
            color: const Color(0xFFB45309).withValues(alpha: 0.9),
            pivot: const Offset(119, 68),
            left: true);
        _wing(canvas,
            path: (Path()
              ..moveTo(36, 64)
              ..quadraticBezierTo(8, 50, 6, 78)
              ..quadraticBezierTo(20, 74, 32, 86)
              ..close()),
            color: const Color(0xFFB45309).withValues(alpha: 0.9),
            pivot: const Offset(9, 68),
            left: false);
        break;
      case 'phoenix':
        _wing(canvas,
            path: (Path()
              ..moveTo(90, 66)
              ..quadraticBezierTo(118, 54, 124, 84)
              ..quadraticBezierTo(104, 78, 94, 90)
              ..close()),
            color: const Color(0xFFF97316).withValues(alpha: 0.92),
            pivot: const Offset(120.6, 72),
            left: true);
        _wing(canvas,
            path: (Path()
              ..moveTo(38, 66)
              ..quadraticBezierTo(10, 54, 4, 84)
              ..quadraticBezierTo(24, 78, 34, 90)
              ..close()),
            color: const Color(0xFFF97316).withValues(alpha: 0.92),
            pivot: const Offset(7.4, 72),
            left: false);
        break;
      case 'wizard':
        canvas.drawOval(
          Rect.fromCenter(center: const Offset(64, 88), width: 100, height: 96),
          Paint()..color = const Color(0xFF8B5CF6).withValues(alpha: 0.18),
        );
        break;
    }
  }

  void _wing(Canvas canvas,
      {required Path path,
      required Color color,
      required Offset pivot,
      required bool left}) {
    // av-wing-l: 0 → -18°, av-wing-r: 0 → +18°, 0.9s.
    final deg = (left ? -18.0 : 18.0) * _osc(0.9);
    canvas.save();
    canvas.translate(pivot.dx, pivot.dy);
    canvas.rotate(deg * math.pi / 180);
    canvas.translate(-pivot.dx, -pivot.dy);
    canvas.drawPath(path, Paint()..color = color);
    canvas.restore();
  }

  // ── Layers IN FRONT of the body (per-character costume) ──────────────────
  void _front(Canvas canvas) {
    switch (id) {
      case 'sprout':
        _sprout(canvas);
        break;
      case 'warrior':
        _warrior(canvas);
        break;
      case 'ninja':
        _ninja(canvas);
        break;
      case 'knight':
        _knight(canvas);
        break;
      case 'wizard':
        _wizard(canvas);
        break;
      case 'astro':
        _astro(canvas);
        break;
      case 'dragon':
        _dragon(canvas);
        break;
      case 'phoenix':
        _phoenix(canvas);
        break;
      case 'king':
        _king(canvas);
        break;
    }
  }

  void _sprout(Canvas canvas) {
    // stem
    canvas.drawLine(
        const Offset(64, 56),
        const Offset(64, 40),
        Paint()
          ..color = const Color(0xFF0F766E)
          ..strokeWidth = 3.4
          ..strokeCap = StrokeCap.round);
    // animated leaf (av-spark)
    _sparked(canvas, const Offset(62, 36), () {
      canvas.drawPath(
          (Path()
            ..moveTo(64, 44)
            ..quadraticBezierTo(52, 36, 60, 28)
            ..quadraticBezierTo(68, 34, 64, 44)
            ..close()),
          Paint()..color = const Color(0xFF34D399));
    });
    // static leaf
    canvas.drawPath(
        (Path()
          ..moveTo(64, 46)
          ..quadraticBezierTo(76, 38, 70, 30)
          ..quadraticBezierTo(62, 36, 64, 46)
          ..close()),
        Paint()..color = const Color(0xFF10B981));
  }

  void _warrior(Canvas canvas) {
    // shield
    final shield = Path()
      ..moveTo(30, 84)
      ..quadraticBezierTo(24, 84, 24, 92)
      ..quadraticBezierTo(24, 104, 36, 110)
      ..quadraticBezierTo(44, 104, 44, 92)
      ..quadraticBezierTo(44, 84, 38, 84)
      ..close();
    canvas.drawPath(shield, Paint()..color = const Color(0xFF9CA3AF));
    canvas.drawPath(
        shield,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = const Color(0xFF4B5563));
    _rupee(canvas, const Offset(34, 95), 11, const Color(0xFFB45309));
    // swinging sword (av-swing, pivot 50% 80% of its bbox)
    canvas.save();
    const pivot = Offset(93, 90.4);
    final deg = -14 + (20 - -14) * _osc(1.4);
    canvas.translate(pivot.dx, pivot.dy);
    canvas.rotate(deg * math.pi / 180);
    canvas.translate(-pivot.dx, -pivot.dy);
    _rrect(canvas, 90, 44, 6, 44, 3, const Color(0xFFE5E7EB),
        stroke: const Color(0xFF9CA3AF), sw: 1);
    _rrect(canvas, 84, 86, 18, 6, 2, const Color(0xFF92400E));
    _rrect(canvas, 91, 90, 4, 12, 2, const Color(0xFF92400E));
    canvas.restore();
    // helmet band
    _rrect(canvas, 46, 58, 36, 7, 3, const Color(0xFFB91C1C));
  }

  void _ninja(Canvas canvas) {
    _rrect(canvas, 34, 78, 60, 13, 3, const Color(0xFF0F172A));
    final glint = Paint()
      ..color = Colors.white
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(const Offset(50, 80), const Offset(62, 84), glint);
    canvas.drawLine(const Offset(78, 84), const Offset(66, 80), glint);
    // headband tail (av-swing, pivot 50% 80%)
    canvas.save();
    const pivot = Offset(99, 94.4);
    final deg = -14 + (20 - -14) * _osc(1.4);
    canvas.translate(pivot.dx, pivot.dy);
    canvas.rotate(deg * math.pi / 180);
    canvas.translate(-pivot.dx, -pivot.dy);
    canvas.drawPath(
        (Path()
          ..moveTo(92, 80)
          ..quadraticBezierTo(108, 84, 104, 98)
          ..quadraticBezierTo(98, 90, 90, 88)
          ..close()),
        Paint()..color = const Color(0xFFDC2626));
    canvas.restore();
  }

  void _knight(Canvas canvas) {
    final helmet = Path()
      ..moveTo(44, 60)
      ..quadraticBezierTo(64, 44, 84, 60)
      ..lineTo(84, 66)
      ..lineTo(44, 66)
      ..close();
    canvas.drawPath(helmet, Paint()..color = const Color(0xFFCBD5E1));
    canvas.drawPath(
        helmet,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = const Color(0xFF94A3B8));
    _rrect(canvas, 60, 66, 8, 18, 2, const Color(0xFF64748B));
    // plume
    canvas.drawPath(
        (Path()
          ..moveTo(64, 44)
          ..quadraticBezierTo(64, 32, 72, 30)),
        Paint()
          ..color = const Color(0xFFEF4444)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round);
    // shield
    final shield = Path()
      ..moveTo(92, 86)
      ..quadraticBezierTo(98, 86, 98, 94)
      ..quadraticBezierTo(98, 106, 86, 112)
      ..quadraticBezierTo(80, 106, 80, 94)
      ..quadraticBezierTo(80, 86, 86, 86)
      ..close();
    canvas.drawPath(shield, Paint()..color = const Color(0xFF94A3B8));
    canvas.drawPath(
        shield,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = const Color(0xFF475569));
    final cross = Paint()
      ..color = const Color(0xFF475569)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(const Offset(89, 92), const Offset(89, 106), cross);
    canvas.drawLine(const Offset(83, 99), const Offset(95, 99), cross);
  }

  void _wizard(Canvas canvas) {
    // hat
    canvas.drawPath(
        (Path()
          ..moveTo(44, 60)
          ..lineTo(64, 18)
          ..lineTo(84, 60)
          ..close()),
        Paint()..color = const Color(0xFF5B21B6));
    canvas.drawPath(
        (Path()
          ..moveTo(44, 60)
          ..lineTo(84, 60)
          ..lineTo(80, 54)
          ..lineTo(48, 54)
          ..close()),
        Paint()..color = const Color(0xFF4C1D95));
    _sparked(canvas, const Offset(64, 30), () {
      canvas.drawCircle(
          const Offset(64, 30), 3.4, Paint()..color = const Color(0xFFFDE68A));
    });
    // staff (gently floats, av-float) + glowing orb
    canvas.save();
    canvas.translate(0, -3 * _osc(2.6));
    _rrect(canvas, 92, 52, 5, 52, 2.5, const Color(0xFF92400E));
    canvas.drawCircle(
        const Offset(94, 50), 7, Paint()..color = const Color(0xFFA78BFA));
    _sparked(canvas, const Offset(94, 50), () {
      canvas.drawCircle(const Offset(94, 50), 3, Paint()..color = Colors.white);
    });
    canvas.restore();
  }

  void _astro(Canvas canvas) {
    canvas.drawCircle(const Offset(64, 86), 34,
        Paint()..color = const Color(0xFFBAE6FD).withValues(alpha: 0.28));
    canvas.drawCircle(
        const Offset(64, 86),
        34,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..color = const Color(0xFF7DD3FC));
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(52, 74), width: 16, height: 10),
      Paint()..color = Colors.white.withValues(alpha: 0.5),
    );
    canvas.drawLine(
        const Offset(64, 52),
        const Offset(64, 42),
        Paint()
          ..color = const Color(0xFF0EA5A4)
          ..strokeWidth = 2.6);
    _sparked(canvas, const Offset(64, 40), () {
      canvas.drawCircle(
          const Offset(64, 40), 3.4, Paint()..color = const Color(0xFF34D399));
    });
  }

  void _dragon(Canvas canvas) {
    // horns
    canvas.drawPath(
        (Path()
          ..moveTo(48, 58)
          ..quadraticBezierTo(42, 44, 50, 42)
          ..quadraticBezierTo(52, 52, 56, 58)
          ..close()),
        Paint()..color = const Color(0xFFFCD34D));
    canvas.drawPath(
        (Path()
          ..moveTo(80, 58)
          ..quadraticBezierTo(86, 44, 78, 42)
          ..quadraticBezierTo(76, 52, 72, 58)
          ..close()),
        Paint()..color = const Color(0xFFFCD34D));
    // gold coin pile
    _coin(canvas, const Offset(40, 112), 7, const Color(0xFFFCD34D));
    _coin(canvas, const Offset(52, 116), 6, const Color(0xFFFDE68A));
  }

  void _phoenix(Canvas canvas) {
    // flame crown (av-flame, origin 50% 100%)
    canvas.save();
    const pivot = Offset(63, 56);
    final f = _osc(0.7);
    canvas.translate(pivot.dx, pivot.dy);
    canvas.scale(1, 1 + 0.18 * f);
    canvas.translate(-pivot.dx, -pivot.dy);
    canvas.translate(0, -2 * f);
    canvas.drawPath(
        (Path()
          ..moveTo(52, 56)
          ..quadraticBezierTo(54, 40, 60, 50)
          ..quadraticBezierTo(62, 38, 66, 50)
          ..quadraticBezierTo(70, 40, 74, 56)
          ..close()),
        Paint()..color = const Color(0xFFF97316));
    canvas.drawPath(
        (Path()
          ..moveTo(56, 56)
          ..quadraticBezierTo(60, 46, 64, 56)
          ..quadraticBezierTo(68, 46, 72, 56)
          ..close()),
        Paint()..color = const Color(0xFFFCD34D));
    canvas.restore();
  }

  void _king(Canvas canvas) {
    final crown = Path()
      ..moveTo(44, 58)
      ..lineTo(44, 42)
      ..lineTo(54, 50)
      ..lineTo(64, 38)
      ..lineTo(74, 50)
      ..lineTo(84, 42)
      ..lineTo(84, 58)
      ..close();
    canvas.drawPath(
        crown,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFFDE68A), Color(0xFFF59E0B)],
          ).createShader(const Rect.fromLTWH(44, 38, 40, 20)));
    canvas.drawCircle(
        const Offset(54, 46), 2.4, Paint()..color = const Color(0xFFEF4444));
    canvas.drawCircle(
        const Offset(64, 42), 2.6, Paint()..color = const Color(0xFF3B82F6));
    canvas.drawCircle(
        const Offset(74, 46), 2.4, Paint()..color = const Color(0xFF10B981));
    _rrect(canvas, 44, 56, 40, 6, 2, const Color(0xFFB45309));
    // scepter (av-float)
    canvas.save();
    canvas.translate(0, -3 * _osc(2.6));
    _rrect(canvas, 93, 58, 5, 46, 2.5, const Color(0xFFB45309));
    canvas.drawCircle(
        const Offset(95.5, 56), 6, Paint()..color = const Color(0xFFFBBF24));
    canvas.drawCircle(
        const Offset(95.5, 56),
        6,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = const Color(0xFF92400E));
    canvas.restore();
  }

  // ── Small helpers ────────────────────────────────────────────────────────
  void _rrect(Canvas canvas, double x, double y, double w, double h, double r,
      Color color,
      {Color? stroke, double sw = 0}) {
    final rr =
        RRect.fromRectAndRadius(Rect.fromLTWH(x, y, w, h), Radius.circular(r));
    canvas.drawRRect(rr, Paint()..color = color);
    if (stroke != null) {
      canvas.drawRRect(
          rr,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = sw
            ..color = stroke);
    }
  }

  void _coin(Canvas canvas, Offset c, double r, Color color) {
    canvas.drawCircle(c, r, Paint()..color = color);
    canvas.drawCircle(
        c,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = const Color(0xFFB45309));
  }

  void _rupee(Canvas canvas, Offset c, double fontSize, Color color) {
    final tp = TextPainter(
      text: TextSpan(
          text: '₹',
          style: TextStyle(
              color: color, fontWeight: FontWeight.w800, fontSize: fontSize)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(c.dx - tp.width / 2, c.dy - tp.height / 2));
  }

  /// av-spark: opacity 0.2→1, scale 0.7→1.1, 1.6s — applied around [center].
  void _sparked(Canvas canvas, Offset center, VoidCallback draw) {
    if (!animate) {
      draw();
      return;
    }
    final f = _osc(1.6);
    final scale = 0.7 + 0.4 * f;
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.scale(scale);
    canvas.translate(-center.dx, -center.dy);
    // Opacity is approximated via a layer so the spark fades like the GUI.
    canvas.saveLayer(
      Rect.fromCenter(center: center, width: 40, height: 40),
      Paint()..color = Colors.white.withValues(alpha: 0.2 + 0.8 * f),
    );
    draw();
    canvas.restore();
    canvas.restore();
  }

  @override
  bool shouldRepaint(_AvatarPainter old) =>
      old.time != time ||
      old.id != id ||
      old.c1 != c1 ||
      old.c2 != c2 ||
      old.glow != glow ||
      old.animate != animate;
}
