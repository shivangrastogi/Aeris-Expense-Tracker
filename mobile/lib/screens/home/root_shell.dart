import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:home_widget/home_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/routes.dart';
import '../../core/theme.dart';
import '../../models/budget.dart';
import '../../models/category.dart';
import '../../models/insight.dart';
import '../../models/transaction.dart';
import '../../services/notification_intake.dart';
import '../../services/notification_service.dart';
import '../../services/reminder_scheduler.dart';
import '../../services/share_intake.dart';
import '../../services/sms_service.dart';
import '../../services/sms_import_service.dart';
import '../../services/sms_parser.dart';
import '../../services/widget_service.dart';
import '../../providers/analytics_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/budgets_provider.dart';
import '../../providers/gamification_provider.dart';
import '../../providers/goals_provider.dart';
import '../../providers/insights_provider.dart';
import '../../providers/transactions_provider.dart';
import '../../providers/village_provider.dart';
import '../../providers/money_providers.dart';
import '../../providers/prefs_data_provider.dart';
import '../../providers/privacy_provider.dart';
import '../../providers/currency_provider.dart';
import '../../utils/motion.dart';
import '../../widgets/aeris_toast.dart';
import '../../widgets/ds.dart';
import '../analytics/analytics_screen.dart';
import '../onboarding/onboarding_screen.dart';
import '../profile/profile_screen.dart';
import '../transactions/transactions_screen.dart';
import 'home_screen.dart';


// ── Nav geometry (AERIS Design System · Navigation) ───────────
// A floating glass pill, 64 dp tall and 16 dp off the bottom, with a centre
// gap for the 56 dp hero-gradient "+".
const _kNavBarH = 64.0; // the pill
const _kNavGap = 16.0; // pill → screen bottom (above the system inset)
const _kNavH = _kNavBarH + _kNavGap + 8; // space the tab pages leave
const _kNavMaxW = 340.0;
const _kFabSize = 56.0;

// ── Radial quick-add: five actions fan out on an arc around "+" ─
// 30° apart on a 150 dp radius, centred 16 dp above the "+" so the lowest
// labels clear the nav pill and no label touches a neighbouring disc.
const _kFanR = 150.0;
const _kFanLift = 16.0;
const _kFanAngles = [150.0, 120.0, 90.0, 60.0, 30.0];

class _FabAction {
  final IconData icon;
  final String label;
  final Color? color; // null = the theme's "money in" green
  final VoidCallback Function(BuildContext, WidgetRef) action;
  const _FabAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.action,
  });
}

final _fabActions = [
  _FabAction(
    icon: Ph.microphone,
    label: 'Voice',
    color: const Color(0xFF8A7ED3),
    action: (ctx, _) => () => Navigator.pushNamed(ctx, AppRoutes.voice),
  ),
  _FabAction(
    icon: Ph.lightning,
    label: 'Quick',
    color: const Color(0xFFB0902F),
    action: (ctx, _) => () => Navigator.pushNamed(ctx, AppRoutes.quickAdd),
  ),
  _FabAction(
    icon: Ph.scan,
    label: 'Scan',
    color: const Color(0xFF2FA287),
    action: (ctx, _) => () => Navigator.pushNamed(ctx, AppRoutes.screenshot),
  ),
  _FabAction(
    icon: Ph.arrowUpRight,
    label: 'Spent',
    color: const Color(0xFFC97A52),
    action: (ctx, _) => () => Navigator.pushNamed(ctx, AppRoutes.addTxn,
        arguments: TxnDirection.debit),
  ),
  _FabAction(
    icon: Ph.arrowDownLeft,
    label: 'Received',
    color: null,
    action: (ctx, _) => () => Navigator.pushNamed(ctx, AppRoutes.addTxn,
        arguments: TxnDirection.credit),
  ),
];

// ── Tab items ─────────────────────────────────────────────────
class _TabItem {
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  const _TabItem(this.icon, this.selectedIcon, this.label);
}

