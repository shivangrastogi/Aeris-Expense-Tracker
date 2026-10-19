import 'package:flutter/material.dart';

/// The bundled UI font, registered with all its weights in pubspec.yaml.
const kFontFamily = 'PlusJakartaSans';

/// Design tokens for AERIS Expense — "Graphite", a calm, professional look.
///
/// Neutral surfaces (soft grey / graphite, never pure black), ONE quiet
/// accent — steel blue — and colour only where it means something: green for
/// money in, amber for "needs you", red for warnings. Spending stays plain
/// ink (it's normal, not an alarm). No neon, no glows. Everything
/// brightness-dependent goes through a `(context)` helper so light and dark
/// stay in step.
class AerisColors {
  AerisColors._();

  /// Brand accent / default theme seed — steel blue.
  static const seed = Color(0xFF4F86C6);

  /// Deep steel blue for accent *text* on light surfaces (~5:1 on white).
  static const seedInk = Color(0xFF2B5F9E);

  // ── Supporting palette (muted; names kept from the old HUD palette) ──
  /// Soft steel blue — the accent as it reads on dark panels.
  static const arc = Color(0xFF7AA6DA);

  /// Iris — the one secondary hue (goals, gradients' far end).
  static const violet = Color(0xFF8C82CF);

  /// Soft green — good / money in on dark.
  static const mint = Color(0xFF63B98F);

  /// Muted amber — streaks, "needs you".
  static const amber = Color(0xFFD2A35A);

  /// Soft red — warnings on dark.
  static const coral = Color(0xFFD9786F);

  // ── Neutrals ───────────────────────────────────────────────
  static const bgLight = Color(0xFFF3F4F6); // soft grey canvas
  static const cardLight = Color(0xFFFFFFFF);
  static const inkLight = Color(0xFF151A22); // headings, amounts
  static const mutedLight = Color(0xFF5E6978); // secondary text (5.6:1)
  static const lineLight = Color(0xFFE3E6EB); // hairlines

  static const bgDark = Color(0xFF0F1115); // graphite canvas
  static const cardDark = Color(0xFF181B21); // panel
  static const inkDark = Color(0xFFE6E8EB);
  static const mutedDark = Color(0xFF9199A5);
  static const lineDark = Color(0xFF272B33);

  /// The interactive accent for the current theme — follows the user's accent
  /// choice (Customize dashboard); softened in dark mode, deepened in light.
  static Color accent(BuildContext context) =>
      Theme.of(context).colorScheme.primary;

  /// Text/icons drawn ON an accent fill (dark on the soft dark-mode tone,
  /// white on the deep light-mode tone).
  static Color onAccent(BuildContext context) =>
      Theme.of(context).colorScheme.onPrimary;

  /// Readable text/icon colour for ANY solid fill: near-black on light fills,
  /// white on deep ones.
  static Color on(Color fill) => fill.computeLuminance() > 0.35
      ? const Color(0xFF111418)
      : Colors.white;

  /// Accent for text. Same as [accent]: the theme picks a tone that reads on
  /// the current background.
  static Color ink(BuildContext context) => accent(context);

  /// A soft tint of the accent, for selected pills and icon plates.
  static Color accentSoft(BuildContext context) =>
      accent(context).withValues(alpha: _dark(context) ? 0.14 : 0.10);

  static Color card(BuildContext context) =>
      _dark(context) ? cardDark : cardLight;
  static Color canvas(BuildContext context) =>
      _dark(context) ? bgDark : bgLight;
  static Color line(BuildContext context) =>
      _dark(context) ? lineDark : lineLight;
  static Color muted(BuildContext context) =>
      _dark(context) ? mutedDark : mutedLight;

  /// Money in — mint/green. Money out — plain ink: spending is normal, so it
  /// isn't painted as an alarm. Use these for every amount.
  static Color moneyIn(BuildContext context) =>
      _dark(context) ? creditDark : credit;
  static Color moneyOut(BuildContext context) =>
      Theme.of(context).colorScheme.onSurface;

