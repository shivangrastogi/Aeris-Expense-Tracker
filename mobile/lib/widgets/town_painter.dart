import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/town_catalog.dart';
import '../providers/village_provider.dart';

/// Aeris Town, drawn in code: a calm night city on a dark isometric grid —
/// slate walls tinted by each building's colour, lit windows, roofs that
/// grow with the level. Shared by the full town screen, the hub preview and
/// the shop icons, so the town looks the same everywhere (no emoji, which
/// differ per phone).
class TownPalette {
  static const groundA = Color(0xFF111A28);
  static const groundB = Color(0xFF0E1622);
  static const gridLine = Color(0xFF1B2536);
  static const wall = Color(0xFF243247);
  static const window = Color(0xFFFFD58A);
  static const skyTop = Color(0xFF05070C);
  static const skyBottom = Color(0xFF0C1626);
}

class Iso {
  final Offset origin; // screen position of tile (0,0) centre
  final double tw; // tile width; height is tw/2
  const Iso(this.origin, this.tw);
  double get th => tw / 2;
  Offset cell(num c, num r) => origin + Offset((c - r) * tw / 2, (c + r) * th / 2);

  /// Grid cell under a screen point, or null if off the grid.
  (int, int)? hit(Offset p, int n) {
    final d = p - origin;
    final a = d.dx / (tw / 2), b = d.dy / (th / 2);
    final c = ((a + b) / 2).round(), r = ((b - a) / 2).round();
    if (c < 0 || r < 0 || c >= n || r >= n) return null;
    return (c, r);
  }
}

Color _mix(Color a, Color b, double t) => Color.lerp(a, b, t)!;

/// Paints one building standing on the tile centred at [p].
void paintBuilding(Canvas c, Offset p, double tw, TownBuilding def, int lvl,
    {bool constructing = false, double progress = 0, double glow = 1}) {
  final s = tw / 64; // design units → pixels
  final growth = 1 + lvl * 0.22;
  final wall = _mix(TownPalette.wall, def.color, 0.18);

  // Soft contact shadow.
  c.drawOval(Rect.fromCenter(center: p + Offset(0, 2 * s), width: tw * 0.7, height: tw * 0.3),
      Paint()..color = Colors.black.withValues(alpha: 0.35));

  if (constructing) {
    _scaffold(c, p, s, def.color, progress);
    return;
  }

  switch (def.id) {
    case 'townhall':
      _box(c, p, 40 * s, 30 * s * growth, wall, windows: 2 + lvl, glow: glow);
      _spire(c, p - Offset(0, 30 * s * growth), 16 * s, 26 * s * (0.8 + lvl * 0.12), def.color);
    case 'house':
      _box(c, p, 30 * s, 18 * s * growth, wall, windows: 1 + lvl ~/ 2, glow: glow);
      _gable(c, p - Offset(0, 18 * s * growth), 30 * s, 13 * s, def.color);
    case 'market':
      _box(c, p, 36 * s, 16 * s * growth, wall, windows: 1 + lvl ~/ 2, glow: glow);
      _awning(c, p - Offset(0, 16 * s * growth), 36 * s, def.color);
    case 'vault':
      _box(c, p, 34 * s, 20 * s * growth, _mix(wall, const Color(0xFF3A3420), 0.4), windows: 0, glow: glow);
      _dome(c, p - Offset(0, 20 * s * growth), 26 * s, def.color);
      _door(c, p, 34 * s, def.color);
    case 'farm':
      _farm(c, p, 46 * s, def.color, lvl);
    case 'tree':
      _tree(c, p, s * (1 + lvl * 0.25), def.color);
    case 'fountain':
      _fountain(c, p, s * (1 + lvl * 0.15), def.color);
    case 'statue':
      _box(c, p, 18 * s, 8 * s, wall, windows: 0, glow: glow);
      _obelisk(c, p - Offset(0, 8 * s), 9 * s, 30 * s * (1 + lvl * 0.2), def.color);
    case 'tower':
      _box(c, p, 26 * s, 34 * s, wall, windows: 3, glow: glow);
      _gable(c, p - Offset(0, 34 * s), 26 * s, 9 * s, def.color);
    default:
      _box(c, p, 30 * s, 20 * s, wall, windows: 1, glow: glow);
  }
}

