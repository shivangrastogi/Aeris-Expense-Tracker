import 'package:aeris_expense/models/transaction.dart';
import 'package:aeris_expense/services/entry_checks.dart';
import 'package:aeris_expense/utils/amount_input_formatter.dart';
import 'package:flutter_test/flutter_test.dart';

Transaction _t(String id, double amt, DateTime at,
        {String? merchant,
        String cat = 'food',
        TxnDirection dir = TxnDirection.debit}) =>
    Transaction(
        id: id,
        amount: amt,
        direction: dir,
        timestamp: at,
        categoryId: cat,
        merchant: merchant);

void main() {
  final now = DateTime(2026, 9, 25, 12, 0);

  group('likelyDuplicate', () {
    final existing = [
      _t('a', 200, now.subtract(const Duration(minutes: 5)), merchant: 'Chai'),
      _t('b', 500, now.subtract(const Duration(hours: 4)), merchant: 'Uber'),
    ];

    test('same amount within the window matches', () {
      expect(
          EntryChecks.likelyDuplicate(existing,
                  amount: 200, direction: TxnDirection.debit, when: now)
              ?.id,
          'a');
    });

    test('same merchant same day matches outside the window', () {
      expect(
          EntryChecks.likelyDuplicate(existing,
                  amount: 500,
                  direction: TxnDirection.debit,
                  when: now,
                  merchant: 'uber')
              ?.id,
          'b');
    });

    test('different amount, direction, or the txn itself do not match', () {
      expect(
          EntryChecks.likelyDuplicate(existing,
              amount: 201, direction: TxnDirection.debit, when: now),
          isNull);
      expect(
          EntryChecks.likelyDuplicate(existing,
              amount: 200, direction: TxnDirection.credit, when: now),
          isNull);
      expect(
          EntryChecks.likelyDuplicate(existing,
              amount: 200,
              direction: TxnDirection.debit,
              when: now,
              excludeId: 'a'),
          isNull);
      // 4 h apart and no merchant given → not a duplicate.
      expect(
          EntryChecks.likelyDuplicate(existing,
              amount: 500, direction: TxnDirection.debit, when: now),
          isNull);
    });
  });

  group('typical / unusually large', () {
    final history = [
      for (var i = 0; i < 7; i++)
        _t('f$i', 200.0 + i * 10, DateTime.now().subtract(Duration(days: i))),
    ];

    test('median of recent same-category amounts', () {
      expect(
          EntryChecks.typicalAmount(history,
              categoryId: 'food', direction: TxnDirection.debit),
          230);
    });

    test('needs enough samples', () {
      expect(
          EntryChecks.typicalAmount(history.take(3),
              categoryId: 'food', direction: TxnDirection.debit),
          isNull);
    });

    test('flags an extra zero, ignores normal and small amounts', () {
      expect(EntryChecks.isUnusuallyLarge(2300, 230), isTrue);
      expect(EntryChecks.isUnusuallyLarge(400, 230), isFalse);
      expect(EntryChecks.isUnusuallyLarge(900, 30), isFalse); // under floor
      expect(EntryChecks.isUnusuallyLarge(5000, null), isFalse);
    });
  });

  test('recentTemplates dedupes by merchant, newest first', () {
    final xs = [
      _t('1', 20, now.subtract(const Duration(days: 3)), merchant: 'Chai'),
      _t('2', 25, now.subtract(const Duration(days: 1)), merchant: 'chai '),
      _t('3', 180, now.subtract(const Duration(days: 2)), merchant: 'Uber'),
      _t('4', 999, now, merchant: 'Salary', dir: TxnDirection.credit),
      _t('5', 50, now),
    ];
    final r = EntryChecks.recentTemplates(xs, direction: TxnDirection.debit);
    expect(r.map((t) => t.id), ['2', '3']);
  });

  group('evalAmount', () {
    test('plain numbers', () {
      expect(evalAmount('120'), 120);
      expect(evalAmount('12.5'), 12.5);
      expect(evalAmount(''), isNull);
      expect(evalAmount('0'), isNull);
    });
    test('precedence and symbols', () {
      expect(evalAmount('120+45×2'), 210);
      expect(evalAmount('100−20÷4'), 95);
      expect(evalAmount('10*3-5'), 25);
      expect(evalAmount('100/3'), 33.33);
    });
    test('trailing operator ignored, bad input rejected', () {
      expect(evalAmount('120+'), 120);
      expect(evalAmount('+5'), isNull);
      expect(evalAmount('5÷0'), isNull);
      expect(evalAmount('5−10'), isNull); // not positive
      expect(isAmountExpression('120+4'), isTrue);
      expect(isAmountExpression('120'), isFalse);
    });
  });

  test('math formatter normalises operators and collapses doubles', () {
    const f = AmountInputFormatter(allowMath: true);
    String fmt(String old, String next) => f
        .formatEditUpdate(
            TextEditingValue(text: old), TextEditingValue(text: next))
        .text;
    expect(fmt('12', '12*'), '12×');
    expect(fmt('12', '12/'), '12÷');
    expect(fmt('12+', '12+-'), '12−');
    expect(fmt('12+3', '12+3.456'), '12+3'); // max 2 decimals per number
    expect(fmt('12', '12a'), '12');
  });
}
