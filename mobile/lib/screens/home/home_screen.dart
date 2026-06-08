import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/routes.dart';
import '../../core/theme.dart';
import '../../models/avatar_skin.dart';
import '../../models/category.dart';
import '../../models/insight.dart';
import '../../models/transaction.dart';
import '../../providers/analytics_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/budgets_provider.dart';
import '../../providers/gamification_provider.dart';
import '../../providers/insights_provider.dart';
import '../../providers/transactions_provider.dart';
import '../../services/quote_service.dart';
import '../../services/sms_service.dart';
import '../../utils/formatters.dart';
import '../../widgets/animated_count.dart';
import '../../widgets/budget_ring.dart';
import '../../widgets/gradient_card.dart';
import '../../widgets/aeris_avatar.dart';
import '../../widgets/greeting_header.dart';
import '../../widgets/mascot/aeris_mascot.dart';
import '../../widgets/quote_carousel.dart';
import '../../widgets/range_selector.dart';
import '../../widgets/skeleton.dart';
import '../../widgets/transaction_tile.dart';

/// Section ids whose entrance animation has already played this app session.
final Set<String> _playedIntros = <String>{};

/// Plays its child's entrance animation exactly once per app session — the
/// first time the section actually mounts with real data — then renders the
/// child statically forever after.
///
/// Because the "already played" flag lives in a session-level set (not in this
/// State), the animation does NOT replay when the ListView disposes and
/// re-mounts the card during scrolling, nor when a provider tick rebuilds it.
/// And because [PlayOnce] is only built inside each section's `data:` branch,
/// the entrance is naturally tied to data arrival rather than a fixed timer.
class PlayOnce extends StatefulWidget {
  final String id;
  final Duration delay;
  final Widget child;
  const PlayOnce(
      {super.key,
      required this.id,
      this.delay = Duration.zero,
      required this.child});

  @override
  State<PlayOnce> createState() => _PlayOnceState();
}

class _PlayOnceState extends State<PlayOnce> {
  late final bool _animate = !_playedIntros.contains(widget.id);

  @override
  void initState() {
    super.initState();
    if (_animate) _playedIntros.add(widget.id);
  }

