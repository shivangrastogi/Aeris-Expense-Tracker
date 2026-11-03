import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/ph_icons.dart';

import '../core/theme.dart';
import '../models/category.dart';
import '../utils/formatters.dart';
import '../utils/motion.dart';

export '../core/ph_icons.dart';

/// The AERIS Design System 1.0 building blocks. Screens compose these instead
/// of hand-rolling cards, rows and pills, so every screen matches the design:
/// 20 dp cards, 40 dp category tiles, 64 dp rows, the rising-line-and-dot
/// progress motif, and money set with a small ₹ and a true minus sign.

/// Phosphor regular / fill / bold, shortened.
typedef Ph = PhosphorIconsRegular;
typedef PhFill = PhosphorIconsFill;
typedef PhBold = PhosphorIconsBold;

/// The true minus sign (U+2212) used for money out.
const kMinus = '−';

// ── Text styles from the type scale ─────────────────────────────────────────
class Ts {
  Ts._();
  static const _tab = [FontFeature.tabularFigures()];
  static const display = TextStyle(
      fontSize: 44, height: 48 / 44, fontWeight: FontWeight.w700,
      letterSpacing: -1, fontFeatures: _tab);
  static const amountL = TextStyle(
      fontSize: 28, height: 32 / 28, fontWeight: FontWeight.w700,
      letterSpacing: -0.5, fontFeatures: _tab);
  static const amountM = TextStyle(
      fontSize: 20, height: 24 / 20, fontWeight: FontWeight.w600,
      fontFeatures: _tab);
  static const headline = TextStyle(
      fontSize: 24, height: 30 / 24, fontWeight: FontWeight.w700,
      letterSpacing: -0.5);
  static const title = TextStyle(
      fontSize: 18, height: 24 / 18, fontWeight: FontWeight.w600);
  static const body = TextStyle(
      fontSize: 15, height: 22 / 15, fontWeight: FontWeight.w400);
  static const rowTitle = TextStyle(
      fontSize: 15, height: 22 / 15, fontWeight: FontWeight.w600);
  static const bodyS = TextStyle(
      fontSize: 13, height: 18 / 13, fontWeight: FontWeight.w400);
  static const label = TextStyle(
      fontSize: 12, height: 16 / 12, fontWeight: FontWeight.w600);
  static const overline = TextStyle(
      fontSize: 11, height: 14 / 11, fontWeight: FontWeight.w700,
      letterSpacing: 0.8);
}

// ── Money ───────────────────────────────────────────────────────────────────

/// "−₹486" / "+₹85,000" as a plain string (true minus, + for money in).
String signedMoney(num amount, {required bool credit, bool compact = false}) =>
    '${credit ? '+' : kMinus}${formatRupees(amount.abs(), compact: compact)}';

/// An amount with the currency symbol set at 64% size and 62% opacity, as the
/// design does for large figures. Hidden amounts ("₹••••") keep their sign.
class MoneyText extends StatelessWidget {
  final num amount;
  final TextStyle style;
  final Color? color;

  /// null = no sign, true = "+", false = "−".
  final bool? credit;
  final bool compact;
  final bool decimals;

  /// Paise in a smaller, secondary tone ("₹85,610.82").
  final bool smallDecimals;
  final bool smallSymbol;
  final TextAlign? textAlign;

  const MoneyText(
    this.amount, {
    super.key,
    this.style = Ts.rowTitle,
    this.color,
    this.credit,
    this.compact = false,
    this.decimals = false,
    this.smallDecimals = false,
    this.smallSymbol = true,
    this.textAlign,
  });

