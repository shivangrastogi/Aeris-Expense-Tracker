import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../models/category.dart';
import '../utils/formatters.dart';

/// An interactive donut chart. Tap a slice and it pops out with an animation
/// while the center shows that category's amount + share; tap again (or
/// outside) to reset to the total. Slices are labelled *outside* the ring with
/// leader lines so even thin slices stay readable, and it sizes itself to the
/// card so it never overflows.
class CategoryDonut extends StatefulWidget {
  final Map<String, double> byCategory;

  /// Fired when a real category slice is tapped (drill-down). The aggregate
  /// "Other" slice doesn't fire it.
  final void Function(String categoryId)? onCategorySelected;
  const CategoryDonut({super.key, required this.byCategory, this.onCategorySelected});

  @override
  State<CategoryDonut> createState() => _CategoryDonutState();
}

class _CategoryDonutState extends State<CategoryDonut>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pop = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
  );
  int? _selected;
  List<_Slice> _slices = const [];
  double _total = 0;

  @override
  void dispose() {
    _pop.dispose();
    super.dispose();
  }

  void _rebuildSlices() {
    final sorted = widget.byCategory.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final slices = <_Slice>[];
    for (final e in sorted.take(7)) {
      final c = Categories.byId(e.key);
      slices.add(_Slice(c.label.split(' ').first, e.value, c.color, e.key));
    }
    if (sorted.length > 7) {
      final rest = sorted.skip(7).fold<double>(0, (s, e) => s + e.value);
      if (rest > 0) slices.add(_Slice('Other', rest, Colors.grey, null));
    }
    _slices = slices;
    _total = slices.fold<double>(0, (s, e) => s + e.value);
  }

  void _handleTap(Offset local, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final r = _ringRadius(size);
    final thickness = r * 0.36;
    final dx = local.dx - center.dx;
    final dy = local.dy - center.dy;
    final dist = math.sqrt(dx * dx + dy * dy);

    // Outside the ring band → deselect.
    if (dist < r - thickness - 10 || dist > r + 16) {
      _select(null);
      return;
    }
    final angle = (math.atan2(dy, dx) + math.pi / 2) % (2 * math.pi);
    final norm = angle < 0 ? angle + 2 * math.pi : angle;
    double acc = 0;
    for (var i = 0; i < _slices.length; i++) {
      final sweep = _slices[i].value / _total * 2 * math.pi;
      if (norm >= acc && norm < acc + sweep) {
        _select(_selected == i ? null : i);
        final id = _slices[i].id;
        if (id != null) widget.onCategorySelected?.call(id);
        return;
      }
      acc += sweep;
    }
    _select(null);
  }

  void _select(int? i) {
    setState(() => _selected = i);
    if (i == null) {
      _pop.reverse();
    } else {
      _pop.forward(from: 0);
    }
  }

  static double _ringRadius(Size size) =>
      math.min(size.height / 2 - 26, size.width / 2 - 78).clamp(40.0, 120.0);

  @override
  Widget build(BuildContext context) {
    if (widget.byCategory.isEmpty) {
      return const Center(child: Text('No spend yet this month.'));
    }
    _rebuildSlices();
    if (_selected != null && _selected! >= _slices.length) _selected = null;

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        return GestureDetector(
          onTapUp: (d) => _handleTap(d.localPosition, size),
          child: CustomPaint(
            size: Size.infinite,
            painter: _DonutPainter(
              slices: _slices,
              total: _total,
              selected: _selected,
              pop: _pop,
              labelColor: Theme.of(context).colorScheme.onSurface,
              subColor: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        );
      },
    );
  }
}

class _Slice {
  final String label;
  final double value;
  final Color color;
  final String? id;
  const _Slice(this.label, this.value, this.color, this.id);
}

class _DonutPainter extends CustomPainter {
  final List<_Slice> slices;
  final double total;
  final int? selected;
  final Animation<double> pop;
  final Color labelColor;
  final Color subColor;

  _DonutPainter({
    required this.slices,
    required this.total,
    required this.selected,
    required this.pop,
    required this.labelColor,
    required this.subColor,
  }) : super(repaint: pop);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final r = _CategoryDonutState._ringRadius(size);
    final thickness = r * 0.36;
    final ringRadius = r - thickness / 2;