  @override
  Widget build(BuildContext context) {
    if (!_animate) return widget.child;
    return widget.child
        .animate(delay: widget.delay)
        .fadeIn(duration: 350.ms)
        .slideY(begin: 0.08, end: 0, curve: Curves.easeOutCubic);
  }
}

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final _aerisTipKey = GlobalKey<TooltipState>();

  @override
  void initState() {
    super.initState();
    // One-time coach tooltip pointing at the Aeris (assistant) button.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final prefs = await SharedPreferences.getInstance();
      if (!(prefs.getBool('seen_aeris_tip') ?? false)) {
        await Future.delayed(const Duration(milliseconds: 700));
        _aerisTipKey.currentState?.ensureTooltipVisible();
        await prefs.setBool('seen_aeris_tip', true);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // This shell now watches only light, infrequently-changing state. The
    // data-heavy, transaction-driven sections each watch their own providers
    // (see the _DashboardCards / _AerisLevelCard / _ForecastCard /
    // _RecentActivity widgets below), so a new transaction rebuilds just that
    // section instead of the entire dashboard tree.
    final profile = ref.watch(userProfileProvider).asData?.value;
    final importProgress = ref.watch(importProgressProvider);
    final quote = ref.watch(quoteProvider);
    final hidden = ref.watch(gamificationProvider.select((s) => s.hiddenCards));
    final name = profile?.displayName?.split(' ').first ?? 'there';

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(transactionsStreamProvider),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
          // Keep the top cards alive across normal scrolling so they aren't
          // disposed + rebuilt (which restarted animations / totals).
          cacheExtent: 1200,
          children: [
            SafeArea(
              bottom: false,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(child: GreetingHeader(name: name)),
                  IconButton(
                    icon: const Icon(Icons.inbox_outlined),
                    tooltip: 'Review SMS imports',
                    onPressed: () =>
                        Navigator.pushNamed(context, AppRoutes.smsReview),
                  ),
                  IconButton(
                    icon: const Icon(Icons.notifications_active_outlined),
                    tooltip: 'Enable SMS auto-import',
                    onPressed: _grantSmsIfNeeded,
                  ),
                  // Aeris → AI assistant
                  Tooltip(
                    key: _aerisTipKey,
                    message: 'Tap Aeris to ask about your money',
                    triggerMode: TooltipTriggerMode.manual,
                    preferBelow: true,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(24),
                      onTap: () =>
                          Navigator.pushNamed(context, AppRoutes.assistant),
                      child: const Padding(
                        padding: EdgeInsets.all(2),
                        child: AerisMascot(mood: MascotMood.happy, size: 40),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: EdgeInsets.only(right: 2, bottom: 2),
                child: RangeSelector(),
              ),
            ),
            const _DailyCheckinCard(),
            if (importProgress != null) ...[
              _importBanner(importProgress),
              const SizedBox(height: 10),
            ],
            const _DashboardCards(),
            if (!hidden.contains('aeris')) ...[
              const SizedBox(height: 14),
              const _AerisLevelCard(),
            ],
            if (!hidden.contains('forecast')) const _ForecastCard(),
            if (!hidden.contains('quote')) ...[
              const SizedBox(height: 14),
              _quoteCard(quote),
            ],
            const SizedBox(height: 14),
            if (!hidden.contains('goals'))
              PlayOnce(
                  id: 'goals', delay: 160.ms, child: _goalsCard(context)),
            const SizedBox(height: 10),
            if (!hidden.contains('subs'))
              PlayOnce(id: 'subs', delay: 200.ms, child: _subsCard(context)),
            const SizedBox(height: 22),
            Row(
              children: [
                Text('Recent activity',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        )),
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.pushNamed(
                      context, AppRoutes.transactions,
                      arguments: TxnDirection.debit),
                  child: const Text('See all'),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const _RecentActivity(),
          ],
        ),
      ),
    );
  }

  // ── Import progress banner ────────────────────────────────
  Widget _importBanner(({int done, int total}) p) {
    final pct = p.total == 0 ? null : p.done / p.total;
    return Card(
      color: AerisColors.info.withValues(alpha: 0.10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2.4, value: pct),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text('Importing your SMS… ${p.done}/${p.total}',
                  style: const TextStyle(fontSize: 13)),
            ),
          ],
        ),
      ),
    );
  }

  // ── Motivational quotes (auto-sliding carousel) ───────────
  Widget _quoteCard(AsyncValue<List<Quote>> q) {
    final quotes = q.asData?.value;
    if (quotes == null || quotes.isEmpty) return const SizedBox.shrink();
    return PlayOnce(id: 'quote', child: QuoteCarousel(quotes: quotes));
  }

  Widget _goalsCard(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AerisColors.seed.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Text('🎯', style: TextStyle(fontSize: 18)),
        ),
        title: const Text('Goals & streaks',
            style: TextStyle(fontWeight: FontWeight.w700)),
        subtitle: const Text('Set targets, keep your streak, earn badges'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.pushNamed(context, AppRoutes.goals),
      ),
    );
  }

  Widget _subsCard(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AerisColors.info.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Text('🔁', style: TextStyle(fontSize: 18)),
        ),
        title: const Text('Subscriptions & bills',
            style: TextStyle(fontWeight: FontWeight.w700)),
        subtitle:
            const Text('See recurring payments detected from your spends'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.pushNamed(context, AppRoutes.subscriptions),
      ),
    );
  }

  Future<void> _grantSmsIfNeeded() async {
    final ok = await SmsService.instance.requestPermission();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(ok
            ? 'SMS reading enabled. Bank alerts will become transactions.'
            : 'Permission denied. Grant SMS access from system settings.')));
  }
}

