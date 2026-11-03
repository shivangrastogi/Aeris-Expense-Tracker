import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aeris_expense/core/ph_icons.dart';
import 'package:aeris_expense/models/category.dart';
import 'package:aeris_expense/models/custom_category.dart';
import 'package:aeris_expense/models/transaction.dart';
import 'package:aeris_expense/providers/accounts_provider.dart';
import 'package:aeris_expense/screens/auth/auth_widgets.dart';
import 'package:aeris_expense/services/sms_import_service.dart';
import 'package:aeris_expense/services/sms_parser.dart';

void main() {
  group('New-password rules', () {
    test('too short / letters only / digits only are refused', () {
      expect(passwordProblem('abc12'), isNotNull);
      expect(passwordProblem('abcdefgh'), isNotNull);
      expect(passwordProblem('12345678'), isNotNull);
    });
    test('8+ characters mixing letters and numbers is fine', () {
      expect(passwordProblem('rent2026ok'), isNull);
    });
  });

  group('Custom categories', () {
    tearDown(() => Categories.custom = const []);

    test('join the built-ins everywhere and resolve by id', () {
      final pets = CustomCategories.fromMap(
          'c_pets', {'label': 'Pets', 'icon': 1, 'color': 2});
      Categories.custom = [pets];
      expect(Categories.all.last.id, 'c_pets');
      expect(Categories.byId('c_pets').label, 'Pets');
    });

    test('an unknown / deleted category reads as "Other", not a custom one', () {
      Categories.custom = [
        CustomCategories.fromMap('c_x', {'label': 'X', 'icon': 0, 'color': 0}),
      ];
      expect(Categories.byId('gone').id, 'other');
    });

    test('icon and colour survive the round-trip', () {
      const c = ExpenseCategory(
          id: 'c_gym',
          label: 'Gym',
          icon: PhosphorIconsRegular.barbell,
          color: Color(0xFF2FA287));
      final back = CustomCategories.fromMap('c_gym', CustomCategories.toMap(c));
      expect(back.icon, c.icon);
      expect(back.color, c.color);
      expect(back.label, 'Gym');
    });
  });

  test('accounts show their nickname, keeping the masked number', () {
    final t = Transaction(
        id: 't1',
        amount: 100,
        direction: TxnDirection.debit,
        timestamp: DateTime(2026, 10, 1),
        categoryId: 'food',
        account: '4521');
    final s = summarizeAccounts([t], const {}, names: {'4521': 'HDFC salary'})
        .single;
    expect(s.label, 'HDFC salary');
    expect(s.nickname, 'HDFC salary');
    expect(accountLabel(s.key), 'A/C ••4521');
  });

  group('Auto-confirm', () {
    final now = DateTime(2026, 10, 12, 10);

    test('a clear card spend is confident enough to skip review', () {
      final p = SmsParser.parse(
          sender: 'JD-HDFCBK',
          body: 'Rs.1,250.00 spent on HDFC Bank Card x1234 at ZOMATO on '
              '12-10-26. Avl bal: Rs.23,456.00',
          receivedAt: now)!;
      expect(SmsImportService.isConfident(p, p.txn), isTrue);
    });

    test('a vague alert with no payee and category "other" waits for review', () {
      final p = SmsParser.parse(
          sender: 'JM-APAYIN',
          body: 'Your Apay Wallet balance is debited for INR 20.00. '
              'Transaction Reference Number is 652732468322.',
          receivedAt: now)!;
      expect(SmsImportService.isConfident(p, p.txn), isFalse);
    });
  });
}
