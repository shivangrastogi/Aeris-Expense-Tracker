import 'package:aeris_expense/services/sync_outbox.dart';
import 'package:aeris_expense/widgets/sync_status.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('JSON round-trip keeps Timestamps and nested data', () {
    final ts = Timestamp.fromMillisecondsSinceEpoch(1758800000000);
    final out = SyncOutbox.roundTrip({
      'timestamp': ts,
      'enc': 'abc.def.ghi',
      'v': 1,
      'nested': {
        'list': [1, 'x', ts]
      },
    });
    expect(out['timestamp'], ts);
    expect(out['enc'], 'abc.def.ghi');
    expect(out['v'], 1);
    expect((out['nested'] as Map)['list'], [1, 'x', ts]);
  });

  group('SyncShell', () {
    final box = SyncOutbox.instance;
    tearDown(() => box.debugSetStats(count: 0, bytes: 0, online: true));

    Future<void> pump(WidgetTester tester,
        {required VoidCallback onTap}) async {
      final nav = GlobalKey<NavigatorState>();
      await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
          navigatorKey: nav,
          builder: (context, child) =>
              SyncShell(navigatorKey: nav, signedIn: true, child: child!),
          home: Scaffold(
            body: Center(
                child: ElevatedButton(
                    onPressed: onTap, child: const Text('App button'))),
          ),
        ),
      ));
    }

    testWidgets('offline strip shows pending count, app stays usable',
        (tester) async {
      var taps = 0;
      await pump(tester, onTap: () => taps++);
      box.debugSetStats(count: 3, bytes: 2048, online: false);
      await tester.pump();
      expect(
          find.text('Offline · 3 changes saved on this phone'), findsOneWidget);
      await tester.tap(find.text('App button'));
      expect(taps, 1);
    });

    testWidgets('showing the strip keeps open screens (no navigator remount)',
        (tester) async {
      final nav = GlobalKey<NavigatorState>();
      await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
          navigatorKey: nav,
          builder: (context, child) =>
              SyncShell(navigatorKey: nav, signedIn: true, child: child!),
          home: const Scaffold(body: Text('Home')),
        ),
      ));
      nav.currentState!.push(MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('Pushed screen'))));
      await tester.pumpAndSettle();
      box.debugSetStats(count: 2, bytes: 100, online: false);
      await tester.pumpAndSettle();
      expect(find.text('Pushed screen'), findsOneWidget);
      box.debugSetStats(count: 0, bytes: 0, online: true);
      await tester.pumpAndSettle();
      expect(find.text('Pushed screen'), findsOneWidget);
    });

    testWidgets('crossing 80% raises the attention dialog', (tester) async {
      await pump(tester, onTap: () {});
      box.debugSetStats(
          count: 900,
          bytes: (SyncOutbox.limitBytes * 0.82).round(),
          online: false);
      await tester.pumpAndSettle();
      expect(find.text('Please connect to the internet'), findsOneWidget);
    });

    testWidgets('full outbox locks the app — only Refresh is tappable',
        (tester) async {
      var taps = 0;
      await pump(tester, onTap: () => taps++);
      box.debugSetStats(
          count: 5000, bytes: SyncOutbox.limitBytes + 10, online: false);
      await tester.pump();
      expect(find.byIcon(Icons.lock_rounded), findsOneWidget);
      expect(find.text('Connect to the internet'), findsOneWidget);
      expect(find.text('Refresh'), findsOneWidget);
      await tester.tap(find.text('App button'), warnIfMissed: false);
      expect(taps, 0, reason: 'the app underneath must not receive taps');

      // Once the backlog drains the lock lifts by itself.
      box.debugSetStats(count: 0, bytes: 0, online: true);
      await tester.pump();
      expect(find.byIcon(Icons.lock_rounded), findsNothing);
      await tester.tap(find.text('App button'));
      expect(taps, 1);
    });
  });
}