    double startAngle = -math.pi / 2;
    for (var i = 0; i < slices.length; i++) {
      final s = slices[i];
      final sweep = (s.value / total) * 2 * math.pi;
      final mid = startAngle + sweep / 2;
      final isSel = i == selected;

      // Selected slice pops outward + thickens slightly.
      final explode = isSel ? 12.0 * pop.value : 0.0;
      final c = center + Offset(math.cos(mid), math.sin(mid)) * explode;
      final paint = Paint()
        ..color = (selected == null || isSel)
            ? s.color
            : s.color.withOpacity(0.45)
        ..style = PaintingStyle.stroke
        ..strokeWidth = thickness + (isSel ? 4 * pop.value : 0);
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: ringRadius),
        startAngle,
        sweep - 0.012,
        false,
        paint,
      );
      startAngle += sweep;
    }

    // Center: selected slice details, otherwise the total.
    if (selected != null && selected! < slices.length) {
      final s = slices[selected!];
      final pct = (s.value / total * 100).toStringAsFixed(0);
      _center(canvas, center, formatRupees(s.value, compact: true),
          '${s.label} · $pct%',
          primaryStyle: TextStyle(
              fontSize: 16, fontWeight: FontWeight.w800, color: s.color));
    } else {
      _center(canvas, center, formatRupees(total, compact: true), 'total',
          primaryStyle: TextStyle(
              fontSize: 16, fontWeight: FontWeight.w800, color: labelColor));
    }

    // Leader-line labels (skip the very tiny ones to avoid clutter).
    startAngle = -math.pi / 2;
    for (var i = 0; i < slices.length; i++) {
      final s = slices[i];
      final frac = s.value / total;
      final sweep = frac * 2 * math.pi;
      final mid = startAngle + sweep / 2;
      startAngle += sweep;
      if (frac < 0.025) continue;

      final dir = Offset(math.cos(mid), math.sin(mid));
      final pOuter = center + dir * r;
      final pElbow = center + dir * (r + 12);
      final toRight = dir.dx >= 0;
      final pEnd = Offset(pElbow.dx + (toRight ? 14 : -14), pElbow.dy);
      final dim = selected != null && i != selected;

      final linePaint = Paint()
        ..color = s.color.withOpacity(dim ? 0.3 : 0.75)
        ..strokeWidth = i == selected ? 2 : 1.3
        ..style = PaintingStyle.stroke;
      canvas.drawLine(pOuter, pElbow, linePaint);
      canvas.drawLine(pElbow, pEnd, linePaint);
      canvas.drawCircle(pEnd, 2.2, Paint()..color = s.color.withOpacity(dim ? 0.4 : 1));

      _sideLabel(
        canvas,
        Offset(pEnd.dx + (toRight ? 6 : -6), pEnd.dy),
        s.label,
        '${(frac * 100).toStringAsFixed(0)}%',
        left: toRight,
        maxX: size.width,
        bold: i == selected,
        color: labelColor.withOpacity(dim ? 0.45 : 1),
      );
    }
  }

  void _center(Canvas canvas, Offset anchor, String primary, String secondary,
      {required TextStyle primaryStyle}) {
    final amt = TextPainter(
      text: TextSpan(text: primary, style: primaryStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    amt.paint(canvas, Offset(anchor.dx - amt.width / 2, anchor.dy - amt.height));
    final sub = TextPainter(
      text: TextSpan(
          text: secondary, style: TextStyle(fontSize: 10.5, color: subColor)),
      textDirection: TextDirection.ltr,
      ellipsis: '…',
      maxLines: 1,
    )..layout(maxWidth: 96);
    sub.paint(canvas, Offset(anchor.dx - sub.width / 2, anchor.dy + 1));
  }

  void _sideLabel(Canvas canvas, Offset anchor, String name, String pct,
      {required bool left,
      required double maxX,
      required bool bold,
      required Color color}) {
    final tp = TextPainter(
      text: TextSpan(children: [
        TextSpan(
            text: '$name  ',
            style: TextStyle(
                fontSize: 11.5,
                fontWeight: bold ? FontWeight.w800 : FontWeight.w700,
                color: color)),
        TextSpan(
            text: pct,
            style: TextStyle(
                fontSize: 10.5, fontWeight: FontWeight.w600, color: subColor)),
      ]),
      textDirection: TextDirection.ltr,
    )..layout();
    double x = left ? anchor.dx : anchor.dx - tp.width;
    x = x.clamp(2.0, maxX - tp.width - 2);
    tp.paint(canvas, Offset(x, anchor.dy - tp.height / 2));
  }

  @override
  bool shouldRepaint(_DonutPainter old) =>
      old.total != total ||
      old.slices.length != slices.length ||
      old.selected != selected;
}
