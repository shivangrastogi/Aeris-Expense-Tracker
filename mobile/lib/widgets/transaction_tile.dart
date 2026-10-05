import 'package:flutter/material.dart';

import '../core/routes.dart';
import '../core/theme.dart';
import '../models/category.dart';
import '../models/transaction.dart';
import '../services/merchant_directory.dart';
import '../utils/formatters.dart';

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
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final muted = AerisColors.muted(context);
    final amountColor = txn.isCredit
        ? AerisColors.moneyIn(context)
        : AerisColors.moneyOut(context);
    final app = MerchantDirectory.appFor(txn.upiVpa);
    final details = [
      cat.label.split(RegExp(r' [&/] ')).first,
      showDate
          ? relativeDate(txn.timestamp)
          : TimeOfDay.fromDateTime(txn.timestamp).format(context),
      if (app != null) app,
      if (txn.account != null) '••${txn.account}',
    ].join(' · ');
    final amount = '${txn.isCredit ? '+' : '−'}${formatRupees(txn.amount)}';

    return Semantics(
      button: true,
      label: '${txn.merchant ?? cat.label}, '
          '${txn.isCredit ? 'received' : 'spent'} ${formatRupees(txn.amount)}, '
          '${relativeDate(txn.timestamp)}'
          '${txn.reviewed ? '' : ', needs review'}',
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap ??
            () => Navigator.pushNamed(context, AppRoutes.txnDetail,
                arguments: txn),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: cat.color.withValues(alpha: dark ? 0.20 : 0.13),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(cat.icon, color: cat.color, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      txn.merchant ?? cat.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      details,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                          color: muted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    amount,
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: amountColor),
                  ),
                  if (!txn.reviewed) ...[
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: AerisColors.warning
                            .withValues(alpha: dark ? 0.22 : 0.12),
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: const Text('Review',
                          style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              color: AerisColors.warning)),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
