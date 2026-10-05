import 'dart:async';

import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../models/avatar_skin.dart';
import '../widgets/aeris_avatar.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  static const _word = 'A.E.R.I.S';
  int _n = 0;
  bool _cursorVisible = true;
  late final Timer _typeTimer;
  late final Timer _cursorTimer;

  @override
  void initState() {
    super.initState();
    // Type one character every 65ms — the word completes in ~0.6s, inside the
    // KeyGate's minimum splash hold, so it never gets cut off mid-word.
    _typeTimer = Timer.periodic(const Duration(milliseconds: 65), (t) {
      if (_n < _word.length) {
        setState(() => _n++);
      } else {
        t.cancel();
      }
    });
    // Blink the cursor at 500ms interval
    _cursorTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (mounted) setState(() => _cursorVisible = !_cursorVisible);
    });
  }

  @override
  void dispose() {
    _typeTimer.cancel();
    _cursorTimer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final defaultSkin = Avatars.byId('sprout');

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: isDark
              ? const RadialGradient(
                  center: Alignment(-0.7, -0.8),
                  radius: 1.2,
                  colors: [
                    Color(0xFF0F1B2A),
                    Color(0xFF080C14),
                    AerisColors.bgDark // = the native launch window colour
                  ],
                  stops: [0.0, 0.6, 1.0],
                )
              : const RadialGradient(
                  center: Alignment(-0.7, -0.8),
                  radius: 1.2,
                  colors: [
                    Color(0xFFE0F7F5),
                    Color(0xFFF4FFFE),
                    Color(0xFFFFFFFF)
                  ],
                  stops: [0.0, 0.5, 1.0],
                ),
        ),
        child: Stack(
          children: [
            // Centered main content
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ── Aeris mascot ──────────────────────────────
                  AerisAvatar(
                    skin: defaultSkin,
                    stage: 1,
                    mood: AvatarMood.happy,
                    size: 150,
                    animate: true,
                  ),

                  const SizedBox(height: 30),

                  // ── Typewriter wordmark ───────────────────────
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        _word.substring(0, _n),
                        style: TextStyle(
                          fontSize: 34,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.04 * 34,
                          color:
                              isDark ? Colors.white : const Color(0xFF0D1C1C),
                        ),
                      ),
                      if (_n < _word.length || _cursorVisible)
                        AnimatedOpacity(
                          opacity: _n < _word.length
                              ? 1.0
                              : (_cursorVisible ? 1.0 : 0.0),
                          duration: const Duration(milliseconds: 120),
                          child: const Text(
                            '|',
                            style: TextStyle(
                              fontSize: 34,
                              fontWeight: FontWeight.w800,
                              color: AerisColors.accent(context),
                            ),
                          ),
                        ),
                    ],
                  ),

                  const SizedBox(height: 10),

                  // ── Tagline ───────────────────────────────────
                  Text(
                    'Private money, beautifully simple.',
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.55)
                          : const Color(0xFF0D1C1C).withValues(alpha: 0.55),
                    ),
                  ),
                ],
              ),
            ),

            // ── Bottom progress ───────────────────────────────
            Positioned(
              bottom: 56,
              left: 0,
              right: 0,
              child: Column(
                children: [
                  Center(
                    child: SizedBox(
                      width: MediaQuery.sizeOf(context).width * 0.7,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(99),
                        child: LinearProgressIndicator(
                          minHeight: 4,
                          backgroundColor: isDark
                              ? Colors.white.withValues(alpha: 0.10)
                              : AerisColors.accent(context).withValues(alpha: 0.15),
                          valueColor:
                              AlwaysStoppedAnimation(AerisColors.accent(context)),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Decrypting your vault · please wait',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.35)
                          : const Color(0xFF0D1C1C).withValues(alpha: 0.40),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
