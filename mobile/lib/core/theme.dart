import 'package:flutter/material.dart';

/// The bundled UI font, registered with all its weights in pubspec.yaml.
const kFontFamily = 'PlusJakartaSans';

/// Design tokens for AERIS Expense — the "Arc" design language, borrowed
/// from the AERIS desktop HUD.
///
/// Dark-first: a near-black void, deep navy panels with hairline edges, and
/// ONE interactive accent — arc cyan — with violet as its gradient partner.
/// Money in is mint, spending stays plain ink (it's normal, not an alarm),
/// coral is reserved for real warnings. Everything brightness-dependent goes
/// through a `(context)` helper so light and dark stay in step.
class AerisColors {
  AerisColors._();

  /// Brand accent / default theme seed — arc cyan.
  static const seed = Color(0xFF37E0EA);

  /// Deep cyan for accent *text* on light surfaces (~5:1 on white).
  static const seedInk = Color(0xFF0E7490);

  // ── HUD palette ────────────────────────────────────────────
  static const arc = Color(0xFF37E0EA);
  static const violet = Color(0xFF7C6CFF);
  static const mint = Color(0xFF54F0C0);
  static const amber = Color(0xFFFFB454);
  static const coral = Color(0xFFFF5A6E);

  // ── Neutrals ───────────────────────────────────────────────
  static const bgLight = Color(0xFFEEF2F7); // cool lab-grey canvas
  static const cardLight = Color(0xFFFFFFFF);
  static const inkLight = Color(0xFF0B1220); // headings, amounts
  static const mutedLight = Color(0xFF5B6B82); // secondary text
  static const lineLight = Color(0xFFDCE3EC); // hairlines

  static const bgDark = Color(0xFF06080D); // void
  static const cardDark = Color(0xFF0D131D); // panel
  static const inkDark = Color(0xFFEAF2F7);
  static const mutedDark = Color(0xFF7C8AA0);
  static const lineDark = Color(0xFF1B2536);

  /// The interactive accent for the current theme — follows the user's accent
  /// choice (Customize dashboard); neon in dark mode, deepened in light mode.
  static Color accent(BuildContext context) =>
      Theme.of(context).colorScheme.primary;

  /// Text/icons drawn ON an accent fill (dark on neon, white on deep cyan).
  static Color onAccent(BuildContext context) =>
      Theme.of(context).colorScheme.onPrimary;

  /// Readable text/icon colour for ANY solid fill: near-black on bright
  /// (neon) fills, white on deep ones.
  static Color on(Color fill) => fill.computeLuminance() > 0.35
      ? const Color(0xFF06080D)
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

  static const credit = Color(0xFF059669); // money in — light
  static const creditDark = mint; // money in — dark
  static const debit = Color(0xFFE11D48); // danger — light
  static const debitDark = coral; // danger — dark
  static const warning = Color(0xFFD97706);
  static const info = Color(0xFF3B82F6);

  /// Old names for the canvas, kept for existing call sites.
  static const surfaceTintLight = bgLight;
  static const surfaceTintDark = bgDark;

  // Mascot / status moods — also reused for delight accents.
  static const moodHappy = Color(0xFF22C55E);
  static const moodNeutral = arc;
  static const moodWorried = Color(0xFFF59E0B);
  static const moodAlert = Color(0xFFEF4444);

  /// Arc gradient — the signature cyan → violet sweep (add button, progress,
  /// avatars). Deep enough at both ends to carry white text.
  static const heroGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF0E7490), Color(0xFF5B4FD6)],
  );

  /// The neon version for glows, bars and the add button on dark panels.
  static const arcGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [arc, violet],
  );

  /// The Home hero HUD panel — a deep navy slab with a faint arc glow.
  static const inkGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF10223A), Color(0xFF080D17)],
  );

  /// Soft accent gradient for secondary cards.
  static const violetGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF7C6CFF), Color(0xFF4F46E5)],
  );

  // Category palette — used in pie / stacked-bar charts.
  static const categoryPalette = <Color>[
    arc,
    Color(0xFFFFB454),
    violet,
    Color(0xFFFF6FB5),
    mint,
    coral,
    Color(0xFF4F9BFF),
    Color(0xFF2DD4BF),
    Color(0xFFB794FF),
    Color(0xFFFF8A4C),
    Color(0xFF22D3EE),
    Color(0xFFA3E635),
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

/// HUD-style caption: small caps with wide tracking ("SPENT · THIS MONTH").
TextStyle hudLabel(BuildContext context, {Color? color, double size = 11}) =>
    TextStyle(
      fontSize: size,
      fontWeight: FontWeight.w700,
      letterSpacing: 1.6,
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

/// The accent tone for [brightness], for any seed hue.
///
/// Light mode darkens the seed until white text on it passes AA (~4.5:1).
/// Dark mode keeps it neon — lifted if needed so it glows on the void — and
/// the theme's onPrimary switches the text on it to near-black.
Color accentFor(Brightness brightness, Color seed) {
  final hsl = HSLColor.fromColor(seed);
  if (brightness == Brightness.dark) {
    var c = seed;
    for (var l = hsl.lightness; c.computeLuminance() < 0.40 && l < 0.9;) {
      l += 0.02;
      c = hsl.withLightness(l).toColor();
    }
    return c;
  }
  var c = seed;
  for (var l = hsl.lightness; c.computeLuminance() > 0.18 && l > 0.1;) {
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
    onPrimary: dark ? const Color(0xFF04121A) : Colors.white,
    secondary: AerisColors.violet,
    surface: card,
    onSurface: ink,
    onSurfaceVariant: muted,
    surfaceTint: Colors.transparent,
    surfaceContainerLowest: dark ? const Color(0xFF04060A) : Colors.white,
    surfaceContainerLow:
        dark ? const Color(0xFF0A0F17) : const Color(0xFFF7F9FC),
    surfaceContainer: dark ? const Color(0xFF111926) : const Color(0xFFE9EEF5),
    surfaceContainerHigh:
        dark ? const Color(0xFF16202F) : const Color(0xFFE3E9F1),
    surfaceContainerHighest:
        dark ? const Color(0xFF1D2939) : const Color(0xFFDCE3EC),
    outline: dark ? const Color(0xFF42506A) : const Color(0xFF94A3B8),
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
      fillColor: dark ? const Color(0xFF0A0F17) : Colors.white,
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
<<<<<<< HEAD
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
      dragHandleColor: dark ? const Color(0xFF2A3749) : const Color(0xFFCBD5E1),
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
      backgroundColor: dark ? const Color(0xFF1B2536) : AerisColors.inkLight,
      contentTextStyle: jakarta(13.5, FontWeight.w600,
          color: dark ? AerisColors.inkDark : Colors.white),
      actionTextColor: dark ? AerisColors.arc : const Color(0xFF67E8F9),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: card,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
=======
      backgroundColor: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
      selectedColor: scheme.primary.withValues(alpha: 0.14),
      checkmarkColor: scheme.primary,
      labelStyle: GoogleFonts.plusJakartaSans(
          fontSize: 12, fontWeight: FontWeight.w600, color: scheme.onSurface),
      secondaryLabelStyle: GoogleFonts.plusJakartaSans(
          fontSize: 12, fontWeight: FontWeight.w600, color: scheme.onSurface),
      iconTheme: IconThemeData(color: scheme.onSurfaceVariant, size: 18),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      side: BorderSide.none,
>>>>>>> 03b46533542cdba8b0b640a9e2a5977620e74684
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
