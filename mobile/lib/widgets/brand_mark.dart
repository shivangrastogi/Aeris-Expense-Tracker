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
