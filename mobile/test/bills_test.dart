import 'package:aeris_expense/models/insight.dart';
import 'package:aeris_expense/models/subscription.dart';
import 'package:aeris_expense/services/reminder_scheduler.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const subs = [
    Subscription(id: 's1', name: 'Rent', amount: 18000, categoryId: 'rent', day: 3),
    Subscription(id: 's2', name: 'Airtel postpaid', amount: 399, categoryId: 'bills', day: 5),
  ];

  test('detected payments that match a saved bill are not listed twice', () {
    final bills = Bill.from(subs, const [
      RecurringPayment(merchant: 'Rent · Mr. Sharma', categoryId: 'rent',
          approxAmount: 18000, dayOfMonth: 3, occurrences: 3),
      RecurringPayment(merchant: 'Airtel recharge', categoryId: 'bills',
          approxAmount: 399, dayOfMonth: 5, occurrences: 3),
      RecurringPayment(merchant: 'Netflix', categoryId: 'entertainment',
          approxAmount: 649, dayOfMonth: 5, occurrences: 3),
    ]);
    expect(bills.map((b) => b.name), ['Rent', 'Airtel postpaid', 'Netflix']);
    expect(bills.last.detected, isTrue);
  });

  test('next due date rolls to next month and clamps short months', () {
    const b = Bill(name: 'X', amount: 1, day: 31, categoryId: 'bills');
    expect(b.nextDue(DateTime(2026, 2, 10)), DateTime(2026, 2, 28));
    expect(b.nextDue(DateTime(2026, 3, 31)), DateTime(2026, 3, 31));
    const c = Bill(name: 'Y', amount: 1, day: 3, categoryId: 'bills');
    expect(c.nextDue(DateTime(2026, 9, 30)), DateTime(2026, 10, 3));
  });
}