// ── primitives ────────────────────────────────────────────────────────

/// Isometric cuboid of footprint [w] (screen width) and height [h], with
/// warm lit windows on both visible faces.
void _box(Canvas c, Offset p, double w, double h, Color base, {int windows = 1, double glow = 1}) {
  final hw = w / 2, hh = w / 4;
  final top = Path()
    ..moveTo(p.dx, p.dy - h - hh)
    ..lineTo(p.dx + hw, p.dy - h)
    ..lineTo(p.dx, p.dy - h + hh)
    ..lineTo(p.dx - hw, p.dy - h)
    ..close();
  final left = Path()
    ..moveTo(p.dx - hw, p.dy - h)
    ..lineTo(p.dx, p.dy - h + hh)
    ..lineTo(p.dx, p.dy + hh)
    ..lineTo(p.dx - hw, p.dy)
    ..close();
  final right = Path()
    ..moveTo(p.dx, p.dy - h + hh)
    ..lineTo(p.dx + hw, p.dy - h)
    ..lineTo(p.dx + hw, p.dy)
    ..lineTo(p.dx, p.dy + hh)
    ..close();
  c.drawPath(left, Paint()..color = base);
  c.drawPath(right, Paint()..color = _mix(base, Colors.black, 0.35));
  c.drawPath(top, Paint()..color = _mix(base, Colors.white, 0.18));
  final edge = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 0.8
    ..color = Colors.white.withValues(alpha: 0.06);
  c.drawPath(top, edge);

  if (windows <= 0 || h < 8) return;
  final rows = math.max(1, (h / 12).floor());
  final win = Paint()..color = TownPalette.window.withValues(alpha: 0.85 * glow);
  final halo = Paint()
    ..color = TownPalette.window.withValues(alpha: 0.18 * glow)
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
  for (final face in [0, 1]) {
    for (var i = 0; i < windows; i++) {
      for (var r = 0; r < rows; r++) {
        // Some windows are dark — a lived-in city, not a grid of LEDs.
        if ((i * 7 + r * 3 + face) % 4 == 3) continue;
        final u = (i + 0.5) / windows;
        final v = (r + 0.55) / (rows + 0.4);
        final q = _facePoint(p, hw, hh, h, face, u, v);
        final ww = hw / (windows * 2.2), wh = math.min(5.0, h / rows * 0.4);
        final rect = Rect.fromCenter(center: q, width: ww, height: wh);
        c.drawRect(rect.inflate(1.5), halo);
        c.drawRect(rect, win);
      }
    }
  }
}

/// Point on a cuboid's left (face 0) or right (face 1) wall: u along, v up.
Offset _facePoint(Offset p, double hw, double hh, double h, int face, double u, double v) {
  final a = face == 0 ? Offset(p.dx - hw, p.dy) : Offset(p.dx, p.dy + hh);
  final b = face == 0 ? Offset(p.dx, p.dy + hh) : Offset(p.dx + hw, p.dy);
  return Offset.lerp(a, b, u)! - Offset(0, h * v);
}

void _gable(Canvas c, Offset p, double w, double h, Color color) {
  final hw = w / 2, hh = w / 4;
  final ridgeL = Offset(p.dx - hw / 2, p.dy - h - hh / 2);
  final ridgeR = Offset(p.dx + hw / 2, p.dy - h + hh / 2);
  final front = Path()
    ..moveTo(p.dx - hw, p.dy)
    ..lineTo(ridgeL.dx, ridgeL.dy)
    ..lineTo(ridgeR.dx, ridgeR.dy)
    ..lineTo(p.dx, p.dy + hh)
    ..close();
  final side = Path()
    ..moveTo(p.dx, p.dy + hh)
    ..lineTo(ridgeR.dx, ridgeR.dy)
    ..lineTo(p.dx + hw, p.dy)
    ..close();
  final back = Path()
    ..moveTo(p.dx - hw, p.dy)
    ..lineTo(ridgeL.dx, ridgeL.dy)
    ..lineTo(p.dx, p.dy - hh)
    ..close();
  c.drawPath(back, Paint()..color = _mix(color, Colors.black, 0.55));
  c.drawPath(front, Paint()..color = _mix(color, Colors.black, 0.15));
  c.drawPath(side, Paint()..color = _mix(color, Colors.black, 0.45));
}

