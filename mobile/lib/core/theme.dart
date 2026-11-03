import 'package:flutter/material.dart';

import 'tokens.dart';

export 'tokens.dart';

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
  static const arc = Color(0xFF6E9EE0);

  /// Iris — the one secondary hue (goals, gradients' far end).
  static const violet = Color(0xFF8C82CF);

  /// Soft green — good / money in on dark.
  static const mint = Color(0xFF5CB88A);

  /// Muted amber — streaks, "needs you".
  static const amber = Color(0xFFD6A453);

  /// Soft red — warnings on dark.
  static const coral = Color(0xFFE0766D);

  // ── Neutrals ───────────────────────────────────────────────
  static const bgLight = Color(0xFFF4F5F7); // soft grey canvas
  static const cardLight = Color(0xFFFFFFFF);
  static const inkLight = Color(0xFF12161C); // headings, amounts
  static const mutedLight = Color(0xFF5E6978); // secondary text (5.6:1)
  static const lineLight = Color(0xFFE3E6EB); // hairlines

  static const bgDark = Color(0xFF0E1013); // graphite canvas
  static const cardDark = Color(0xFF16191E); // panel
  static const inkDark = Color(0xFFECEEF1);
  static const mutedDark = Color(0xFF9AA2AE);
  static const lineDark = Color(0xFF2A2F37);

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
      context.tk.accSoft;

  static Color card(BuildContext context) =>
      context.tk.surface;
  static Color canvas(BuildContext context) =>
      context.tk.bg;
  static Color line(BuildContext context) =>
      context.tk.hair;
  static Color muted(BuildContext context) =>
      context.tk.t2;

  /// Money in — mint/green. Money out — plain ink: spending is normal, so it
  /// isn't painted as an alarm. Use these for every amount.
  static Color moneyIn(BuildContext context) =>
      context.tk.ok;
  static Color moneyOut(BuildContext context) =>
      context.tk.t1;

  /// Warnings and destructive actions only (over budget, delete, sign out).
  static Color danger(BuildContext context) =>
      context.tk.bad;

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
    colors: [Color(0xFF3E78C2), Color(0xFF2A5B9C)],
  );

  /// The same on dark panels (lighter, still quiet).
  static const arcGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF7AA6DA), Color(0xFF4F86C6)],
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
      {double radius = Rad.card, Color? color}) {
    final tk = context.tk;
    // Graphite: depth by tone + a 1 dp hairline. Porcelain: one soft shadow.
    return BoxDecoration(
      color: color ?? tk.surface,
      borderRadius: BorderRadius.circular(radius),
      border: tk.edge,
      boxShadow: tk.shadow,
    );
  }
}

