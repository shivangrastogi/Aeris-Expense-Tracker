import 'dart:math' as math;

import '../models/budget.dart';
import '../models/category.dart';
import '../models/transaction.dart';
import '../utils/formatters.dart';

/// Pure money maths behind the newer features — safe-to-spend, the weekly
/// recap, the monthly report card, net worth and budget rollover. No IO, no
/// providers: everything takes data in and returns values, so it's all
/// unit-tested (test/money_insights_test.dart).

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

bool _inMonth(DateTime d, DateTime m) => d.year == m.year && d.month == m.month;

/// The overall monthly budget: the explicit "total" budget wins, else the sum
/// of the per-category caps.
double totalBudget(List<Budget> budgets) {
  final explicit = budgets
      .where((b) => b.categoryId == Budget.totalId)
      .fold<double>(0, (s, b) => s + b.monthlyCap);
  if (explicit > 0) return explicit;
  return budgets
      .where((b) => b.categoryId != Budget.totalId)
      .fold<double>(0, (s, b) => s + b.monthlyCap);
}

// ══ Safe to spend ═════════════════════════════════════════════
class SafeSpend {
  final double budget;
  final double spentBeforeToday;
  final double spentToday;
  final int daysLeft; // including today

  const SafeSpend({
    required this.budget,
    required this.spentBeforeToday,
    required this.spentToday,
    required this.daysLeft,
  });

  /// Today's allowance, fixed at the start of the day: what's left of the
  /// month's budget spread evenly over the remaining days.
  double get dailyLimit =>
      math.max(0, budget - spentBeforeToday) / math.max(1, daysLeft);

  /// Positive = under today's limit, negative = over it.
  double get leftToday => dailyLimit - spentToday;

  static SafeSpend? compute(
      List<Transaction> txns, List<Budget> budgets, DateTime now) {
    final budget = totalBudget(budgets);
    if (budget <= 0) return null;
    double before = 0, today = 0;
    for (final t in txns) {
      if (!t.isDebit || !_inMonth(t.timestamp, now)) continue;
      if (_sameDay(t.timestamp, now)) {
        today += t.amount;
      } else if (t.timestamp.isBefore(now)) {
        before += t.amount;
      }
    }
    final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
    return SafeSpend(
      budget: budget,
      spentBeforeToday: before,
      spentToday: today,
      daysLeft: daysInMonth - now.day + 1,
    );
  }

  /// "Today: ₹640 · ₹310 under your ₹950 daily limit"
  String get message {
    final spent = formatRupees(spentToday);
    final limit = formatRupees(dailyLimit);
    if (spentToday == 0) return 'No spending today — ₹0 of your $limit limit';
    return leftToday >= 0
        ? 'Today: $spent · ${formatRupees(leftToday)} under your $limit daily limit'
        : 'Today: $spent · ${formatRupees(-leftToday)} over your $limit daily limit';
  }
}

// ══ No-spend days ═════════════════════════════════════════════
/// Days of [now]'s week (Mon→Sun, or from [weekStart]) — past days only —
/// with no spending at all,
/// counted only after the user's first ever transaction.
List<bool?> noSpendWeek(List<Transaction> txns, DateTime now,
    {DateTime? weekStart}) {
  final start = weekStart ??
      DateTime(now.year, now.month, now.day)
          .subtract(Duration(days: now.weekday - 1));
  final first = txns.isEmpty
      ? null
      : txns.map((t) => t.timestamp).reduce((a, b) => a.isBefore(b) ? a : b);
  final spentDays = <String>{
    for (final t in txns)
      if (t.isDebit)
        '${t.timestamp.year}-${t.timestamp.month}-${t.timestamp.day}'
  };
  return List.generate(7, (i) {
    final d = start.add(Duration(days: i));
    final today = DateTime(now.year, now.month, now.day);
    if (!d.isBefore(today)) return null; // today / future: not decided yet
    if (first == null || d.isBefore(DateTime(first.year, first.month, first.day))) {
      return null;
    }
    return !spentDays.contains('${d.year}-${d.month}-${d.day}');
  });
}