void _spire(Canvas c, Offset p, double w, double h, Color color) {
  final hw = w / 2;
  final tip = p - Offset(0, h);
  c.drawPath(
      Path()
        ..moveTo(p.dx - hw, p.dy)
        ..lineTo(tip.dx, tip.dy)
        ..lineTo(p.dx, p.dy + hw / 2)
        ..close(),
      Paint()..color = _mix(color, Colors.black, 0.2));
  c.drawPath(
      Path()
        ..moveTo(p.dx, p.dy + hw / 2)
        ..lineTo(tip.dx, tip.dy)
        ..lineTo(p.dx + hw, p.dy)
        ..close(),
      Paint()..color = _mix(color, Colors.black, 0.5));
  // Beacon — the town's heartbeat, in the AERIS accent.
  c.drawCircle(tip, w * 0.16, Paint()..color = color);
  c.drawCircle(tip, w * 0.5,
      Paint()
        ..color = color.withValues(alpha: 0.25)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
}

void _awning(Canvas c, Offset p, double w, Color color) {
  final hw = w / 2, hh = w / 4;
  const stripes = 6;
  for (var i = 0; i < stripes; i++) {
    final a = Offset.lerp(Offset(p.dx - hw, p.dy), Offset(p.dx, p.dy + hh), i / stripes)!;
    final b = Offset.lerp(Offset(p.dx - hw, p.dy), Offset(p.dx, p.dy + hh), (i + 1) / stripes)!;
    c.drawPath(
        Path()
          ..moveTo(a.dx, a.dy)
          ..lineTo(b.dx, b.dy)
          ..lineTo(b.dx - 3, b.dy + 7)
          ..lineTo(a.dx - 3, a.dy + 7)
          ..close(),
        Paint()..color = i.isEven ? color : const Color(0xFFEAF2F7));
  }
  c.drawPath(
      Path()
        ..moveTo(p.dx - hw, p.dy)
        ..lineTo(p.dx, p.dy - hh)
        ..lineTo(p.dx + hw, p.dy)
        ..lineTo(p.dx, p.dy + hh)
        ..close(),
      Paint()..color = _mix(color, Colors.black, 0.35));
}

void _dome(Canvas c, Offset p, double w, Color color) {
  final r = Rect.fromCenter(center: p, width: w, height: w * 0.9);
  c.drawArc(r, math.pi, math.pi, true, Paint()..color = _mix(color, Colors.black, 0.25));
  c.drawArc(r.deflate(w * 0.18).shift(Offset(-w * 0.08, 0)), math.pi * 1.1, math.pi * 0.4, false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.white.withValues(alpha: 0.35));
}

void _door(Canvas c, Offset p, double w, Color color) {
  final q = _facePoint(p, w / 2, w / 4, 20, 0, 0.55, 0.3);
  c.drawCircle(q, w * 0.09, Paint()..color = color.withValues(alpha: 0.9));
}

void _farm(Canvas c, Offset p, double w, Color color, int lvl) {
  final hw = w / 2, hh = w / 4;
  final plot = Path()
    ..moveTo(p.dx, p.dy - hh)
    ..lineTo(p.dx + hw, p.dy)
    ..lineTo(p.dx, p.dy + hh)
    ..lineTo(p.dx - hw, p.dy)
    ..close();
  c.drawPath(plot, Paint()..color = const Color(0xFF2A2318));
  final crop = Paint()
    ..strokeWidth = 2.2
    ..strokeCap = StrokeCap.round
    ..color = color.withValues(alpha: 0.85);
  final rows = 4 + lvl;
  for (var i = 1; i < rows; i++) {
    final t = i / rows;
    final a = Offset.lerp(Offset(p.dx - hw, p.dy), Offset(p.dx, p.dy - hh), t)!;
    final b = Offset.lerp(Offset(p.dx, p.dy + hh), Offset(p.dx + hw, p.dy), t)!;
    for (var k = 1; k < 6; k++) {
      final q = Offset.lerp(a, b, k / 6)!;
      c.drawLine(q, q - Offset(0, 3 + lvl.toDouble()), crop);
    }
  }
}

void _tree(Canvas c, Offset p, double s, Color color) {
  c.drawRect(Rect.fromCenter(center: p - Offset(0, 5 * s), width: 3 * s, height: 10 * s),
      Paint()..color = const Color(0xFF4A3424));
  for (var i = 0; i < 3; i++) {
    final base = p - Offset(0, (8 + i * 8) * s);
    final w = (20 - i * 5) * s;
    c.drawPath(
        Path()
          ..moveTo(base.dx - w / 2, base.dy)
          ..lineTo(base.dx, base.dy - 14 * s)
          ..lineTo(base.dx + w / 2, base.dy)
          ..close(),
        Paint()..color = _mix(color, Colors.black, 0.25 + i * 0.1));
  }
}

void _fountain(Canvas c, Offset p, double s, Color color) {
  c.drawOval(Rect.fromCenter(center: p, width: 34 * s, height: 16 * s), Paint()..color = const Color(0xFF2B3A52));
  c.drawOval(Rect.fromCenter(center: p - Offset(0, 1 * s), width: 28 * s, height: 12 * s),
      Paint()..color = color.withValues(alpha: 0.55));
  c.drawRect(Rect.fromCenter(center: p - Offset(0, 8 * s), width: 4 * s, height: 14 * s),
      Paint()..color = const Color(0xFF3A4B66));
  final jet = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.6 * s
    ..color = color.withValues(alpha: 0.9);
  final top = p - Offset(0, 16 * s);
  c.drawArc(Rect.fromCenter(center: top + Offset(-6 * s, 4 * s), width: 12 * s, height: 10 * s), math.pi, math.pi * 0.9, false, jet);
  c.drawArc(Rect.fromCenter(center: top + Offset(6 * s, 4 * s), width: 12 * s, height: 10 * s), -math.pi * 0.9 + math.pi * 0.9, -math.pi * 0.9, false, jet);
}

void _obelisk(Canvas c, Offset p, double w, double h, Color color) {
  c.drawPath(
      Path()
        ..moveTo(p.dx - w / 2, p.dy)
        ..lineTo(p.dx - w * 0.3, p.dy - h)
        ..lineTo(p.dx, p.dy - h - w * 0.5)
        ..lineTo(p.dx, p.dy + w / 4)
        ..close(),
      Paint()..color = color);
  c.drawPath(
      Path()
        ..moveTo(p.dx, p.dy + w / 4)
        ..lineTo(p.dx, p.dy - h - w * 0.5)
        ..lineTo(p.dx + w * 0.3, p.dy - h)
        ..lineTo(p.dx + w / 2, p.dy)
        ..close(),
      Paint()..color = _mix(color, Colors.black, 0.4));
}

void _scaffold(Canvas c, Offset p, double s, Color color, double progress) {
  final w = 30 * s, h = 26 * s;
  final pole = Paint()
    ..strokeWidth = 1.4
    ..color = const Color(0xFF8A96A8);
  for (final dx in [-w / 2, 0.0, w / 2]) {
    c.drawLine(p + Offset(dx, dx == 0 ? w / 4 : 0), p + Offset(dx, (dx == 0 ? w / 4 : 0) - h), pole);
  }
  for (var y = 6 * s; y < h; y += 8 * s) {
    c.drawLine(p + Offset(-w / 2, -y), p + Offset(0, w / 4 - y), pole);
    c.drawLine(p + Offset(0, w / 4 - y), p + Offset(w / 2, -y), pole);
  }
  // Rising wall shows the progress.
  final fill = h * progress.clamp(0.0, 1.0);
  if (fill > 1) _box(c, p, w * 0.9, fill, _mix(TownPalette.wall, color, 0.18), windows: 0);
  // Crane light.
  c.drawCircle(p - Offset(0, h + 4 * s), 2.2 * s, Paint()..color = const Color(0xFFD2A35A));
}

/// Draws the ground diamond for one tile.
void paintTile(Canvas c, Offset p, double tw, {Color? fill, Color? outline}) {
  final hw = tw / 2, hh = tw / 4;
  final path = Path()
    ..moveTo(p.dx, p.dy - hh)
    ..lineTo(p.dx + hw, p.dy)
    ..lineTo(p.dx, p.dy + hh)
    ..lineTo(p.dx - hw, p.dy)
    ..close();
  if (fill != null) c.drawPath(path, Paint()..color = fill);
  c.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = outline == null ? 0.8 : 1.6
        ..color = outline ?? TownPalette.gridLine);
}

