import 'package:flutter/material.dart';

import '../utils/formatters.dart';

/// A money figure that counts up/down smoothly **only when its value actually
/// changes**.
///
/// It tweens from the previous value to the new one — not from zero — so when
/// a `ListView` disposes and re-mounts this widget during scrolling, it shows
/// the final figure immediately (begin == end → no animation) instead of
/// re-counting from ₹0 and looking like the screen reloaded.
class AnimatedCount extends StatefulWidget {
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
  State<AnimatedCount> createState() => _AnimatedCountState();
}

class _AnimatedCountState extends State<AnimatedCount> {
  // Where the next tween should start from. On first mount this equals the
  // current value, so a freshly built (or scroll-recycled) widget paints the
  // final number with no count-up animation.
  late double _from = widget.value;

  @override
  void didUpdateWidget(AnimatedCount old) {
    super.didUpdateWidget(old);
    // Animate from the value we were last showing to the new one.
    if (old.value != widget.value) _from = old.value;
  }

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: _from, end: widget.value),
      duration: _from == widget.value ? Duration.zero : widget.duration,
      curve: Curves.easeOutCubic,
      builder: (_, v, __) => Text(
        formatRupees(v, compact: widget.compact, decimals: widget.decimals),
        style: widget.style,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
