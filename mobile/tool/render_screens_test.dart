// Dev tool, not part of the test suite: renders every main screen — light
// and dark — with the real fonts and realistic fake data, to PNGs you can
// review without a phone.
//
//   flutter test tool/render_screens_test.dart --update-goldens
//
// Output goes to $AERIS_SHOTS_DIR, or tool/shots/ (git-ignored) if unset.
// The "failures" it prints are platform plugins (SMS, widgets, Firebase)
// that don't exist in a headless run; every PNG is still written.
//
// ignore_for_file: invalid_use_of_visible_for_testing_member
import 'dart:io';
import 'dart:math' as math;

import 'package:aeris_expense/core/routes.dart';
import 'package:aeris_expense/core/theme.dart';
import 'package:aeris_expense/models/budget.dart';
import 'package:aeris_expense/models/category.dart';
import 'package:aeris_expense/models/goal.dart';
import 'package:aeris_expense/models/loan.dart';
import 'package:aeris_expense/models/split.dart';
import 'package:aeris_expense/models/subscription.dart';
import 'package:aeris_expense/models/transaction.dart';
import 'package:aeris_expense/models/user_profile.dart';
import 'package:aeris_expense/providers/accounts_provider.dart';
import 'package:aeris_expense/providers/auth_provider.dart';
import 'package:aeris_expense/providers/budgets_provider.dart';
import 'package:aeris_expense/providers/goals_provider.dart';
import 'package:aeris_expense/providers/loans_provider.dart';
import 'package:aeris_expense/providers/prefs_data_provider.dart';
import 'package:aeris_expense/providers/privacy_provider.dart';
import 'package:aeris_expense/providers/split_provider.dart';
import 'package:aeris_expense/providers/subscriptions_provider.dart';
import 'package:aeris_expense/providers/transactions_provider.dart';
import 'package:aeris_expense/core/ph_icons.dart';
import 'package:aeris_expense/screens/home/root_shell.dart';
import 'package:aeris_expense/screens/transactions/add_transaction_screen.dart';
import 'package:aeris_expense/screens/transactions/transaction_detail_screen.dart';
import 'package:aeris_expense/widgets/aeris_toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _outDir = Platform.environment['AERIS_SHOTS_DIR'] ??
    '${Directory.current.path}/tool/shots';

/// Material Icons ship with the Flutter SDK, next to the test runner:
/// <sdk>/bin/cache/artifacts/engine/<platform>/flutter_tester(.exe).
String get _materialIcons {
  final artifacts = File(Platform.resolvedExecutable).parent.parent.parent;
  final font =
      File('${artifacts.path}/material_fonts/materialicons-regular.otf');
  if (!font.existsSync()) {
    throw StateError('Material Icons font not found at ${font.path}');
  }
  return font.path;
}

Future<void> _family(String name, List<String> files) async {
  final loader = FontLoader(name);
  for (final f in files) {
    final bytes = File(f).readAsBytesSync();
    loader.addFont(Future.value(ByteData.view(bytes.buffer)));
  }
  await loader.load();
}

// ── Fake data ─────────────────────────────────────────────────
final _rnd = math.Random(7);
int _id = 0;

Transaction _t(double amount, DateTime when, String cat, String merchant,
        {bool credit = false,
        String? vpa,
        String? account,
        bool sms = false}) =>
    Transaction(
      id: 't${_id++}',
      amount: amount,
      direction: credit ? TxnDirection.credit : TxnDirection.debit,
      timestamp: when,
      categoryId: cat,
      merchant: merchant,
      upiVpa: vpa,
      account: account,
      source: sms ? TxnSource.sms : TxnSource.manual,
      reviewed: !sms,
    );

