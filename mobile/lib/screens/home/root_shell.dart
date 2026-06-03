import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/routes.dart';
import '../../models/category.dart';
import '../../models/insight.dart';
import '../../models/transaction.dart';
import '../../services/notification_service.dart';
import '../../services/sms_service.dart';
import '../../services/sms_import_service.dart';
import '../../services/widget_service.dart';
import '../../providers/analytics_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/budgets_provider.dart';
import '../../providers/gamification_provider.dart';
import '../../providers/goals_provider.dart';
import '../../providers/insights_provider.dart';
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
    // Defer the (heavier) inbox backfill a couple of seconds so the dashboard
    // paints and becomes interactive FIRST — the scan + encrypt then runs
    // quietly in the background with a progress chip.
    Future.delayed(const Duration(seconds: 2), () async {
      if (!mounted) return;
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
    });
  }

  Future<void> _persist(String uid, parsed) async {
    final blocked = ref.read(blockedSendersProvider).valueOrNull ?? const {};
    await SmsImportService.instance.persistOne(uid, parsed, blocked);
  }

  /// Fire a single budget-risk notification per day when reminders are on and
  /// a budget is already over or projected to exceed within ~5 days.
  Future<void> _maybeAlertBudgets(List<BudgetProjection> projections) async {
    final prefs = await SharedPreferences.getInstance();
    if (!(prefs.getBool('reminders_on') ?? false)) return;
    final now = DateTime.now();
    final today = '${now.year}-${now.month}-${now.day}';
    if (prefs.getString('last_budget_alert') == today) return;
    final risky = projections
        .where((p) =>
            p.alreadyOver ||
            (p.willExceed && (p.daysUntilExceed ?? 99) <= 5))
        .toList();
    if (risky.isEmpty) return;
    final names =
        risky.take(2).map((p) => Categories.byId(p.categoryId).label).join(', ');
    await NotificationService.instance.showNow(
      3001,
      'Budget alert ⚠️',
      risky.length == 1
          ? '$names is on track to exceed its budget this month.'
          : '$names${risky.length > 2 ? ' & more' : ''} are on track to exceed budget this month.',
    );
    await prefs.setString('last_budget_alert', today);
  }

  @override
  Widget build(BuildContext context) {
    // Keep the blocklist subscription warm so _persist sees live updates.
    ref.watch(blockedSendersProvider);
    // Once data is ready, check budget projections and alert (rate-limited).
    ref.listen(insightsProvider, (_, next) {
      final b = next.asData?.value;
      if (b != null) _maybeAlertBudgets(b.budgetProjections);
    });
    // Award Aura whenever the underlying data changes (idempotent).
    void syncAura() => ref.read(gamificationProvider.notifier).sync();
    ref.listen(transactionsStreamProvider, (_, __) => syncAura());
    ref.listen(budgetsStreamProvider, (_, __) => syncAura());
    ref.listen(goalsStreamProvider, (_, __) => syncAura());
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
              onPressed: () => _addSheet(context),
              icon: const Icon(Icons.add),
              label: const Text('Add'),
            )
          : null,
    );
  }

  // Quick chooser so logging income is as easy as logging an expense.
  void _addSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const CircleAvatar(
                backgroundColor: Color(0x33EF4444),
                child: Icon(Icons.south, color: Color(0xFFEF4444)),
              ),
              title: const Text('Add expense'),
              onTap: () {
                Navigator.pop(context);
                Navigator.pushNamed(context, AppRoutes.addTxn,
                    arguments: TxnDirection.debit);
              },
            ),
            ListTile(
              leading: const CircleAvatar(
                backgroundColor: Color(0x3322C55E),
                child: Icon(Icons.north, color: Color(0xFF22C55E)),
              ),
              title: const Text('Add income'),
              subtitle: const Text('Log salary, refunds, cash in — keeps Net accurate'),
              onTap: () {
                Navigator.pop(context);
                Navigator.pushNamed(context, AppRoutes.addTxn,
                    arguments: TxnDirection.credit);
              },
            ),
          ],
        ),
      ),
    );
  }
}