  @override
  Widget build(BuildContext context) {
    final tk = context.tk;
    final base = style.copyWith(
        color: color ?? style.color ?? tk.t1,
        fontFeatures: const [FontFeature.tabularFigures()]);
    final text = formatRupees(amount.abs(),
        compact: compact, decimals: decimals || smallDecimals);
    final m = RegExp(r'^([^\d•]*)(.*)$').firstMatch(text)!;
    var number = m[2]!;
    String? paise;
    if (smallDecimals && number.contains('.')) {
      final i = number.lastIndexOf('.');
      paise = number.substring(i);
      number = number.substring(0, i);
      if (paise == '.00') paise = null;
    }
    final sign = credit == null ? '' : (credit! ? '+' : kMinus);
    final size = base.fontSize ?? 15;
    return Text.rich(
      TextSpan(children: [
        if (sign.isNotEmpty) TextSpan(text: sign),
        TextSpan(
          text: m[1],
          style: smallSymbol && size >= 20
              ? TextStyle(
                  fontSize: size * 0.64,
                  fontWeight: FontWeight.w600,
                  color: base.color!.withValues(alpha: 0.62))
              : null,
        ),
        TextSpan(text: number),
        if (paise != null)
          TextSpan(
              text: paise,
              style: TextStyle(
                  fontSize: size * 0.8,
                  fontWeight: FontWeight.w500,
                  color: tk.t2)),
      ]),
      maxLines: 1,
      softWrap: false,
      textAlign: textAlign,
      style: base,
      semanticsLabel: kAmountsHidden
          ? 'amount hidden'
          : '${sign == kMinus ? 'minus ' : ''}$text',
    );
  }
}

/// A large amount that counts up from 0 the first time it's shown, then only
/// tweens between real changes. Instant with reduce-motion on.
class CountUpMoney extends StatefulWidget {
  final double value;
  final TextStyle style;
  final Color? color;
  final bool Function() counted;
  final VoidCallback markCounted;
  const CountUpMoney({
    super.key,
    required this.value,
    required this.counted,
    required this.markCounted,
    this.style = Ts.display,
    this.color,
  });

  @override
  State<CountUpMoney> createState() => _CountUpMoneyState();
}

class _CountUpMoneyState extends State<CountUpMoney> {
  late double _from = widget.counted() ? widget.value : 0;

  @override
  void initState() {
    super.initState();
    widget.markCounted();
  }

  @override
  void didUpdateWidget(CountUpMoney old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value) _from = old.value;
  }

  @override
  Widget build(BuildContext context) {
    final still = reduceMotion(context) || _from == widget.value;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: still ? widget.value : _from, end: widget.value),
      duration: still ? Duration.zero : Mo.countUp,
      curve: Curves.easeOutCubic,
      builder: (_, v, __) =>
          MoneyText(v.roundToDouble(), style: widget.style, color: widget.color),
    );
  }
}

// ── Surfaces ────────────────────────────────────────────────────────────────

/// A list-group card: rows separated by hairlines inset past the 40 dp tile.
class ListGroup extends StatelessWidget {
  final List<Widget> children;
  final double inset;
  final EdgeInsetsGeometry padding;
  const ListGroup({
    super.key,
    required this.children,
    this.inset = 68,
    this.padding = EdgeInsets.zero,
  });

  @override
  Widget build(BuildContext context) {
    final tk = context.tk;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: AerisColors.cardDecoration(context),
      padding: padding,
      child: Material(
        type: MaterialType.transparency,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0)
              Padding(
                padding: EdgeInsetsDirectional.only(start: inset),
                child: Container(height: 1, color: tk.hair),
              ),
            children[i],
          ],
        ]),
      ),
    );
  }
}

/// A titled card section ("Balances  from bank SMS", "Where it went  See all").
class SectionTitle extends StatelessWidget {
  final String title;
  final String? note;
  final String? action;
  final VoidCallback? onAction;
  final EdgeInsetsGeometry padding;
  const SectionTitle(
    this.title, {
    super.key,
    this.note,
    this.action,
    this.onAction,
    this.padding = EdgeInsets.zero,
  });

  @override
  Widget build(BuildContext context) {
    final tk = context.tk;
    return Padding(
      padding: padding,
      // The title (and note) take all the spare width, so the action sits
      // flush right; everything is centred on one line.
      child: Row(
        children: [
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Flexible(
                  child: Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Ts.title.copyWith(color: tk.t1)),
                ),
                if (note != null) ...[
                  const SizedBox(width: 8),
                  Text(note!,
                      style: Ts.label
                          .copyWith(fontWeight: FontWeight.w400, color: tk.t2)),
                ],
              ],
            ),
          ),
          if (action != null)
            // Nudge half the 8 dp touch padding out so the text lines up
            // with the day totals and card content on the right.
            Transform.translate(
              offset: const Offset(4, 0),
              child: TextLink(action!, onTap: onAction),
            ),
        ],
      ),
    );
  }
}

