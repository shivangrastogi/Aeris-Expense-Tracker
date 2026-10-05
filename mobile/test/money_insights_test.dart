import 'package:aeris_expense/models/budget.dart';
import 'package:aeris_expense/models/transaction.dart';
import 'package:aeris_expense/services/money_insights.dart';
import 'package:flutter_test/flutter_test.dart';

int _id = 0;
Transaction _t(double amt, DateTime when,
        {String cat = 'food',
        String? merchant,
        TxnDirection dir = TxnDirection.debit}) =>
    Transaction(
        id: 't${_id++}',
        amount: amt,
        direction: dir,
        timestamp: when,
        categoryId: cat,
        merchant: merchant);

Budget _b(String cat, double cap) =>
    Budget(id: cat, categoryId: cat, monthlyCap: cap, updatedAt: DateTime(2026));

void main() {
  final now = DateTime(2026, 9, 20, 21); // Sun 20 Sep, 9 PM; 11 days left

  group('SafeSpend', () {
    test('daily limit is fixed at the start of the day', () {
      final s = SafeSpend.compute([
        _t(9000, DateTime(2026, 9, 5)),
        _t(640, DateTime(2026, 9, 20, 13)),
      ], [
        _b(Budget.totalId, 20000)
      ], now)!;
      expect(s.daysLeft, 11);
      expect(s.dailyLimit, closeTo(1000, 0.01)); // (20000-9000)/11
      expect(s.leftToday, closeTo(360, 0.01));
      expect(s.message, contains('under'));
    });

    test('no budget → no safe-spend', () {
      expect(SafeSpend.compute([_t(10, now)], const [], now), isNull);
    });
  });

  test('noSpendWeek marks past days without spending', () {
    final week = noSpendWeek([
      _t(100, DateTime(2026, 9, 10)), // first activity (before this week)
      _t(50, DateTime(2026, 9, 14)), // Mon
      _t(50, DateTime(2026, 9, 16)), // Wed
    ], now); // week of Mon 14 … Sun 20
    expect(week.sublist(0, 6), [false, true, false, true, true, true]);
    expect(week[6], isNull); // today — not decided yet
  });

  group('WeeklyRecap', () {
    test('finds the biggest change, a repeated habit and a win', () {
      final txns = [
        // previous week: food 600
        _t(600, DateTime(2026, 9, 8), merchant: 'Zomato'),
        // this week: food 4×400 = 1600
        for (var d = 14; d <= 17; d++)
          _t(400, DateTime(2026, d == 17 ? 9 : 9, d), merchant: 'Swiggy'),
      ];
      final r = WeeklyRecap.build(txns, now)!;
      expect(r.change, contains('Food is up'));
      expect(r.habit, contains('4× Swiggy'));
      expect(r.win, contains('no-spend')); // 18, 19 had no spending
    });

    test('nothing to say about an empty history', () {
      expect(WeeklyRecap.build(const [], now), isNull);
    });
  });

  group('ReportCard', () {
    test('great month → A grade', () {
      final txns = [
        _t(100000, DateTime(2026, 8, 1), dir: TxnDirection.credit, cat: 'salary'),
        for (var d = 1; d <= 31; d += 2) _t(1000, DateTime(2026, 8, d)),
      ];
      final c = ReportCard.build(txns, [_b(Budget.totalId, 30000)],
          DateTime(2026, 8), now);
      expect(c.inProgress, isFalse);
      expect(c.budgetScore, 40); // 16k of 30k
      expect(c.savingsScore, 40); // 84% saved
      expect(c.grade, anyOf('A', 'A+'));
    });

    test('overspent, no savings → failing grade', () {
      final txns = [
        _t(20000, DateTime(2026, 8, 1), dir: TxnDirection.credit, cat: 'salary'),
        _t(26000, DateTime(2026, 8, 3)),
      ];
      final c = ReportCard.build(txns, [_b(Budget.totalId, 20000)],
          DateTime(2026, 8), now);
      expect(c.budgetScore, 0);
      expect(c.savingsScore, 0);
      expect(c.grade, 'F');
    });
  });

  group('NetWorth', () {
    test('total and projection', () {
      const w = NetWorth(
          cash: 50000, cashExact: true, goals: 20000, owedToYou: 1500, youOwe: 500);
      expect(w.total, 71000);
      final (target, value) = NetWorth.projection(w.total, 10000, now);
      expect(target, DateTime(2027, 12));
      expect(value, 71000 + 10000 * 15);
    });

    test('cash trend accumulates month by month', () {
      final trend = NetWorth.cashTrend([
        _t(1000, DateTime(2026, 8, 5), dir: TxnDirection.credit),
        _t(300, DateTime(2026, 9, 5)),
      ], 500, now, months: 2);
      expect(trend.map((e) => e.$2).toList(), [1500, 1200]);
    });
  });

  test('rollover adds last month\'s leftover, capped at one month', () {
    final budgets = [_b('food', 5000), _b('travel', 2000)];
    final txns = [
      _t(3000, DateTime(2026, 8, 10), cat: 'food'), // 2000 left
      _t(2500, DateTime(2026, 8, 10), cat: 'travel'), // overspent
    ];
    final out = BudgetRollover.apply(budgets, txns, now);
    expect(out.firstWhere((b) => b.categoryId == 'food').monthlyCap, 7000);
    expect(out.firstWhere((b) => b.categoryId == 'travel').monthlyCap, 2000);
  });
}
