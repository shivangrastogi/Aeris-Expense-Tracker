import 'package:flutter/material.dart';

/// The AERIS mark — the same "A" as the launcher icon — so sign-in, splash
/// and the assistant all wear one identity.
class AerisBrandMark extends StatelessWidget {
  final double size;
  const AerisBrandMark({super.key, this.size = 44});

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(size * 0.26),
        child: Image.asset(
          'assets/icons/app_icon.png',
          width: size,
          height: size,
          filterQuality: FilterQuality.medium,
          // Never show a broken-image box: fall back to a plain "A" tile in
          // the icon's colours.
          errorBuilder: (_, __, ___) => Container(
            width: size,
            height: size,
            color: const Color(0xFF181B21),
            alignment: Alignment.center,
            child: Text('A',
                style: TextStyle(
                    color: const Color(0xFF7AA6DA),
                    fontSize: size * 0.55,
                    fontWeight: FontWeight.w800)),
          ),
        ),
      );
}

/// The bare "A" mark as vector strokes (the design's splash glyph): two legs,
/// a rising crossbar and its dot. No tile behind it — callers place it.
class AerisMarkGlyph extends StatelessWidget {
  final double size;
  final Color color;
  final double stroke;
  const AerisMarkGlyph({
    super.key,
    this.size = 104,
    this.color = const Color(0xFF6E9EE0),
    this.stroke = 3,
  });

  @override
  Widget build(BuildContext context) => CustomPaint(
        size: Size.square(size),
        painter: _MarkPainter(color, stroke),
      );
}

class _MarkPainter extends CustomPainter {
  final Color color;
  final double stroke;
  _MarkPainter(this.color, this.stroke);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 40; // the mark is drawn on a 40-unit grid
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke * s
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(
        Path()
          ..moveTo(9 * s, 32 * s)
          ..lineTo(20 * s, 8 * s)
          ..lineTo(31 * s, 32 * s),
        p);
    canvas.drawLine(Offset(12.6 * s, 25 * s), Offset(24.5 * s, 19.6 * s), p);
    canvas.drawCircle(
        Offset(28.6 * s, 17.8 * s), 2.4 * s, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_MarkPainter o) => o.color != color || o.stroke != stroke;
}