const _tabs = [
  _TabItem(Ph.house, PhFill.house, 'Home'),
  _TabItem(Ph.listBullets, PhFill.listBullets, 'Activity'),
  _TabItem(Ph.chartPieSlice, PhFill.chartPieSlice, 'Insights'),
  _TabItem(Ph.userCircle, PhFill.userCircle, 'Me'),
];

// ── Root Shell ────────────────────────────────────────────────
class RootShell extends ConsumerStatefulWidget {
  const RootShell({super.key});

  @override
  ConsumerState<RootShell> createState() => _RootShellState();
}

class _RootShellState extends ConsumerState<RootShell>
    with SingleTickerProviderStateMixin {
  int _idx = 0;
  // Tabs are built lazily: only Home exists at first mount so the splash→home
  // transition isn't janked by building Transactions/Analytics/Profile too.
  final Set<int> _visited = {0};
  late final AnimationController _fabCtrl;
  Timer? _auraDebounce;
  Timer? _widgetDebounce;
  Timer? _reminderDebounce;
  StreamSubscription<Uri?>? _widgetClickSub;

  @override
  void initState() {
    super.initState();
    _fabCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
      reverseDuration: const Duration(milliseconds: 400),
    );
    // The user's own categories join the built-in list everywhere.
    ref.listenManual(customCategoriesProvider, (_, next) {
      Categories.custom = next.valueOrNull ?? const [];
      if (mounted) setState(() {});
    }, fireImmediately: true);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _wireSms();
      _wireWidgetLaunch();
      _ensureDailyCheckinScheduled();
      _wireNotificationTaps();
      _wireShareIntake();
      _scheduleReminders();
      if (!await OnboardingScreen.isDone() && mounted) {
        Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => const OnboardingScreen(), fullscreenDialog: true));
      }
    });
  }

  @override
  void dispose() {
    _fabCtrl.dispose();
    ShareIntake.stop();
    _auraDebounce?.cancel();
    _widgetDebounce?.cancel();
    _widgetClickSub?.cancel();
    _reminderDebounce?.cancel();
    super.dispose();
  }

  // ── Notifications: tap → the matching screen ────────────────
  Future<void> _wireNotificationTaps() async {
    NotificationService.instance.onTapRoute = (route) {
      if (mounted) Navigator.of(context).pushNamed(route);
    };
    // Cold start from a notification tap.
    final route = await NotificationService.instance.launchRoute();
    if (route != null && mounted) Navigator.of(context).pushNamed(route);
  }

  // ── Screenshots shared in from another app ──────────────────
  void _wireShareIntake() {
    ShareIntake.listen(_openShared); // shared while the app is running
    _openShared(); // the app was opened by the share
  }

  Future<void> _openShared() async {
    final paths = await ShareIntake.take();
    if (paths.isEmpty || !mounted) return;
    Navigator.of(context).pushNamed(AppRoutes.screenshot, arguments: paths);
  }

  /// Re-plans the smart reminders (tonight's spend alert, bills due
  /// tomorrow, Sunday recap, report card) from the latest data — debounced,
  /// so a burst of SMS imports reschedules once.
  void _scheduleReminders() {
    _reminderDebounce?.cancel();
    _reminderDebounce = Timer(const Duration(seconds: 2), () {
      if (!mounted) return;
      ReminderScheduler.refresh(
        txns: ref.read(transactionsStreamProvider).valueOrNull ?? const [],
        budgets: ref.read(effectiveBudgetsProvider),
        bills: ref.read(billsProvider),
      ).catchError((Object _) {/* notifications unavailable — ignore */});
    });
  }

  // ── Quick-capture widget deep links ─────────────────────────
  void _wireWidgetLaunch() {
    // Cold start: the app may have been launched by tapping the widget.
    HomeWidget.initiallyLaunchedFromHomeWidget().then(_routeWidgetUri);
    // Warm: widget tapped while the app is already running.
    _widgetClickSub = HomeWidget.widgetClicked.listen(_routeWidgetUri);
  }

  void _routeWidgetUri(Uri? uri) {
    if (uri == null || !mounted) return;
    switch (uri.host) {
      case 'quickadd':
        Navigator.of(context).pushNamed(AppRoutes.quickAdd);
      case 'add':
        Navigator.of(context).pushNamed(AppRoutes.addTxn);
      case 'voice':
        Navigator.of(context).pushNamed(AppRoutes.voice);
      case 'village':
        Navigator.of(context).pushNamed(AppRoutes.village);
      case 'budgets':
        Navigator.of(context).pushNamed(AppRoutes.budgets);
      case 'activity':
        _goTab(1);
      case 'checkin':
        _goTab(0);
        _checkInFromWidget();
    }
  }

  void _goTab(int i) {
    if (i == _idx) return;
    setState(() {
      _visited.add(i);
      _idx = i;
    });
  }

  /// The streak widget's "Check in" — one tap from the home screen. On a
  /// cold start the gamification state loads asynchronously, so wait for it.
  Future<void> _checkInFromWidget() async {
    for (var i = 0; i < 30 && !ref.read(gamificationProvider).loaded; i++) {
      await Future.delayed(const Duration(milliseconds: 100));
    }
    if (!mounted) return;
    final awarded = ref.read(gamificationProvider.notifier).checkIn();
    final streak = ref.read(gamificationProvider).checkinStreak;
    ScaffoldMessenger.of(context).showToast(SnackBar(
      content: Text(awarded > 0
          ? 'Checked in · +$awarded Aura · $streak-day streak'
          : 'Already checked in today · $streak-day streak'),
      duration: const Duration(seconds: 3),
    ));
  }

  // ── The add button ──────────────────────────────────────────
  // Tap: straight into a new expense (the common case — one tap).
  // Hold: the radial menu fans out — voice, quick sentence, screenshot scan,
  // spent, received, lent. While it's open, tapping + (or the scrim) closes it.
  //
  // The menu is driven purely off the AnimationController — NO setState — so
  // opening it never rebuilds the shell (IndexedStack pages + nav); only the
  // two AnimatedBuilders listening to _fabCtrl repaint.
  bool get _fabOpen =>
      _fabCtrl.status == AnimationStatus.forward ||
      _fabCtrl.status == AnimationStatus.completed;

  void _add() {
    if (_fabOpen) {
      _closeFab();
      return;
    }
    HapticFeedback.lightImpact();
    Navigator.pushNamed(context, AppRoutes.addTxn,
        arguments: TxnDirection.debit);
  }

  void _openFab() {
    if (_fabOpen) return;
    HapticFeedback.mediumImpact();
    // With the system "remove animations" setting on, the menu snaps open.
    reduceMotion(context) ? _fabCtrl.value = 1 : _fabCtrl.forward();
  }

  void _closeFab() {
    if (!_fabOpen) return;
    reduceMotion(context) ? _fabCtrl.value = 0 : _fabCtrl.reverse();
  }

  /// System back: close the add menu first, then step back to Home, and only
  /// leave the app from Home.
  Widget _backGuard(Widget child) => PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) return;
          if (_fabOpen) {
            _closeFab();
          } else if (_idx != 0) {
            setState(() => _idx = 0);
          } else {
            SystemNavigator.pop();
          }
        },
        child: child,
      );

  /// On the rail (tablets) holding Add lists the same quick-add actions the
  /// phone's radial fan shows.
  void _showAddSheet(BuildContext context) {
    HapticFeedback.mediumImpact();
    showDsSheet<void>(
      context,
      title: 'Add',
      builder: (ctx) => ListGroup(inset: 68, children: [
        for (final a in _fabActions)
          DsRow(
            minHeight: 56,
            leading: CatTile(color: a.color ?? ctx.tk.ok, icon: a.icon),
            title: a.label,
            onTap: () {
              Navigator.pop(ctx);
              a.action(context, ref)();
            },
          ),
      ]),
    );
  }

  void _scheduleAuraSync() {
    _auraDebounce?.cancel();
    _auraDebounce = Timer(const Duration(milliseconds: 500), () {
      if (mounted) ref.read(gamificationProvider.notifier).sync();
    });
  }

  void _scheduleWidgetPush() {
    _widgetDebounce?.cancel();
    _widgetDebounce = Timer(const Duration(milliseconds: 800), () {
      if (!mounted) return;
      final txns = ref.read(transactionsStreamProvider).valueOrNull;
      if (txns == null) return; // not loaded yet — don't push zeros
      final budgets = ref.read(effectiveBudgetsProvider);
      final gam = ref.read(gamificationProvider);
      final explicitTotal = budgets
          .where((b) => b.categoryId == Budget.totalId)
          .fold<double>(0, (s, b) => s + b.monthlyCap);
      final target = explicitTotal > 0
          ? explicitTotal
          : budgets
              .where((b) => b.categoryId != Budget.totalId)
              .fold<double>(0, (s, b) => s + b.monthlyCap);
      final profile = ref.read(userProfileProvider).valueOrNull;
      final fullName = (profile?.displayName ?? '').trim();
      WidgetService.pushAll(
        // Calendar month + today, NOT the Analytics range selector.
        snap: WidgetSnapshot.compute(txns, DateTime.now()),
        budget: target,
        streak: gam.checkinStreak,
        lastCheckinDay: gam.lastCheckinDay,
        checkinDays: [
          for (final k in gam.awardedKeys)
            if (k.startsWith('checkin_')) k.substring(8)
        ],
        aura: gam.available,
        townLevel: ref.read(villageProvider).townLevel,
        firstName:
            fullName.isEmpty ? null : fullName.split(RegExp(r'\s+')).first,
      );
    });
  }

  Future<void> _ensureDailyCheckinScheduled() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('reminders_on') ?? false) {
      await NotificationService.instance.scheduleDailyCheckin();
    }
  }

  Future<void> _wireSms() async {
    final uid = ref.read(currentUserIdProvider);
    if (uid == null) return;
    (await SharedPreferences.getInstance()).setString('current_uid', uid);
    // UPI-app notifications don't need the SMS permission.
    unawaited(NotificationIntake.instance.attach((p) => _persist(uid, p)));
    if (!await SmsService.instance.hasPermission()) return;
    await SmsService.instance
        .startLiveListening(onTxn: (p) => _persist(uid, p));
    Future.delayed(const Duration(seconds: 4), () async {
      if (!mounted) return;
      // Re-read past imports with the improved parser BEFORE backfilling, so
      // a message that now parses differently isn't imported a second time.
      try {
        final r = await SmsImportService.instance.repairImported(uid);
        final parts = [
          if (r.fixed > 0) '${r.fixed} corrected',
          if (r.merged > 0) '${r.merged} duplicate${r.merged == 1 ? '' : 's'} merged',
          if (r.transfers > 0)
            '${r.transfers} own-account transfer${r.transfers == 1 ? '' : 's'} found',
        ];
        if (parts.isNotEmpty && mounted) {
          ScaffoldMessenger.of(context).showToast(SnackBar(
              content: Text('Re-read your bank SMS: ${parts.join(' · ')}.')));
        }
      } catch (_) {} // best-effort; it retries on the next app open
      if (!mounted) return;
      final blocked = ref.read(blockedSendersProvider).valueOrNull ?? const {};
      await SmsImportService.instance.backfill(
        uid,
        blocked: blocked,
        days: 30,
        incremental: true,
        onProgress: (done, total) {
          if (!mounted) return;
          ref.read(importProgressProvider.notifier).state =
              done >= total ? null : (done: done, total: total);
        },
      );
    });
  }

  Future<void> _persist(String uid, ParsedSms parsed) async {
    final blocked = ref.read(blockedSendersProvider).valueOrNull ?? const {};
    await SmsImportService.instance.persistOne(uid, parsed, blocked);
  }

  Future<void> _maybeAlertBudgets(List<BudgetProjection> projections) async {
    final prefs = await SharedPreferences.getInstance();
    if (!(prefs.getBool('reminders_on') ?? false)) return;
    final now = DateTime.now();
    final today = '${now.year}-${now.month}-${now.day}';
    if (prefs.getString('last_budget_alert') == today) return;
    final risky = projections
        .where((p) =>
            p.alreadyOver || (p.willExceed && (p.daysUntilExceed ?? 99) <= 5))
        .toList();
    if (risky.isEmpty) return;
    final names = risky
        .take(2)
        .map((p) => Categories.byId(p.categoryId).label)
        .join(', ');
    await NotificationService.instance.showNow(
      3001,
      'Budget alert ⚠️',
      risky.length == 1
          ? '$names is on track to exceed its budget this month.'
          : '$names${risky.length > 2 ? ' & more' : ''} are on track to exceed budget this month.',
      route: AppRoutes.budgets,
      actions: const [('See budgets', AppRoutes.budgets)],
    );
    await prefs.setString('last_budget_alert', today);
  }

  @override
  Widget build(BuildContext context) {
    // Reactive listeners — side-effects only
    ref.listen(insightsProvider, (_, next) {
      final b = next.valueOrNull;
      if (b != null) _maybeAlertBudgets(b.budgetProjections);
    });
    ref.listen(transactionsStreamProvider, (_, __) {
      _scheduleAuraSync();
      _scheduleWidgetPush();
      _scheduleReminders();
    });
    ref.listen(effectiveBudgetsProvider, (_, __) => _scheduleReminders());
    ref.listen(billsProvider, (_, __) => _scheduleReminders());
    ref.listen(budgetsStreamProvider, (_, __) {
      _scheduleAuraSync();
      _scheduleWidgetPush();
    });
    ref.listen(goalsStreamProvider, (_, __) => _scheduleAuraSync());
    ref.listen(analyticsProvider, (_, __) => _scheduleWidgetPush());
    // Streak, check-ins and Aura all show on widgets.
    ref.listen(
        gamificationProvider.select(
            (g) => (g.checkinStreak, g.lastCheckinDay, g.available)),
        (_, __) => _scheduleWidgetPush());
    ref.listen(villageProvider.select((v) => v.townLevel),
        (_, __) => _scheduleWidgetPush());
    ref.listen(amountHiddenProvider, (_, __) => _scheduleWidgetPush());
    ref.listen(currencyProvider, (_, __) => _scheduleWidgetPush());
    ref.listen(userProfileProvider, (_, __) => _scheduleWidgetPush());
    ref.listen(blockedSendersProvider, (_, next) {
      next.whenData((set) async {
        (await SharedPreferences.getInstance())
            .setStringList('blocked_senders', set.toList());
      });
    });

    // TickerMode pauses every AnimationController in a tab's subtree while
    // it's off-screen. IndexedStack keeps all four tabs mounted (for instant
    // switching), so without this the list shimmers etc. would keep
    // repainting at 60fps on hidden tabs.
    final pages = IndexedStack(
      index: _idx,
      children: List.generate(4, (i) {
        // Unvisited tabs are cheap placeholders until first opened.
        if (!_visited.contains(i)) return const SizedBox.shrink();
        final Widget page = switch (i) {
          0 => const HomeScreen(),
          1 => const TransactionsScreen(),
          2 => const AnalyticsScreen(),
          _ => const MeTab(),
        };
        return TickerMode(enabled: _idx == i, child: page);
      }),
    );
    void onTabTap(int i) {
      _closeFab();
      if (i == _idx) return;
      HapticFeedback.selectionClick();
      // Home keeps its state across tab switches (entrance animations play
      // once per session) — re-mounting it on every tap rebuilt and
      // re-animated the whole dashboard.
      setState(() {
        _visited.add(i);
        _idx = i;
      });
    }

    // Tablets and unfolded foldables (600 dp+): the floating pill becomes a
    // left navigation rail with Add at the top.
    if (MediaQuery.sizeOf(context).width >= 600) {
      return _backGuard(Scaffold(
        body: Row(children: [
          _NavRail(
            idx: _idx,
            onTabTap: onTabTap,
            onAdd: _add,
            onAddHold: () => _showAddSheet(context),
          ),
          Expanded(child: pages),
        ]),
      ));
    }

    return _backGuard(Scaffold(
      body: Stack(
        children: [
          // ── Tab pages ───────────────────────────────────────
          Padding(
            padding: const EdgeInsets.only(bottom: _kNavH),
            child: pages,
          ),

          // ── Nav pill ────────────────────────────────────────
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: _NavBar(idx: _idx, onTabTap: onTabTap),
          ),

          // ── Radial menu (scrim + action buttons), shown on hold ─
          // Above the pill so the scrim dims it too.
          _FabMenu(
            controller: _fabCtrl,
            actions: _fabActions,
            onClose: _closeFab,
            onAction: (i) {
              _closeFab();
              _fabActions[i].action(context, ref)();
            },
          ),

          // ── Add button, above the scrim ─────────────────────
          Positioned(
            bottom: MediaQuery.paddingOf(context).bottom +
                _kNavGap +
                (_kNavBarH - _kFabSize) / 2,
            left: 0,
            right: 0,
            child: Center(
              child: _AddButton(
                  controller: _fabCtrl, onTap: _add, onHold: _openFab),
            ),
          ),
        ],
      ),
    ));
  }
}