// ── Daily check-in reward card ────────────────────────────────
// Shows only until the user has claimed today's reward, then disappears so the
// dashboard stays clean. Tapping claims the aura and advances the streak.
class _DailyCheckinCard extends ConsumerWidget {
  const _DailyCheckinCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gam = ref.watch(gamificationProvider);
    final ctrl = ref.read(gamificationProvider.notifier);
    if (!gam.loaded || ctrl.checkedInToday) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final streak = gam.checkinStreak;

    void claim() {
      final awarded = ctrl.checkIn();
      if (awarded > 0) {
        final s = ref.read(gamificationProvider).checkinStreak;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('+$awarded Aura claimed · $s-day streak 🔥'),
          duration: const Duration(seconds: 2),
        ));
      }
    }

    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 2),
      child: Material(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: claim,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AerisColors.warning.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.card_giftcard,
                      color: AerisColors.warning, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Daily check-in',
                          style: TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 14)),
                      const SizedBox(height: 1),
                      Text(
                        streak > 0
                            ? 'Keep your $streak-day streak going 🔥'
                            : 'Claim +${GamificationController.checkinBase} Aura & start a streak',
                        style: TextStyle(
                            fontSize: 12, color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.tonal(
                  onPressed: claim,
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                  ),
                  child: const Text('Claim'),
                ),
              ],
            ),
          ),
        ),
      ),
    ).animate().fadeIn(duration: 300.ms).slideY(begin: 0.08, end: 0);
  }
}

