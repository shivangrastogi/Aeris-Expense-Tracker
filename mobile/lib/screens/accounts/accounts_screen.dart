import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/routes.dart';
import '../../core/theme.dart';
import '../../providers/accounts_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/prefs_data_provider.dart';
import '../../providers/transactions_provider.dart';
import '../../utils/formatters.dart';
import 'account_detail_screen.dart';
import '../../utils/amount_input_formatter.dart';
import '../../widgets/text_input_dialog.dart';
import '../../widgets/ds.dart';

class AccountsScreen extends ConsumerWidget {
  const AccountsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tk = context.tk;
    final accounts = ref.watch(accountsProvider);
    final cash = accounts
        .where((a) => a.balance != null)
        .fold<double>(0, (s, a) => s + a.balance!);
    final anyBalance = accounts.any((a) => a.balance != null);
    return Scaffold(
      appBar: AppBar(title: const Text('Accounts')),
      body: accounts.isEmpty
          ? const Center(
              child: EmptyState(
                icon: Ph.bank,
                title: 'No accounts yet',
                body: 'Once AERIS reads bank SMS or you import a statement, '
                    'your accounts appear here.',
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
              children: [
                Row(children: [
                  Icon(Ph.chatText, size: 15, color: tk.t2),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text('Balances come from your bank SMS',
                        style: Ts.bodyS.copyWith(color: tk.t2)),
                  ),
                ]),
                const SizedBox(height: 12),
                if (anyBalance) ...[
                  Material(
                    color: tk.accSoft,
                    borderRadius: BorderRadius.circular(Rad.button),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(Rad.button),
                      onTap: () =>
                          Navigator.pushNamed(context, AppRoutes.netWorth),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                        child: Row(children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Cash in accounts',
                                    style: Ts.bodyS.copyWith(color: tk.t2)),
                                MoneyText(cash,
                                    smallDecimals: true,
                                    smallSymbol: false,
                                    style: Ts.amountM
                                        .copyWith(fontWeight: FontWeight.w700)),
                              ],
                            ),
                          ),
                          Text('Net worth',
                              style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: tk.acc)),
                          const SizedBox(width: 4),
                          Icon(Ph.arrowRight, size: 16, color: tk.acc),
                        ]),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                for (final a in accounts) ...[
                  _AccountCard(account: a),
                  const SizedBox(height: 16),
                ],
                Text(
                  'For an account whose SMS show no balance, set an opening '
                  'balance from its menu. Tap an account to see its activity.',
                  style: Ts.label
                      .copyWith(fontWeight: FontWeight.w400, color: tk.t3),
                ),
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
                  prefixIcon: const Icon(Ph.wallet)),
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

  /// "HDFC salary" → "HD"; "A/C ••1234" → "AC"; "SBI ••8208" → "SBI".
  static String _badge(String label) {
    final w = label.trim().split(RegExp(r'\s+')).first.toUpperCase();
    final letters = w.replaceAll(RegExp(r'[^A-Z]'), '');
    if (letters.isEmpty) return '••';
    return letters.length <= 3 ? letters : letters.substring(0, 2);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tk = context.tk;
    final net = account.net;
    final bal = account.balance;
    final sub = [
      if (account.nickname != null) accountLabel(account.key),
      '${account.count} txns',
      if (account.lastTxn != null) relativeDate(account.lastTxn!),
    ].join(' · ');
    return AerisCard(
      padding: const EdgeInsets.fromLTRB(16, 16, 8, 16),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => AccountDetailScreen(accountKey: account.key),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              BadgeTile(text: _badge(account.label)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(account.label,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style:
                            Ts.rowTitle.copyWith(fontSize: 17, color: tk.t1)),
                    Text(sub,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Ts.label.copyWith(
                            fontWeight: FontWeight.w400, color: tk.t2)),
                  ],
                ),
              ),
              if (account.key != unassignedAccount)
                PopupMenuButton<String>(
                  tooltip: 'Account options',
                  icon: Icon(Ph.dotsThreeVertical, size: 20, color: tk.t2),
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
                )
              else
                const SizedBox(width: 8),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 12),
                // Live balance: as the bank last reported it, else opening +
                // tracked activity.
                if (bal != null) ...[
                  MoneyText(bal,
                      smallDecimals: true,
                      credit: bal < 0 ? false : null,
                      color: bal < 0 ? tk.bad : tk.t1,
                      style: const TextStyle(
                          fontSize: 36,
                          height: 40 / 36,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -1)),
                  const SizedBox(height: 4),
                  Row(children: [
                    Icon(Ph.chatText, size: 13, color: tk.t2),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                          account.bankBalance != null
                              ? 'per bank SMS, ${asOfLabel(account.bankBalanceAt!)}'
                              : 'from your opening balance + tracked activity',
                          style: Ts.label.copyWith(
                              fontWeight: FontWeight.w400, color: tk.t2)),
                    ),
                  ]),
                ] else if (account.key != unassignedAccount)
                  TextButton.icon(
                    onPressed: () => _setOpeningBalance(context, ref),
                    icon: const Icon(Ph.plus, size: 16),
                    label: const Text('Set opening balance for live balance'),
                    style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(0, 40),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                  ),
                const SizedBox(height: 12),
                Container(height: 1, color: tk.hair),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _metric(context, 'Spent', account.spent, tk.t1),
                    _metric(context, 'Received', account.received, tk.ok),
                    _metric(context, 'Net', net, net >= 0 ? tk.ok : tk.t1,
                        signed: true),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _metric(BuildContext context, String label, double v, Color c,
      {bool signed = false}) {
    final tk = context.tk;
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style:
                  Ts.label.copyWith(fontWeight: FontWeight.w400, color: tk.t2)),
          const SizedBox(height: 2),
          MoneyText(v,
              compact: true,
              credit: signed ? v >= 0 : null,
              color: c,
              style:
                  const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
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
