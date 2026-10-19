import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/transaction.dart';
import 'auth_provider.dart';
import 'prefs_data_provider.dart';
import 'transactions_provider.dart';

/// Aggregated per-account view, derived from the `account` tag on each
/// transaction (set by the SMS parser from "A/c XX1234"). Transactions with no
/// account (manual / statement imports) are grouped under "Unassigned".
class AccountSummary {
  final String key; // the raw account fragment, or 'unassigned'
  final String label; // the nickname, else e.g. 'A/C ••1234'
  final String? nickname; // user-given name ("HDFC salary"), if any
  final double spent; // sum of debits
  final double received; // sum of credits
  final int count;
  final DateTime? lastTxn;
  final double? openingBalance; // null until the user sets it

  /// The balance the bank itself last printed in an SMS ("Avl Bal"), moved
  /// on by any later transactions on this account that didn't print one.
  final double? bankBalance;

  /// When the bank last printed a balance for this account.
  final DateTime? bankBalanceAt;

  const AccountSummary({
    required this.key,
    required this.label,
    this.nickname,
    required this.spent,
    required this.received,
    required this.count,
    required this.lastTxn,
    this.openingBalance,
    this.bankBalance,
    this.bankBalanceAt,
  });

  double get net => received - spent;

  /// Best known current balance: what the bank reported, else opening + net
  /// (null when neither is known).
  double? get balance =>
      bankBalance ??
      (openingBalance == null ? null : openingBalance! + net);
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
  final names = ref.watch(accountNamesProvider).valueOrNull ?? const {};
  return summarizeAccounts(txns, opening, names: names);
});

/// Pure core of [accountsProvider] (testable).
List<AccountSummary> summarizeAccounts(
    List<Transaction> txns, Map<String, double> opening,
    {Map<String, String> names = const {}}) {
  final spent = <String, double>{};
  final received = <String, double>{};
  final count = <String, int>{};
  final last = <String, DateTime>{};
  final byAccount = <String, List<Transaction>>{};

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
    (byAccount[k] ??= []).add(t);
  }

  final keys = count.keys.toList()
    ..sort((a, b) {
      if (a == unassignedAccount) return 1;
      if (b == unassignedAccount) return -1;
      return (count[b] ?? 0).compareTo(count[a] ?? 0);
    });

  return [
    for (final k in keys)
      () {
        final bank =
            k == unassignedAccount ? null : bankBalanceOf(byAccount[k]!);
        return AccountSummary(
          key: k,
          label: names[k] ?? accountLabel(k),
          nickname: names[k],
          spent: spent[k] ?? 0,
          received: received[k] ?? 0,
          count: count[k] ?? 0,
          lastTxn: last[k],
          openingBalance: opening[k],
          bankBalance: bank?.value,
          bankBalanceAt: bank?.at,
        );
      }(),
  ];
}

/// The latest balance a bank SMS printed for one account's [txns], plus the
/// effect of the transactions after it that printed none (e.g. a payment
/// picked up from a UPI app notification).
({double value, DateTime at})? bankBalanceOf(List<Transaction> txns) {
  Transaction? anchor;
  for (final t in txns) {
    if (t.balance == null) continue;
    if (anchor == null || t.timestamp.isAfter(anchor.timestamp)) anchor = t;
  }
  if (anchor == null) return null;
  var value = anchor.balance!;
  for (final t in txns) {
    if (t.balance == null && t.timestamp.isAfter(anchor.timestamp)) {
      value += t.signed;
    }
  }
  return (value: value, at: anchor.timestamp);
}
