import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/budget.dart';
import '../services/money_insights.dart';
import '../services/reminder_scheduler.dart';
import 'accounts_provider.dart';
import 'auth_provider.dart';
import 'budgets_provider.dart';
import 'goals_provider.dart';
import 'insights_provider.dart';
import 'loans_provider.dart';
import 'subscriptions_provider.dart';
import 'transactions_provider.dart';

// ── Budget rollover ───────────────────────────────────────────
/// Whether last month's unspent budget carries into this month (prefs).
final rolloverProvider =
    StateNotifierProvider<_PrefBool, bool>((_) => _PrefBool('budget_rollover'));

class _PrefBool extends StateNotifier<bool> {
  final String key;
  _PrefBool(this.key) : super(false) {
    SharedPreferences.getInstance().then((p) {
      if (mounted) state = p.getBool(key) ?? false;
    });
  }

  Future<void> set(bool v) async {
    state = v;
    (await SharedPreferences.getInstance()).setBool(key, v);
  }
}

/// Budgets as they apply THIS month: the stored caps, plus last month's
/// leftover when rollover is on. Use this wherever budgets are *shown*; edit
/// screens keep using [budgetsStreamProvider] (the stored caps).
final effectiveBudgetsProvider = Provider<List<Budget>>((ref) {
  final budgets = ref.watch(budgetsStreamProvider).valueOrNull ?? const [];
  if (!ref.watch(rolloverProvider)) return budgets;
  final txns = ref.watch(transactionsStreamProvider).valueOrNull ?? const [];
  return BudgetRollover.apply(budgets, txns, DateTime.now());
});

/// Per-budget amount rolled in this month (categoryId → ₹), for labels.
final rolledOverProvider = Provider<Map<String, double>>((ref) {
  if (!ref.watch(rolloverProvider)) return const {};
  final budgets = ref.watch(budgetsStreamProvider).valueOrNull ?? const [];
  final txns = ref.watch(transactionsStreamProvider).valueOrNull ?? const [];
  final left = BudgetRollover.leftovers(budgets, txns, DateTime.now());
  return {
    for (final b in budgets)
      if ((left[b.categoryId] ?? 0) > 0)
        b.categoryId: (left[b.categoryId]!).clamp(0, b.monthlyCap).toDouble(),
  };
});

// ── Safe-to-spend, recap, report card ─────────────────────────
final safeSpendProvider = Provider<SafeSpend?>((ref) {
  final txns = ref.watch(transactionsStreamProvider).valueOrNull ?? const [];
  return SafeSpend.compute(
      txns, ref.watch(effectiveBudgetsProvider), DateTime.now());
});

final weeklyRecapProvider = Provider<WeeklyRecap?>((ref) {
  final txns = ref.watch(transactionsStreamProvider).valueOrNull ?? const [];
  return WeeklyRecap.build(txns, DateTime.now());
});

/// Report card for the month containing the given date.
final reportCardProvider =
    Provider.family<ReportCard, DateTime>((ref, month) {
  final txns = ref.watch(transactionsStreamProvider).valueOrNull ?? const [];
  final budgets = ref.watch(budgetsStreamProvider).valueOrNull ?? const [];
  final income = ref.watch(userProfileProvider).valueOrNull?.monthlyIncome ?? 0;
  return ReportCard.build(txns, budgets, month, DateTime.now(),
      fallbackIncome: income);
});

// ── Net worth ─────────────────────────────────────────────────
final netWorthProvider = Provider<NetWorth>((ref) {
  final accounts = ref.watch(accountsProvider);
  final goals = ref.watch(goalsStreamProvider).valueOrNull ?? const [];
  final loans = ref.watch(loanTotalsProvider);
  var cash = 0.0;
  var exact = accounts.isNotEmpty;
  for (final a in accounts) {
    final bal = a.balance;
    if (bal == null) exact = false;
    cash += bal ?? a.net;
  }
  return NetWorth(
    cash: cash,
    cashExact: exact,
    goals: goals.fold<double>(0, (s, g) => s + g.saved),
    owedToYou: loans.owedToYou,
    youOwe: loans.youOwe,
  );
});

final netWorthTrendProvider = Provider<List<(DateTime, double)>>((ref) {
  final txns = ref.watch(transactionsStreamProvider).valueOrNull ?? const [];
  final opening = ref.watch(openingBalancesProvider).valueOrNull ?? const {};
  final openingTotal = opening.values.fold<double>(0, (a, b) => a + b);
  return NetWorth.cashTrend(txns, openingTotal, DateTime.now());
});

/// "At ₹X/month you'll have ₹Y by Dec 2027" — null until there's history.
final projectionProvider =
    Provider<({double perMonth, DateTime by, double value})?>((ref) {
  final txns = ref.watch(transactionsStreamProvider).valueOrNull ?? const [];
  if (txns.isEmpty) return null;
  final now = DateTime.now();
  final perMonth = NetWorth.monthlySaving(txns, now);
  if (perMonth <= 0) return null;
  final (by, value) =
      NetWorth.projection(ref.watch(netWorthProvider).total, perMonth, now);
  return (perMonth: perMonth, by: by, value: value);
});

// ── Bills ─────────────────────────────────────────────────────
/// Saved subscriptions + monthly payments spotted in history.
final billsProvider = Provider<List<Bill>>((ref) {
  final subs = ref.watch(subscriptionsStreamProvider).valueOrNull ?? const [];
  final recurring =
      ref.watch(insightsProvider).valueOrNull?.recurring ?? const [];
  return Bill.from(subs, recurring);
});