/// An accent text action with a 48 dp hit area ("See all").
class TextLink extends StatelessWidget {
  final String text;
  final VoidCallback? onTap;
  final Color? color;
  const TextLink(this.text, {super.key, this.onTap, this.color});

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Rad.chip),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          child: Text(text,
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: color ?? context.tk.acc)),
        ),
      );
}

/// Overline caption: 11/14 bold, +0.8 tracking, caps.
class Overline extends StatelessWidget {
  final String text;
  final Color? color;
  const Overline(this.text, {super.key, this.color});

  @override
  Widget build(BuildContext context) => Text(text.toUpperCase(),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: Ts.overline.copyWith(color: color ?? context.tk.t2));
}

// ── Tiles and avatars ───────────────────────────────────────────────────────

/// A category tile: hue at 14% fill, the icon in full hue. 40 dp, radius 12.
class CatTile extends StatelessWidget {
  final Color color;
  final IconData icon;
  final double size;
  final double? radius;
  const CatTile(
      {super.key, required this.color, required this.icon, this.size = 40, this.radius});

  factory CatTile.of(ExpenseCategory c, {double size = 40}) =>
      CatTile(color: c.color, icon: c.icon, size: size);

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(radius ?? size * 0.3),
        ),
        child: Icon(icon, color: color, size: size * 0.55),
      );
}

/// A neutral tile: bank badges ("HD", "SBI") or a plain icon on press tone.
class BadgeTile extends StatelessWidget {
  final String? text;
  final IconData? icon;
  final Color? tint;
  final double size;
  const BadgeTile({super.key, this.text, this.icon, this.tint, this.size = 40});

  @override
  Widget build(BuildContext context) {
    final tk = context.tk;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: tint == null ? tk.press : tint!.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(size * 0.3),
      ),
      alignment: Alignment.center,
      child: icon != null
          ? Icon(icon, size: size * 0.55, color: tint ?? tk.t2)
          : Text(text ?? '',
              maxLines: 1,
              style: TextStyle(
                  fontSize: size * 0.275,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.4,
                  color: tint ?? tk.t2)),
    );
  }
}

/// An initials avatar on a soft category hue.
class InitialAvatar extends StatelessWidget {
  final String name;
  final double size;
  final Color? color;
  /// Ready-made initials ("SR"), shown as given.
  final String? initials;
  const InitialAvatar(this.name,
      {super.key, this.size = 40, this.color, this.initials});

  static const _hues = [
    Color(0xFF8A7ED3), Color(0xFF5F9A4C), Color(0xFFC97A52),
    Color(0xFF5F8CCB), Color(0xFFC9789A), Color(0xFF2FA287),
  ];

  static String initialsOf(String name, {int max = 2}) => name
      .trim()
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .take(max)
      .map((w) => w[0].toUpperCase())
      .join();

  @override
  Widget build(BuildContext context) {
    final hue = color ??
        _hues[name.isEmpty ? 0 : name.codeUnits.fold<int>(0, (a, b) => a + b) % _hues.length];
    final init = initials ?? initialsOf(name, max: size >= 44 ? 2 : 1);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
          shape: BoxShape.circle, color: hue.withValues(alpha: 0.22)),
      alignment: Alignment.center,
      child: Text(init.isEmpty ? '?' : init,
          style: TextStyle(
              fontSize: size * 0.34,
              fontWeight: FontWeight.w700,
              color: context.tk.t1)),
    );
  }
}

// ── Rows ────────────────────────────────────────────────────────────────────

/// The standard row: 40 dp leading, title + sub-line, trailing. Min height
/// 64 dp, 16 dp padding, 12 dp gaps. Rows wrap rather than clip at 1.3×.
class DsRow extends StatelessWidget {
  final Widget? leading;
  final String title;
  final Widget? titleTrailing;
  final String? sub;
  final Widget? subWidget;
  final Widget? trailing;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double minHeight;
  final EdgeInsetsGeometry padding;
  final Color? titleColor;
  final int titleMaxLines;
  final int subMaxLines;
  const DsRow({
    super.key,
    this.leading,
    required this.title,
    this.titleTrailing,
    this.sub,
    this.subWidget,
    this.trailing,
    this.onTap,
    this.onLongPress,
    this.minHeight = 64,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    this.titleColor,
    this.titleMaxLines = 2,
    this.subMaxLines = 2,
  });

