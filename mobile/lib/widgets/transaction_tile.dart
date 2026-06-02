import 'package:flutter/material.dart';

import '../core/routes.dart';
import '../core/theme.dart';
import '../models/category.dart';
import '../models/transaction.dart';
import '../utils/formatters.dart';

class TransactionTile extends StatelessWidget {
  final Transaction txn;
  final VoidCallback? onTap;

  const TransactionTile({super.key, required this.txn, this.onTap});

  @override
  Widget build(BuildContext context) {
    final cat = Categories.byId(txn.categoryId);
    final theme = Theme.of(context);
    final color = txn.isCredit ? AerisColors.credit : AerisColors.debit;

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap ??
          () => Navigator.pushNamed(context, AppRoutes.txnDetail, arguments: txn),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: cat.color.withOpacity(0.18),
                borderRadius: BorderRadius.circular(12),
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
                    style:
                        theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${cat.label}  •  ${relativeDate(txn.timestamp)}'
                    '${txn.account != null ? "  •  ••${txn.account}" : ""}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Amount on top, then review/edit affordances below.
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${txn.isCredit ? "+" : "−"} ${formatRupees(txn.amount)}',
                  style: theme.textTheme.bodyLarge
                      ?.copyWith(fontWeight: FontWeight.w700, color: color),
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!txn.reviewed) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AerisColors.warning.withOpacity(0.18),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text('REVIEW',
                            style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                color: AerisColors.warning)),
                      ),
                      const SizedBox(width: 6),
                    ],
                    Icon(Icons.edit_outlined,
                        size: 14, color: theme.colorScheme.onSurfaceVariant),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
