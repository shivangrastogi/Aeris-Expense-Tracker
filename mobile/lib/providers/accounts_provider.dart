import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_provider.dart';
import 'transactions_provider.dart';

/// Aggregated per-account view, derived from the `account` tag on each
/// transaction (set by the SMS parser from "A/c XX1234"). Transactions with no
/// account (manual / statement imports) are grouped under "Unassigned".
class AccountSummary {
  final String key; // the raw account fragment, or 'unassigned'
  final String label; // display label, e.g. 'A/C ••1234'
  final double spent; // sum of debits
  final double received; // sum of credits
  final int count;
  final DateTime? lastTxn;
  final double? openingBalance; // null until the user sets it

  const AccountSummary({
    required this.key,
    required this.label,
    required this.spent,
    required this.received,
    required this.count,
    required this.lastTxn,
    this.openingBalance,
  });

  double get net => received - spent;

  /// True running balance = opening + net. Null until an opening balance is set.
  double? get balance =>
      openingBalance == null ? null : openingBalance! + net;
}

const unassignedAccount = 'unassigned';

String accountLabel(String key) =>
    key == unassignedAccount ? 'Unassigned' : 'A/C ••$key';

/// Encrypted per-account opening balances, streamed from Firestore.
final openingBalancesProvider = StreamProvider<Map<String, double>>((ref) {
  final uid = ref.watch(currentUserIdProvider);
  if (uid == null) return Stream.value(const <String, double>{});
  return ref.read(firestoreServiceProvider).watchOpeningBalances(uid);
});

/// All accounts the user has activity on, sorted by transaction count (busiest
/// first), with the "Unassigned" bucket always last.
final accountsProvider = Provider<List<AccountSummary>>((ref) {
  final txns = ref.watch(transactionsStreamProvider).valueOrNull ?? const [];
  final opening = ref.watch(openingBalancesProvider).valueOrNull ?? const {};
  final spent = <String, double>{};
  final received = <String, double>{};
  final count = <String, int>{};
  final last = <String, DateTime>{};

  for (final t in txns) {
    final k = (t.account == null || t.account!.trim().isEmpty)
        ? unassignedAccount
        : t.account!.trim();
    if (t.isCredit) {
      received[k] = (received[k] ?? 0) + t.amount;
    } else {
      spent[k] = (spent[k] ?? 0) + t.amount;
    }
    count[k] = (count[k] ?? 0) + 1;
    final prev = last[k];
    if (prev == null || t.timestamp.isAfter(prev)) last[k] = t.timestamp;
  }

  final keys = count.keys.toList()
    ..sort((a, b) {
      if (a == unassignedAccount) return 1;
      if (b == unassignedAccount) return -1;
      return (count[b] ?? 0).compareTo(count[a] ?? 0);
    });

  return [
    for (final k in keys)
      AccountSummary(
        key: k,
        label: accountLabel(k),
        spent: spent[k] ?? 0,
        received: received[k] ?? 0,
        count: count[k] ?? 0,
        lastTxn: last[k],
        openingBalance: opening[k],
      ),
  ];
});