/// The whole town: ground + buildings, back to front.
class TownPainter extends CustomPainter {
  final VillageState village;
  final Iso iso;
  final int now;
  final String? selected;
  final Set<(int, int)> placeable;
  final double glow;

  TownPainter({
    required this.village,
    required this.iso,
    required this.now,
    this.selected,
    this.placeable = const {},
    this.glow = 1,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const n = TownCatalog.gridSize;
    // Raised plateau edge under the grid.
    final l = iso.cell(0, n - 1) + Offset(-iso.tw / 2, 0);
    final b = iso.cell(n - 1, n - 1) + Offset(0, iso.th / 2);
    final r = iso.cell(n - 1, 0) + Offset(iso.tw / 2, 0);
    final depth = iso.tw * 0.35;
    canvas.drawPath(
        Path()
          ..moveTo(l.dx, l.dy)
          ..lineTo(b.dx, b.dy)
          ..lineTo(r.dx, r.dy)
          ..lineTo(r.dx, r.dy + depth)
          ..lineTo(b.dx, b.dy + depth)
          ..lineTo(l.dx, l.dy + depth)
          ..close(),
        Paint()..color = const Color(0xFF0A0F18));

    for (var row = 0; row < n; row++) {
      for (var col = 0; col < n; col++) {
        final can = placeable.contains((col, row));
        paintTile(canvas, iso.cell(col, row), iso.tw,
            fill: can
                ? const Color(0xFF15344A)
                : ((col + row).isEven ? TownPalette.groundA : TownPalette.groundB),
            outline: can ? const Color(0xFF7AA6DA) : null);
      }
    }
    final order = village.buildings.entries.toList()
      ..sort((a, b) => (a.value.col + a.value.row).compareTo(b.value.col + b.value.row));
    for (final e in order) {
      final v = e.value;
      final p = iso.cell(v.col, v.row);
      if (e.key == selected) {
        paintTile(canvas, p, iso.tw, fill: const Color(0x337AA6DA), outline: const Color(0xFF7AA6DA));
      }
      final busy = v.busy(now);
      final total = v.def.buildMs(v.lvl);
      paintBuilding(canvas, p, iso.tw, v.def, v.lvl,
          constructing: busy, progress: busy ? 1 - (v.endMs - now) / total : 0, glow: glow);
    }
  }

  @override
  bool shouldRepaint(TownPainter o) =>
      o.village != village || o.now ~/ 1000 != now ~/ 1000 || o.selected != selected ||
      o.placeable.length != placeable.length || o.iso.origin != iso.origin || o.iso.tw != iso.tw || o.glow != glow;
}

/// A single building as an icon (shop tiles, info panel).
class BuildingIcon extends StatelessWidget {
  final TownBuilding def;
  final int lvl;
  final double size;
  const BuildingIcon(this.def, {super.key, this.lvl = 0, this.size = 56});

  @override
  Widget build(BuildContext context) => CustomPaint(
        size: Size.square(size),
        painter: _IconPainter(def, lvl),
      );
}

class _IconPainter extends CustomPainter {
  final TownBuilding def;
  final int lvl;
  _IconPainter(this.def, this.lvl);

  @override
  void paint(Canvas canvas, Size size) {
    final tw = size.width * 0.78;
    final p = Offset(size.width / 2, size.height * 0.78);
    paintTile(canvas, p, tw, fill: TownPalette.groundA);
    paintBuilding(canvas, p, tw, def, lvl);
  }

  @override
  bool shouldRepaint(_IconPainter o) => o.def != def || o.lvl != lvl;
}
