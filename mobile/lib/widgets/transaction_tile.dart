import 'package:flutter/material.dart';

import '../core/routes.dart';
import '../core/theme.dart';
import '../models/category.dart';
import '../models/transaction.dart';
import '../services/merchant_directory.dart';
import '../services/sync_outbox.dart';
import '../utils/formatters.dart';
import 'ds.dart';
import 'income_text.dart';

/// One transaction row: category plate · merchant + details · amount.
///
/// Spend reads in plain ink ("−₹486"), money in reads green ("+₹1,200").
/// Auto-imported rows that still need a look carry a small "Review" tag.
class TransactionTile extends StatelessWidget {
  final Transaction txn;
  final VoidCallback? onTap;

  /// Show the date in the details line. Lists already grouped under a date
  /// header pass false and get just the time.
  final bool showDate;

  const TransactionTile(
      {super.key, required this.txn, this.onTap, this.showDate = true});

  @override
  Widget build(BuildContext context) {
    final cat = Categories.byId(txn.categoryId);
    final tk = context.tk;
    final isSalary = txn.isCredit && txn.categoryId == 'salary';
    final app = MerchantDirectory.appFor(txn.upiVpa);
    // Sub-line order is always Category · Time · Source. A payback, loan or
    // own-account transfer names itself instead of a category. Plain text —
    // never struck through.
    final kind = txn.linkKind ?? cat.label;
    final details = [
      kind,
      showDate
          ? relativeDate(txn.timestamp)
          : TimeOfDay.fromDateTime(txn.timestamp).format(context),
      if (app != null) app,
      if (app == null && txn.account != null) '••${txn.account}',
    ].join(' · ');
    final tile = txn.isSettlement || txn.selfTransfer
        ? CatTile(
            color: tk.acc,
            icon: txn.isSettlement ? Ph.handCoins : Ph.arrowsLeftRight)
        : CatTile.of(cat);

    return Semantics(
      button: true,
      label: '${txn.merchant ?? cat.label}, $kind, '
          '${txn.isCredit ? 'received' : 'spent'} '
          '${kAmountsHidden || (isSalary && kIncomeMasked) ? 'amount hidden' : formatRupees(txn.amount)}, '
          '${relativeDate(txn.timestamp)}'
          '${txn.reviewed ? '' : ', needs review'}',
      excludeSemantics: true,
      child: DsRow(
        leading: tile,
        title: txn.merchant ?? cat.label,
        // Saved on this phone, not yet synced: the design's cloud-off mark.
        titleTrailing: ListenableBuilder(
          listenable: SyncOutbox.instance,
          builder: (_, __) => SyncOutbox.instance.pendingIds.contains(txn.id)
              ? Tooltip(
                  message: 'Not synced yet',
                  child: Icon(Ph.cloudSlash, size: 14, color: tk.warn))
              : const SizedBox.shrink(),
        ),
        sub: details,
        // One even line per row; large text sizes may wrap to two.
        subMaxLines: MediaQuery.textScalerOf(context).scale(1) > 1.15 ? 2 : 1,
        onTap: onTap ??
            () {
              // Tablet list–detail: open in the side pane instead.
              final open = TxnOpener.maybeOf(context);
              open != null
                  ? open(txn)
                  : Navigator.pushNamed(context, AppRoutes.txnDetail,
                      arguments: txn);
            },
        trailing: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Salary stays hidden behind the fingerprint while the lock is on.
            if (isSalary)
              IncomeText(txn.amount, credit: true, color: tk.ok)
            else
              MoneyText(
                txn.amount,
                credit: txn.isCredit,
                color: txn.isCredit ? tk.ok : tk.t1,
              ),
            if (!txn.reviewed) ...[
              const SizedBox(height: 3),
              const StatusPill('Review', tone: Tone.accent, small: true),
            ],
          ],
        ),
      ),
    );
  }
}

/// Provided by a list–detail layout (tablets): rows open the transaction in
/// the side pane instead of pushing the detail screen.
class TxnOpener extends InheritedWidget {
  final ValueChanged<Transaction> open;
  const TxnOpener({super.key, required this.open, required super.child});

  static ValueChanged<Transaction>? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<TxnOpener>()?.open;

  @override
  bool updateShouldNotify(TxnOpener old) => old.open != open;
}