  @override
  Widget build(BuildContext context) {
    final tk = context.tk;
    final body = ConstrainedBox(
      constraints: BoxConstraints(minHeight: minHeight),
      child: Padding(
        padding: padding,
        child: Row(children: [
          if (leading != null) ...[leading!, const SizedBox(width: 12)],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(children: [
                  Flexible(
                    child: Text(title,
                        maxLines: titleMaxLines,
                        overflow: TextOverflow.ellipsis,
                        style: Ts.rowTitle
                            .copyWith(color: titleColor ?? tk.t1)),
                  ),
                  if (titleTrailing != null) ...[
                    const SizedBox(width: 6),
                    titleTrailing!,
                  ],
                ]),
                if (subWidget != null)
                  subWidget!
                else if (sub != null && sub!.isNotEmpty)
                  Text(sub!,
                      maxLines: subMaxLines,
                      overflow: TextOverflow.ellipsis,
                      // Plain text — sub-lines are never struck through.
                      style: Ts.bodyS.copyWith(
                          color: tk.t2, decoration: TextDecoration.none)),
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 12), trailing!],
        ]),
      ),
    );
    if (onTap == null && onLongPress == null) return body;
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      highlightColor: tk.press,
      splashColor: tk.press,
      child: body,
    );
  }
}

/// A settings row: 36 dp neutral icon tile, title, sub, a trailing control.
class SettingsRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? sub;
  final Widget? trailing;
  final VoidCallback? onTap;
  final Color? iconColor;
  final Color? titleColor;
  final bool chevron;
  const SettingsRow({
    super.key,
    required this.icon,
    required this.title,
    this.sub,
    this.trailing,
    this.onTap,
    this.iconColor,
    this.titleColor,
    this.chevron = false,
  });

  @override
  Widget build(BuildContext context) {
    final tk = context.tk;
    return DsRow(
      minHeight: 58,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: iconColor == null
              ? tk.press
              : iconColor!.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, size: 18, color: iconColor ?? tk.t2),
      ),
      title: title,
      titleColor: titleColor,
      sub: sub,
      trailing: trailing ??
          (chevron || onTap != null
              ? Icon(Ph.caretRight, size: 16, color: tk.t3)
              : null),
      onTap: onTap,
    );
  }
}

// ── Pills, chips, segmented ─────────────────────────────────────────────────

enum Tone { neutral, accent, ok, warn, bad }

/// A status pill: always an icon AND a word, never colour alone.
class StatusPill extends StatelessWidget {
  final String text;
  final IconData? icon;
  final Tone tone;
  final bool small;
  const StatusPill(this.text,
      {super.key, this.icon, this.tone = Tone.neutral, this.small = false});

  @override
  Widget build(BuildContext context) {
    final tk = context.tk;
    final (bg, fg) = switch (tone) {
      Tone.neutral => (tk.press, tk.t2),
      Tone.accent => (tk.accSoft, tk.acc),
      Tone.ok => (tk.okSoft, tk.ok),
      Tone.warn => (tk.warnSoft, tk.warn),
      Tone.bad => (tk.badSoft, tk.bad),
    };
    return Container(
      height: small ? 20 : 28,
      padding: EdgeInsets.symmetric(horizontal: small ? 7 : 10),
      decoration: BoxDecoration(
          color: bg, borderRadius: BorderRadius.circular(small ? 10 : 14)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[
          Icon(icon, size: small ? 11 : 14, color: fg),
          SizedBox(width: small ? 3 : 4),
        ],
        Text(text,
            style: TextStyle(
                fontSize: small ? 10 : 12,
                fontWeight: FontWeight.w700,
                color: fg)),
      ]),
    );
  }
}

/// A filter / choice chip: 36 dp tall, radius 12. Selected = accent-soft,
/// accent text and a check (not just a tint).
class DsChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final IconData? icon;
  final bool showCheck;
  const DsChip(this.label,
      {super.key,
      this.selected = false,
      this.onTap,
      this.icon,
      this.showCheck = false});

  @override
  Widget build(BuildContext context) {
    final tk = context.tk;
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        onTap: onTap == null
            ? null
            : () {
                HapticFeedback.selectionClick();
                onTap!();
              },
        borderRadius: BorderRadius.circular(Rad.chip),
        child: AnimatedContainer(
          duration: Mo.standard,
          curve: Mo.curve,
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: selected ? tk.accSoft : Colors.transparent,
            borderRadius: BorderRadius.circular(Rad.chip),
            border: Border.all(
                color: selected ? Colors.transparent : tk.hair2),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (selected && showCheck) ...[
              Icon(PhBold.check, size: 14, color: tk.acc),
              const SizedBox(width: 6),
            ] else if (icon != null) ...[
              Icon(icon, size: 15, color: selected ? tk.acc : tk.t1),
              const SizedBox(width: 6),
            ],
            Text(label,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: selected ? tk.acc : tk.t1)),
          ]),
        ),
      ),
    );
  }
}

