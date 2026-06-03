import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Design tokens for AERIS Expense.
///
/// Colours are intentionally tuned for a "personal-finance" mood — calm
/// teals and slate, with green/red reserved STRICTLY for credit/debit so
/// they read as money signal, not chrome.
class AerisColors {
  AerisColors._();
  static const seed = Color(0xFF0EA5A4);
  static const credit = Color(0xFF22C55E);   // money in
  static const debit = Color(0xFFEF4444);    // money out
  static const warning = Color(0xFFF59E0B);
  static const info = Color(0xFF3B82F6);
  static const surfaceTintLight = Color(0xFFF7FAFA);
  static const surfaceTintDark = Color(0xFF0B1416);

  // Mascot / status moods — also reused for delight accents.
  static const moodHappy = Color(0xFF22C55E);
  static const moodNeutral = Color(0xFF0EA5A4);
  static const moodWorried = Color(0xFFF59E0B);
  static const moodAlert = Color(0xFFEF4444);

  /// Hero gradient for the balance card & celebratory surfaces.
  static const heroGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF0EA5A4), Color(0xFF0F766E)],
  );

  /// Soft accent gradient for secondary cards.
  static const violetGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF8B5CF6), Color(0xFF6366F1)],
  );

  // Category palette — used in pie / stacked-bar charts.
  static const categoryPalette = <Color>[
    Color(0xFF0EA5A4),
    Color(0xFFF59E0B),
    Color(0xFF8B5CF6),
    Color(0xFFEC4899),
    Color(0xFF22C55E),
    Color(0xFFEF4444),
    Color(0xFF3B82F6),
    Color(0xFF14B8A6),
    Color(0xFFA855F7),
    Color(0xFFF97316),
    Color(0xFF06B6D4),
    Color(0xFF84CC16),
  ];
}

ThemeData buildAerisTheme(Brightness brightness, {Color? seed}) {
  final scheme = ColorScheme.fromSeed(
    seedColor: seed ?? AerisColors.seed,
    brightness: brightness,
  );
  final base = brightness == Brightness.light ? ThemeData.light() : ThemeData.dark();
  return base.copyWith(
    colorScheme: scheme,
    scaffoldBackgroundColor: brightness == Brightness.light
        ? AerisColors.surfaceTintLight
        : AerisColors.surfaceTintDark,
    textTheme: GoogleFonts.interTextTheme(base.textTheme).apply(
      bodyColor: scheme.onSurface,
      displayColor: scheme.onSurface,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      foregroundColor: scheme.onSurface,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: GoogleFonts.inter(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: scheme.onSurface,
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: scheme.surfaceVariant.withOpacity(0.40),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceVariant.withOpacity(0.45),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: scheme.surfaceVariant.withOpacity(0.6),
      // Pin label + icon colour to the scheme — without this the label has no
      // colour and falls back to white (fine on dark, invisible on light).
      labelStyle: GoogleFonts.inter(
          fontSize: 12, fontWeight: FontWeight.w500, color: scheme.onSurface),
      secondaryLabelStyle: GoogleFonts.inter(
          fontSize: 12, fontWeight: FontWeight.w500, color: scheme.onSurface),
      iconTheme: IconThemeData(color: scheme.onSurfaceVariant, size: 18),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      side: BorderSide.none,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: brightness == Brightness.light
          ? Colors.white
          : const Color(0xFF101B1D),
      indicatorColor: AerisColors.seed.withOpacity(0.16),
      elevation: 3,
      labelTextStyle: WidgetStateProperty.all(
        GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600),
      ),
      iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? AerisColors.seed
                : scheme.onSurfaceVariant,
          )),
    ),
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: ZoomPageTransitionsBuilder(),
      TargetPlatform.iOS: ZoomPageTransitionsBuilder(),
    }),
  );
}