List<Transaction> _fakeTxns(DateTime now) {
  final out = <Transaction>[];
  DateTime at(int monthsBack, int day, int hour, int minute) =>
      DateTime(now.year, now.month - monthsBack, day, hour, minute);
  double r(double lo, double hi) =>
      (lo + _rnd.nextDouble() * (hi - lo)).roundToDouble();

  for (var back = 2; back >= 0; back--) {
    final lastDay =
        back == 0 ? now.day : DateTime(now.year, now.month - back + 1, 0).day;
    final scale = back == 0 ? 0.92 : (back == 1 ? 1.08 : 1.0);
    out.add(_t(85000, at(back, 1, 10, 5), 'salary', 'Salary · Acme Corp',
        credit: true, account: '4521'));
    final rent = _t(18000, at(back, math.min(3, lastDay), 9, 30), 'rent',
        'Rent · Mr. Sharma',
        vpa: 'sharma@okicici');
    // Rent is split three ways with the flatmates; Rahul has paid back.
    final shared = rent.copyWith(
        split: SplitInfo(groupId: 'flat', shares: [
      const SplitShare(name: 'Rahul', amount: 6000, received: 6000),
      SplitShare(name: 'Amit', amount: 6000, received: back == 0 ? 0 : 6000),
    ]));
    out.add(shared);
    out.add(_t(6000, at(back, math.min(4, lastDay), 20, 15), 'rent', 'Rahul',
            credit: true, vpa: 'rahul.k@okaxis')
        .copyWith(settles: shared.id, settlesMember: 'Rahul'));
    if (lastDay >= 5) {
      out.add(_t(649, at(back, 5, 7, 0), 'entertainment', 'Netflix',
          account: '4521'));
      out.add(_t(399, at(back, 5, 8, 12), 'bills', 'Airtel recharge',
          vpa: 'airtel@ybl'));
    }
    if (lastDay >= 12) {
      out.add(_t(1450, at(back, 12, 18, 40), 'bills', 'BESCOM electricity',
          vpa: 'bescom@okaxis'));
    }
    for (var d = 1; d <= lastDay; d++) {
      if (d % 2 == 0) {
        out.add(_t((r(220, 640) * scale).roundToDouble(), at(back, d, 20, 15),
            'food', d % 4 == 0 ? 'Swiggy' : 'Zomato',
            vpa: d % 4 == 0 ? 'swiggy@ybl' : 'zomato@okhdfcbank'));
      }
      if (d % 3 == 0) {
        out.add(_t((r(160, 420) * scale).roundToDouble(), at(back, d, 9, 10),
            'travel', d % 6 == 0 ? 'Ola' : 'Uber',
            vpa: 'uber@okicici'));
      }
      if (d % 7 == 1) {
        out.add(_t((r(1100, 2300) * scale).roundToDouble(), at(back, d, 11, 20),
            'groceries', 'BigBasket',
            vpa: 'bigbasket@ybl'));
      }
      if (d % 5 == 2) {
        out.add(_t(r(120, 380), at(back, d, 16, 45), 'food', 'Starbucks',
            account: '4521'));
      }
    }
    if (lastDay >= 9) {
      out.add(_t(
          back == 0 ? 2499 : 1299, at(back, 9, 22, 5), 'shopping', 'Amazon',
          vpa: 'amazon@apl'));
    }
    if (lastDay >= 17) {
      out.add(_t(
          back == 0 ? 2199 : 899, at(back, 17, 19, 30), 'shopping', 'Myntra',
          vpa: 'myntra@ybl'));
      out.add(_t(560, at(back, 17, 13, 10), 'health', 'Apollo Pharmacy',
          vpa: 'apollo@okaxis'));
    }
  }
  // Two fresh bank-SMS imports waiting for review.
  out.add(_t(1200, now.subtract(const Duration(hours: 3)), 'travel', 'UBER',
      vpa: 'uber@okicici', sms: true));
  out.add(_t(486, now.subtract(const Duration(hours: 1)), 'food', 'Swiggy',
      vpa: 'swiggy@ybl', sms: true));
  return out..sort((a, b) => b.timestamp.compareTo(a.timestamp));
}

List<Budget> _fakeBudgets(DateTime now) => [
      Budget(
          id: 'b0',
          categoryId: Budget.totalId,
          monthlyCap: 60000,
          updatedAt: now),
      Budget(id: 'b1', categoryId: 'food', monthlyCap: 9000, updatedAt: now),
      Budget(id: 'b2', categoryId: 'travel', monthlyCap: 5000, updatedAt: now),
      Budget(
          id: 'b3', categoryId: 'shopping', monthlyCap: 4000, updatedAt: now),
    ];