/// The segmented control: a sunken track with the selected segment raised.
class DsSegmented extends StatelessWidget {
  final List<String> labels;
  final int index;
  final ValueChanged<int> onChanged;
  final double height;
  const DsSegmented({
    super.key,
    required this.labels,
    required this.index,
    required this.onChanged,
    this.height = 42,
  });

  @override
  Widget build(BuildContext context) {
    final tk = context.tk;
    return Container(
      height: height,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: tk.sunken,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: tk.hair),
      ),
      child: LayoutBuilder(builder: (context, c) {
        final w = c.maxWidth / labels.length;
        return Stack(children: [
          AnimatedPositioned(
            duration: Mo.standard,
            curve: Mo.curve,
            left: w * index,
            top: 0,
            bottom: 0,
            width: w,
            child: Container(
              decoration: BoxDecoration(
                color: tk.segSel,
                borderRadius: BorderRadius.circular(10),
                boxShadow: tk.segShadow,
              ),
            ),
          ),
          Row(children: [
            for (var i = 0; i < labels.length; i++)
              Expanded(
                child: Semantics(
                  button: true,
                  selected: i == index,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      if (i == index) return;
                      HapticFeedback.selectionClick();
                      onChanged(i);
                    },
                    child: Center(
                      child: Text(labels[i],
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: i == index ? tk.t1 : tk.t2)),
                    ),
                  ),
                ),
              ),
          ]),
        ]);
      }),
    );
  }
}

// ── Buttons ─────────────────────────────────────────────────────────────────

/// A 44 dp round icon button on the surface (Home header), optional dot.
class RoundIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool dot;
  final bool active;
  final double size;
  const RoundIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.dot = false,
    this.active = false,
    this.size = 44,
  });

  @override
  Widget build(BuildContext context) {
    final tk = context.tk;
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        child: Material(
          color: active ? tk.accSoft : tk.surface,
          shape: CircleBorder(
              side: tk.isDark && !active
                  ? BorderSide(color: tk.hair)
                  : BorderSide.none),
          shadowColor: Colors.transparent,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: active ? null : tk.shadow),
              child: Stack(alignment: Alignment.center, children: [
                Icon(icon, size: 20, color: active ? tk.acc : tk.t1),
                if (dot)
                  Positioned(
                    top: 10,
                    right: 11,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: tk.acc,
                        border: Border.all(color: tk.surface, width: 1.5),
                      ),
                    ),
                  ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// A tonal button (accent-soft fill, accent text).
class TonalButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final double height;
  const TonalButton(this.label,
      {super.key, this.icon, this.onPressed, this.height = 48});

  @override
  Widget build(BuildContext context) {
    final tk = context.tk;
    return FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: tk.accSoft,
        foregroundColor: tk.acc,
        minimumSize: Size(0, height),
        padding: const EdgeInsets.symmetric(horizontal: 16),
      ).copyWith(
          overlayColor: WidgetStateProperty.resolveWith((s) =>
              s.contains(WidgetState.pressed) ? tk.accSoft2 : null)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: 18), const SizedBox(width: 6)],
        Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
      ]),
    );
  }
}

// ── Progress ────────────────────────────────────────────────────────────────

/// A flat, rounded progress bar. Over the limit, callers pass red (and add a
/// word and an icon). [rise] and [dot] are kept for older call sites and are
/// ignored: the bar is always level, with no end dot.
class RisingProgress extends StatelessWidget {
  final double value;
  final Color? color;
  final Color? track;
  final double stroke;
  final double rise;
  final double dot;
  final bool animate;
  const RisingProgress({
    super.key,
    required this.value,
    this.color,
    this.track,
    this.stroke = 4,
    this.rise = 0,
    this.dot = 0,
    this.animate = true,
  });