/// Distance from the screen bottom to the "+" button's centre.
double _fabCenterFromBottom(BuildContext context) =>
    MediaQuery.paddingOf(context).bottom + _kNavGap + _kNavBarH / 2;

// ── Radial menu: scrim + the six actions in ONE AnimatedBuilder ──────────────
// Actions fan out on an arc around "+" with a 30 ms stagger (closing reverses it);
// the scrim fades over 250 ms. Driven by the controller alone — no setState —
// so opening it never rebuilds the tab pages.
class _FabMenu extends StatelessWidget {
  final AnimationController controller;
  final List<_FabAction> actions;
  final VoidCallback onClose;
  final ValueChanged<int> onAction;

  const _FabMenu({
    required this.controller,
    required this.actions,
    required this.onClose,
    required this.onAction,
  });

  static double _seg(double v, double start, double end) {
    if (end <= start) return v >= end ? 1.0 : 0.0;
    return Mo.curve.transform(((v - start) / (end - start)).clamp(0.0, 1.0));
  }

  @override
  Widget build(BuildContext context) {
    final tk = context.tk;
    const disc = 52.0;
    const slot = 96.0;
    // Disc centre → item bottom: half the disc, the gap, the 22 dp label pill.
    const below = disc / 2 + 6 + 22;
    final centerBottom = _fabCenterFromBottom(context);
    final width = MediaQuery.sizeOf(context).width;
    final cx = width / 2;
    final n = actions.length;
    // Narrow phones: tighten the arc so the side labels stay on screen.
    final r = math.min(_kFanR, (cx - slot / 2 - 4) / math.cos(math.pi / 6));

    final content = <Widget>[
      for (var i = 0; i < n; i++)
        Semantics(
          button: true,
          label: actions[i].label,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => onAction(i),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: disc,
                height: disc,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: tk.raised,
                  border: tk.isDark ? Border.all(color: tk.hair) : null,
                  boxShadow: tk.shadowRaised,
                ),
                child: Icon(actions[i].icon,
                    color: actions[i].color ?? tk.ok, size: 24),
              ),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: tk.raised,
                  borderRadius: BorderRadius.circular(11),
                  border: tk.isDark ? Border.all(color: tk.hair) : null,
                  boxShadow: tk.shadowRaised,
                ),
                child: Text(actions[i].label,
                    maxLines: 1,
                    style: TextStyle(
                        fontSize: 12,
                        height: 16 / 12,
                        fontWeight: FontWeight.w600,
                        color: tk.t1)),
              ),
            ]),
          ),
        ),
    ];

    // Total timeline: 300 ms per item + 30 ms × 5 stagger = 450 ms.
    const total = 450.0;
    return Positioned.fill(
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: controller,
          builder: (context, _) {
            final v = controller.value;
            if (v == 0) return const SizedBox.shrink();
            final closing = controller.status == AnimationStatus.reverse;
            final children = <Widget>[
              Positioned.fill(
                child: IgnorePointer(
                  ignoring: closing,
                  child: GestureDetector(
                    onTap: onClose,
                    // A soft blur under the scrim so page text can't read
                    // through the labels. It only exists while the menu is up.
                    child: ClipRect(
                      child: BackdropFilter(
                        filter: ImageFilter.blur(
                            sigmaX: 6 * _seg(v, 0, 250 / total),
                            sigmaY: 6 * _seg(v, 0, 250 / total)),
                        child: ColoredBox(
                            color: tk.scrim.withValues(
                                alpha:
                                    tk.scrim.a * _seg(v, 0, 250 / total))),
                      ),
                    ),
                  ),
                ),
              ),
            ];
            for (var i = 0; i < n; i++) {
              final a = _kFanAngles[i] * math.pi / 180;
              final dx = math.cos(a) * r, dy = math.sin(a) * r + _kFanLift;
              final start = i * 30 / total;
              final p = _seg(v, start, start + 300 / total);
              children.add(Positioned(
                left: cx + dx * p - slot / 2,
                bottom: centerBottom + dy * p - below,
                child: IgnorePointer(
                  ignoring: p < 0.6 || closing,
                  child: Opacity(
                    opacity: p,
                    child: Transform.scale(
                      scale: 0.4 + 0.6 * p,
                      // Grow from the disc centre (26 of the 80 dp item).
                      alignment: const Alignment(0, -0.35),
                      child: SizedBox(width: slot, child: content[i]),
                    ),
                  ),
                ),
              ));
            }
            return Stack(clipBehavior: Clip.none, children: children);
          },
        ),
      ),
    );
  }
}