// ── Harness ───────────────────────────────────────────────────
Future<void> _app(WidgetTester tester,
    {required ThemeMode mode, bool empty = false}) async {
  final now = DateTime.now();
  final txns = empty ? <Transaction>[] : _fakeTxns(now);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      currentUserIdProvider.overrideWithValue('u1'),
      userProfileProvider.overrideWith((ref) async => UserProfile(
            uid: 'u1',
            email: 'shivang@example.com',
            displayName: 'Shivang Rastogi',
            createdAt: DateTime(2026, 1, 1),
            monthlyIncome: 85000,
          )),
      transactionsStreamProvider.overrideWith((ref) => Stream.value(txns)),
      budgetsStreamProvider.overrideWith(
          (ref) => Stream.value(empty ? const <Budget>[] : _fakeBudgets(now))),
      goalsStreamProvider.overrideWith((ref) => Stream.value([
            Goal(
                id: 'g1',
                title: 'Goa trip',
                target: 40000,
                saved: 18000,
                emoji: '🏖️',
                createdAt: DateTime(2026, 6, 1),
                deadline: DateTime(2026, 12, 20)),
            Goal(
                id: 'g2',
                title: 'Emergency fund',
                target: 150000,
                saved: 62000,
                emoji: '🛟',
                createdAt: DateTime(2026, 2, 1)),
          ])),
      loansStreamProvider.overrideWith((ref) => Stream.value([
            Loan(
                id: 'l1',
                person: 'Rahul',
                amount: 1500,
                createdAt: now.subtract(const Duration(days: 4))),
          ])),
      subscriptionsStreamProvider.overrideWith((ref) => Stream.value(const [
            Subscription(
                id: 's1',
                name: 'Netflix',
                amount: 649,
                categoryId: 'entertainment',
                day: 5),
            Subscription(
                id: 's2',
                name: 'Rent',
                amount: 18000,
                categoryId: 'rent',
                day: 3),
            Subscription(
                id: 's3',
                name: 'Airtel postpaid',
                amount: 399,
                categoryId: 'bills',
                day: 5),
            Subscription(
                id: 's4',
                name: 'Spotify',
                amount: 119,
                categoryId: 'entertainment',
                day: 1),
          ])),
      blockedSendersProvider.overrideWith((ref) => Stream.value(<String>{})),
      customCategoriesProvider
          .overrideWith((ref) => Stream.value(const <ExpenseCategory>[])),
      accountNamesProvider.overrideWith(
          (ref) => Stream.value(const {'4521': 'HDFC salary'})),
      splitGroupsProvider.overrideWith((ref) => Stream.value(const [
            SplitGroup(
                id: 'flat',
                name: 'Flat',
                members: [SplitMember(name: 'Rahul'), SplitMember(name: 'Amit')],
                autoPayees: ['sharma@okicici']),
          ])),
      openingBalancesProvider
          .overrideWith((ref) => Stream.value(<String, double>{})),
    ],
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      navigatorKey: appNavigatorKey,
      theme: buildAerisTheme(Brightness.light),
      darkTheme: buildAerisTheme(Brightness.dark),
      themeMode: mode,
      onGenerateRoute: AppRoutes.onGenerateRoute,
      home: const RootShell(),
    ),
  ));
  await _settle(tester);
}

/// Layout overflows seen while rendering (big-font / small-phone checks).
final overflows = <String>[];
String _current = '';

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 250));
  }
  // Keep overflow reports; swallow the rest (platform plugins that don't
  // exist in tests).
  Object? e;
  while ((e = tester.takeException()) != null) {
    final s = e.toString();
    if (s.contains('overflowed')) {
      overflows.add('$_current: ${s.split('\n').first}');
    }
  }
}

Future<void> _shot(WidgetTester tester, String name) async {
  await expectLater(find.byType(MaterialApp),
      matchesGoldenFile(Uri.file('$_outDir/$name.png')));
}

/// Flutter's own system channels speak JSON, not the standard codec.
const _jsonChannels = {
  'flutter/platform',
  'flutter/textinput',
  'flutter/navigation',
  'flutter/keyevent',
  'flutter/mousecursor',
  'flutter/spellcheck',
  'flutter/scribe',
};

