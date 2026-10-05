import 'dart:async';
import 'dart:math' as math;

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
import '../../services/notification_service.dart';
import '../../services/reminder_scheduler.dart';
import '../../services/share_intake.dart';
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
import '../../providers/village_provider.dart';
import '../../providers/money_providers.dart';
import '../../utils/motion.dart';
import '../analytics/analytics_screen.dart';
import '../loans/loans_screen.dart';
import '../onboarding/onboarding_screen.dart';
import '../profile/profile_screen.dart';
import '../transactions/transactions_screen.dart';
import 'home_screen.dart';

// ── Nav geometry ──────────────────────────────────────────────
const _kNavH = 88.0; // total height of nav area (pill + margin)
const _kFabSize = 58.0;
const _kNavBarH = 64.0; // nav pill height

// ── Radial menu (hold +) ──────────────────────────────────────
const _kA0 = 162.0 * math.pi / 180; // start angle in radians
const _kA1 = 18.0 * math.pi / 180; // end angle in radians
const _kR = 134.0; // orbit radius, px (five actions)
const _kRWide = 160.0; // with a sixth, where the screen is wide enough

class _FabAction {
  final IconData icon;
  final String label;
  final Color color;
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
    icon: Icons.mic_rounded,
    label: 'Voice',
    color: AerisColors.violet,
    action: (ctx, _) => () => Navigator.pushNamed(ctx, AppRoutes.voice),
  ),
  _FabAction(
    icon: Icons.bolt_rounded,
    label: 'Quick',
    color: AerisColors.arc,
    action: (ctx, _) => () => Navigator.pushNamed(ctx, AppRoutes.quickAdd),
  ),
  _FabAction(
    icon: Icons.image_search_rounded,
    label: 'Scan',
    color: AerisColors.info,
    action: (ctx, _) => () => Navigator.pushNamed(ctx, AppRoutes.screenshot),
  ),
  _FabAction(
    icon: Icons.south_west_rounded,
    label: 'Spent',
    color: AerisColors.coral,
    action: (ctx, _) => () => Navigator.pushNamed(ctx, AppRoutes.addTxn,
        arguments: TxnDirection.debit),
  ),
  _FabAction(
    icon: Icons.north_east_rounded,
    label: 'Received',
    color: AerisColors.mint,
    action: (ctx, _) => () => Navigator.pushNamed(ctx, AppRoutes.addTxn,
        arguments: TxnDirection.credit),
  ),
  _FabAction(
    icon: Icons.handshake_outlined,
    label: 'Lent',
    color: AerisColors.amber,
    action: (ctx, ref) => () => showAddLoanSheet(ctx, ref),
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
  _TabItem(Icons.home_outlined, Icons.home_rounded, 'Home'),
  _TabItem(Icons.receipt_long_outlined, Icons.receipt_long_rounded, 'Activity'),
  _TabItem(Icons.insights_outlined, Icons.insights_rounded, 'Insights'),
  _TabItem(Icons.person_outline_rounded, Icons.person_rounded, 'Me'),
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
      duration: const Duration(milliseconds: 400),
      reverseDuration: const Duration(milliseconds: 300),
    );
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
        break;
      case 'voice':
        Navigator.of(context).pushNamed(AppRoutes.voice);
        break;
      case 'village':
        Navigator.of(context).pushNamed(AppRoutes.village);
        break;
    }
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
      final analytics = ref.read(analyticsProvider).valueOrNull;
      final budgets = ref.read(effectiveBudgetsProvider);
      if (analytics == null) return;
      final gam = ref.read(gamificationProvider);
      final streak = gam.liveStreak;
      final week = gam.weekCheckins();
      final todayIdx = gam.todayWeekIndex;
      final explicitTotal = budgets
          .where((b) => b.categoryId == Budget.totalId)
          .fold<double>(0, (s, b) => s + b.monthlyCap);
      final target = explicitTotal > 0
          ? explicitTotal
          : budgets
              .where((b) => b.categoryId != Budget.totalId)
              .fold<double>(0, (s, b) => s + b.monthlyCap);
      // Today's spend for the 1×1 widget.
      final txns = ref.read(transactionsStreamProvider).valueOrNull ?? const [];
      final now = DateTime.now();
      final todaySpend = txns
          .where((t) =>
              t.direction == TxnDirection.debit &&
              t.timestamp.year == now.year &&
              t.timestamp.month == now.month &&
              t.timestamp.day == now.day)
          .fold<double>(0, (s, t) => s + t.amount);
      final profile = ref.read(userProfileProvider).valueOrNull;
      final fullName = (profile?.displayName ?? '').trim();
      WidgetService.pushAll(
        spent: analytics.monthExpense,
        budget: target,
        label: analytics.label,
        streak: streak,
        todaySpend: todaySpend,
        aura: gam.available,
        townLevel: ref.read(villageProvider).townLevel,
        firstName:
            fullName.isEmpty ? null : fullName.split(RegExp(r'\s+')).first,
        week: week,
        todayIdx: todayIdx,
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
    if (!await SmsService.instance.hasPermission()) return;
    await SmsService.instance
        .startLiveListening(onTxn: (p) => _persist(uid, p));
    Future.delayed(const Duration(seconds: 4), () async {
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

  Future<void> _persist(String uid, parsed) async {
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
    ref.listen(gamificationProvider.select((g) => g.checkinStreak),
        (_, __) => _scheduleWidgetPush());
    ref.listen(blockedSendersProvider, (_, next) {
      next.whenData((set) async {
        (await SharedPreferences.getInstance())
            .setStringList('blocked_senders', set.toList());
      });
    });

    return Scaffold(
      body: Stack(
        children: [
          // ── Tab pages ───────────────────────────────────────
          Padding(
            padding: const EdgeInsets.only(bottom: _kNavH),
            // TickerMode pauses every AnimationController in a tab's subtree
            // while it's off-screen. IndexedStack keeps all four tabs mounted
            // (for instant switching), so without this the list shimmers etc.
            // would keep repainting at 60fps on hidden tabs.
            child: IndexedStack(
              index: _idx,
              children: List.generate(4, (i) {
                // Unvisited tabs are cheap placeholders until first opened.
                if (!_visited.contains(i)) return const SizedBox.shrink();
                final Widget page = switch (i) {
                  0 => const HomeScreen(),
                  1 => const TransactionsScreen(),
                  2 => const AnalyticsScreen(),
                  _ => const ProfileScreen(),
                };
                return TickerMode(enabled: _idx == i, child: page);
              }),
            ),
          ),

          // ── Radial menu (scrim + action buttons), shown on hold ─
          _FabMenu(
            controller: _fabCtrl,
            actions: _fabActions,
            onClose: _closeFab,
            onAction: (i) {
              _closeFab();
              _fabActions[i].action(context, ref)();
            },
          ),

          // ── Nav bar + add button ────────────────────────────
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: _NavBar(
              idx: _idx,
              fabCtrl: _fabCtrl,
              onTabTap: (i) {
                _closeFab();
                if (i == _idx) return;
                HapticFeedback.selectionClick();
                // Home keeps its state across tab switches (entrance
                // animations play once per session) — re-mounting it on every
                // tap rebuilt and re-animated the whole dashboard.
                setState(() {
                  _visited.add(i);
                  _idx = i;
                });
              },
              onAdd: _add,
              onAddHold: _openFab,
            ),
          ),
        ],
      ),
    );
  }
}

/// Vertical distance from the screen bottom to the add button's centre.
double _fabCenterFromBottom(BuildContext context) =>
    MediaQuery.paddingOf(context).bottom +
    10 +
    _kNavBarH -
    _kFabSize * 0.62 +
    _kFabSize / 2;

// ── Radial menu: scrim + all action buttons in ONE AnimatedBuilder ───────────
// One builder per frame (instead of one per button + a blur builder), and a
// flat fading scrim (no BackdropFilter) — the reliable, jank-free path.
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

  // Curve over a sub-interval [start,end] of the controller value.
  static double _seg(double v, double start, double end, Curve curve) {
    if (end <= start) return v >= end ? 1.0 : 0.0;
    return curve.transform(((v - start) / (end - start)).clamp(0.0, 1.0));
  }

  @override
  Widget build(BuildContext context) {
    const btnSize = 52.0;
    const slot = btnSize + 24; // room for the label under each disc
    const totalSec = 0.48;
    final centerBottom = _fabCenterFromBottom(context);
    final n = actions.length;
    final cx = MediaQuery.sizeOf(context).width / 2;
    // A sixth action needs a wider orbit to keep the discs apart — as wide
    // as the screen allows without pushing the outer two off its edge.
    final r = n <= 5
        ? _kR
        : ((cx - btnSize / 2 - 8) / math.cos(_kA1)).clamp(_kR, _kRWide);

    // Precompute, once, the per-button geometry and the *static* button
    // content. The AnimatedBuilder below then only wraps these with
    // Positioned/Opacity/scale every frame — it never rebuilds the glows,
    // icons or text — so open/close stays smooth.
    final geom = <(double orbX, double orbY, double delay)>[];
    final content = <Widget>[];
    for (var i = 0; i < n; i++) {
      final t = n == 1 ? 0.5 : i / (n - 1);
      final ang = _kA0 + (_kA1 - _kA0) * t;
      geom.add(
          (math.cos(ang) * r, math.sin(ang) * r, (t - 0.5).abs() * 0.12));
      final a = actions[i];
      content.add(Semantics(
        button: true,
        label: a.label,
        child: GestureDetector(
          onTap: () => onAction(i),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: btnSize,
                height: btnSize,
                // Neon disc lit from the top-left + a glow in its own colour.
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color.lerp(a.color, Colors.white, 0.25)!, a.color],
                  ),
                  boxShadow: [
                    BoxShadow(
                        color: a.color.withValues(alpha: 0.55),
                        blurRadius: 20,
                        spreadRadius: 1,
                        offset: const Offset(0, 4))
                  ],
                ),
                child: Icon(a.icon, color: const Color(0xFF06080D), size: 23),
              ),
              const SizedBox(height: 7),
              Text(
                a.label.toUpperCase(),
                maxLines: 1,
                style: const TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                  color: Colors.white,
                  shadows: [Shadow(blurRadius: 4, color: Colors.black54)],
                ),
              ),
            ],
          ),
        ),
      ));
    }

    // Positioned.fill MUST be the outermost widget: _FabMenu is a direct child
    // of the shell's Stack, and Positioned only works when its render child's
    // parent is that Stack.
    return Positioned.fill(
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: controller,
          builder: (context, _) {
            final v = controller.value;
            if (v == 0) return const SizedBox.shrink();
            const scrim = Color(0xFF03050A);
            final closing = controller.status == AnimationStatus.reverse;

            final children = <Widget>[
              // Scrim — lighter at the top, near-opaque where the buttons sit.
              Positioned.fill(
                child: IgnorePointer(
                  ignoring: closing,
                  child: GestureDetector(
                    onTap: onClose,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          stops: const [0.0, 0.45, 1.0],
                          colors: [
                            scrim.withValues(alpha: 0.55 * v),
                            scrim.withValues(alpha: 0.80 * v),
                            scrim.withValues(alpha: 0.94 * v),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ];

            for (var i = 0; i < n; i++) {
              final (orbX, orbY, delay) = geom[i];
              // Middle pops first, outers last.
              final p = _seg(
                  v,
                  delay / totalSec,
                  ((delay + 0.42) / totalSec).clamp(0.0, 1.0),
                  Curves.easeOutBack);
              final op = _seg(v, delay / totalSec,
                  ((delay + 0.28) / totalSec).clamp(0.0, 1.0), Curves.easeOut);
              final sc = 0.2 + 0.8 * p;

              children.add(Positioned(
                left: cx + orbX * p - slot / 2,
                bottom: centerBottom + orbY * p - btnSize / 2,
                child: IgnorePointer(
                  ignoring: op < 0.1 || closing,
                  child: Opacity(
                    opacity: op.clamp(0.0, 1.0),
                    child: Transform.scale(
                      scale: sc,
                      alignment: Alignment.topCenter,
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

// ── Nav bar ───────────────────────────────────────────────────
class _NavBar extends StatelessWidget {
  final int idx;
  final AnimationController fabCtrl;
  final ValueChanged<int> onTabTap;
  final VoidCallback onAdd;
  final VoidCallback onAddHold;

  const _NavBar({
    required this.idx,
    required this.fabCtrl,
    required this.onTabTap,
    required this.onAdd,
    required this.onAddHold,
  });

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
<<<<<<< HEAD
    final dark = Theme.of(context).brightness == Brightness.dark;
    final accent = AerisColors.accent(context);
    final inactive = AerisColors.muted(context);
=======
    final glassColor = isDark
        ? const Color(0xFF162122).withValues(alpha: 0.97)
        : Colors.white.withValues(alpha: 0.97);
    final glassBorder = isDark
        ? Colors.white.withValues(alpha: 0.10)
        : const Color(0xFF0E1A18).withValues(alpha: 0.10);
    const active = AerisColors.seed;
    final inactive = isDark ? const Color(0xFF6A7E7C) : const Color(0xFF8B9997);
>>>>>>> 03b46533542cdba8b0b640a9e2a5977620e74684

    return SizedBox(
      height: _kNavBarH + bottomInset + 22,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.bottomCenter,
        children: [
          // ── The pill ───────────────────────────────────────
          Positioned(
            left: 16,
            right: 16,
            bottom: bottomInset + 10,
            // No BackdropFilter: a live blur under the bar re-rendered on every
            // scrolled frame — the main source of app-wide scroll jitter.
            child: RepaintBoundary(
              child: Container(
                height: _kNavBarH,
                decoration: BoxDecoration(
                  color: AerisColors.card(context),
                  borderRadius: BorderRadius.circular(26),
                  border: Border.all(
                      color: dark
                          ? AerisColors.arc.withValues(alpha: 0.14)
                          : AerisColors.lineLight),
                  boxShadow: [
                    BoxShadow(
                        color: dark
                            ? AerisColors.arc.withValues(alpha: 0.06)
                            : Colors.black.withValues(alpha: 0.08),
                        blurRadius: 24,
                        offset: const Offset(0, 8)),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Row(
                    children: [
                      _item(context, 0, accent, inactive),
                      _item(context, 1, accent, inactive),
                      const SizedBox(width: _kFabSize + 14), // add-button gap
                      _item(context, 2, accent, inactive),
                      _item(context, 3, accent, inactive),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // ── Add button — sits on the pill's top edge ────────
          Positioned(
            bottom: bottomInset + 10 + _kNavBarH - _kFabSize * 0.62,
            child: _AddButton(
                controller: fabCtrl, onTap: onAdd, onHold: onAddHold),
          ),
        ],
      ),
    );
  }

  Widget _item(BuildContext context, int tabIdx, Color active, Color inactive) {
    final tab = _tabs[tabIdx];
    final selected = idx == tabIdx;
    return Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        label: tab.label,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => onTabTap(tabIdx),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
                decoration: BoxDecoration(
                  color: selected
                      ? AerisColors.accentSoft(context)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Icon(
                  selected ? tab.selectedIcon : tab.icon,
                  size: 22,
                  color: selected ? active : inactive,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                tab.label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? active : inactive,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The glowing arc "+": tap to add an expense, hold to fan out the radial
/// menu. Presses down slightly, and turns into × while the menu is open.
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
    final dark = Theme.of(context).brightness == Brightness.dark;
    final glow = dark ? AerisColors.arc : AerisColors.accent(context);
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
          scale: _down ? 0.92 : 1,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          child: Container(
            width: _kFabSize,
            height: _kFabSize,
            decoration: BoxDecoration(
              gradient:
                  dark ? AerisColors.arcGradient : AerisColors.heroGradient,
              shape: BoxShape.circle,
              border: Border.all(color: AerisColors.canvas(context), width: 4),
              boxShadow: [
                BoxShadow(
                  color: glow.withValues(alpha: dark ? 0.45 : 0.30),
                  blurRadius: 20,
                  offset: const Offset(0, 6),
                )
              ],
            ),
            child: AnimatedBuilder(
              animation: widget.controller,
              builder: (_, child) => Transform.rotate(
                // 135°: + becomes × over the first ~70% of the open animation.
                angle: Curves.easeOut.transform(
                        (widget.controller.value / 0.7).clamp(0.0, 1.0)) *
                    (3 * math.pi / 4),
                child: child,
              ),
              child: Icon(Icons.add_rounded,
                  color: dark ? const Color(0xFF06080D) : Colors.white,
                  size: 30),
            ),
          ),
        ),
      ),
    );
  }
}
