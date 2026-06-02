// Smoke tests for AERIS Expense.
//
// The full app boots Firebase + Riverpod, which isn't available in the plain
// widget-test harness, so instead we unit-test pure, dependency-free logic
// (the SMS parser) plus a trivial widget render. Richer integration tests can
// be added later with a Firebase mock.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aeris_expense/services/sms_parser.dart';

void main() {
  group('SmsParser spam hardening', () {
    test('rejects lottery spam that mimics a bank credit', () {
      final r = SmsParser.parse(
        sender: 'VK-WINBIG',
        body: 'Congratulations! Rs 50000 credited to your account. Claim now: bit.ly/x',
        receivedAt: DateTime.now(),
      );
      expect(r, isNull);
    });

    test('rejects a credit from an untrusted sender', () {
      final r = SmsParser.parse(
        sender: 'AD-RANDOM',
        body: 'Rs 2000 credited to your a/c via UPI.',
        receivedAt: DateTime.now(),
      );
      expect(r, isNull);
    });

    test('accepts a genuine bank debit alert', () {
      final r = SmsParser.parse(
        sender: 'VM-SBIBNK',
        body: 'Rs.499.00 debited from a/c XX1234 on 30-05-26 to AMAZON via UPI. Avl Bal Rs.1200',
        receivedAt: DateTime.now(),
      );
      expect(r, isNotNull);
      expect(r!.txn.amount, 499.0);
    });

    test('catches Amazon Pay / Juspay wallet debit', () {
      final r = SmsParser.parse(
        sender: 'JM-JUSPAY',
        body: 'Your Apay Wallet balance is debited for INR 36.00. '
            'Transaction Reference Number is 651729744124. '
            'If not you? call 180012001637 - SMS via Juspay',
        receivedAt: DateTime.now(),
      );
      expect(r, isNotNull);
      expect(r!.txn.amount, 36.0);
      expect(r.txn.isDebit, isTrue);
    });

    test('parses 4-digit amount without a comma (1200, not 120)', () {
      final r = SmsParser.parse(
        sender: 'JM-JUSPAY',
        body: 'Your Apay Wallet balance is debited for INR 1200.00. '
            'Transaction Reference Number is 651829849476.',
        receivedAt: DateTime.now(),
      );
      expect(r, isNotNull);
      expect(r!.txn.amount, 1200.0);
    });

    test('parses Indian-grouped lakh amount', () {
      final r = SmsParser.parse(
        sender: 'VM-SBIBNK',
        body: 'INR 1,50,000 credited to A/c XX5678 - Salary',
        receivedAt: DateTime.now(),
      );
      expect(r, isNotNull);
      expect(r!.txn.amount, 150000.0);
    });

    test('ignores debit-card limit/permission change notice', () {
      final r = SmsParser.parse(
        sender: 'VM-BOBSMS',
        body: 'Your request via bob World to change Daily Tran. Limit/Usage '
            'Permission for Debit Card ending with 9177 is processed '
            'successfully. ATM: Rs.50,000.00 POS/ECOM: Rs.2,00,000.00 '
            'Contactless: Disabled',
        receivedAt: DateTime.now(),
      );
      expect(r, isNull);
    });
  });

  testWidgets('renders a trivial widget', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: Text('ok'))));
    expect(find.text('ok'), findsOneWidget);
  });
}