// ══ Weekly recap ══════════════════════════════════════════════
class WeeklyRecap {
  final String change;
  final String habit;
  final String win;
  const WeeklyRecap(
      {required this.change, required this.habit, required this.win});

  static String _cat(String id) =>
      Categories.byId(id).label.split(RegExp(r' [&/] ')).first;

  /// Last 7 days (ending [now]) vs the 7 before.
  static WeeklyRecap? build(List<Transaction> txns, DateTime now) {
    final end = DateTime(now.year, now.month, now.day, 23, 59, 59);
    final start = DateTime(now.year, now.month, now.day)
        .subtract(const Duration(days: 6));
    final prevStart = start.subtract(const Duration(days: 7));
    final cur = <String, double>{}, prev = <String, double>{};
    final curTx = <Transaction>[];
    for (final t in txns) {
      if (!t.isDebit || t.timestamp.isAfter(end)) continue;
      if (!t.timestamp.isBefore(start)) {
        cur[t.categoryId] = (cur[t.categoryId] ?? 0) + t.amount;
        curTx.add(t);
      } else if (!t.timestamp.isBefore(prevStart)) {
        prev[t.categoryId] = (prev[t.categoryId] ?? 0) + t.amount;
      }
    }
    if (curTx.isEmpty && prev.isEmpty) return null;
    final curTotal = cur.values.fold<double>(0, (a, b) => a + b);
    final prevTotal = prev.values.fold<double>(0, (a, b) => a + b);

    // 1 · Biggest change.
    String change;
    final deltas = {
      for (final k in {...cur.keys, ...prev.keys})
        k: (cur[k] ?? 0) - (prev[k] ?? 0)
    };
    if (prev.isEmpty) {
      change =
          'You spent ${formatRupees(curTotal)} across ${curTx.length} transactions this week.';
    } else {
      final top = deltas.entries.reduce(
          (a, b) => a.value.abs() >= b.value.abs() ? a : b);
      final before = prev[top.key] ?? 0;
      final pct = before > 0 ? ' (${(top.value / before * 100).round().abs()}%)' : '';
      change = top.value >= 0
          ? '${_cat(top.key)} is up ${formatRupees(top.value)}$pct vs last week.'
          : '${_cat(top.key)} is down ${formatRupees(-top.value)}$pct vs last week.';
    }

    // 2 · One habit to fix: the most repeated small spend.
    String habit;
    final byMerchant = <String, List<Transaction>>{};
    for (final t in curTx) {
      final m = (t.merchant ?? _cat(t.categoryId)).trim();
      byMerchant.putIfAbsent(m.toLowerCase(), () => []).add(t);
    }
    final repeat = byMerchant.values.where((l) => l.length >= 3).toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    if (repeat.isNotEmpty) {
      final l = repeat.first;
      final sum = l.fold<double>(0, (a, t) => a + t.amount);
      final name = l.first.merchant ?? _cat(l.first.categoryId);
      habit =
          '${l.length}× $name (${formatRupees(sum)}) — skipping two saves ~${formatRupees(sum / l.length * 2)}.';
    } else {
      habit = 'Log every spend the day it happens — accurate data makes every tip better.';
    }

    // 3 · One win.
    final week = noSpendWeekOf(txns, start, now);
    String win;
    final down = deltas.entries.where((e) => e.value < 0).toList()
      ..sort((a, b) => a.value.compareTo(b.value));
    if (week > 0) {
      win = '$week no-spend day${week == 1 ? '' : 's'} this week — nice discipline.';
    } else if (prevTotal > 0 && curTotal < prevTotal) {
      win =
          'You spent ${formatRupees(prevTotal - curTotal)} less than last week.';
    } else if (down.isNotEmpty) {
      win =
          '${_cat(down.first.key)} dropped by ${formatRupees(-down.first.value)}.';
    } else {
      win = 'You tracked ${curTx.length} transactions — the habit that makes budgets work.';
    }
    return WeeklyRecap(change: change, habit: habit, win: win);
  }

