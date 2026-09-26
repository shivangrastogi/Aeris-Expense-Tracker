import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

/// True when the user turned on the system "remove animations" setting.
/// Decorative motion (loops, shimmers, confetti, entrances) should be skipped;
/// motion that answers a tap may stay but should be instant.
bool reduceMotion(BuildContext context) =>
    MediaQuery.maybeDisableAnimationsOf(context) ?? false;

extension MotionAwareWidget on Widget {
  /// A looping loading shimmer — static when reduce-motion is on.
  Widget shimmerLoop(BuildContext context,
      {required Duration duration, required Color color}) {
    if (reduceMotion(context)) return this;
    return animate(onPlay: (c) => c.repeat())
        .shimmer(duration: duration, color: color);
  }
}
