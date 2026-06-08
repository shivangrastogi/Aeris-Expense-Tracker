import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../core/theme.dart';

/// Animated AERIS launch screen.
///
/// Shows a glowing wallet mark, then types out the "A.E.R.I.S" wordmark one
/// glyph at a time, a tagline, and a slim indeterminate progress bar with a
/// "please wait" line — so the cold-start wait reads as a deliberate loader
/// rather than a frozen spinner.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  // The wordmark, split so each glyph (and dot) can animate in on its own beat.
  static const _glyphs = ['A', '.', 'E', '.', 'R', '.', 'I', '.', 'S'];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: Stack(
        children: [
          // Soft radial wash behind everything for depth.
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0, -0.25),
                  radius: 1.1,
                  colors: [
                    AerisColors.seed.withValues(alpha: dark ? 0.22 : 0.14),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── Glowing logo mark ──────────────────────────────
                Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    gradient: AerisColors.heroGradient,
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: [
                      BoxShadow(
                        color: AerisColors.seed.withValues(alpha: 0.45),
                        blurRadius: 40,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: const Icon(Icons.account_balance_wallet_rounded,
                      size: 48, color: Colors.white),
                )
                    .animate()
                    .fadeIn(duration: 600.ms)
                    .scale(
                        begin: const Offset(0.8, 0.8),
                        end: const Offset(1, 1),
                        curve: Curves.easeOutBack)
                    .slideY(begin: 0.3, end: 0, curve: Curves.easeOutCubic),

                const SizedBox(height: 30),

                // ── Typed "A.E.R.I.S" wordmark ─────────────────────
                Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    for (var i = 0; i < _glyphs.length; i++)
                      Text(
                        _glyphs[i],
                        style: TextStyle(
                          fontSize: _glyphs[i] == '.' ? 26 : 36,
                          height: 1,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1,
                          color: _glyphs[i] == '.'
                              ? AerisColors.seed
                              : scheme.onSurface,
                        ),
                      )
                          .animate()
                          .fadeIn(
                              delay: (250 + i * 110).ms, duration: 280.ms)
                          .slideX(begin: 0.4, end: 0, curve: Curves.easeOutBack),
                  ],
                ),

                const SizedBox(height: 8),
                Text(
                  'Your money, beautifully understood',
                  style: TextStyle(
                    fontSize: 13,
                    color: scheme.onSurfaceVariant,
                    letterSpacing: 0.2,
                  ),
                ).animate().fadeIn(delay: 1500.ms, duration: 500.ms),

                const SizedBox(height: 40),

                // ── Slim indeterminate progress bar ───────────────
                SizedBox(
                  width: 180,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      minHeight: 4,
                      backgroundColor: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                      valueColor:
                          const AlwaysStoppedAnimation(AerisColors.seed),
                    ),
                  ),
                ).animate().fadeIn(delay: 1300.ms, duration: 400.ms),

                const SizedBox(height: 14),
                Text(
                  'Please wait — decrypting your vault',
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurfaceVariant,
                  ),
                )
                    .animate(onPlay: (c) => c.repeat(reverse: true))
                    .fadeIn(delay: 1300.ms)
                    .then()
                    .fade(begin: 1, end: 0.45, duration: 900.ms),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