// ── Nav bar: the floating pill ────────────────────────────────
class _NavBar extends StatelessWidget {
  final int idx;
  final ValueChanged<int> onTabTap;

  const _NavBar({required this.idx, required this.onTabTap});

  @override
  Widget build(BuildContext context) {
    final tk = context.tk;
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final width =
        math.min(_kNavMaxW, MediaQuery.sizeOf(context).width - 2 * 16);

    return SizedBox(
      height: _kNavBarH + _kNavGap + bottomInset,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.bottomCenter,
        children: [
          Positioned(
            bottom: bottomInset + _kNavGap,
            child: RepaintBoundary(
              // Glass without a live blur: a backdrop blur under the bar
              // re-rendered every scrolled frame (app-wide scroll jitter), so
              // the pill uses the glass tone at near-opacity instead.
              child: Container(
                width: width,
                height: _kNavBarH,
                padding: const EdgeInsets.symmetric(horizontal: 6),
                decoration: BoxDecoration(
                  color: tk.glass.withValues(alpha: 0.96),
                  borderRadius: BorderRadius.circular(_kNavBarH / 2),
                  border: Border.all(
                      color: tk.isDark ? tk.hair : tk.glassEdge),
                  boxShadow: tk.navShadow,
                ),
                child: Row(children: [
                  _item(context, 0),
                  _item(context, 1),
                  const SizedBox(width: 76), // the "+" gap
                  _item(context, 2),
                  _item(context, 3),
                ]),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _item(BuildContext context, int tabIdx) {
    final tk = context.tk;
    final tab = _tabs[tabIdx];
    final selected = idx == tabIdx;
    final color = selected ? tk.acc : tk.t2;
    return Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        label: tab.label,
        excludeSemantics: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => onTabTap(tabIdx),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(selected ? tab.selectedIcon : tab.icon,
                  size: 22, color: color),
              const SizedBox(height: 1),
              Text(tab.label,
                  maxLines: 1,
                  style: TextStyle(
                      fontSize: 11,
                      height: 14 / 11,
                      fontWeight:
                          selected ? FontWeight.w700 : FontWeight.w600,
                      color: color)),
            ],
          ),
        ),
      ),
    );
  }
}

/// The 56 dp hero-gradient "+": tap to add an expense, hold to fan out the
/// quick-add actions. Pressed = 0.98 scale; open = neutral, rotated to ×.
class _AddButton extends StatefulWidget {
  final AnimationController controller;
  final VoidCallback onTap;
  final VoidCallback onHold;
  const _AddButton(
      {required this.controller, required this.onTap, required this.onHold});