// ── Hero "Spent" block + budget ring ─────────────────────────
// Watches analytics + budgets only, so a new transaction rebuilds just these
// two cards rather than the whole dashboard.
class _DashboardCards extends ConsumerWidget {
  const _DashboardCards();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final analytics = ref.watch(analyticsProvider);
    final budgets = ref.watch(budgetsStreamProvider).asData?.value ?? const [];
    return analytics.when(
      data: (s) => Column(
        children: [
          // The hero holds the animated count; isolate its repaints so the
          // count-up never invalidates the rest of the list.
          PlayOnce(id: 'hero', child: RepaintBoundary(child: _heroCard(context, s))),
          const SizedBox(height: 14),
          PlayOnce(
              id: 'budget',
              delay: 80.ms,
              child: _budgetCard(context, s, budgets)),
        ],
      ),
      loading: () => const DashboardCardsSkeleton(),
      error: (e, _) => Text('Could not load analytics: $e'),
    );
  }

  Widget _heroCard(BuildContext context, AnalyticsSnapshot s) {
    final mom = _momChange(s);
    return GradientCard(
      gradient: AerisColors.heroGradient,
      onTap: () => Navigator.pushNamed(context, AppRoutes.transactions,
          arguments: TxnDirection.debit),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Spent · ${s.label}',
                  style: const TextStyle(color: Colors.white70, fontSize: 13)),
              const Spacer(),
              if (mom != null) _momBadge(mom),
            ],
          ),
          const SizedBox(height: 4),
          AnimatedCount(
            value: s.monthExpense,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 38,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _heroChip(Icons.south_west, 'Income',
                  formatRupees(s.monthIncome, compact: true),
                  onTap: () => Navigator.pushNamed(
                      context, AppRoutes.transactions,
                      arguments: TxnDirection.credit)),
              const SizedBox(width: 10),
              _heroChip(
                s.monthNet >= 0 ? Icons.savings_outlined : Icons.warning_amber,
                s.monthNet >= 0 ? 'Saved' : 'Deficit',
                formatRupees(s.monthNet.abs(), compact: true),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _heroChip(Icons.calendar_today_outlined, 'Avg / day',
                  formatRupees(s.dailyAvgExpense, compact: true)),
              const SizedBox(width: 10),
              _heroChip(Icons.category_outlined, _topCatLabel(s),
                  formatRupees(_topCatTotal(s), compact: true)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _momBadge(({double pct, bool down}) m) {
    final color = m.down ? const Color(0xFF86EFAC) : const Color(0xFFFCA5A5);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(m.down ? Icons.arrow_downward : Icons.arrow_upward,
              size: 12, color: color),
          const SizedBox(width: 2),
          Text('${m.pct.toStringAsFixed(0)}% vs last mo',
              style: TextStyle(
                  color: color, fontSize: 11, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  ({double pct, bool down})? _momChange(AnalyticsSnapshot s) {
    if (s.label != 'This month') return null;
    final now = DateTime.now();
    String mk(DateTime d) =>
        '${d.year}-${d.month.toString().padLeft(2, '0')}';
    final cur = s.monthlyExpenseSeries[mk(now)] ?? s.monthExpense;
    final last =
        s.monthlyExpenseSeries[mk(DateTime(now.year, now.month - 1, 1))] ?? 0;
    if (last <= 0) return null;
    final pct = (cur - last) / last * 100;
    return (pct: pct.abs(), down: cur < last);
  }

  Widget _heroChip(IconData icon, String label, String value,
      {VoidCallback? onTap}) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Icon(icon, color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 11)),
                    Text(value,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _budgetCard(BuildContext context, AnalyticsSnapshot s, List budgets) {
    // An explicit overall "total monthly budget" (if set) wins; otherwise fall
    // back to the sum of the per-category caps.
    final explicitTotal = budgets
        .where((b) => b.categoryId == '__total__')
        .fold<double>(0, (sum, b) => sum + (b.monthlyCap as double));
    final categorySum = budgets
        .where((b) => b.categoryId != '__total__')
        .fold<double>(0, (sum, b) => sum + (b.monthlyCap as double));
    final target = explicitTotal > 0 ? explicitTotal : categorySum;
    final spent = s.monthExpense;

    if (target <= 0) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              const Icon(Icons.savings_outlined, color: AerisColors.seed),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Set monthly budgets to see how much you have left '
                  'to spend — with live progress here.',
                  style: TextStyle(fontSize: 13),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.tonal(
                onPressed: () =>
                    Navigator.pushNamed(context, AppRoutes.budgetEdit),
                child: const Text('Set'),
              ),
            ],
          ),
        ),
      );
    }

    final pct = (spent / target).clamp(0.0, 1.0);
    final left = target - spent;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            BudgetRing(
              progress: spent / target,
              size: 116,
              center: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('${(pct * 100).toStringAsFixed(0)}%',
                      style: const TextStyle(
                          fontSize: 22, fontWeight: FontWeight.w800)),
                  const Text('used',
                      style: TextStyle(fontSize: 11, color: Colors.grey)),
                ],
              ),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Monthly budget',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          )),
                  const SizedBox(height: 10),
                  _budgetRow('Spent', spent, AerisColors.debit),
                  const SizedBox(height: 6),
                  _budgetRow('Budget', target, AerisColors.seed),
                  const SizedBox(height: 6),
                  _budgetRow(left >= 0 ? 'Left' : 'Over', left.abs(),
                      left >= 0 ? AerisColors.credit : AerisColors.debit),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _budgetRow(String label, double v, Color c) {
    return Row(
      children: [
        Container(
            width: 8,
            height: 8,
            decoration:
                BoxDecoration(color: c, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 8),
        Text(label, style: const TextStyle(fontSize: 13)),
        const Spacer(),
        Text(formatRupees(v),
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
      ],
    );
  }

  double _topCatTotal(AnalyticsSnapshot s) {
    if (s.byCategory.isEmpty) return 0;
    return s.byCategory.values.reduce((a, b) => a > b ? a : b);
  }

  String _topCatLabel(AnalyticsSnapshot s) {
    if (s.byCategory.isEmpty) return 'Top cat';
    final top =
        s.byCategory.entries.reduce((a, b) => a.value > b.value ? a : b);
    return Categories.byId(top.key).label;
  }
}

// ── Aeris level / aura card ───────────────────────────────────
class _AerisLevelCard extends ConsumerWidget {
  const _AerisLevelCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final aeris = ref.watch(avatarStatusProvider);
    final gam = ref.watch(gamificationProvider);
    return PlayOnce(
      id: 'aeris',
      delay: 100.ms,
      child: GestureDetector(
        onTap: () => Navigator.pushNamed(context, AppRoutes.aerisWorld),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color.lerp(aeris.skin.aura, Colors.black, 0.05)!,
                Color.lerp(aeris.skin.aura, Colors.black, 0.38)!,
              ],
            ),
          ),
          child: Row(children: [
            AerisAvatar(
                skin: aeris.skin,
                stage: aeris.stage,
                mood: aeris.mood,
                size: 62,
                animate: false),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Level ${aeris.level} · ${stageNames[aeris.stage]}',
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 16)),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: (gam.earned % auraPerLevel) / auraPerLevel,
                      minHeight: 7,
                      backgroundColor: Colors.white24,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                      '${gam.available} Aura · ${auraToNextLevel(gam.earned)} to level ${aeris.level + 1}',
                      style: const TextStyle(color: Colors.white, fontSize: 12)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.white),
          ]),
        ),
      ),
    );
  }
}

