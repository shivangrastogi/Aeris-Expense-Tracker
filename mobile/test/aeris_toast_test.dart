import 'package:aeris_expense/widgets/aeris_toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

late ScaffoldMessengerState _messenger;

Future<void> _pump(WidgetTester tester) async {
  await tester.pumpWidget(MaterialApp(
    navigatorKey: appNavigatorKey,
    home: Scaffold(
      body: Builder(builder: (context) {
        _messenger = ScaffoldMessenger.of(context);
        return const SizedBox.expand();
      }),
    ),
  ));
}

SnackBar _bar(String text, {VoidCallback? onUndo}) => SnackBar(
      content: Text(text),
      action: onUndo == null
          ? null
          : SnackBarAction(label: 'Undo', onPressed: onUndo),
    );

void main() {
  testWidgets('a toast WITH an action still dismisses itself',
      (tester) async {
    await _pump(tester);
    final c = _messenger.showToast(_bar('Saved', onUndo: () {}));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Saved'), findsOneWidget);
    expect(find.byIcon(Icons.close_rounded), findsOneWidget);

    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Saved'), findsNothing);
    expect(await c.closed, SnackBarClosedReason.timeout);
  });

  testWidgets('the × closes it right away', (tester) async {
    await _pump(tester);
    final c = _messenger.showToast(_bar('Deleted'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Deleted'), findsNothing);
    expect(await c.closed, SnackBarClosedReason.dismiss);
  });

  testWidgets('the action runs and reports "action"', (tester) async {
    await _pump(tester);
    var undone = false;
    final c = _messenger.showToast(_bar('Deleted', onUndo: () => undone = true));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('UNDO'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(undone, isTrue);
    expect(find.text('Deleted'), findsNothing);
    expect(await c.closed, SnackBarClosedReason.action);
  });

  testWidgets('a new toast replaces the old one instantly', (tester) async {
    await _pump(tester);
    final first = _messenger.showToast(_bar('First'));
    await tester.pump(const Duration(milliseconds: 300));
    _messenger.showToast(_bar('Second'));
    await tester.pump();
    expect(find.text('First'), findsNothing);
    expect(find.text('Second'), findsOneWidget);
    expect(await first.closed, SnackBarClosedReason.hide);
    await tester.pump(const Duration(seconds: 5));
  });
}
