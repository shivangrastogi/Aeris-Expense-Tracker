// Home-screen widget numbers: always the calendar month and today (never the
// Analytics range), income ignored, refunds netted off, never negative.
import 'package:aeris_expense/models/transaction.dart';
import 'package:aeris_expense/services/widget_service.dart';
import 'package:flutter_test/flutter_test.dart';

Transaction _t(double amt, DateTime at, {bool credit = false, String cat = 'food'}) => Transaction(
      id: '${at.millisecondsSinceEpoch}-$amt',
      amount: amt,
      direction: credit ? TxnDirection.credit : TxnDirection.debit,
      timestamp: at,
      categoryId: cat,
    );

void main() {
  final now = DateTime(2026, 10, 18, 15, 30);

  test('month and today totals', () {
    final s = WidgetSnapshot.compute([
      _t(100, DateTime(2026, 10, 18, 9)), // today
      _t(250, DateTime(2026, 10, 2)), // this month
      _t(999, DateTime(2026, 9, 30, 23, 59)), // last month — excluded
      _t(5000, DateTime(2026, 10, 1), credit: true), // income — excluded
    ], now);
    expect(s.monthSpent, 350);
    expect(s.todaySpent, 100);
    expect(s.monthKey, '2026-10');
    expect(s.dayKey, '2026-10-18');
  });

  test('refunds come off spend, never below zero', () {
    final s = WidgetSnapshot.compute([
      _t(400, DateTime(2026, 10, 18, 8)),
      _t(150, DateTime(2026, 10, 18, 10), credit: true, cat: 'refund'),
      _t(900, DateTime(2026, 10, 3), credit: true, cat: 'refund'),
    ], now);
    expect(s.todaySpent, 250);
    expect(s.monthSpent, 0);
  });

  test('same day-of-month in another month is not "today"', () {
    final s = WidgetSnapshot.compute([_t(70, DateTime(2026, 9, 18, 12))], now);
    expect(s.todaySpent, 0);
    expect(s.monthSpent, 0);
  });
}