  /// No-spend days between [start] and yesterday.
  static int noSpendWeekOf(
      List<Transaction> txns, DateTime start, DateTime now) {
    final spent = <String>{
      for (final t in txns)
        if (t.isDebit)
          '${t.timestamp.year}-${t.timestamp.month}-${t.timestamp.day}'
    };
    var n = 0;
    for (var d = start;
        d.isBefore(DateTime(now.year, now.month, now.day));
        d = d.add(const Duration(days: 1))) {
      if (!spent.contains('${d.year}-${d.month}-${d.day}')) n++;
    }
    return n;
  }
}

// ══ Monthly report card ═══════════════════════════════════════
class ReportCard {
  final DateTime month;
  final bool inProgress;
  final double spent;
  final double income;
  final double budget;
  final int noSpendDays;
  final int trackedDays;
  final int budgetScore; // /40
  final int savingsScore; // /40
  final int habitScore; // /20

  const ReportCard({
    required this.month,
    required this.inProgress,
    required this.spent,
    required this.income,
    required this.budget,
    required this.noSpendDays,
    required this.trackedDays,
    required this.budgetScore,
    required this.savingsScore,
    required this.habitScore,
  });

  int get score => budgetScore + savingsScore + habitScore;

  String get grade {
    final s = score;
    if (s >= 93) return 'A+';
    if (s >= 85) return 'A';
    if (s >= 77) return 'B+';
    if (s >= 70) return 'B';
    if (s >= 60) return 'C';
    if (s >= 50) return 'D';
    return 'F';
  }

  double? get savingsRate => income > 0 ? (income - spent) / income : null;

  /// [month] is any day in the month to grade; [fallbackIncome] (the
  /// profile's monthly income) is used when no income was recorded.
  static ReportCard build(List<Transaction> txns, List<Budget> budgets,
      DateTime month, DateTime now,
      {double fallbackIncome = 0}) {
    double spent = 0, income = 0;
    final spendDays = <int>{}, anyDays = <int>{};
    DateTime? first;
    for (final t in txns) {
      if (first == null || t.timestamp.isBefore(first)) first = t.timestamp;
      if (!_inMonth(t.timestamp, month)) continue;
      anyDays.add(t.timestamp.day);
      if (t.isDebit) {
        spent += t.amount;
        spendDays.add(t.timestamp.day);
      } else if (t.categoryId != 'transfer') {
        income += t.amount;
      }
    }
    if (income <= 0) income = fallbackIncome;
    final inProgress = _inMonth(now, month);
    final lastDay = inProgress
        ? now.day - 1
        : DateTime(month.year, month.month + 1, 0).day;
    var noSpend = 0;
    for (var d = 1; d <= lastDay; d++) {
      final day = DateTime(month.year, month.month, d);
      if (first != null &&
          day.isBefore(DateTime(first.year, first.month, first.day))) {
        continue;
      }
      if (!spendDays.contains(d)) noSpend++;
    }

    final cap = totalBudget(budgets);
    final int b;
    if (cap <= 0) {
      b = 20; // neutral — no budget to judge against
    } else {
      final r = spent / cap;
      b = r <= 0.9 ? 40 : r <= 1.0 ? 32 : r <= 1.1 ? 20 : r <= 1.25 ? 10 : 0;
    }
    final int sv;
    if (income <= 0) {
      sv = 20;
    } else {
      final rate = (income - spent) / income;
      sv = rate >= 0.3
          ? 40
          : rate >= 0.2
              ? 32
              : rate >= 0.1
                  ? 24
                  : rate >= 0
                      ? 14
                      : 0;
    }
    final h = (noSpend >= 4 ? 10 : noSpend >= 2 ? 6 : noSpend >= 1 ? 3 : 0) +
        (anyDays.length >= 15 ? 10 : anyDays.length >= 8 ? 6 : 3);
    return ReportCard(
      month: DateTime(month.year, month.month),
      inProgress: inProgress,
      spent: spent,
      income: income,
      budget: cap,
      noSpendDays: noSpend,
      trackedDays: anyDays.length,
      budgetScore: b,
      savingsScore: sv,
      habitScore: h,
    );
  }
}

