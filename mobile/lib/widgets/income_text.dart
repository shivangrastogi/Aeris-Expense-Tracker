import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme.dart';
import '../providers/income_lock_provider.dart';
import '../utils/formatters.dart';
import 'ds.dart';

/// An income amount (salary, monthly income). While the salary lock is on it
/// reads "₹••••" with a small lock; tapping it asks for the fingerprint and
/// then shows the real figure until the app leaves the screen.
class IncomeText extends ConsumerWidget {
  final num amount;
  final TextStyle style;
  final Color? color;
  final bool? credit;
  final bool compact;
  final bool smallDecimals;
  const IncomeText(
    this.amount, {
    super.key,
    this.style = Ts.rowTitle,
    this.color,
    this.credit,
    this.compact = false,
    this.smallDecimals = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lock = ref.watch(incomeLockProvider);
    if (!lock.masked) {
      return MoneyText(amount,
          style: style,
          color: color,
          credit: credit,
          compact: compact,
          smallDecimals: smallDecimals);
    }
    return IncomeLockBadge(
      size: (style.fontSize ?? 15) * 0.8,
      child: Text(
        '${credit == null ? '' : (credit! ? '+' : kMinus)}'
        '${kCurrency.symbol}••••',
        maxLines: 1,
        style: style.copyWith(color: color ?? style.color ?? context.tk.t1),
      ),
    );
  }
}

/// Wraps masked income: adds the lock glyph and makes it tap-to-unlock.
class IncomeLockBadge extends ConsumerWidget {
  final Widget child;
  final double size;
  const IncomeLockBadge({super.key, required this.child, this.size = 12});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tk = context.tk;
    return Semantics(
      button: true,
      label: 'Income hidden. Double tap to unlock with your fingerprint.',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => unlockIncome(context, ref),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(PhFill.lockSimple, size: size, color: tk.t2),
          const SizedBox(width: 4),
          child,
        ]),
      ),
    );
  }
}

/// Fingerprint → show income. Says so if it didn't work.
Future<bool> unlockIncome(BuildContext context, WidgetRef ref) async {
  HapticFeedback.selectionClick();
  final messenger = ScaffoldMessenger.maybeOf(context);
  final ok = await ref.read(incomeLockProvider.notifier).reveal();
  if (!ok) {
    messenger?.showSnackBar(const SnackBar(
        content: Text('Couldn\'t verify it\'s you — income stays hidden.')));
  }
  return ok;
}