  /// Warnings and destructive actions only (over budget, delete, sign out).
  static Color danger(BuildContext context) =>
      _dark(context) ? debitDark : debit;

  static bool _dark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  static const credit = Color(0xFF2E8656); // money in — light (4.6:1)
  static const creditDark = mint; // money in — dark
  static const debit = Color(0xFFBF433A); // danger — light (5.3:1)
  static const debitDark = coral; // danger — dark
  static const warning = Color(0xFFA9711C); // text-safe amber (4.6:1)
  static const info = Color(0xFF3D73B0);

  /// Old names for the canvas, kept for existing call sites.
  static const surfaceTintLight = bgLight;
  static const surfaceTintDark = bgDark;

  // Mascot / status moods.
  static const moodHappy = Color(0xFF4C9A6C);
  static const moodNeutral = arc;
  static const moodWorried = Color(0xFFC9952E);
  static const moodAlert = Color(0xFFC0443B);

  /// Accent fill for primary surfaces that carry white text (add button,
  /// avatars) — a barely-there steel-blue → slate-indigo shift, not a sweep.
  static const heroGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF3A6EAD), Color(0xFF3F5596)],
  );

  /// The same on dark panels (lighter, still quiet).
  static const arcGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF6F9CD3), Color(0xFF6E86C4)],
  );

  /// The Home hero panel — a flat graphite slab in both themes.
  static const inkGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF20252E), Color(0xFF181C23)],
  );

  /// Secondary accent fill (goal / feature cards).
  static const violetGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF6C7CC2), Color(0xFF5867A9)],
  );

  /// Chart palette — muted, and validated (dataviz checks: lightness band,
  /// chroma, colour-blind separation of neighbours, contrast) on BOTH the
  /// white and the graphite surface. Use in this fixed order; never cycle
  /// past it — fold extra series into "Other".
  static const categoryPalette = <Color>[
    Color(0xFF5F8CCB), // steel blue
    Color(0xFFC97A52), // terracotta
    Color(0xFF2FA287), // teal
    Color(0xFFB0902F), // ochre
    Color(0xFFC9789A), // rose
    Color(0xFF5F9A4C), // sage
    Color(0xFF8A7ED3), // iris
    Color(0xFFC96A66), // brick
  ];

  /// The standard panel: white with a soft cool shadow in light mode, a
  /// hairline-edged navy panel in dark mode (shadows vanish on dark).
  static BoxDecoration cardDecoration(BuildContext context,
      {double radius = 22, Color? color}) {
    final dark = _dark(context);
    return BoxDecoration(
      color: color ?? card(context),
      borderRadius: BorderRadius.circular(radius),
      border: dark ? Border.all(color: lineDark) : null,
      boxShadow: dark
          ? null
          : const [
              BoxShadow(
                  color: Color(0x120B1220),
                  blurRadius: 18,
                  offset: Offset(0, 6)),
              BoxShadow(
                  color: Color(0x0A0B1220),
                  blurRadius: 3,
                  offset: Offset(0, 1)),
            ],
    );
  }
}

/// Small-caps caption ("SPENT · THIS MONTH") — modest tracking.
TextStyle hudLabel(BuildContext context, {Color? color, double size = 11}) =>
    TextStyle(
      fontSize: size,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.9,
      color: color ?? AerisColors.muted(context),
    );

/// A plain content card in the house style. Prefer this over hand-rolled
/// `Container(decoration: ...)` cards so every screen matches.
class AerisCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final VoidCallback? onTap;
  final Color? color;

  const AerisCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.radius = 22,
    this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final body = Padding(padding: padding, child: child);
    return DecoratedBox(
      decoration:
          AerisColors.cardDecoration(context, radius: radius, color: color),
      child: onTap == null
          ? body
          : Material(
              type: MaterialType.transparency,
              child: InkWell(
                borderRadius: BorderRadius.circular(radius),
                onTap: onTap,
                child: body,
              ),
            ),
    );
  }
}

