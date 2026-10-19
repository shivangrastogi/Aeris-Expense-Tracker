import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../providers/accounts_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/prefs_data_provider.dart';
import '../../providers/transactions_provider.dart';
import '../../utils/formatters.dart';
import '../transactions/transactions_screen.dart';
import '../../utils/amount_input_formatter.dart';
import '../../widgets/text_input_dialog.dart';

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
                  'Balances come from your bank SMS. For an account whose SMS '
                  'show no balance, set an opening balance instead. Tap an '
                  'account to see its activity.',
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
        text: account.openingBalance == null
            ? ''
            : '${account.openingBalance! < 0 ? '-' : ''}'
                '${inrToDisplayText(account.openingBalance!.abs())}');
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
              decoration: InputDecoration(
                  labelText: 'Opening balance',
                  prefixText: '${kCurrency.symbol.trim()} ',
                  prefixIcon: const Icon(Icons.account_balance_wallet_outlined)),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () =>
                Navigator.pop(ctx, _signedInr(ctrl.text)),
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

  Future<void> _rename(BuildContext context, WidgetRef ref) async {
    final uid = ref.read(currentUserIdProvider);
    final name = await promptText(context,
        title: 'Name ${accountLabel(account.key)}',
        initial: account.nickname,
        hint: 'e.g. HDFC salary, SBI savings',
        helper: 'Leave empty to remove the name.',
        capitalization: TextCapitalization.words);
    if (name == null || uid == null) return;
    final names = ref.read(accountNamesProvider).valueOrNull ?? const {};
    await ref
        .read(firestoreServiceProvider)
        .setAccountName(uid, account.key, name, names);
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
                    backgroundColor: AerisColors.accent(context).withValues(alpha: 0.15),
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
                          '${account.nickname != null ? '${accountLabel(account.key)} · ' : ''}'
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
                  if (account.key != unassignedAccount)
                    PopupMenuButton<String>(
                      tooltip: 'Account options',
                      icon: const Icon(Icons.more_vert_rounded, size: 20),
                      onSelected: (v) => v == 'rename'
                          ? _rename(context, ref)
                          : _setOpeningBalance(context, ref),
                      itemBuilder: (_) => [
                        PopupMenuItem(
                            value: 'rename',
                            child: Text(account.nickname == null
                                ? 'Name this account'
                                : 'Rename')),
                        const PopupMenuItem(
                            value: 'opening', child: Text('Opening balance')),
                      ],
                    ),
                ],
              ),
              const SizedBox(height: 12),
              // Live balance: as the bank last reported it, else opening +
              // tracked activity.
              if (bal != null) ...[
                Text(
                    account.bankBalance != null
                        ? 'Balance · per bank SMS, ${asOfLabel(account.bankBalanceAt!)}'
                        : 'Current balance',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant)),
                Text(formatRupees(bal),
                    style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                        color: bal >= 0 ? AerisColors.moneyIn(context) : AerisColors.danger(context))),
                const SizedBox(height: 10),
              ] else if (account.key != unassignedAccount)
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
                  _metric(context, 'Spent', account.spent, AerisColors.moneyOut(context)),
                  _metric(
                      context, 'Received', account.received, AerisColors.moneyIn(context)),
                  _metric(context, 'Net', net,
                      net >= 0 ? AerisColors.moneyIn(context) : AerisColors.danger(context)),
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

/// Opening balance typed in the display currency (may be negative, e.g. an
/// overdrawn account) → INR. Empty or invalid input counts as 0.
double _signedInr(String text) {
  final t = text.trim();
  final neg = t.startsWith('-') || t.startsWith('−');
  final v = displayToInr(neg ? t.substring(1) : t) ?? 0;
  return neg ? -v : v;
}
