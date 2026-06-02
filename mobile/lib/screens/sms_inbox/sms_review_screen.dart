import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/routes.dart';
import '../../models/category.dart';
import '../../models/transaction.dart';
import '../../providers/auth_provider.dart';
import '../../providers/transactions_provider.dart';
import '../../utils/formatters.dart';

class SmsReviewScreen extends ConsumerWidget {
  const SmsReviewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final txns = ref.watch(transactionsStreamProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Review SMS imports')),
      body: txns.when(
        loading: () => const _ReviewSkeleton(),
        error: (e, _) => Center(child: Text('$e')),
        data: (list) {
          final pending = list
              .where((t) => t.source == TxnSource.sms && !t.reviewed)
              .toList();
          if (pending.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(28),
                child: Text(
                  'Nothing waiting for review. Auto-imported SMS transactions '
                  'land here so you can correct a category or merchant before '
                  'they\'re finalised.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return ListView.builder(
            itemCount: pending.length,
            itemBuilder: (ctx, i) {
              final t = pending[i];
              final cat = Categories.byId(t.categoryId);
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Icon(cat.icon, color: cat.color),
                        const SizedBox(width: 8),
                        Expanded(child: Text(
                          t.merchant ?? cat.label,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        )),
                        Text('${t.isCredit ? "+" : "−"} ${formatRupees(t.amount)}',
                            style: const TextStyle(fontWeight: FontWeight.w700)),
                      ]),
                      const SizedBox(height: 6),
                      Text(t.smsBody ?? '',
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11)),
                      if (t.smsSender != null) ...[
                        const SizedBox(height: 4),
                        Text('from ${t.smsSender}',
                            style: TextStyle(
                                fontSize: 11,
                                color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
                      ],
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 4,
                        children: [
                          TextButton.icon(
                            onPressed: () => Navigator.pushNamed(
                                ctx, AppRoutes.txnDetail, arguments: t),
                            icon: const Icon(Icons.edit, size: 18),
                            label: const Text('Edit'),
                          ),
                          TextButton.icon(
                            onPressed: () async {
                              final uid = ref.read(currentUserIdProvider);
                              if (uid == null) return;
                              await ref.read(firestoreServiceProvider)
                                  .updateTransaction(uid, t.copyWith(reviewed: true));
                            },
                            icon: const Icon(Icons.check, size: 18),
                            label: const Text('Looks good'),
                          ),
                          TextButton.icon(
                            onPressed: () async {
                              final uid = ref.read(currentUserIdProvider);
                              if (uid == null) return;
                              await ref.read(firestoreServiceProvider)
                                  .deleteTransaction(uid, t.id);
                            },
                            icon: const Icon(Icons.delete_outline,
                                size: 18, color: Colors.red),
                            label: const Text('Delete',
                                style: TextStyle(color: Colors.red)),
                          ),
                          if (t.smsSender != null)
                            TextButton.icon(
                              onPressed: () =>
                                  _blockSender(ctx, ref, t),
                              icon: const Icon(Icons.block,
                                  size: 18, color: Colors.orange),
                              label: const Text('Block sender',
                                  style: TextStyle(color: Colors.orange)),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _blockSender(
      BuildContext context, WidgetRef ref, Transaction t) async {
    final sender = t.smsSender;
    if (sender == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Block this sender?'),
        content: Text(
            'Messages from "$sender" will no longer be imported as transactions. '
            'This entry will be removed too. You can undo this later in Settings.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(d, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(d, true),
              child: const Text('Block')),
        ],
      ),
    );
    if (confirm != true) return;
    final uid = ref.read(currentUserIdProvider);
    if (uid == null) return;
    final fs = ref.read(firestoreServiceProvider);
    final messenger = ScaffoldMessenger.of(context);
    await fs.blockSender(uid, sender);
    await fs.deleteTransaction(uid, t.id);
    messenger.showSnackBar(
        SnackBar(content: Text('Blocked $sender — future messages ignored.')));
  }
}

class _ReviewSkeleton extends StatelessWidget {
  const _ReviewSkeleton();
  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.4);
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        for (var i = 0; i < 6; i++)
          Container(
            height: 96,
            margin: const EdgeInsets.symmetric(vertical: 6),
            decoration: BoxDecoration(
                color: base, borderRadius: BorderRadius.circular(14)),
          )
              .animate(onPlay: (c) => c.repeat())
              .shimmer(
                  duration: 1200.ms,
                  color: Theme.of(context).colorScheme.surface.withOpacity(0.5)),
      ],
    );
  }
}
