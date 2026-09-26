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
import '../../utils/motion.dart';
import '../analytics/analytics_screen.dart';
import '../onboarding/onboarding_screen.dart';
import '../profile/profile_screen.dart';
import '../transactions/transactions_screen.dart';
import '../loans/loans_screen.dart';
import 'home_screen.dart';

// ── Radial FAB spec from flow-app.jsx ─────────────────────────
const _kA0 = 162.0 * math.pi / 180; // start angle in radians
const _kA1 = 18.0 * math.pi / 180; // end angle in radians
const _kR = 124.0; // orbit radius, px
const _kNavH = 88.0; // total height of nav area (pill + margin)
const _kFabSize = 56.0;
const _kNavBarH = 66.0; // glass pill height

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
    icon: Icons.mic,
    label: 'Voice',
    color: const Color(0xFF8B5CF6),
    action: (ctx, _) => () => Navigator.pushNamed(ctx, AppRoutes.voice),
  ),
  _FabAction(
    icon: Icons.bolt,
    label: 'Quick',
    color: AerisColors.seed,
    action: (ctx, _) => () => Navigator.pushNamed(ctx, AppRoutes.quickAdd),
  ),
  _FabAction(
    icon: Icons.south_west,
    label: 'Debit',
    color: const Color(0xFFE5484D),
    action: (ctx, _) => () => Navigator.pushNamed(ctx, AppRoutes.addTxn,
        arguments: TxnDirection.debit),
  ),
  _FabAction(
    icon: Icons.north_east,
    label: 'Credit',
    color: const Color(0xFF15A24A),
    action: (ctx, _) => () => Navigator.pushNamed(ctx, AppRoutes.addTxn,
        arguments: TxnDirection.credit),
  ),
  _FabAction(
    icon: Icons.handshake_outlined,
    label: 'Lent',
    color: const Color(0xFFD97706),
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
  _TabItem(Icons.cottage_outlined, Icons.cottage, 'Home'),
  _TabItem(Icons.receipt_long_outlined, Icons.receipt_long, 'Activity'),
  _TabItem(Icons.insights_outlined, Icons.insights, 'Insights'),
  _TabItem(Icons.person_outline, Icons.person, 'Me'),
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
      if (!await OnboardingScreen.isDone() && mounted) {
        Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => const OnboardingScreen(), fullscreenDialog: true));
      }
    });
  }

  @override
  void dispose() {
    _fabCtrl.dispose();
    _auraDebounce?.cancel();
    _widgetDebounce?.cancel();
    _widgetClickSub?.cancel();
    super.dispose();
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

  // The FAB toggle is driven purely off the AnimationController — NO setState,
  // so tapping never rebuilds the whole shell (the IndexedStack pages + blurred
  // nav). The two AnimatedBuilders that listen to _fabCtrl (the rotating +
  // button and the radial menu) repaint on their own. This is what makes the
  // open/close buttery instead of stuttering on the first frame.
  bool get _fabOpen =>
      _fabCtrl.status == AnimationStatus.forward ||
      _fabCtrl.status == AnimationStatus.completed;

  void _toggleFab() {
    HapticFeedback.lightImpact(); // immediate tactile response on tap
    _fabOpen ? _closeFab() : _openFab();
  }

  // With the system "remove animations" setting on, the menu snaps open /
  // shut instead of flying out.
  void _openFab() => reduceMotion(context)
      ? _fabCtrl.value = 1
      : _fabCtrl.forward();

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
      final budgets = ref.read(budgetsStreamProvider).valueOrNull;
      if (analytics == null || budgets == null) return;
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
    });
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

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final size = MediaQuery.sizeOf(context);

    return Scaffold(
      body: Stack(
        children: [
          // ── Tab pages ───────────────────────────────────────
          Padding(
            padding: const EdgeInsets.only(bottom: _kNavH),
            // TickerMode pauses every AnimationController in a tab's subtree
            // while it's off-screen. IndexedStack keeps all four tabs mounted
            // (for instant switching), so without this the home avatar, list
            // shimmers, etc. would keep repainting at 60fps on hidden tabs.
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

          // ── FAB radial menu (scrim + action buttons) ─────────
          //    A single AnimatedBuilder drives the whole overlay. The scrim
          //    fades a flat colour — no per-frame BackdropFilter blur, which
          //    was what made the + button jitter on mobile GPUs.
          _FabMenu(
            controller: _fabCtrl,
            actions: _fabActions,
            isDark: isDark,
            screenWidth: size.width,
            onClose: _closeFab,
            onAction: (i) {
              _closeFab();
              _fabActions[i].action(context, ref)();
            },
          ),

          // ── Glass nav bar + FAB ─────────────────────────────
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: _GlassNav(
              idx: _idx,
              isDark: isDark,
              onTabTap: (i) {
                _closeFab();
                // Home keeps its state across tab switches (entrance
                // animations play once per session, per the Flow spec) —
                // re-mounting it on every tap rebuilt and re-animated the
                // whole dashboard.
                setState(() {
                  _visited.add(i);
                  _idx = i;
                });
              },
              onFabTap: _toggleFab,
              fabCtrl: _fabCtrl,
            ),
          ),
        ],
      ),
    );
  }
}