  @override
  Widget build(BuildContext context) {
    final tk = context.tk;
    final c = color ?? tk.acc;
    final t = track ?? tk.track;
    final target = value.clamp(0.0, 1.0);
    // Thin hairline callers (stroke 2) still read as a bar.
    final h = math.max(stroke, 4.0);
    Widget bar(double v) => ClipRRect(
          borderRadius: BorderRadius.circular(h / 2),
          child: SizedBox(
            width: double.infinity,
            height: h,
            child: Stack(children: [
              Positioned.fill(child: ColoredBox(color: t)),
              FractionallySizedBox(
                widthFactor: v,
                heightFactor: 1,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                      color: c, borderRadius: BorderRadius.circular(h / 2)),
                ),
              ),
            ]),
          ),
        );
    if (!animate || reduceMotion(context)) return bar(target);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: target),
      duration: Mo.fill,
      curve: Mo.curve,
      builder: (_, v, __) => bar(v),
    );
  }
}

/// The loading indicator: a small standard spinner in the accent colour.
class RisingLoader extends StatelessWidget {
  final Color? color;
  final double width;
  const RisingLoader({super.key, this.color, this.width = 22});

  @override
  Widget build(BuildContext context) => SizedBox(
        width: width * 0.8,
        height: width * 0.8,
        child: CircularProgressIndicator(
          strokeWidth: 2.2,
          strokeCap: StrokeCap.round,
          color: color ?? context.tk.acc,
        ),
      );
}

/// A ring around a category tile ("Where it went", budgets). Stroke 6.
class CatRing extends StatelessWidget {
  final double value;
  final Color color;
  final Widget? center;
  final double size;
  final double stroke;
  final bool over;
  const CatRing({
    super.key,
    required this.value,
    required this.color,
    this.center,
    this.size = 72,
    this.stroke = 6,
    this.over = false,
  });

  @override
  Widget build(BuildContext context) {
    final tk = context.tk;
    final target = value.clamp(0.0, 1.0);
    final c = over ? tk.bad : color;
    Widget paint(double v) => CustomPaint(
          painter: _RingPainter(v, c, tk.track, stroke),
          child: Center(child: center),
        );
    return SizedBox(
      width: size,
      height: size,
      child: reduceMotion(context)
          ? paint(target)
          : TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: target),
              duration: Mo.fill,
              curve: Mo.curve,
              builder: (_, v, __) => paint(v),
            ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double v;
  final Color color, track;
  final double stroke;
  _RingPainter(this.v, this.color, this.track, this.stroke);

  @override
  void paint(Canvas canvas, Size size) {
    final r = (size.width - stroke) / 2;
    final c = size.center(Offset.zero);
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(c, r, p..color = track);
    if (v > 0) {
      canvas.drawArc(Rect.fromCircle(center: c, radius: r), -math.pi / 2,
          2 * math.pi * v, false, p..color = color);
    }
  }

  @override
  bool shouldRepaint(_RingPainter o) => o.v != v || o.color != color;
}

// ── States ──────────────────────────────────────────────────────────────────

/// Empty state: 64 dp accent tile, title, one line, one action.
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  final String? cta;
  final VoidCallback? onCta;
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    this.cta,
    this.onCta,
  });

  @override
  Widget build(BuildContext context) {
    final tk = context.tk;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
              color: tk.accSoft, borderRadius: BorderRadius.circular(18)),
          child: Icon(icon, size: 30, color: tk.acc),
        ),
        const SizedBox(height: 12),
        Text(title,
            textAlign: TextAlign.center,
            style: Ts.title.copyWith(color: tk.t1)),
        const SizedBox(height: 8),
        Text(body,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, height: 20 / 14, color: tk.t2)),
        if (cta != null) ...[
          const SizedBox(height: 18),
          FilledButton(onPressed: onCta, child: Text(cta!)),
        ],
      ]),
    );
  }
}