void main() {
  setUpAll(() async {
    await _family('PlusJakartaSans', [
      for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold'])
        'assets/google_fonts/PlusJakartaSans-$w.ttf',
    ]);
    await _family('MaterialIcons', [_materialIcons]);
    // Phosphor icons (package fonts are addressed as packages/<pkg>/<family>).
    final ph = '${Platform.environment['LOCALAPPDATA']}/Pub/Cache/hosted/pub.dev/phosphor_flutter-2.1.0/lib/fonts';
    for (final (fam, file) in [('Regular', 'Phosphor'), ('Fill', 'Phosphor-Fill'), ('Bold', 'Phosphor-Bold')]) {
      await _family('packages/phosphor_flutter/Phosphor$fam', ['$ph/$file.ttf']);
    }
    // Every platform channel answers "null" instead of throwing.
    TestDefaultBinaryMessengerBinding
            .instance.defaultBinaryMessenger.allMessagesHandler =
        (channel, handler, message) async => _jsonChannels.contains(channel)
            ? const JSONMethodCodec().encodeSuccessEnvelope(null)
            : const StandardMethodCodec().encodeSuccessEnvelope(null);
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({'onboarded': true});
    debugDisableShadows = false;
  });
  tearDown(() => debugDisableShadows = true);

  Future<void> phone(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390 * 2.0, 844 * 2.0);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
  }

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    final tag = mode.name;

    testWidgets('home $tag', (tester) async {
      await phone(tester);
      await _app(tester, mode: mode);
      await _shot(tester, 'home_$tag');
    });

    testWidgets('home scrolled $tag', (tester) async {
      await phone(tester);
      await _app(tester, mode: mode);
      await tester.drag(find.byType(ListView).first, const Offset(0, -420));
      await _settle(tester);
      await _shot(tester, 'home_scrolled_$tag');
    });

    for (final tab in ['Activity', 'Insights', 'Me']) {
      testWidgets('$tab $tag', (tester) async {
        await phone(tester);
        await _app(tester, mode: mode);
        await tester.tap(find.text(tab).first);
        await _settle(tester);
        await _shot(tester, '${tab.toLowerCase()}_$tag');
      });
    }

    testWidgets('toast $tag', (tester) async {
      await phone(tester);
      await _app(tester, mode: mode);
      ScaffoldMessenger.of(tester.element(find.byType(RootShell))).showToast(
          SnackBar(
              content: const Text('Expense of ₹486 saved'),
              action: SnackBarAction(label: 'Add another', onPressed: () {})));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await _shot(tester, 'toast_$tag');
      await tester.pump(const Duration(seconds: 6));
    });

    testWidgets('radial menu $tag', (tester) async {
      await phone(tester);
      await _app(tester, mode: mode);
      await tester.longPress(find.byIcon(PhosphorIconsBold.plus).last);
      await _settle(tester);
      await _shot(tester, 'radial_$tag');
    });

    testWidgets('add $tag', (tester) async {
      await phone(tester);
      await _app(tester, mode: mode);
      await tester.tap(find.byIcon(Icons.add_rounded));
      await _settle(tester);
      await _shot(tester, 'add_$tag');
    });
  }

  testWidgets('home first run', (tester) async {
    await phone(tester);
    await _app(tester, mode: ThemeMode.light, empty: true);
    await _shot(tester, 'home_first_run_light');
  });

  for (final sub in ['Lent', 'Subscriptions']) {
    testWidgets('activity $sub', (tester) async {
      await phone(tester);
      await _app(tester, mode: ThemeMode.light);
      await tester.tap(find.text('Activity').first);
      await _settle(tester);
      await tester.tap(find.text(sub).first);
      await _settle(tester);
      await _shot(tester, 'activity_${sub.toLowerCase()}_light');
    });
  }

  // Tablet · landscape (1280 × 800 dp): rail, two-column Home, list–detail.
  Future<void> tablet(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280 * 2.0, 800 * 2.0);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
  }

  testWidgets('tablet home', (tester) async {
    await tablet(tester);
    await _app(tester, mode: ThemeMode.dark);
    await _shot(tester, 'tablet_home_dark');
  });

  testWidgets('tablet activity detail', (tester) async {
    await tablet(tester);
    await _app(tester, mode: ThemeMode.light);
    await tester.tap(find.text('Activity').first);
    await _settle(tester);
    await tester.tap(find.textContaining('Food ·').first);
    await _settle(tester);
    await _shot(tester, 'tablet_activity_light');
  });

  testWidgets('tablet me', (tester) async {
    await tablet(tester);
    await _app(tester, mode: ThemeMode.dark);
    await tester.tap(find.text('Me').first);
    await _settle(tester);
    await _shot(tester, 'tablet_me_dark');
  });

  testWidgets('tablet insights', (tester) async {
    await tablet(tester);
    await _app(tester, mode: ThemeMode.light);
    await tester.tap(find.text('Insights').first);
    await _settle(tester);
    await _shot(tester, 'tablet_insights_light');
  });

  // The payback row ("Rahul · Payback · time · Google Pay") must read as
  // plain text — never struck through.
  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets('activity payback row ${mode.name}', (tester) async {
      await phone(tester);
      await _app(tester, mode: mode);
      await tester.tap(find.text('Activity').first);
      await _settle(tester);
      final payback = find.textContaining('Payback ·');
      // The list builds lazily: scroll until the row exists, then bring it
      // up to mid-screen.
      final list = find.byType(Scrollable).last;
      for (var i = 0; i < 40 && payback.evaluate().isEmpty; i++) {
        await tester.drag(list, const Offset(0, -300));
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.drag(list, const Offset(0, -150));
      await _settle(tester);
      expect(payback, findsWidgets);
      // visitChildren walks the span itself and every descendant.
      bool struck(InlineSpan s) {
        var hit = false;
        s.visitChildren((c) {
          hit = c.style?.decoration?.contains(TextDecoration.lineThrough) ??
              false;
          return !hit;
        });
        return hit;
      }

      final struckTexts = tester
          .widgetList<RichText>(find.byType(RichText))
          .where((r) => struck(r.text))
          .map((r) => r.text.toPlainText())
          .toList();
      expect(struckTexts, isEmpty, reason: 'struck-through text on Activity');
      await _shot(tester, 'activity_payback_${mode.name}');
    });
  }

  // Hide amounts, scroll Activity (day headers get built masked), show them
  // again: no day total may stay masked.
  testWidgets('activity unhide day totals', (tester) async {
    await phone(tester);
    await _app(tester, mode: ThemeMode.light);
    await tester.tap(find.text('Activity').first);
    await _settle(tester);
    final container =
        ProviderScope.containerOf(tester.element(find.byType(RootShell)));
    Future<void> toggle() async {
      await container.read(amountHiddenProvider.notifier).toggle();
      await _settle(tester);
    }

    final list = find.byType(Scrollable).last;
    await toggle(); // hide
    for (var i = 0; i < 6; i++) {
      await tester.drag(list, const Offset(0, -400));
      await tester.pump(const Duration(milliseconds: 100));
    }
    await toggle(); // show
    final masked = find.textContaining('••••');
    for (var i = 0; i < 12; i++) {
      expect(masked, findsNothing, reason: 'masked amount after unhide');
      await tester.drag(list, const Offset(0, 300));
      await tester.pump(const Duration(milliseconds: 100));
    }
  });

  // Money in from a friend: the edit form's "Loan paid back" lists the
  // loans they owe, and a linked repayment shows what's left.
  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets('loan payback ${mode.name}', (tester) async {
      await phone(tester);
      await _app(tester, mode: mode);
      final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
      final credit = _t(500, DateTime.now(), 'transfer', 'Rahul Kumar',
          credit: true, vpa: 'rahul.k@okaxis');
      nav.push(MaterialPageRoute(
          builder: (_) => AddTransactionScreen(existing: credit)));
      await _settle(tester);
      await tester.tap(find.text('Loan paid back'));
      await _settle(tester);
      await _shot(tester, 'loan_pick_${mode.name}');
      nav.pop();
      nav.push(MaterialPageRoute(
          builder: (_) => TransactionDetailScreen(
              txn: credit.copyWith(
                  settles: '${Transaction.loanRepay}l1',
                  settlesMember: 'Rahul'))));
      await _settle(tester);
      await _shot(tester, 'loan_linked_${mode.name}');
    });
  }

  const routes = {
    'budgets': AppRoutes.budgets,
    'goals': AppRoutes.goals,
    'accounts': AppRoutes.accounts,
    'shared': AppRoutes.shared,
    'people': AppRoutes.people,
    'account': AppRoutes.account,
    'categories': AppRoutes.categories,
    'about': AppRoutes.about,
    'loans': AppRoutes.loans,
    'subscriptions': AppRoutes.subscriptions,
    'settings': AppRoutes.settings,
    'notifications': AppRoutes.notifications,
    'sms_review': AppRoutes.smsReview,
    'voice': AppRoutes.voice,
    'screenshot': AppRoutes.screenshot,
    'quick_add': AppRoutes.quickAdd,
    'wrapped': AppRoutes.wrapped,
    'aeris_world': AppRoutes.aerisWorld,
    'village': AppRoutes.village,
    'widgets': AppRoutes.widgets,
    'import': AppRoutes.importStatement,
    'assistant': AppRoutes.assistant,
    'edit_profile': AppRoutes.editProfile,
    'login': AppRoutes.login,
    'signup': AppRoutes.signup,
    'bills': AppRoutes.bills,
    'net_worth': AppRoutes.netWorth,
    'report_card': AppRoutes.reportCard,
  };
  for (final e in routes.entries) {
    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      testWidgets('route ${e.key} ${mode.name}', (tester) async {
        await phone(tester);
        await _app(tester, mode: mode);
        tester
            .state<NavigatorState>(find.byType(Navigator).first)
            .pushNamed(e.value);
        await _settle(tester);
        await _shot(tester, 'route_${e.key}_${mode.name}');
      });
    }
  }

  testWidgets('activity plain-language search', (tester) async {
    await phone(tester);
    await _app(tester, mode: ThemeMode.dark);
    await tester.tap(find.text('Activity').first);
    await _settle(tester);
    await tester.enterText(
        find.byType(TextField).first, 'above 1000 last month');
    await tester.pump(const Duration(milliseconds: 300));
    await _settle(tester);
    await _shot(tester, 'activity_search_dark');
  });

  // ── Stress: small phone + large system font ─────────────────
  // Every overflow is logged (file:line) to overflow_report.txt.
  const stressRoutes = {
    'home': null,
    'activity': 'Activity',
    'insights': 'Insights',
    'me': 'Me',
    'add': AppRoutes.addTxn,
    'budgets': AppRoutes.budgets,
    'bills': AppRoutes.bills,
    'net_worth': AppRoutes.netWorth,
    'report_card': AppRoutes.reportCard,
    'settings': AppRoutes.settings,
    'sms_review': AppRoutes.smsReview,
    'goals': AppRoutes.goals,
    'accounts': AppRoutes.accounts,
    'subscriptions': AppRoutes.subscriptions,
    'notifications': AppRoutes.notifications,
  };
  for (final (label, size, scale) in [
    ('small', const Size(320, 640), 1.0),
    ('bigfont', const Size(390, 844), 1.3),
  ]) {
    for (final e in stressRoutes.entries) {
      testWidgets('stress $label ${e.key}', (tester) async {
        tester.view.physicalSize = size * 2.0;
        tester.view.devicePixelRatio = 2.0;
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.view.reset);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        _current = '$label/${e.key}';
        final orig = FlutterError.onError;
        FlutterError.onError = (d) {
          final s = d.exceptionAsString();
          if (s.contains('overflowed')) {
            final where = RegExp(r'lib/[\w/]+\.dart:\d+')
                .firstMatch(d.toString())
                ?.group(0);
            overflows
                .add('$_current: ${s.split('\n').first} @ ${where ?? '?'}');
          } else {
            orig?.call(d);
          }
        };
        try {
          await _app(tester, mode: ThemeMode.dark);
          final v = e.value;
          if (v != null && !v.startsWith('/')) {
            await tester.tap(find.text(v).first);
            await _settle(tester);
          } else if (v != null) {
            tester
                .state<NavigatorState>(find.byType(Navigator).first)
                .pushNamed(v);
            await _settle(tester);
          }
          await _shot(tester, 'stress_${label}_${e.key}');
        } finally {
          FlutterError.onError = orig;
        }
      });
    }
  }

  tearDownAll(() {
    File('$_outDir/overflow_report.txt').writeAsStringSync(overflows.isEmpty
        ? 'No overflows.\n'
        : '${overflows.toSet().join('\n')}\n');
  });
}