/// Small caps section label ("MONEY", "TOOLS") used above grouped lists.
class SectionLabel extends StatelessWidget {
  final String text;
  final EdgeInsetsGeometry padding;
  const SectionLabel(this.text,
      {super.key, this.padding = const EdgeInsets.fromLTRB(4, 0, 4, 8)});

  @override
  Widget build(BuildContext context) => Padding(
        padding: padding,
        child: Text(text.toUpperCase(),
            style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.1,
                color: AerisColors.muted(context))),
      );
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

/// The accent tone for [brightness], for any seed hue (including the user's
/// accent choice).
///
/// Saturation is capped first so no choice turns neon. Light mode then
/// darkens until white text on it passes AA (~4.5:1). Dark mode lightens
/// just enough to read on graphite (luminance ~0.30) — soft, not glowing —
/// and the theme's onPrimary puts near-black text on it.
Color accentFor(Brightness brightness, Color seed) {
  var hsl = HSLColor.fromColor(seed);
  final maxSat = brightness == Brightness.dark ? 0.52 : 0.58;
  if (hsl.saturation > maxSat) hsl = hsl.withSaturation(maxSat);
  var c = hsl.toColor();
  if (brightness == Brightness.dark) {
    for (var l = hsl.lightness; c.computeLuminance() < 0.30 && l < 0.85;) {
      l += 0.02;
      c = hsl.withLightness(l).toColor();
    }
    for (var l = hsl.lightness; c.computeLuminance() > 0.42 && l > 0.3;) {
      l -= 0.02;
      c = hsl.withLightness(l).toColor();
    }
    return c;
  }
  for (var l = hsl.lightness; c.computeLuminance() > 0.17 && l > 0.1;) {
    l -= 0.02;
    c = hsl.withLightness(l).toColor();
  }
  return c;
}

