import 'package:aeris_expense/utils/amount_input_formatter.dart';
import 'package:aeris_expense/widgets/discard_guard.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pushGuarded(WidgetTester tester, {required bool dirty}) async {
  await tester.pumpWidget(MaterialApp(
    home: Builder(
      builder: (ctx) => TextButton(
        onPressed: () => Navigator.of(ctx).push(MaterialPageRoute(
          builder: (_) => DiscardGuard(
            dirty: dirty,
            child: Scaffold(appBar: AppBar(title: const Text('Form'))),
          ),
        )),
        child: const Text('open'),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('clean form pops without asking', (tester) async {
    await _pushGuarded(tester, dirty: false);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Form'), findsNothing);
  });

  testWidgets('dirty form asks; Keep editing stays, Discard leaves',
      (tester) async {
    await _pushGuarded(tester, dirty: true);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Discard this entry?'), findsOneWidget);

    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();
    expect(find.text('Form'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(find.text('Form'), findsNothing);
  });

  testWidgets('guard also protects a bottom sheet', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (ctx) => TextButton(
          onPressed: () => showModalBottomSheet<void>(
            context: ctx,
            // As in the Lent sheet: drag-dismiss would bypass the guard.
            enableDrag: false,
            builder: (_) => const DiscardGuard(
                dirty: true,
                child: SizedBox(height: 200, child: Text('Sheet'))),
          ),
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // Tapping the scrim above the sheet asks first.
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();
    expect(find.text('Discard this entry?'), findsOneWidget);
    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();
    expect(find.text('Sheet'), findsOneWidget);

    // Swiping it down must not silently drop entered data either.
    await tester.drag(find.text('Sheet'), const Offset(0, 500));
    await tester.pumpAndSettle();
    expect(find.text('Sheet'), findsOneWidget);

    // System back asks, and Discard really closes it.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(find.text('Sheet'), findsNothing);
  });

  test('amount formatter', () {
    const f = AmountInputFormatter();
    TextEditingValue fmt(String old, String next) => f.formatEditUpdate(
        TextEditingValue(text: old), TextEditingValue(text: next));
    expect(fmt('12', '12.5').text, '12.5');
    expect(fmt('12.50', '12.505').text, '12.50'); // max 2 decimals
    expect(fmt('12', '12a').text, '12');
    expect(fmt('1.2', '1.2.').text, '1.2');
    expect(fmt('', '1,200').text, '1200');
    expect(fmt('', '.5').text, '0.5');
  });
}
