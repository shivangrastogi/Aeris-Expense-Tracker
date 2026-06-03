import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/gamification_provider.dart';

/// A calm, private world that grows with the Aura you earn (i.e. with your
/// saving discipline). Every ~120 Aura plants/upgrades something. Fully
/// custom-painted, offline, with a gentle breeze sway.
class GardenScreen extends ConsumerStatefulWidget {
  const GardenScreen({super.key});
  @override
  ConsumerState<GardenScreen> createState() => _GardenScreenState();
}

class _GardenScreenState extends ConsumerState<GardenScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(seconds: 8))
        ..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final earned = ref.watch(gamificationProvider).earned;
    final plants = (earned ~/ 120).clamp(0, 36);
    return Scaffold(
      appBar: AppBar(title: const Text('Money Garden')),
      body: Column(
        children: [
          Expanded(
            child: AnimatedBuilder(
              animation: _c,
              builder: (_, __) => CustomPaint(
                size: Size.infinite,
                painter: _GardenPainter(t: _c.value, plants: plants),
              ),
            ),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            color: Theme.of(context).colorScheme.surface,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$plants plant${plants == 1 ? '' : 's'} grown',
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 18)),
                const SizedBox(height: 4),
                Text(
                  'Your garden flourishes as you earn Aura by saving, beating '
                  'budgets and winning challenges. ${earned % 120} / 120 Aura to '
                  'the next sprout.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GardenPainter extends CustomPainter {
  final double t;
  final int plants;
  _GardenPainter({required this.t, required this.plants});

  @override
  void paint(Canvas canvas, Size size) {
    // Sky
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF0a1f1c), Color(0xFF12302b)],
        ).createShader(Offset.zero & size),
    );
    // Sun/moon glow
    final sun = Offset(size.width * 0.8, size.height * 0.2);
    canvas.drawCircle(
      sun,
      60,
      Paint()
        ..shader = RadialGradient(colors: [
          const Color(0xFF5eead4).withValues(alpha: 0.5),
          const Color(0xFF5eead4).withValues(alpha: 0.0),
        ]).createShader(Rect.fromCircle(center: sun, radius: 60)),
    );
    // Ground
    final groundY = size.height * 0.74;
    final ground = Path()
      ..moveTo(0, groundY)
      ..quadraticBezierTo(
          size.width * 0.5, groundY - 18, size.width, groundY)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(ground, Paint()..color = const Color(0xFF14463c));

    if (plants == 0) {
      _text(canvas, size, 'Plant your first seed —\nsave a little to begin 🌱',
          groundY - 40);
      return;
    }

    final rnd = math.Random(7);
    for (var i = 0; i < plants; i++) {
      final x = size.width * ((i + 0.5) / plants);
      final baseY = groundY + 6 + (i % 3) * 6;
      final h = 26.0 + (i % 5) * 10 + math.min(i, 10) * 1.5;
      final sway = math.sin(t * 2 * math.pi + i) * 4;
      final kind = i % 3;
      if (kind == 0) {
        _tree(canvas, Offset(x, baseY), h, sway);
      } else if (kind == 1) {
        _flower(canvas, Offset(x, baseY), h, sway, rnd.nextInt(360).toDouble());
      } else {
        _bush(canvas, Offset(x, baseY), h * 0.7);
      }
    }
  }

  void _tree(Canvas canvas, Offset base, double h, double sway) {
    final top = base + Offset(sway, -h);
    canvas.drawLine(
        base,
        top,
        Paint()
          ..color = const Color(0xFF6b4f2a)
          ..strokeWidth = 4
          ..strokeCap = StrokeCap.round);
    canvas.drawCircle(top, h * 0.5, Paint()..color = const Color(0xFF34D399));
    canvas.drawCircle(top + Offset(-h * 0.3, h * 0.1), h * 0.32,
        Paint()..color = const Color(0xFF10b981));
  }

  void _flower(Canvas canvas, Offset base, double h, double sway, double hue) {
    final top = base + Offset(sway, -h);
    canvas.drawLine(
        base,
        top,
        Paint()
          ..color = const Color(0xFF34D399)
          ..strokeWidth = 3);
    final petal = Paint()..color = HSVColor.fromAHSV(1, hue, 0.55, 0.95).toColor();
    for (var k = 0; k < 6; k++) {
      final a = k * math.pi / 3;
      canvas.drawCircle(top + Offset(math.cos(a), math.sin(a)) * 6, 5, petal);
    }
    canvas.drawCircle(top, 4, Paint()..color = const Color(0xFFFBBF24));
  }

  void _bush(Canvas canvas, Offset base, double h) {
    final p = Paint()..color = const Color(0xFF0f766e);
    canvas.drawCircle(base + Offset(0, -h * 0.4), h * 0.5, p);
    canvas.drawCircle(base + Offset(-h * 0.4, -h * 0.2), h * 0.4, p);
    canvas.drawCircle(base + Offset(h * 0.4, -h * 0.2), h * 0.4, p);
  }

  void _text(Canvas canvas, Size size, String s, double y) {
    final tp = TextPainter(
      text: TextSpan(
          text: s,
          style: const TextStyle(color: Colors.white70, fontSize: 14)),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: size.width * 0.7);
    tp.paint(canvas, Offset((size.width - tp.width) / 2, y));
  }

  @override
  bool shouldRepaint(_GardenPainter old) =>
      old.t != t || old.plants != plants;
}
