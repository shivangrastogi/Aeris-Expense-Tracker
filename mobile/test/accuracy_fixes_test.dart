import 'package:flutter_test/flutter_test.dart';
import 'package:aeris_expense/models/category.dart';
import 'package:aeris_expense/models/transaction.dart';
import 'package:aeris_expense/providers/analytics_provider.dart';
import 'package:aeris_expense/services/sms_parser.dart';

void main() {
  group('Categories.classify — word-aware matching', () {
    test('keywords inside other words no longer match', () {
      expect(Categories.classify('Torrent Power'), isNot('rent'));
      expect(Categories.classify('Motorola Store'), isNot('travel'));
      expect(Categories.classify('Gossip Bar'), isNot('investment'));
      expect(Categories.classify('Vegas Mall'), isNot('bills'));
    });

    test('real keywords still match', () {
      expect(Categories.classify('House rent October'), 'rent');
      expect(Categories.classify('OLA CABS'), 'travel');
      expect(Categories.classify('Monthly SIP'), 'investment');
      expect(Categories.classify('Gas cylinder'), 'bills');
      expect(Categories.classify('Electricity bills'), 'bills');
      expect(Categories.classify('amazonpay'), 'shopping');
      expect(Categories.classify('SWIGGY'), 'food');
    });
  });

  group('SmsParser — accuracy fixes', () {
    final now = DateTime(2026, 10, 2, 10);

    test('failed payment is not saved as an expense', () {
      final p = SmsParser.parse(
        sender: 'AD-HDFCBK',
        body: 'Your transaction of Rs.1000 at ZOMATO has failed. '
            'Amount if debited will be reversed.',
        receivedAt: now,
      );
      expect(p, isNull);
    });

    test('declined card payment is skipped', () {
      final p = SmsParser.parse(
        sender: 'AX-ICICIB',
        body: 'Txn of INR 2,500.00 on ICICI Bank Card XX4321 at MYNTRA was '
            'declined due to insufficient balance.',
        receivedAt: now,
      );
      expect(p, isNull);
    });

    test('card spend picks up the merchant after "on"', () {
      final p = SmsParser.parse(
        sender: 'AX-ICICIB',
        body: 'INR 1,299.00 spent using ICICI Bank Card XX4321 on 02-Oct-26 '
            'on AMAZON. Avl Limit: INR 50,000.00.',
        receivedAt: now,
      );
      expect(p, isNotNull);
      expect(p!.txn.amount, 1299.0);
      expect(p.txn.merchant?.toLowerCase(), contains('amazon'));
      expect(p.txn.categoryId, 'shopping');
    });

    test('refund is tagged as a refund credit', () {
      final p = SmsParser.parse(
        sender: 'AD-HDFCBK',
        body: 'Refund of Rs.450 has been credited to your A/c XX1234 '
            'from FLIPKART.',
        receivedAt: now,
      );
      expect(p, isNotNull);
      expect(p!.txn.direction, TxnDirection.credit);
      expect(p.txn.categoryId, 'refund');
      expect(p.txn.isRefund, isTrue);
    });
  });

  test('refunds reduce spend and are not income', () {
    Transaction t(String id, double amt, TxnDirection d, String cat) =>
        Transaction(
          id: id,
          amount: amt,
          direction: d,
          timestamp: DateTime(2026, 10, 2),
          categoryId: cat,
        );
    final snap = AnalyticsSnapshot.from(
      [
        t('a', 1000, TxnDirection.debit, 'shopping'),
        t('b', 300, TxnDirection.credit, 'refund'),
        t('c', 5000, TxnDirection.credit, 'salary'),
      ],
      AnalyticsRange(DateTime(2026, 10, 1), DateTime(2026, 10, 31, 23, 59),
          'October'),
    );
    expect(snap.monthExpense, 700);
    expect(snap.monthIncome, 5000);
    expect(snap.monthlyExpenseSeries['2026-10'], 700);
    expect(snap.monthlyIncomeSeries['2026-10'], 5000);
  });
}
