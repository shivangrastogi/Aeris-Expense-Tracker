import 'package:flutter/material.dart';

import '../widgets/brand_mark.dart';
import '../widgets/ds.dart';

/// The launch screen, matching the Android 12+ system splash so the hand-off
/// is seamless: graphite ground, the mark on a 192 dp disc, and the rising
/// line loader while the vault decrypts.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  // Same in both themes — it continues the native launch window.
  static const _bg = Color(0xFF0E1013);
  static const _disc = Color(0xFF16191E);
  static const _mark = Color(0xFF6E9EE0);
  static const _meta = Color(0xFF6B7380);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: Stack(children: [
        Center(
          child: Container(
            width: 192,
            height: 192,
            decoration:
                const BoxDecoration(color: _disc, shape: BoxShape.circle),
            alignment: Alignment.center,
            child: const AerisMarkGlyph(size: 104, color: _mark),
          ),
        ),
        const Positioned(
          left: 0,
          right: 0,
          bottom: 64,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            RisingLoader(color: _mark, width: 26),
            SizedBox(height: 10),
            Text('Unlocking your data',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: _meta)),
          ]),
        ),
      ]),
    );
  }
}