// ── Forecast / month-estimate card ────────────────────────────
class _ForecastCard extends ConsumerWidget {
  const _ForecastCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final insights = ref.watch(insightsProvider).asData?.value;
    if (insights == null) return const SizedBox.shrink();
    final riskyBudgets = insights.budgetProjections
        .where((p) =>
            p.alreadyOver ||
            (p.willExceed && (p.daysUntilExceed ?? 99) <= 7))
        .length;
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: PlayOnce(
        id: 'forecast',
        delay: 120.ms,
        child: Card(
          color: riskyBudgets > 0
              ? AerisColors.warning.withValues(alpha: 0.10)
              : AerisColors.info.withValues(alpha: 0.08),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              Icon(
                  riskyBudgets > 0
                      ? Icons.warning_amber_rounded
                      : Icons.insights,
                  color: riskyBudgets > 0
                      ? AerisColors.warning
                      : AerisColors.info),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(insights.monthEstimate.label,
                        style: const TextStyle(fontSize: 12)),
                    Text(formatRupees(insights.monthEstimate.estimate),
                        style: const TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 18)),
                    const SizedBox(height: 2),
                    Text(insights.cashflow.message,
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: switch (insights.cashflow.severity) {
                              InsightSeverity.positive => AerisColors.credit,
                              InsightSeverity.warning => AerisColors.warning,
                              InsightSeverity.alert => AerisColors.debit,
                              InsightSeverity.info =>
                                Theme.of(context).colorScheme.onSurfaceVariant,
                            })),
                    if (riskyBudgets > 0)
                      Text(
                          '$riskyBudgets budget${riskyBudgets == 1 ? '' : 's'} on track to exceed — see AI tab',
                          style: const TextStyle(
                              fontSize: 12,
                              color: AerisColors.warning,
                              fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

// ── Recent activity list ──────────────────────────────────────
class _RecentActivity extends ConsumerWidget {
  const _RecentActivity();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recent = ref.watch(recentTransactionsProvider(8));
    return recent.when(
      data: (list) {
        if (list.isEmpty) return _emptyRecent(context);
        return PlayOnce(
          id: 'recent',
          child: Column(
              children: [for (final t in list) TransactionTile(txn: t)]),
        );
      },
      loading: () => Column(
        children: [
          for (var i = 0; i < 4; i++)
            const SkeletonBox(
                height: 54, radius: 12, margin: EdgeInsets.symmetric(vertical: 5)),
        ],
      ),
      error: (e, _) => Text('Could not load: $e'),
    );
  }

  Widget _emptyRecent(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 30),
      child: Center(
        child: Column(
          children: [
            Icon(Icons.receipt_long_outlined,
                size: 44, color: Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(height: 10),
            const Text(
              'No transactions yet.\nEnable SMS auto-import or tap + to add one.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
