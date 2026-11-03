import 'package:aeris_expense/models/transaction.dart';
import 'package:aeris_expense/providers/analytics_provider.dart';
import 'package:flutter_test/flutter_test.dart';

Transaction _t(double amount, bool credit, {String? settles}) => Transaction(
      id: '$amount$credit$settles',
      amount: amount,
      direction: credit ? TxnDirection.credit : TxnDirection.debit,
      timestamp: DateTime.now(),
      categoryId: 'transfer',
      merchant: 'Rahul',
      settles: settles,
    );

void main() {
  const start = Transaction.loanStart, repay = Transaction.loanRepay;

  test('loan-linked payments name themselves', () {
    expect(_t(5000, false, settles: '${start}l1').linkKind, 'Lent');
    expect(_t(5000, true, settles: '${start}l1').linkKind, 'Borrowed');
    expect(_t(2000, true, settles: '${repay}l1').linkKind, 'Payback');
    expect(_t(2000, false, settles: '${repay}l1').linkKind, 'Repaid');
    expect(_t(2000, true, settles: 'bill1').linkKind, 'Payback');
    expect(_t(2000, true).linkKind, isNull);
    expect(_t(2000, true, settles: '${repay}l1').loanId, 'l1');
    expect(_t(2000, true, settles: 'bill1').loanId, isNull);
  });

  test('lending and partial paybacks are neither spend nor income', () {
    final snap = AnalyticsSnapshot.from([
      _t(5000, false, settles: '${start}l1'), // lent ₹5,000
      _t(2000, true, settles: '${repay}l1'), // ₹2,000 of it back
      _t(300, false), // a real expense
      _t(1000, true), // real income
    ], AnalyticsRange.thisMonth());
    expect(snap.monthExpense, 300);
    expect(snap.monthIncome, 1000);
    expect(_t(5000, false, settles: '${start}l1').isSpend, isFalse);
    expect(_t(2000, true, settles: '${repay}l1').isIncoming, isFalse);
  });
}