/// A banner card: soft status fill, icon, title, line, optional action.
class Banner2 extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? body;
  final Tone tone;
  final String? action;
  final VoidCallback? onAction;
  final VoidCallback? onTap;
  const Banner2({
    super.key,
    required this.icon,
    required this.title,
    this.body,
    this.tone = Tone.accent,
    this.action,
    this.onAction,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tk = context.tk;
    final (bg, line, fg) = switch (tone) {
      Tone.bad => (tk.badSoft, tk.badLine, tk.bad),
      Tone.warn => (tk.warnSoft, tk.warnLine, tk.warn),
      Tone.ok => (tk.okSoft, Colors.transparent, tk.ok),
      Tone.accent => (tk.accSoft, Colors.transparent, tk.acc),
      Tone.neutral => (tk.surface, tk.hair, tk.t2),
    };
    return Material(
      color: bg,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Rad.card),
          side: BorderSide(color: line)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Rad.card),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, size: 24, color: fg),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Ts.rowTitle.copyWith(color: tk.t1)),
                  if (body != null) ...[
                    const SizedBox(height: 2),
                    Text(body!, style: Ts.bodyS.copyWith(color: tk.t2)),
                  ],
                  if (action != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: InkWell(
                        onTap: onAction ?? onTap,
                        borderRadius: BorderRadius.circular(Rad.chip),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Text(action!,
                              style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: tk.t1,
                                  decoration: TextDecoration.underline,
                                  decorationColor: tk.t1)),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

/// A day header over a group of rows: "Today ........ −₹1,686".
class DayHeader extends StatelessWidget {
  final String day;
  final String? total;
  const DayHeader(this.day, {super.key, this.total});

  @override
  Widget build(BuildContext context) {
    final tk = context.tk;
    final s = TextStyle(
        fontSize: 12,
        height: 16 / 12,
        fontWeight: FontWeight.w700,
        color: tk.t2,
        fontFeatures: const [FontFeature.tabularFigures()]);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 6, 4, 6),
      child: Row(children: [
        Expanded(child: Text(day, style: s)),
        if (total != null) Text(total!, style: s),
      ]),
    );
  }
}

/// A bottom-sheet scaffold: handle, title, optional sub-line, content.
Future<T?> showDsSheet<T>(
  BuildContext context, {
  required String title,
  String? subtitle,
  required WidgetBuilder builder,
  bool scrollControlled = false,
}) =>
    showModalBottomSheet<T>(
      context: context,
      showDragHandle: true,
      isScrollControlled: scrollControlled,
      useSafeArea: true,
      builder: (ctx) {
        final tk = ctx.tk;
        return SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
                20, 0, 20, 16 + MediaQuery.viewInsetsOf(ctx).bottom),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Ts.title.copyWith(color: tk.t1)),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(subtitle, style: Ts.bodyS.copyWith(color: tk.t2)),
                ],
                const SizedBox(height: 12),
                Flexible(child: builder(ctx)),
              ],
            ),
          ),
        );
      },
    );

// ── Large title → collapsed bar on scroll ───────────────────────────────────

/// Tracks whether the vertical scroll under it has passed [threshold] (the
/// design's "scroll to collapse"). Horizontal lists (chips) are ignored, and
/// a freshly shown list at the top (e.g. after a tab switch) un-collapses.
class CollapseOnScroll extends StatefulWidget {
  final Widget Function(BuildContext context, bool collapsed) builder;
  final double threshold;
  const CollapseOnScroll(
      {super.key, required this.builder, this.threshold = 26});

  @override
  State<CollapseOnScroll> createState() => _CollapseOnScrollState();
}

class _CollapseOnScrollState extends State<CollapseOnScroll> {
  bool _collapsed = false;

  bool _on(Notification n) {
    final m = switch (n) {
      ScrollNotification(:final metrics) => metrics,
      ScrollMetricsNotification(:final metrics) => metrics,
      _ => null,
    };
    if (m == null || m.axis != Axis.vertical) return false;
    final c = m.pixels > widget.threshold;
    if (c != _collapsed) setState(() => _collapsed = c);
    return false;
  }

  @override
  Widget build(BuildContext context) => NotificationListener<Notification>(
        onNotification: _on,
        child: widget.builder(context, _collapsed),
      );
}

/// A tab's title bar: the large title (left) shrinks into an 18 dp title in a
/// 56 dp bar with a hairline under it once the page scrolls. Actions stay put.
class CollapsingHeader extends StatelessWidget {
  final String title;
  final bool collapsed;
  final List<Widget> actions;
  final double largeSize;
  const CollapsingHeader({
    super.key,
    required this.title,
    required this.collapsed,
    this.actions = const [],
    this.largeSize = 28,
  });

