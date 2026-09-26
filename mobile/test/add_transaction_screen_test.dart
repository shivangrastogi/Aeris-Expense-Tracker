import 'package:aeris_expense/models/transaction.dart';
import 'package:aeris_expense/providers/accounts_provider.dart';
import 'package:aeris_expense/providers/auth_provider.dart';
import 'package:aeris_expense/providers/budgets_provider.dart';
import 'package:aeris_expense/providers/transactions_provider.dart';
import 'package:aeris_expense/screens/transactions/add_transaction_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final history = [
    Transaction(
        id: 'r1',
        amount: 20,
        direction: TxnDirection.debit,
        timestamp: DateTime.now().subtract(const Duration(days: 1)),
        categoryId: 'food',
        merchant: 'Chai Point'),
  ];
  await tester.pumpWidget(ProviderScope(
    overrides: [
      currentUserIdProvider.overrideWithValue('u1'),
      transactionsStreamProvider.overrideWith((_) => Stream.value(history)),
      budgetsStreamProvider.overrideWith((_) => Stream.value(const [])),
      accountsProvider.overrideWithValue(const []),
    ],
    child: const MaterialApp(home: AddTransactionScreen()),
  ));
  await tester.pumpAndSettle();
}

Finder get _amountField => find.byType(TextField).first;

void main() {
  for (final size in const [Size(360, 640), Size(412, 915)]) {
    testWidgets(
        'builds on ${size.width.toInt()}×${size.height.toInt()} '
        'with Save pinned on screen', (tester) async {
      await _pump(tester, size);
      expect(tester.takeException(), isNull);
      expect(find.text('Save expense'), findsOneWidget);
      expect(find.text('Today'), findsOneWidget);
      final save = tester.getRect(find.text('Save expense'));
      expect(save.bottom, lessThanOrEqualTo(size.height));
    });
  }

  testWidgets('no calculator keypad — amount uses the text field',
      (tester) async {
    await _pump(tester, const Size(412, 915));
    // Digit keys of the old in-app keypad must be gone.
    expect(find.text('7'), findsNothing);
    await tester.enterText(_amountField, '250');
    expect(find.text('250'), findsOneWidget);
  });

  testWidgets('operator rail inserts symbols, shows the sum, keeps focus',
      (tester) async {
    await _pump(tester, const Size(412, 915));
    await tester.enterText(_amountField, '120');
    await tester.pump();
    await tester.tap(find.text('+'));
    await tester.pump();
    final field = tester.widget<TextField>(_amountField);
    expect(field.controller!.text, '120+');
    expect(field.focusNode!.hasFocus, isTrue); // keyboard stays up
    field.controller!.value = const TextEditingValue(
        text: '120+45', selection: TextSelection.collapsed(offset: 6));
    await tester.pump();
    expect(find.text('= ₹ 165'), findsOneWidget);
    // Tapping the result collapses the expression.
    await tester.tap(find.text('= ₹ 165'));
    await tester.pump();
    expect(field.controller!.text, '165');
  });

  testWidgets('back with an amount entered asks before discarding',
      (tester) async {
    await _pump(tester, const Size(412, 915));
    await tester.enterText(_amountField, '7');
    await tester.pump();
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(find.text('Discard this expense?'), findsOneWidget);
  });

  testWidgets('empty save shows an inline hint, not a dialog', (tester) async {
    await _pump(tester, const Size(412, 915));
    await tester.tap(find.text('Save expense'));
    await tester.pump();
    expect(find.text('Enter an amount to save'), findsOneWidget);
  });
}
