import 'package:flutter/material.dart';

/// The AERIS Design System 1.0 tokens — the exact values from the design
/// (Graphite = dark, the hero theme; Porcelain = light). Read them with
/// `context.tk` (e.g. `context.tk.surface`). Same token, two themes.
@immutable
class AerisTokens extends ThemeExtension<AerisTokens> {
  final Color bg, surface, raised, sunken, hair, hair2;
  final Color t1, t2, t3;
  final Color acc, accP, onAcc, accSoft, accSoft2;
  final Color heroA, heroB, onHero;
  final Color ok, warn, bad, okSoft, warnSoft, warnLine, badSoft, badLine;
  final Color glass, glassSheet, glassEdge, scrim, press;
  final Color inv, onInv, invAcc, field, track, segSel, skel, skel2;

  /// Light theme casts one soft shadow; dark gets depth from tone instead.
  final List<BoxShadow> shadow, shadowRaised, navShadow, sheetShadow, segShadow;
  final bool isDark;

  const AerisTokens({
    required this.bg,
    required this.surface,
    required this.raised,
    required this.sunken,
    required this.hair,
    required this.hair2,
    required this.t1,
    required this.t2,
    required this.t3,
    required this.acc,
    required this.accP,
    required this.onAcc,
    required this.accSoft,
    required this.accSoft2,
    required this.heroA,
    required this.heroB,
    required this.onHero,
    required this.ok,
    required this.warn,
    required this.bad,
    required this.okSoft,
    required this.warnSoft,
    required this.warnLine,
    required this.badSoft,
    required this.badLine,
    required this.glass,
    required this.glassSheet,
    required this.glassEdge,
    required this.scrim,
    required this.press,
    required this.inv,
    required this.onInv,
    required this.invAcc,
    required this.field,
    required this.track,
    required this.segSel,
    required this.skel,
    required this.skel2,
    required this.shadow,
    required this.shadowRaised,
    required this.navShadow,
    required this.sheetShadow,
    required this.segShadow,
    required this.isDark,
  });

  /// Graphite — dark, the hero theme.
  static const graphite = AerisTokens(
    bg: Color(0xFF0E1013),
    surface: Color(0xFF16191E),
    raised: Color(0xFF1D2127),
    sunken: Color(0xFF0A0C0F),
    hair: Color(0xFF2A2F37),
    hair2: Color(0xFF3A414B),
    t1: Color(0xFFECEEF1),
    t2: Color(0xFF9AA2AE),
    t3: Color(0xFF6B7380),
    acc: Color(0xFF6E9EE0),
    accP: Color(0xFF5A8AD0),
    onAcc: Color(0xFF0E141C),
    accSoft: Color(0x1F6E9EE0), // .12
    accSoft2: Color(0x386E9EE0), // .22
    heroA: Color(0xFF7AA6DA),
    heroB: Color(0xFF4F86C6),
    onHero: Color(0xFF0E141C),
    ok: Color(0xFF5CB88A),
    warn: Color(0xFFD6A453),
    bad: Color(0xFFE0766D),
    okSoft: Color(0x1F5CB88A),
    warnSoft: Color(0x1FD6A453),
    warnLine: Color(0x4DD6A453),
    badSoft: Color(0x1AE0766D),
    badLine: Color(0x4DE0766D),
    glass: Color(0xB81D2127), // .72
    glassSheet: Color(0xDB1D2127), // .86
    glassEdge: Color(0x12ECEEF1), // .07
    scrim: Color(0x9E050608), // .62
    press: Color(0x0FECEEF1), // .06
    inv: Color(0xFFECEEF1),
    onInv: Color(0xFF12161C),
    invAcc: Color(0xFF2F66AE),
    field: Color(0xFF0A0C0F),
    track: Color(0xFF2A2F37),
    segSel: Color(0xFF2A2F37),
    skel: Color(0xFF1D2127),
    skel2: Color(0xFF262B32),
    shadow: [],
    shadowRaised: [],
    navShadow: [],
    sheetShadow: [],
    segShadow: [],
    isDark: true,
  );

