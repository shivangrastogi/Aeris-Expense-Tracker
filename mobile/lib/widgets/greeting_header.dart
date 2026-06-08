import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

/// Time-of-day greeting: the user's name on top, then "Good morning/…"
/// with a custom-painted animated sky icon (sun with rotating rays + glow by
/// day, an orange low sun at evening, a moon with twinkling stars at night).
/// Fully offline — no GIF/Lottie assets.
class GreetingHeader extends StatefulWidget {
  final String name;
  const GreetingHeader({super.key, required this.name});

  @override
  State<GreetingHeader> createState() => _GreetingHeaderState();
}

enum _Sky { morning, afternoon, evening, night }

class _GreetingHeaderState extends State<GreetingHeader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(seconds: 6))
        ..repeat();

  ({_Sky sky, String label}) _now() {
    final h = DateTime.now().hour;
    if (h < 12) return (sky: _Sky.morning, label: 'Good morning');
    if (h < 17) return (sky: _Sky.afternoon, label: 'Good afternoon');
    if (h < 20) return (sky: _Sky.evening, label: 'Good evening');
    return (sky: _Sky.night, label: 'Good night');
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final info = _now();
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.name,
          style: Theme.of(context)
              .textTheme
              .headlineSmall
              ?.copyWith(fontWeight: FontWeight.w800),
        ).animate().fadeIn(duration: 350.ms).slideX(begin: -0.06, end: 0),
        const SizedBox(height: 2),
        Row(
          children: [
            RepaintBoundary(
              child: AnimatedBuilder(
                animation: _c,
                builder: (_, __) => CustomPaint(
                  size: const Size(26, 26),
                  painter: _SkyPainter(t: _c.value, sky: info.sky),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              info.label,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ).animate(delay: 120.ms).fadeIn(duration: 350.ms),
          ],
        ),
      ],
    );
  }
}

class _SkyPainter extends CustomPainter {
  final double t;
  final _Sky sky;
  _SkyPainter({required this.t, required this.sky});

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    switch (sky) {
      case _Sky.morning:
        _sun(canvas, c, size, const Color(0xFFFFC107), const Color(0xFFFF9800));
        break;
      case _Sky.afternoon:
        _sun(canvas, c, size, const Color(0xFFFFD54F), const Color(0xFFFFB300));
        break;
      case _Sky.evening:
        _sun(canvas, c, size, const Color(0xFFFF8A65), const Color(0xFFF4511E));
        break;
      case _Sky.night:
        _moon(canvas, c, size);
        break;
    }
  }

  void _sun(Canvas canvas, Offset c, Size size, Color core, Color ray) {
    final r = size.width * 0.22;
    // glow
    canvas.drawCircle(c, r * 1.7,
        Paint()..color = core.withOpacity(0.18 + 0.06 * math.sin(t * 2 * math.pi)));
    // rotating rays
    final rayPaint = Paint()
      ..color = ray
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    final rot = t * 2 * math.pi;
    for (var i = 0; i < 8; i++) {
      final a = rot + i * math.pi / 4;
      final d = Offset(math.cos(a), math.sin(a));
      canvas.drawLine(c + d * (r * 1.35), c + d * (r * 1.85), rayPaint);
    }
    canvas.drawCircle(c, r, Paint()..color = core);
  }

  void _moon(Canvas canvas, Offset c, Size size) {
    final r = size.width * 0.24;
    // Crescent via clear — needs its own layer to punch transparency cleanly.
    canvas.saveLayer(Rect.fromCircle(center: c, radius: r * 2.4), Paint());
    canvas.drawCircle(c, r, Paint()..color = const Color(0xFFE3E7EF));
    canvas.drawCircle(c.translate(r * 0.55, -r * 0.25), r * 0.95,
        Paint()..blendMode = BlendMode.clear);
    canvas.restore();
    // twinkling stars
    final twinkle = (0.4 + 0.6 * (0.5 + 0.5 * math.sin(t * 2 * math.pi))).clamp(0.0, 1.0);
    final star = Paint()..color = const Color(0xFFFFE082).withValues(alpha: twinkle);
    canvas.drawCircle(Offset(size.width * 0.85, size.height * 0.2), 1.4, star);
    canvas.drawCircle(Offset(size.width * 0.2, size.height * 0.8), 1.1,
        Paint()..color = const Color(0xFFFFE082).withValues(alpha: 1 - twinkle));
  }

  @override
  bool shouldRepaint(_SkyPainter old) => old.t != t || old.sky != sky;
}