/// Small-caps caption ("SPENT · THIS MONTH") — modest tracking.
TextStyle hudLabel(BuildContext context, {Color? color, double size = 11}) =>
    TextStyle(
      fontSize: size,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.8,
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
    this.radius = Rad.card,
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
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
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


/// The app theme, built from the AERIS Design System tokens ([AerisTokens]).
/// Graphite (dark) gets depth from tone and hairlines; Porcelain (light) from
/// one soft shadow. Everything a Material widget draws comes from the tokens.
ThemeData buildAerisTheme(Brightness brightness, {Color? seed}) {
  final dark = brightness == Brightness.dark;
  final baseTokens = dark ? AerisTokens.graphite : AerisTokens.porcelain;
  // The design's exact accent by default; a user-picked accent is toned for
  // the theme by accentFor().
  final accent = seed == null || seed == AerisColors.seed
      ? baseTokens.acc
      : accentFor(brightness, seed);
  final tk = accent == baseTokens.acc
      ? baseTokens
      : baseTokens.withAccent(
          accent, dark ? const Color(0xFF0E141C) : Colors.white);

  final scheme = ColorScheme.fromSeed(
    seedColor: accent,
    brightness: brightness,
  ).copyWith(
    primary: tk.acc,
    onPrimary: tk.onAcc,
    primaryContainer: tk.accSoft2,
    onPrimaryContainer: tk.t1,
    secondary: tk.acc,
    onSecondary: tk.onAcc,
    secondaryContainer: tk.accSoft,
    onSecondaryContainer: tk.t1,
    surface: tk.surface,
    onSurface: tk.t1,
    onSurfaceVariant: tk.t2,
    surfaceTint: Colors.transparent,
    surfaceContainerLowest: tk.sunken,
    surfaceContainerLow: tk.surface,
    surfaceContainer: tk.raised,
    surfaceContainerHigh: tk.raised,
    surfaceContainerHighest: tk.sunken,
    outline: tk.hair2,
    outlineVariant: tk.hair,
    error: tk.bad,
    onError: dark ? const Color(0xFF1A0F0E) : Colors.white,
    inverseSurface: tk.inv,
    onInverseSurface: tk.onInv,
    inversePrimary: tk.invAcc,
  );

  final base = dark ? ThemeData.dark() : ThemeData.light();
  final text = base.textTheme.apply(
    fontFamily: kFontFamily,
    bodyColor: tk.t1,
    displayColor: tk.t1,
  );
  TextStyle jakarta(double size, FontWeight w, {Color? color, double? height}) =>
      TextStyle(
          fontFamily: kFontFamily,
          fontSize: size,
          fontWeight: w,
          height: height,
          color: color ?? tk.t1);
  const label = TextStyle(
      fontFamily: kFontFamily, fontSize: 15, fontWeight: FontWeight.w600);
  OutlineInputBorder box(Color c, [double w = 1]) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(Rad.input),
      borderSide: BorderSide(color: c, width: w));
  final pressed = WidgetStateProperty.resolveWith<Color?>(
      (s) => s.contains(WidgetState.pressed) ? tk.press : null);

  return base.copyWith(
    colorScheme: scheme,
    extensions: [tk],
    scaffoldBackgroundColor: tk.bg,
    canvasColor: tk.bg,
    dividerColor: tk.hair,
    splashFactory: InkSparkle.splashFactory,
    textTheme: _tabular(text),
    primaryTextTheme: base.primaryTextTheme.apply(fontFamily: kFontFamily),
    iconTheme: IconThemeData(color: tk.t1, size: 22),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      foregroundColor: tk.t1,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: jakarta(24, FontWeight.w700).copyWith(letterSpacing: -0.5),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: tk.surface,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Rad.card),
        side: BorderSide(color: dark ? tk.hair : const Color(0x0A12161C)),
      ),
    ),
    dividerTheme: DividerThemeData(color: tk.hair, thickness: 1, space: 1),
    listTileTheme: ListTileThemeData(
      iconColor: tk.t2,
      minVerticalPadding: 12,
      titleTextStyle: jakarta(15, FontWeight.w600),
      subtitleTextStyle: jakarta(13, FontWeight.w400, color: tk.t2),
    ),
    // Fields: 56 dp, radius 14, sunken well in dark / white in light; focus is
    // a 2 dp accent edge; errors are red with helper text (never colour alone).
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: tk.field,
      prefixIconColor: tk.t2,
      suffixIconColor: tk.t2,
      labelStyle: jakarta(14, FontWeight.w500, color: tk.t2),
      floatingLabelStyle: jakarta(14, FontWeight.w600, color: tk.acc),
      hintStyle: jakarta(15, FontWeight.w400, color: tk.t3),
      helperStyle: jakarta(12, FontWeight.w500, color: tk.t2),
      errorStyle: jakarta(12, FontWeight.w600, color: tk.bad),
      border: box(tk.hair),
      enabledBorder: box(tk.hair),
      disabledBorder: box(tk.hair.withValues(alpha: 0.5)),
      focusedBorder: box(tk.acc, 2),
      errorBorder: box(tk.bad),
      focusedErrorBorder: box(tk.bad, 2),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 17),
    ),
    // Buttons: 48 dp, radius 16, label 15/600.
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: tk.acc,
        foregroundColor: tk.onAcc,
        disabledBackgroundColor: tk.hair,
        disabledForegroundColor: tk.t3,
        minimumSize: const Size(64, 48),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 13),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Rad.button)),
        textStyle: label,
      ).copyWith(overlayColor: pressed),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: tk.acc,
        foregroundColor: tk.onAcc,
        elevation: 0,
        minimumSize: const Size(64, 48),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 13),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Rad.button)),
        textStyle: label,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: tk.t1,
        side: BorderSide(color: tk.hair2, width: 1.5),
        minimumSize: const Size(64, 48),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Rad.button)),
        textStyle: label,
      ).copyWith(overlayColor: pressed),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: tk.acc,
        textStyle: label.copyWith(fontSize: 14, fontWeight: FontWeight.w700),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: tk.t1,
        minimumSize: const Size(48, 48),
        iconSize: 22,
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        backgroundColor: tk.sunken,
        selectedBackgroundColor: tk.segSel,
        selectedForegroundColor: tk.t1,
        foregroundColor: tk.t2,
        side: BorderSide.none,
        textStyle: jakarta(14, FontWeight.w600),
      ),
    ),
    // Chips: 40 dp, radius 12; selected = accent-soft + accent text.
    chipTheme: ChipThemeData(
      backgroundColor: tk.surface,
      selectedColor: tk.accSoft2,
      checkmarkColor: tk.acc,
      labelStyle: jakarta(13.5, FontWeight.w600),
      secondaryLabelStyle: jakarta(13.5, FontWeight.w700, color: tk.acc),
      iconTheme: IconThemeData(color: tk.t2, size: 18),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Rad.chip)),
      side: BorderSide(color: tk.hair2),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: tk.acc,
      linearTrackColor: tk.track,
      circularTrackColor: Colors.transparent,
      // Pull-to-refresh: the accent spinner on a raised disc.
      refreshBackgroundColor: tk.raised,
    ),
    switchTheme: SwitchThemeData(
      trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
      thumbColor: WidgetStateProperty.resolveWith((s) =>
          s.contains(WidgetState.selected)
              ? (dark ? const Color(0xFFF4F5F7) : Colors.white)
              : (dark ? tk.t2 : Colors.white)),
      trackColor: WidgetStateProperty.resolveWith((s) =>
          s.contains(WidgetState.selected) ? tk.acc : tk.hair2),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? tk.acc : Colors.transparent),
      checkColor: WidgetStateProperty.all(tk.onAcc),
      side: BorderSide(color: tk.hair2, width: 1.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: tk.acc,
      inactiveTrackColor: tk.track,
      thumbColor: tk.acc,
      overlayColor: tk.accSoft,
      trackHeight: 4,
    ),
    // Sheets: radius 28 top, frosted glass, 36×4 handle.
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: tk.glassSheet,
      surfaceTintColor: Colors.transparent,
      modalBackgroundColor: dark ? tk.raised : tk.surface,
      modalBarrierColor: tk.scrim,
      dragHandleColor: tk.hair2,
      dragHandleSize: const Size(36, 4),
      // Tablets: sheets stay a comfortable reading width, centred.
      constraints: const BoxConstraints(maxWidth: 560),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(Rad.sheet))),
    ),
    // Dialogs: raised surface, radius 28, max 320 dp wide.
    dialogTheme: DialogThemeData(
      backgroundColor: tk.raised,
      surfaceTintColor: Colors.transparent,
      barrierColor: tk.scrim,
      insetPadding: const EdgeInsets.symmetric(horizontal: 36, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Rad.dialog)),
      titleTextStyle: jakarta(20, FontWeight.w700),
      contentTextStyle: jakarta(15, FontWeight.w400, color: tk.t2, height: 1.45),
    ),
    // Snackbars: inverse surface, floating 16 dp above the nav.
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: tk.inv,
      contentTextStyle: jakarta(14, FontWeight.w600, color: tk.onInv),
      actionTextColor: tk.invAcc,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Rad.input)),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: tk.raised,
      surfaceTintColor: Colors.transparent,
      textStyle: jakarta(15, FontWeight.w500),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Rad.button),
          side: BorderSide(color: dark ? tk.hair : Colors.transparent)),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
          color: tk.inv, borderRadius: BorderRadius.circular(8)),
      textStyle: jakarta(12, FontWeight.w600, color: tk.onInv),
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: tk.t1,
      unselectedLabelColor: tk.t2,
      indicatorColor: tk.acc,
      dividerColor: tk.hair,
      labelStyle: jakarta(14, FontWeight.w700),
      unselectedLabelStyle: jakarta(14, FontWeight.w600),
    ),
    bottomAppBarTheme: BottomAppBarThemeData(
      color: tk.surface,
      elevation: 0,
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: tk.acc,
      foregroundColor: tk.onAcc,
      shape: const StadiumBorder(),
      elevation: 0,
    ),
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: ZoomPageTransitionsBuilder(),
      TargetPlatform.iOS: ZoomPageTransitionsBuilder(),
    }),
  );
}