// ── FAB radial menu: scrim + all action buttons in ONE AnimatedBuilder ───────
// One builder per frame (instead of one per button + a blur builder), and a
// flat fading scrim (no BackdropFilter) — this is the reliable, jank-free path.
class _FabMenu extends StatelessWidget {
  final AnimationController controller;
  final List<_FabAction> actions;
  final bool isDark;
  final double screenWidth;
  final VoidCallback onClose;
  final ValueChanged<int> onAction;

  const _FabMenu({
    required this.controller,
    required this.actions,
    required this.isDark,
    required this.screenWidth,
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
    const btnSize = 50.0;
    const totalSec = 0.48;
    const centerBottom = _kNavH + _kFabSize * 0.5 - 20;
    final n = actions.length;
    final cx = screenWidth / 2;

    // Precompute, once, the per-button geometry and the *static* button content
    // (Container + shadow + Icon + label + tap handler). The AnimatedBuilder
    // below then only wraps these with Positioned/Opacity/scale every frame —
    // it never rebuilds the shadows/icons/text — so the open/close stays smooth
    // and the + rotation never competes with heavy per-frame button builds.
    final geom = <(double orbX, double orbY, double delay)>[];
    final content = <Widget>[];
    for (var i = 0; i < n; i++) {
      final t = n == 1 ? 0.5 : i / (n - 1);
      final ang = _kA0 + (_kA1 - _kA0) * t;
      geom.add(
          (math.cos(ang) * _kR, math.sin(ang) * _kR, (t - 0.5).abs() * 0.12));
      final a = actions[i];
      content.add(GestureDetector(
        onTap: () => onAction(i),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: btnSize,
              height: btnSize,
              // Solid tonal disc (lit from the top-left) + a glow in its own
              // colour — separates it from the dark scrim without an outline.
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color.lerp(a.color, Colors.white, 0.22)!, a.color],
                ),
                boxShadow: [
                  BoxShadow(
                      color: a.color.withValues(alpha: 0.50),
                      blurRadius: 18,
                      spreadRadius: 1,
                      offset: const Offset(0, 4))
                ],
              ),
              child: Icon(a.icon, color: Colors.white, size: 22),
            ),
            const SizedBox(height: 7),
            Text(
              a.label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.2,
                color: Colors.white,
                shadows: [Shadow(blurRadius: 4, color: Colors.black54)],
              ),
            ),
          ],
        ),
      ));
    }

    // Positioned.fill MUST be the outermost widget: _FabMenu is a direct child
    // of the shell's Stack, and Positioned only works when its render child's
    // parent is that Stack. Wrapping it inside RepaintBoundary/AnimatedBuilder
    // broke StackParentData (release: TypeError mid-build) — scrim drew, but
    // the action buttons never appeared.
    return Positioned.fill(
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: controller,
          builder: (context, _) {
            final v = controller.value;
            if (v == 0) return const SizedBox.shrink();
            final scrim = isDark ? Colors.black : const Color(0xFF0B1413);
            final closing = controller.status == AnimationStatus.reverse;

            final children = <Widget>[
              // Scrim — flat colour fade only (smooth; no per-frame blur).
              Positioned.fill(
                child: IgnorePointer(
                  ignoring: closing,
                  child: GestureDetector(
                    onTap: onClose,
                    // Gradient scrim: lighter at the top, near-opaque at the
                    // bottom where the radial buttons sit, so they never blend
                    // into busy dashboard content behind them. (Still no live
                    // BackdropFilter — that was the + jitter source.)
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          stops: const [0.0, 0.45, 1.0],
                          colors: [
                            scrim.withValues(alpha: 0.55 * v),
                            scrim.withValues(alpha: 0.78 * v),
                            scrim.withValues(alpha: 0.92 * v),
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
                left: cx + orbX * p - btnSize / 2,
                bottom: centerBottom + orbY * p - btnSize / 2,
                child: IgnorePointer(
                  ignoring: op < 0.1 || closing,
                  child: Opacity(
                    opacity: op.clamp(0.0, 1.0),
                    child: Transform.scale(scale: sc, child: content[i]),
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

// ── Glass nav bar widget ──────────────────────────────────────
class _GlassNav extends StatelessWidget {
  final int idx;
  final bool isDark;
  final ValueChanged<int> onTabTap;
  final VoidCallback onFabTap;
  final AnimationController fabCtrl;

  const _GlassNav({
    required this.idx,
    required this.isDark,
    required this.onTabTap,
    required this.onFabTap,
    required this.fabCtrl,
  });

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final glassColor = isDark
        ? const Color(0xFF162122).withValues(alpha: 0.97)
        : Colors.white.withValues(alpha: 0.97);
    final glassBorder = isDark
        ? Colors.white.withValues(alpha: 0.10)
        : const Color(0xFF0E1A18).withValues(alpha: 0.10);
    final active = AerisColors.seed;
    final inactive = isDark ? const Color(0xFF6A7E7C) : const Color(0xFF8B9997);

    return SizedBox(
      height: _kNavBarH + bottomInset,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.bottomCenter,
        children: [
          // ── Frosted glass pill ─────────────────────────────
          Positioned(
            left: 20,
            right: 20,
            bottom: bottomInset + 10,
            // No BackdropFilter: a live blur under the bar re-rendered on every
            // scrolled frame (and every idle animation frame) — the main source
            // of app-wide scroll jitter. A near-opaque surface reads the same.
            child: RepaintBoundary(
              child: Container(
                height: _kNavBarH,
                decoration: BoxDecoration(
                  color: glassColor,
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: glassBorder, width: 1.0),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black
                            .withValues(alpha: isDark ? 0.35 : 0.10),
                        blurRadius: 22,
                        offset: const Offset(0, 8)),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      // Left 2 tabs
                      _navItem(0, active, inactive),
                      _navItem(1, active, inactive),
                      // FAB gap
                      const SizedBox(width: _kFabSize + 4),
                      // Right 2 tabs
                      _navItem(2, active, inactive),
                      _navItem(3, active, inactive),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // ── FAB button — rises above pill ─────────────────
          Positioned(
            bottom: bottomInset + 10 + (_kNavBarH - _kFabSize) / 2 + 12,
            child: GestureDetector(
              onTap: onFabTap,
              child: AnimatedBuilder(
                animation: fabCtrl,
                builder: (_, __) => Transform.rotate(
                  // 135°: the spin completes over the first ~70% of the 400ms
                  // controller (≈280ms) — fast but clearly visible — while the
                  // radial buttons keep flying out over the remaining time.
                  angle: Curves.easeOut
                          .transform((fabCtrl.value / 0.7).clamp(0.0, 1.0)) *
                      (3 * math.pi / 4),
                  child: Container(
                    width: _kFabSize,
                    height: _kFabSize,
                    decoration: BoxDecoration(
                      gradient: AerisColors.heroGradient,
                      borderRadius: BorderRadius.circular(19),
                      border: Border.all(
                          color: Colors.white.withValues(alpha: 0.25),
                          width: 2.5),
                      boxShadow: [
                        BoxShadow(
                          color: AerisColors.seed.withValues(alpha: 0.45),
                          blurRadius: 18,
                          offset: const Offset(0, 6),
                        )
                      ],
                    ),
                    child: const Icon(
                      Icons.add,
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _navItem(int tabIdx, Color active, Color inactive) {
    final tab = _tabs[tabIdx];
    final selected = idx == tabIdx;
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onTabTap(tabIdx),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: selected
                    ? active.withValues(alpha: 0.13)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(99),
              ),
              child: Icon(
                selected ? tab.selectedIcon : tab.icon,
                size: 22,
                color: selected ? active : inactive,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              tab.label,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? active : inactive,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
