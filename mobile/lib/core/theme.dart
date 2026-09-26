import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Design tokens for AERIS Expense — "Flow" design language.
class AerisColors {
  AerisColors._();
  static const seed = Color(0xFF0EA5A4);

  /// Deep teal for teal *text* on light surfaces. [seed] is only ~3:1 on
  /// white (fails WCAG AA for small text); this is ~5.5:1. Keep [seed] for
  /// fills, icons and buttons.
  static const seedInk = Color(0xFF0F766E);

  /// Teal for text: [seedInk] in light mode, [seed] in dark mode (where the
  /// bright teal already reads well and the deep one would be too dim).
  static Color ink(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? seed : seedInk;

  /// Money-in / money-out colours for the current brightness. Use these for
  /// every amount so income and spend look the same on every screen.
  static Color moneyIn(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? creditDark : credit;
  static Color moneyOut(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? debitDark : debit;

  static const credit = Color(0xFF15A24A); // money in — #15A24A light
  static const creditDark = Color(0xFF34D27B); // money in — dark
  static const debit = Color(0xFFE5484D); // money out
  static const debitDark = Color(0xFFFF6B6F); // money out — dark
  static const warning = Color(0xFFE08C00);
  static const info = Color(0xFF3B82F6);
  static const surfaceTintLight = Color(0xFFF2F7F6);
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

/// Equal-width digits app-wide: amounts line up in lists and totals don't
/// jiggle while counting up. Explicit `TextStyle(...)`s inherit this through
/// DefaultTextStyle unless they set their own fontFeatures.
TextTheme _tabular(TextTheme t) {
  const f = [FontFeature.tabularFigures()];
  TextStyle? s(TextStyle? x) => x?.copyWith(fontFeatures: f);
  return t.copyWith(
    displayLarge: s(t.displayLarge),
    displayMedium: s(t.displayMedium),
    displaySmall: s(t.displaySmall),
    headlineLarge: s(t.headlineLarge),
    headlineMedium: s(t.headlineMedium),
    headlineSmall: s(t.headlineSmall),
    titleLarge: s(t.titleLarge),
    titleMedium: s(t.titleMedium),
    titleSmall: s(t.titleSmall),
    bodyLarge: s(t.bodyLarge),
    bodyMedium: s(t.bodyMedium),
    bodySmall: s(t.bodySmall),
    labelLarge: s(t.labelLarge),
    labelMedium: s(t.labelMedium),
    labelSmall: s(t.labelSmall),
  );
}

ThemeData buildAerisTheme(Brightness brightness, {Color? seed}) {
  final scheme = ColorScheme.fromSeed(
    seedColor: seed ?? AerisColors.seed,
    brightness: brightness,
  );
  final base =
      brightness == Brightness.light ? ThemeData.light() : ThemeData.dark();
  return base.copyWith(
    colorScheme: scheme,
    scaffoldBackgroundColor: brightness == Brightness.light
        ? AerisColors.surfaceTintLight
        : AerisColors.surfaceTintDark,
    textTheme: _tabular(
      GoogleFonts.plusJakartaSansTextTheme(base.textTheme).apply(
        bodyColor: scheme.onSurface,
        displayColor: scheme.onSurface,
      ),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      foregroundColor: scheme.onSurface,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: GoogleFonts.plusJakartaSans(
        fontSize: 20,
        fontWeight: FontWeight.w800,
        color: scheme.onSurface,
        letterSpacing: -0.5,
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: brightness == Brightness.light
          ? Colors.white
          : const Color(0xFF14221F),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(
          color: brightness == Brightness.light
              ? const Color(0x170E1A18)
              : const Color(0x17FFFFFF),
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
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
        textStyle: GoogleFonts.plusJakartaSans(
            fontSize: 15, fontWeight: FontWeight.w700),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
      labelStyle: GoogleFonts.plusJakartaSans(
          fontSize: 12, fontWeight: FontWeight.w600, color: scheme.onSurface),
      secondaryLabelStyle: GoogleFonts.plusJakartaSans(
          fontSize: 12, fontWeight: FontWeight.w600, color: scheme.onSurface),
      iconTheme: IconThemeData(color: scheme.onSurfaceVariant, size: 18),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      side: BorderSide.none,
    ),
    bottomAppBarTheme: BottomAppBarThemeData(
      color: brightness == Brightness.light
          ? Colors.white
          : const Color(0xFF0D1518),
      elevation: 8,
      shadowColor: Colors.black.withValues(alpha: 0.12),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: AerisColors.seed,
      foregroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      elevation: 6,
    ),
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: ZoomPageTransitionsBuilder(),
      TargetPlatform.iOS: ZoomPageTransitionsBuilder(),
    }),
  );
}