ThemeData buildAerisTheme(Brightness brightness, {Color? seed}) {
  final dark = brightness == Brightness.dark;
  final accent = accentFor(brightness, seed ?? AerisColors.seed);
  final ink = dark ? AerisColors.inkDark : AerisColors.inkLight;
  final muted = dark ? AerisColors.mutedDark : AerisColors.mutedLight;
  final line = dark ? AerisColors.lineDark : AerisColors.lineLight;
  final card = dark ? AerisColors.cardDark : AerisColors.cardLight;
  final canvas = dark ? AerisColors.bgDark : AerisColors.bgLight;

  final scheme = ColorScheme.fromSeed(
    seedColor: seed ?? AerisColors.seed,
    brightness: brightness,
  ).copyWith(
    primary: accent,
    // Neon accent in dark mode → near-black text on it; deep accent in light
    // mode → white text.
    onPrimary: dark ? const Color(0xFF0E141C) : Colors.white,
    secondary: AerisColors.violet,
    surface: card,
    onSurface: ink,
    onSurfaceVariant: muted,
    surfaceTint: Colors.transparent,
    surfaceContainerLowest: dark ? const Color(0xFF0B0D10) : Colors.white,
    surfaceContainerLow:
        dark ? const Color(0xFF14171C) : const Color(0xFFF8F9FA),
    surfaceContainer: dark ? const Color(0xFF1D2128) : const Color(0xFFECEEF1),
    surfaceContainerHigh:
        dark ? const Color(0xFF22262E) : const Color(0xFFE6E9ED),
    surfaceContainerHighest:
        dark ? const Color(0xFF2A2F38) : const Color(0xFFE0E3E8),
    outline: dark ? const Color(0xFF4A515C) : const Color(0xFF9AA3AF),
    outlineVariant: line,
    error: dark ? AerisColors.debitDark : AerisColors.debit,
  );

  final base = dark ? ThemeData.dark() : ThemeData.light();
  final text = base.textTheme.apply(
    fontFamily: kFontFamily,
    bodyColor: ink,
    displayColor: ink,
  );
  TextStyle jakarta(double size, FontWeight w, {Color? color}) => TextStyle(
      fontFamily: kFontFamily,
      fontSize: size,
      fontWeight: w,
      color: color ?? ink);

  return base.copyWith(
    colorScheme: scheme,
    scaffoldBackgroundColor: canvas,
    canvasColor: canvas,
    dividerColor: line,
    textTheme: _tabular(text),
    primaryTextTheme: base.primaryTextTheme.apply(fontFamily: kFontFamily),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      foregroundColor: ink,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontFamily: kFontFamily,
        fontSize: 20,
        fontWeight: FontWeight.w800,
        color: ink,
        letterSpacing: -0.5,
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: card,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(
            color: dark ? AerisColors.lineDark : const Color(0x0D0F1A1A)),
      ),
    ),
    dividerTheme: DividerThemeData(color: line, thickness: 1, space: 1),
    listTileTheme: ListTileThemeData(
      iconColor: muted,
      titleTextStyle: jakarta(15, FontWeight.w600),
      subtitleTextStyle: jakarta(12.5, FontWeight.w500, color: muted),
    ),
    // Fields are white with a hairline, so they read on the warm canvas and
    // on white sheets alike; focus swaps the hairline for the accent.
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: dark ? const Color(0xFF14171C) : Colors.white,
      prefixIconColor: muted,
      labelStyle: jakarta(14, FontWeight.w500, color: muted),
      floatingLabelStyle: jakarta(14, FontWeight.w600, color: accent),
      hintStyle: jakarta(14, FontWeight.w500, color: muted),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: line),
      ),
      disabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: line.withValues(alpha: 0.5)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: accent, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: scheme.error),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: scheme.error, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: accent,
        foregroundColor: scheme.onPrimary,
        minimumSize: const Size(64, 50),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(
            fontFamily: kFontFamily, fontSize: 15, fontWeight: FontWeight.w700),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: accent,
        foregroundColor: scheme.onPrimary,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(
            fontFamily: kFontFamily, fontSize: 15, fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: ink,
        side: BorderSide(color: line, width: 1.2),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(
            fontFamily: kFontFamily, fontSize: 15, fontWeight: FontWeight.w700),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: accent,
        textStyle: const TextStyle(
            fontFamily: kFontFamily, fontSize: 14, fontWeight: FontWeight.w700),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: card,
      selectedColor: accent.withValues(alpha: dark ? 0.22 : 0.12),
      labelStyle: jakarta(12.5, FontWeight.w600),
      secondaryLabelStyle: jakarta(12.5, FontWeight.w700, color: accent),
      iconTheme: IconThemeData(color: muted, size: 18),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      side: BorderSide(color: line),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: accent,
      linearTrackColor: accent.withValues(alpha: 0.14),
      circularTrackColor: accent.withValues(alpha: 0.14),
    ),
    switchTheme: SwitchThemeData(
      trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: card,
      surfaceTintColor: Colors.transparent,
      modalBackgroundColor: card,
      dragHandleColor: dark ? const Color(0xFF353A44) : const Color(0xFFD1D5DB),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: card,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      titleTextStyle: jakarta(19, FontWeight.w800),
      contentTextStyle: jakarta(14, FontWeight.w500, color: muted),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: dark ? const Color(0xFF272B33) : AerisColors.inkLight,
      contentTextStyle: jakarta(13.5, FontWeight.w600,
          color: dark ? AerisColors.inkDark : Colors.white),
      actionTextColor: dark ? AerisColors.arc : const Color(0xFF9CC3EC),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: card,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    bottomAppBarTheme: BottomAppBarThemeData(
      color: card,
      elevation: 8,
      shadowColor: Colors.black.withValues(alpha: 0.12),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: accent,
      foregroundColor: scheme.onPrimary,
      shape: const StadiumBorder(),
      elevation: 2,
    ),
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: ZoomPageTransitionsBuilder(),
      TargetPlatform.iOS: ZoomPageTransitionsBuilder(),
    }),
  );
}