  @override
  Widget build(BuildContext context) {
    final tk = context.tk;
    final instant = reduceMotion(context);
    final d = instant ? Duration.zero : Mo.standard;
    return AnimatedContainer(
      duration: d,
      curve: Mo.curve,
      height: collapsed ? 56 : 64,
      padding: const EdgeInsets.fromLTRB(20, 0, 16, 0),
      decoration: BoxDecoration(
        color: tk.bg,
        border: Border(
            bottom: BorderSide(
                color: collapsed ? tk.hair : tk.hair.withValues(alpha: 0))),
      ),
      child: Row(children: [
        Expanded(
          child: AnimatedDefaultTextStyle(
            duration: d,
            curve: Mo.curve,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: kFontFamily,
              fontSize: collapsed ? 18 : largeSize,
              height: collapsed ? 24 / 18 : 34 / 28,
              fontWeight: collapsed ? FontWeight.w600 : FontWeight.w700,
              letterSpacing: collapsed ? 0 : -0.6,
              color: tk.t1,
            ),
            child: Text(title),
          ),
        ),
        // Privacy mode: an eye-off badge says amounts are hidden.
        if (kAmountsHidden) ...[
          Container(
            height: 28,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
                color: tk.press, borderRadius: BorderRadius.circular(14)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Ph.eyeSlash, size: 14, color: tk.t2),
              const SizedBox(width: 4),
              Text('Hidden',
                  style: TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w700, color: tk.t2)),
            ]),
          ),
          const SizedBox(width: 8),
        ],
        ...actions,
      ]),
    );
  }
}

// ── Pull to refresh: the design's "Syncing…" pill ────────────────────────────

/// Pull-to-refresh with the design's pill instead of the round spinner:
/// "Pull to sync" while dragging, "Release to sync" when armed, then a loader
/// with [label] ("Syncing 3 accounts") until [onRefresh] finishes.
class SyncRefresh extends StatefulWidget {
  final Future<void> Function() onRefresh;
  final String label;
  final Widget child;

  /// How far below the top the pill floats (clears a pinned bar).
  final double top;
  const SyncRefresh({
    super.key,
    required this.onRefresh,
    required this.child,
    this.label = 'Syncing',
    this.top = 8,
  });

  @override
  State<SyncRefresh> createState() => _SyncRefreshState();
}

class _SyncRefreshState extends State<SyncRefresh> {
  RefreshIndicatorStatus? _status;

  @override
  Widget build(BuildContext context) {
    final tk = context.tk;
    final s = _status;
    final visible = s == RefreshIndicatorStatus.drag ||
        s == RefreshIndicatorStatus.armed ||
        s == RefreshIndicatorStatus.snap ||
        s == RefreshIndicatorStatus.refresh;
    final busy =
        s == RefreshIndicatorStatus.snap || s == RefreshIndicatorStatus.refresh;
    final text = busy
        ? widget.label
        : s == RefreshIndicatorStatus.armed
            ? 'Release to sync'
            : 'Pull to sync';
    return Stack(children: [
      RefreshIndicator.noSpinner(
        onRefresh: widget.onRefresh,
        onStatusChange: (st) {
          if (mounted && st != _status) setState(() => _status = st);
        },
        child: widget.child,
      ),
      Positioned(
        top: widget.top,
        left: 0,
        right: 0,
        child: IgnorePointer(
          child: Center(
            child: AnimatedOpacity(
              opacity: visible ? 1 : 0,
              duration: Mo.standard,
              child: AnimatedSlide(
                offset: visible ? Offset.zero : const Offset(0, -0.4),
                duration: Mo.standard,
                curve: Mo.curve,
                child: Container(
                  height: 36,
                  padding: const EdgeInsets.fromLTRB(10, 0, 14, 0),
                  decoration: BoxDecoration(
                    color: tk.raised,
                    borderRadius: BorderRadius.circular(18),
                    border: tk.isDark ? Border.all(color: tk.hair) : null,
                    boxShadow: tk.shadowRaised,
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    if (busy)
                      const RisingLoader(width: 20)
                    else
                      Icon(Ph.arrowDown, size: 16, color: tk.acc),
                    const SizedBox(width: 8),
                    Text(text,
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: tk.t1)),
                  ]),
                ),
              ),
            ),
          ),
        ),
      ),
    ]);
  }
}
