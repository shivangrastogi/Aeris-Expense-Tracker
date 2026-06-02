import 'package:flutter_test/flutter_test.dart';
import 'package:aeris_expense/models/transaction.dart';
import 'package:aeris_expense/services/prediction_service.dart';

Transaction _t({
  required double amount,
  required DateTime when,
  required String catId,
  String? merchant,
  TxnDirection dir = TxnDirection.debit,
}) => Transaction(
  id: '${when.millisecondsSinceEpoch}-${merchant ?? amount}',
  amount: amount,
  direction: dir,
  timestamp: when,
  categoryId: catId,
  merchant: merchant,
);

void main() {
  final svc = PredictionService.instance;

  test('predictCurrentMonth blends history + burn rate', () {
    final txns = <Transaction>[
      // Two prior months at 30k each.
      for (var m = 3; m <= 4; m++)
        for (var d = 1; d <= 30; d++)
          _t(amount: 1000, when: DateTime(2026, m, d), catId: 'food'),
      // Current month at 1k/day for first 10 days.
      for (var d = 1; d <= 10; d++)
        _t(amount: 1000, when: DateTime(2026, 5, d), catId: 'food'),
    ];
    final p = svc.predictCurrentMonth(txns);
    expect(p.estimate, greaterThan(20000));
    expect(p.low, lessThan(p.estimate));
    expect(p.high, greaterThan(p.estimate));
  });

  test('detectAnomalies flags large outliers', () {
    final txns = <Transaction>[
      // Six routine small spends in a category.
      for (var i = 0; i < 8; i++)
        _t(amount: 200.0 + i, when: DateTime(2026, 5, i + 1), catId: 'food'),
      // One huge spike — should appear in the anomalies list.
      _t(amount: 9999, when: DateTime(2026, 5, 25), catId: 'food', merchant: 'Big bill'),
    ];
    final out = svc.detectAnomalies(txns);
    expect(out, isNotEmpty);
    expect(out.first.amount, 9999);
  });

  test('detectRecurring picks up monthly fixed charges', () {
    final txns = <Transaction>[
      for (var m = 1; m <= 4; m++)
        _t(amount: 499, when: DateTime(2026, m, 5),
           catId: 'entertainment', merchant: 'Netflix'),
    ];
    final r = svc.detectRecurring(txns);
    expect(r, isNotEmpty);
    expect(r.first.merchant, 'Netflix');
    expect(r.first.occurrences, 4);
    expect(r.first.dayOfMonth, 5);
  });

  test('predictPerCategoryNextMonth uses EMA over history', () {
    final txns = <Transaction>[
      // Food expense growing slightly month by month.
      _t(amount: 5000, when: DateTime(2026, 1, 15), catId: 'food'),
      _t(amount: 5500, when: DateTime(2026, 2, 15), catId: 'food'),
      _t(amount: 6000, when: DateTime(2026, 3, 15), catId: 'food'),
      _t(amount: 6500, when: DateTime(2026, 4, 15), catId: 'food'),
    ];
    final preds = svc.predictPerCategoryNextMonth(txns);
    expect(preds.any((p) => p.categoryId == 'food'), isTrue);
    final food = preds.firstWhere((p) => p.categoryId == 'food');
    // EMA with alpha 0.45 should sit between 5500 and 6500.
    expect(food.estimate, greaterThan(5500));
    expect(food.estimate, lessThan(6500));
  });
}
