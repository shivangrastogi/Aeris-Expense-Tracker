import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../providers/accounts_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/transactions_provider.dart';
import '../../utils/formatters.dart';
import '../transactions/transactions_screen.dart';

class AccountsScreen extends ConsumerWidget {
  const AccountsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accounts = ref.watch(accountsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Accounts')),
      body: accounts.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(28),
                child: Text(
                  'No accounts yet. Once AERIS reads bank SMS or you import a '
                  'statement, your accounts appear here.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 24),
              children: [
                Text(
                  'Set an opening balance to see a true running balance. '
                  'Tap an account to see its activity.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 10),
                for (final a in accounts) _AccountCard(account: a),
              ],
            ),
    );
  }
}

class _AccountCard extends ConsumerWidget {
  final AccountSummary account;
  const _AccountCard({required this.account});

  Future<void> _setOpeningBalance(BuildContext context, WidgetRef ref) async {
    final uid = ref.read(currentUserIdProvider);
    if (uid == null) return;
    final ctrl = TextEditingController(
        text: account.openingBalance != null
            ? account.openingBalance!.toStringAsFixed(0)
            : '');
    final result = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Opening balance · ${account.label}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
                'Your account balance before AERIS started tracking. We add '
                'your tracked income/spend on top to show the live balance.',
                style: TextStyle(fontSize: 12)),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                  decimal: true, signed: true),
              decoration: const InputDecoration(
                  labelText: 'Opening balance (₹)',
                  prefixIcon: Icon(Icons.currency_rupee)),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () =>
                Navigator.pop(ctx, double.tryParse(ctrl.text) ?? 0),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (result != null) {
      await ref
          .read(firestoreServiceProvider)
          .setOpeningBalance(uid, account.key, result);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final net = account.net;
    final bal = account.balance;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => TransactionsScreen(initialAccount: account.key),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: AerisColors.seed.withValues(alpha: 0.15),
                    child: const Icon(Icons.account_balance, size: 18),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(account.label,
                            style: const TextStyle(
                                fontWeight: FontWeight.w800, fontSize: 16)),
                        Text(
                          '${account.count} txns'
                          '${account.lastTxn != null ? ' · last ${relativeDate(account.lastTxn!)}' : ''}',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Set opening balance',
                    icon: const Icon(Icons.tune, size: 20),
                    onPressed: () => _setOpeningBalance(context, ref),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Live balance (only when an opening balance is set).
              if (bal != null) ...[
                Text('Current balance',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant)),
                Text(formatRupees(bal),
                    style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                        color: bal >= 0 ? AerisColors.credit : AerisColors.debit)),
                const SizedBox(height: 10),
              ] else
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: TextButton.icon(
                    onPressed: () => _setOpeningBalance(context, ref),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Set opening balance for live balance'),
                    style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(0, 0),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                  ),
                ),
              Row(
                children: [
                  _metric(context, 'Spent', account.spent, AerisColors.debit),
                  _metric(
                      context, 'Received', account.received, AerisColors.credit),
                  _metric(context, 'Net', net,
                      net >= 0 ? AerisColors.credit : AerisColors.debit),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _metric(BuildContext context, String label, double v, Color c) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant)),
          const SizedBox(height: 2),
          Text(formatRupees(v, compact: true),
              style: TextStyle(
                  fontWeight: FontWeight.w800, fontSize: 15, color: c)),
        ],
      ),
    );
  }
}
