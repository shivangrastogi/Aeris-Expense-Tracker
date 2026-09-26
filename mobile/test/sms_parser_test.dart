import 'package:flutter_test/flutter_test.dart';
import 'package:aeris_expense/services/sms_parser.dart';
import 'package:aeris_expense/models/transaction.dart';

void main() {
  group('SmsParser — debit fixtures', () {
    final now = DateTime(2026, 5, 30, 10, 15);

    test('HDFC card debit', () {
      final p = SmsParser.parse(
        sender: 'JD-HDFCBK',
        body:
            'Rs.499.00 spent on your HDFC Bank Card xx1234 at AMAZON on 30-05-26. Avl bal: Rs.12,345.00',
        receivedAt: now,
      );
      expect(p, isNotNull);
      expect(p!.txn.amount, 499.0);
      expect(p.txn.direction, TxnDirection.debit);
      expect(p.txn.merchant, 'Amazon'); // normalised by the merchant directory
      expect(p.txn.account, '1234');
      expect(p.txn.categoryId, 'shopping');
      expect(p.confidence, greaterThan(0.7));
    });

    test('SBI UPI debit to VPA', () {
      final p = SmsParser.parse(
        sender: 'VM-SBIBNK',
        body:
            'INR 1,250 debited from A/c XX5678 to VPA swiggy@oksbi on 30/05/2026 UPI Ref 123',
        receivedAt: now,
      );
      expect(p, isNotNull);
      expect(p!.txn.amount, 1250.0);
      expect(p.txn.direction, TxnDirection.debit);
      expect(p.txn.merchant, contains('Swiggy'));
      expect(p.txn.categoryId, 'food');
    });

    test('ICICI fuel POS', () {
      final p = SmsParser.parse(
        sender: 'AX-ICICIB',
        body:
            'Rs 2,000 spent on ICICI Card xx9012 at HPCL PETROL PUMP on 30-05-2026',
        receivedAt: now,
      );
      expect(p, isNotNull);
      expect(p!.txn.amount, 2000.0);
      expect(p.txn.merchant, 'HP Petrol'); // normalised from HPCL
      expect(p.txn.categoryId, 'travel');
    });

    test('Amazon Pay wallet via Juspay (INR, no merchant)', () {
      final p = SmsParser.parse(
        sender: 'JM-APAYIN',
        body:
            'Your Apay Wallet balance is debited for INR 20.00. Transaction Reference Number is 652732468322. If not you? call 180012001637 - SMS via Juspay',
        receivedAt: now,
      );
      expect(p, isNotNull);
      expect(p!.txn.amount, 20.0);
      expect(p.txn.direction, TxnDirection.debit);
      expect(p.txn.reference, '652732468322');
    });

    test('SBI "debited by" with no Rs symbol + text-month date', () {
      final p = SmsParser.parse(
        sender: 'JM-SBIBNK',
        body:
            'Dear UPI user A/C X8208 debited by 101.00 on date 07Jun26 trf to Naib Subedar San Refno 615809770746 If not u? call-1800111109',
        receivedAt: now,
      );
      expect(p, isNotNull);
      expect(p!.txn.amount, 101.0);
      expect(p.txn.direction, TxnDirection.debit);
    });

    test('Paytm UPI debit', () {
      final p = SmsParser.parse(
        sender: 'VK-PAYTM',
        body: 'Paid Rs.350 to Bigbasket via Paytm UPI. Txn ID 9988',
        receivedAt: now,
      );
      expect(p, isNotNull);
      expect(p!.txn.direction, TxnDirection.debit);
      expect(p.txn.categoryId, 'groceries');
    });
  });

  group('SmsParser — credit fixtures', () {
    final now = DateTime(2026, 5, 30);

    test('Salary credit', () {
      final p = SmsParser.parse(
        sender: 'VM-SBIBNK',
        body: 'Credit Alert! INR 50,000 credited to A/c XX5678 - Salary May',
        receivedAt: now,
      );
      expect(p, isNotNull);
      expect(p!.txn.direction, TxnDirection.credit);
      expect(p.txn.amount, 50000.0);
      expect(p.txn.categoryId, 'salary');
    });

    test('UPI credit from a friend', () {
      final p = SmsParser.parse(
        sender: 'JD-HDFCBK',
        body:
            'Rs.500 credited to your A/c xx1234 received from rohan@oksbi on 30-05-26',
        receivedAt: now,
      );
      expect(p, isNotNull);
      expect(p!.txn.direction, TxnDirection.credit);
      expect(p.txn.amount, 500.0);
    });
  });

  group('SmsParser — rejects', () {
    final now = DateTime(2026, 5, 30);

    test('OTP message is ignored', () {
      final p = SmsParser.parse(
        sender: 'VM-HDFCBK',
        body: '123456 is your OTP for verification. Do not share.',
        receivedAt: now,
      );
      expect(p, isNull);
    });

    test('Promotional cashback offer is ignored', () {
      final p = SmsParser.parse(
        sender: 'VM-HDFCBK',
        body:
            'Special offer! Get Rs.500 cashback on your next shopping. Apply now.',
        receivedAt: now,
      );
      expect(p, isNull);
    });

    test('Random non-bank sender is rejected', () {
      final p = SmsParser.parse(
        sender: 'AD-MYNTRA',
        body: 'Your order has shipped. Track at myntra.com',
        receivedAt: now,
      );
      expect(p, isNull);
    });

    test('Bank body without amount is rejected', () {
      final p = SmsParser.parse(
        sender: 'VM-SBIBNK',
        body: 'Dear customer, your KYC is pending. Please update.',
        receivedAt: now,
      );
      expect(p, isNull);
    });

    test('Upcoming mandate / autopay reminder is not a spend', () {
      final p = SmsParser.parse(
        sender: 'VA-YESBNK-S',
        body: 'For the upcoming mandate set for 16-06-26, your account will be '
            'debited with Rs.1000.00 towards Amazon Pay Balance for the Wallet '
            'Reload. If mandate is paused the execution for the same will not '
            'happen. - Amazon and Yes Bank.',
        receivedAt: now,
      );
      expect(p, isNull);
    });
  });
}
