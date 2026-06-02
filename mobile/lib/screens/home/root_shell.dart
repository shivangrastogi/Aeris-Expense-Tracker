import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/routes.dart';
import '../../services/sms_service.dart';
import '../../services/sms_import_service.dart';
import '../../services/widget_service.dart';
import '../../providers/analytics_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/budgets_provider.dart';
import '../../providers/transactions_provider.dart';
import '../analytics/analytics_screen.dart';
import '../budgets/budgets_screen.dart';
import '../onboarding/onboarding_screen.dart';
import '../insights/insights_screen.dart';
import '../profile/profile_screen.dart';
import '../transactions/transactions_screen.dart';
import 'home_screen.dart';

class RootShell extends ConsumerStatefulWidget {
  const RootShell({super.key});

  @override
  ConsumerState<RootShell> createState() => _RootShellState();
}

class _RootShellState extends ConsumerState<RootShell> {
  int _idx = 0;

  final _pages = const [
    HomeScreen(),
    TransactionsScreen(),
    AnalyticsScreen(),
    BudgetsScreen(),
    InsightsScreen(),
    ProfileScreen(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _wireSms();
      if (!await OnboardingScreen.isDone() && mounted) {
        Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => const OnboardingScreen(), fullscreenDialog: true));
      }
    });
  }

  /// Once the user is signed in, kick the SMS listener so any new bank
  /// alert is auto-saved as a transaction. Backfill the last 30 days
  /// on first run only (the dedupe ledger in Firestore prevents repeats).
  Future<void> _wireSms() async {
    final uid = ref.read(currentUserIdProvider);
    if (uid == null) return;
    // Persist uid so the background SMS isolate knows whose data to write.
    (await SharedPreferences.getInstance()).setString('current_uid', uid);
    if (!await SmsService.instance.hasPermission()) return;
    // Live incoming SMS → persist immediately.
    await SmsService.instance.startLiveListening(onTxn: (p) => _persist(uid, p));
    // Controlled startup backfill (last 30 days) — batched + progress-reported
    // so it never floods the UI.
    final blocked = ref.read(blockedSendersProvider).valueOrNull ?? const {};
    await SmsImportService.instance.backfill(
      uid,
      blocked: blocked,
      days: 30,
      incremental: true, // only scan SMS since the last sync — no redundancy
      onProgress: (done, total) {
        if (!mounted) return;
        ref.read(importProgressProvider.notifier).state =
            done >= total ? null : (done: done, total: total);
      },
    );
  }

  Future<void> _persist(String uid, parsed) async {
    final blocked = ref.read(blockedSendersProvider).valueOrNull ?? const {};
    await SmsImportService.instance.persistOne(uid, parsed, blocked);
  }

  @override
  Widget build(BuildContext context) {
    // Keep the blocklist subscription warm so _persist sees live updates.
    ref.watch(blockedSendersProvider);
    // Push "budget left" to the home-screen widget whenever data changes.
    final analytics = ref.watch(analyticsProvider).valueOrNull;
    final budgets = ref.watch(budgetsStreamProvider).valueOrNull;
    if (analytics != null && budgets != null) {
      final target = budgets.fold<double>(0, (s, b) => s + b.monthlyCap);
      WidgetService.updateBudgetLeft(
        left: target - analytics.monthExpense,
        target: target,
        label: analytics.label,
      );
    }
    return Scaffold(
      body: IndexedStack(index: _idx, children: _pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _idx,
        onDestinationSelected: (i) => setState(() => _idx = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home),
            label: 'Home'),
          NavigationDestination(
            icon: Icon(Icons.list_alt_outlined), selectedIcon: Icon(Icons.list_alt),
            label: 'Txns'),
          NavigationDestination(
            icon: Icon(Icons.analytics_outlined), selectedIcon: Icon(Icons.analytics),
            label: 'Charts'),
          NavigationDestination(
            icon: Icon(Icons.savings_outlined), selectedIcon: Icon(Icons.savings),
            label: 'Budgets'),
          NavigationDestination(
            icon: Icon(Icons.tips_and_updates_outlined),
            selectedIcon: Icon(Icons.tips_and_updates),
            label: 'AI'),
          NavigationDestination(
            icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person),
            label: 'Me'),
        ],
      ),
      floatingActionButton: _idx == 1
          ? FloatingActionButton.extended(
              onPressed: () =>
                  Navigator.pushNamed(context, AppRoutes.addTxn),
              icon: const Icon(Icons.add),
              label: const Text('Add'),
            )
          : null,
    );
  }
}