  @override
  State<_AddButton> createState() => _AddButtonState();
}

class _AddButtonState extends State<_AddButton> {
  bool _down = false;

  void _set(bool v) {
    if (_down != v) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    final tk = context.tk;
    return Semantics(
      button: true,
      label: 'Add transaction',
      hint: 'Double tap to add an expense. Long press for more ways to add.',
      child: GestureDetector(
        onTapDown: (_) => _set(true),
        onTapCancel: () => _set(false),
        onTapUp: (_) => _set(false),
        onTap: widget.onTap,
        onLongPress: () {
          _set(false);
          widget.onHold();
        },
        child: AnimatedScale(
          scale: _down ? 0.98 : 1,
          duration: Mo.press,
          curve: Mo.curve,
          child: AnimatedBuilder(
            animation: widget.controller,
            builder: (_, __) {
              final v = Mo.curve
                  .transform((widget.controller.value / 0.55).clamp(0.0, 1.0));
              final open = v > 0.5;
              return Container(
                width: _kFabSize,
                height: _kFabSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: open ? null : tk.hero,
                  color: open ? tk.raised : null,
                  border: open ? Border.all(color: tk.hair2) : null,
                  boxShadow: open ? null : tk.navShadow,
                ),
                child: Transform.rotate(
                  angle: v * math.pi / 4,
                  child: Icon(PhBold.plus,
                      size: 24, color: open ? tk.t1 : tk.onHero),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

// ── Navigation rail (600 dp+) ─────────────────────────────────
// The tablet form of the nav: Add (hero gradient) at the top, then the four
// tabs; the active one gets the filled icon and accent label.
class _NavRail extends StatelessWidget {
  final int idx;
  final ValueChanged<int> onTabTap;
  final VoidCallback onAdd;
  final VoidCallback onAddHold;
  const _NavRail({
    required this.idx,
    required this.onTabTap,
    required this.onAdd,
    required this.onAddHold,
  });

  @override
  Widget build(BuildContext context) {
    final tk = context.tk;
    return Container(
      width: 88,
      decoration: BoxDecoration(
        color: tk.surface,
        border: Border(right: BorderSide(color: tk.hair)),
      ),
      child: SafeArea(
        right: false,
        child: Column(children: [
          const SizedBox(height: 16),
          Semantics(
            button: true,
            label: 'Add transaction',
            hint: 'Long press for more ways to add.',
            child: GestureDetector(
              onTap: onAdd,
              onLongPress: onAddHold,
              child: Container(
                width: _kFabSize,
                height: _kFabSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: tk.hero,
                  boxShadow: tk.navShadow,
                ),
                child: Icon(PhBold.plus, size: 24, color: tk.onHero),
              ),
            ),
          ),
          const SizedBox(height: 24),
          for (var i = 0; i < _tabs.length; i++)
            Semantics(
              button: true,
              selected: idx == i,
              label: _tabs[i].label,
              excludeSemantics: true,
              child: InkWell(
                onTap: () => onTabTap(i),
                child: SizedBox(
                  width: 88,
                  height: 68,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      AnimatedContainer(
                        duration: Mo.standard,
                        curve: Mo.curve,
                        width: 56,
                        height: 32,
                        decoration: BoxDecoration(
                          color: idx == i ? tk.accSoft : Colors.transparent,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Icon(
                            idx == i ? _tabs[i].selectedIcon : _tabs[i].icon,
                            size: 22,
                            color: idx == i ? tk.acc : tk.t2),
                      ),
                      const SizedBox(height: 4),
                      Text(_tabs[i].label,
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight:
                                  idx == i ? FontWeight.w700 : FontWeight.w600,
                              color: idx == i ? tk.acc : tk.t2)),
                    ],
                  ),
                ),
              ),
            ),
        ]),
      ),
    );
  }
}