// ══ Net worth ═════════════════════════════════════════════════
class NetWorth {
  final double cash; // bank/wallet balances (or net flows where unknown)
  final bool cashExact; // every account has an opening balance
  final double goals;
  final double owedToYou;
  final double youOwe;

  const NetWorth({
    required this.cash,
    required this.cashExact,
    required this.goals,
    required this.owedToYou,
    required this.youOwe,
  });

  double get total => cash + goals + owedToYou - youOwe;

  /// Month-end cash position for the last [months] months: opening balances
  /// plus the cumulative net of every transaction up to that month's end.
  static List<(DateTime, double)> cashTrend(
      List<Transaction> txns, double openingTotal, DateTime now,
      {int months = 12}) {
    final out = <(DateTime, double)>[];
    for (var i = months - 1; i >= 0; i--) {
      final monthEnd = DateTime(now.year, now.month - i + 1, 0, 23, 59, 59);
      final cutoff = i == 0 ? now : monthEnd;
      var v = openingTotal;
      for (final t in txns) {
        if (!t.timestamp.isAfter(cutoff)) v += t.signed;
      }
      out.add((DateTime(now.year, now.month - i), v));
    }
    return out;
  }

  /// Average (income − spending) over the last 3 completed months that have
  /// any activity; falls back to this month so far.
  static double monthlySaving(List<Transaction> txns, DateTime now) {
    final byMonth = <String, double>{};
    for (final t in txns) {
      final k = '${t.timestamp.year}-${t.timestamp.month}';
      byMonth[k] = (byMonth[k] ?? 0) + t.signed;
    }
    final vals = <double>[];
    for (var i = 1; i <= 3; i++) {
      final m = DateTime(now.year, now.month - i);
      final v = byMonth['${m.year}-${m.month}'];
      if (v != null) vals.add(v);
    }
    if (vals.isEmpty) return byMonth['${now.year}-${now.month}'] ?? 0;
    return vals.reduce((a, b) => a + b) / vals.length;
  }

  /// Where [total] lands by December of next year at [perMonth].
  static (DateTime, double) projection(
      double total, double perMonth, DateTime now) {
    final target = DateTime(now.year + 1, 12);
    final months =
        (target.year - now.year) * 12 + target.month - now.month;
    return (target, total + perMonth * months);
  }
}

// ══ Budget rollover ═══════════════════════════════════════════
class BudgetRollover {
  /// Last month's unspent amount per budget (0 when overspent).
  static Map<String, double> leftovers(
      List<Budget> budgets, List<Transaction> txns, DateTime now) {
    final last = DateTime(now.year, now.month - 1);
    final byCat = <String, double>{};
    double total = 0;
    for (final t in txns) {
      if (!t.isDebit || !_inMonth(t.timestamp, last)) continue;
      byCat[t.categoryId] = (byCat[t.categoryId] ?? 0) + t.amount;
      total += t.amount;
    }
    return {
      for (final b in budgets)
        if (b.monthlyCap > 0)
          b.categoryId: math.max(
              0,
              b.monthlyCap -
                  (b.categoryId == Budget.totalId
                      ? total
                      : (byCat[b.categoryId] ?? 0))),
    };
  }

  /// Budgets with last month's leftover added (at most one extra month's
  /// cap), so saving in one month buys room in the next.
  static List<Budget> apply(
      List<Budget> budgets, List<Transaction> txns, DateTime now) {
    final left = leftovers(budgets, txns, now);
    return [
      for (final b in budgets)
        Budget(
          id: b.id,
          categoryId: b.categoryId,
          monthlyCap:
              b.monthlyCap + math.min(left[b.categoryId] ?? 0, b.monthlyCap),
          updatedAt: b.updatedAt,
        ),
    ];
  }
}