  /// Porcelain — light.
  static const porcelain = AerisTokens(
    bg: Color(0xFFF4F5F7),
    surface: Color(0xFFFFFFFF),
    raised: Color(0xFFFFFFFF),
    sunken: Color(0xFFEBEDF1),
    hair: Color(0xFFE3E6EB),
    hair2: Color(0xFFCDD2D9),
    t1: Color(0xFF12161C),
    t2: Color(0xFF5E6978),
    t3: Color(0xFF8A93A0),
    acc: Color(0xFF2F66AE),
    accP: Color(0xFF24528F),
    onAcc: Color(0xFFFFFFFF),
    accSoft: Color(0x1A2F66AE), // .10
    accSoft2: Color(0x2E2F66AE), // .18
    heroA: Color(0xFF3E78C2),
    heroB: Color(0xFF2A5B9C),
    onHero: Color(0xFFFFFFFF),
    ok: Color(0xFF2E8656),
    warn: Color(0xFFA9711C),
    bad: Color(0xFFBF433A),
    okSoft: Color(0x1A2E8656),
    warnSoft: Color(0x1AA9711C),
    warnLine: Color(0x3DA9711C),
    badSoft: Color(0x12BF433A),
    badLine: Color(0x38BF433A),
    glass: Color(0xC2FFFFFF), // .76
    glassSheet: Color(0xE6FFFFFF), // .9
    glassEdge: Color(0x0F12161C), // .06
    scrim: Color(0x5212161C), // .32
    press: Color(0x0D12161C), // .05
    inv: Color(0xFF12161C),
    onInv: Color(0xFFF4F5F7),
    invAcc: Color(0xFF6E9EE0),
    field: Color(0xFFFFFFFF),
    track: Color(0xFFE3E6EB),
    segSel: Color(0xFFFFFFFF),
    skel: Color(0xFFE8EAEE),
    skel2: Color(0xFFF5F6F8),
    shadow: [
      BoxShadow(color: Color(0x1412161C), blurRadius: 18, offset: Offset(0, 6)),
    ],
    shadowRaised: [
      BoxShadow(color: Color(0x1F12161C), blurRadius: 28, offset: Offset(0, 10)),
    ],
    navShadow: [
      BoxShadow(color: Color(0x1A12161C), blurRadius: 24, offset: Offset(0, 8)),
    ],
    sheetShadow: [
      BoxShadow(color: Color(0x1F12161C), blurRadius: 32, offset: Offset(0, -10)),
    ],
    segShadow: [
      BoxShadow(color: Color(0x2412161C), blurRadius: 3, offset: Offset(0, 1)),
    ],
    isDark: false,
  );

  /// Card edge: a 1 dp hairline in dark, a near-invisible one in light.
  Border get edge => isDark
      ? Border.all(color: hair)
      : Border.all(color: const Color(0x0A12161C));

  /// The hero gradient — the main spend card and the "+" only.
  LinearGradient get hero => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [heroA, heroB],
      );

  /// These tokens with a user-chosen accent (Customize Home).
  AerisTokens withAccent(Color a, Color onA) => AerisTokens(
        bg: bg, surface: surface, raised: raised, sunken: sunken,
        hair: hair, hair2: hair2, t1: t1, t2: t2, t3: t3,
        acc: a,
        accP: Color.lerp(a, isDark ? Colors.black : Colors.black, 0.15)!,
        onAcc: onA,
        accSoft: a.withValues(alpha: isDark ? 0.12 : 0.10),
        accSoft2: a.withValues(alpha: isDark ? 0.22 : 0.18),
        heroA: heroA, heroB: heroB, onHero: onHero,
        ok: ok, warn: warn, bad: bad, okSoft: okSoft, warnSoft: warnSoft,
        warnLine: warnLine, badSoft: badSoft, badLine: badLine,
        glass: glass, glassSheet: glassSheet, glassEdge: glassEdge,
        scrim: scrim, press: press, inv: inv, onInv: onInv, invAcc: invAcc,
        field: field, track: track, segSel: segSel, skel: skel, skel2: skel2,
        shadow: shadow, shadowRaised: shadowRaised, navShadow: navShadow,
        sheetShadow: sheetShadow, segShadow: segShadow, isDark: isDark,
      );

  @override
  AerisTokens copyWith() => this;

  @override
  AerisTokens lerp(ThemeExtension<AerisTokens>? other, double t) =>
      other is AerisTokens && t >= 0.5 ? other : this;
}

extension AerisTokensContext on BuildContext {
  /// The design tokens for the current theme.
  AerisTokens get tk =>
      Theme.of(this).extension<AerisTokens>() ??
      (Theme.of(this).brightness == Brightness.dark
          ? AerisTokens.graphite
          : AerisTokens.porcelain);
}

/// Spacing scale (8 dp grid, 4 dp for fine adjustments).
class Sp {
  Sp._();
  static const s1 = 4.0, s2 = 8.0, s3 = 12.0, s4 = 16.0, s5 = 20.0;
  static const s6 = 24.0, s8 = 32.0, s10 = 40.0, s12 = 48.0;

  /// Screen side margin.
  static const margin = 20.0;
}

/// Corner radii.
class Rad {
  Rad._();
  static const card = 20.0, sheet = 28.0, button = 16.0, input = 14.0;
  static const chip = 12.0, tile = 12.0, dialog = 28.0;
}

/// Motion tokens.
class Mo {
  Mo._();
  static const curve = Cubic(0.2, 0, 0, 1);
  static const standard = Duration(milliseconds: 250);
  static const enter = Duration(milliseconds: 300);
  static const exit = Duration(milliseconds: 200);
  static const press = Duration(milliseconds: 100);
  static const countUp = Duration(milliseconds: 600);
  static const fill = Duration(milliseconds: 600);
}
