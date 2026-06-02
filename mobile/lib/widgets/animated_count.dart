import 'package:flutter/material.dart';

import '../utils/formatters.dart';

/// A money figure that counts up/down smoothly whenever its value changes.
/// Used for the balance hero and stat cards to add a touch of delight.
class AnimatedCount extends StatelessWidget {
  final double value;
  final TextStyle? style;
  final bool compact;
  final bool decimals;
  final Duration duration;

  const AnimatedCount({
    super.key,
    required this.value,
    this.style,
    this.compact = false,
    this.decimals = false,
    this.duration = const Duration(milliseconds: 650),
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value),
      duration: duration,
      curve: Curves.easeOutCubic,
      builder: (_, v, __) => Text(
        formatRupees(v, compact: compact, decimals: decimals),
        style: style,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
