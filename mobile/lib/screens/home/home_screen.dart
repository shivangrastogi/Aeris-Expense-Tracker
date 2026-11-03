import '../../widgets/sms_disclosure.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/routes.dart';
import '../../core/theme.dart';
import '../../models/budget.dart';
import '../../models/category.dart';
import '../../models/transaction.dart';
import '../../models/user_profile.dart';
import '../../providers/accounts_provider.dart';
import '../../providers/analytics_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/income_lock_provider.dart';
import '../../providers/gamification_provider.dart';
import '../../providers/goals_provider.dart';
import '../../providers/insights_provider.dart';
import '../../providers/privacy_provider.dart';
import '../../providers/setup_provider.dart';
import '../../providers/split_provider.dart';
import '../../providers/transactions_provider.dart';
import '../../providers/money_providers.dart';
import '../../services/money_insights.dart';
import '../../services/notification_intake.dart';
import '../../utils/formatters.dart';
import '../../widgets/skeleton.dart';
import '../../widgets/transaction_tile.dart';
import '../../widgets/aeris_toast.dart';
import '../../utils/motion.dart';
import '../../widgets/ds.dart';

// Home dashboard ids the "Customize dashboard" screen can hide.
const kHomeCardForecast = 'forecast';
const kHomeCardCheckin = 'checkin';
const kHomeCardCategories = 'categories';
const kHomeCardMomentum = 'momentum';
const kHomeCardBalances = 'balances';

// The hero's spend figure counts up once per app session — the single
// entrance moment on Home. Everything else paints immediately.
bool _heroCounted = false;

// ── Home Screen ──────────────────────────────────────────────
//
// Three zones: this month (hero + where it went), one "needs attention"
// card, and recent activity. Goals, Aeris World and widgets live on the Me
// tab, so Home stays short and the important number is the loudest thing.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final importProgress = ref.watch(importProgressProvider);
    final hidden = ref.watch(gamificationProvider.select((g) => g.hiddenCards));
    return Scaffold(
      // The whole list sits below the status bar, so nothing scrolls under
      // the clock.
      body: SafeArea(
        bottom: false,
        // The design's scroll behaviour: the greeting scrolls away under a
        // pinned bar, which then takes the page colour, a hairline and a
        // small avatar + name.
        child: CollapseOnScroll(
          threshold: 30,
          builder: (context, collapsed) => Stack(children: [
            SyncRefresh(
              top: _kHomeBarH + 4,
              label: _syncLabel(ref),
              onRefresh: () async {
                ref.invalidate(transactionsStreamProvider);
                // Hold the pill until fresh data is in (and long enough to
                // read it).
                await Future.wait([
                  ref.read(transactionsStreamProvider.future).timeout(
                      const Duration(seconds: 8),
                      onTimeout: () => const <Transaction>[]),
                  Future<void>.delayed(const Duration(milliseconds: 600)),
                ]);
              },
              child: LayoutBuilder(builder: (context, box) {
                // This month: spend, setup, balances.
                final money = <Widget>[
                  const _HeroCard(),
                  const _SetupCard(),
                  if (!hidden.contains(kHomeCardBalances))
                    const _BalancesCard(),
                ];
                // Where it went, momentum, what needs you, recent.
                final story = <Widget>[
                  if (!hidden.contains(kHomeCardCategories)) ...[
                    const SizedBox(height: 16),
                    const _TopCategories(),
                  ],
                  if (!hidden.contains(kHomeCardMomentum)) ...[
                    const SizedBox(height: 16),
                    const _MomentumCard(),
                  ],
                  const _AttentionSlot(),
                  // Always rendered (an empty box when idle). Conditionally
                  // inserting the banner used to shift every keyless child
                  // below it, so reconciliation re-matched them by index and
                  // churned their elements mid-rebuild during SMS import. A
                  // constant slot keeps every sibling at a stable index.
                  _importBanner(context, importProgress),
                  const SizedBox(height: 16),
                  const _RecentActivitySection(),
                ];
                // Tablets / unfolded foldables: two columns side by side.
                final wide = box.maxWidth >= 760;
                return ListView(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
                  children: [
                    _Greeting(collapsed: collapsed),
                    const SizedBox(height: 8),
                    if (wide)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: Column(children: money)),
                          const SizedBox(width: 20),
                          // Its first item is a 16 dp gap; drop it so both
                          // columns start level.
                          Expanded(
                              child: Column(
                                  children: story.first is SizedBox
                                      ? story.skip(1).toList()
                                      : story)),
                        ],
                      )
                    else ...[
                      ...money,
                      ...story,
                    ],
                  ],
                );
              }),
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: _Header(collapsed: collapsed),
            ),
          ]),
        ),
      ),
    );
  }

  /// "Syncing 3 accounts" for the pull-to-refresh pill.
  String _syncLabel(WidgetRef ref) {
    final n = ref
        .watch(accountsProvider)
        .where((a) => a.key != unassignedAccount)
        .length;
    return n == 0 ? 'Syncing' : 'Syncing $n account${n == 1 ? '' : 's'}';
  }

  Widget _importBanner(BuildContext context, ({int done, int total})? p) {
    if (p == null) return const SizedBox.shrink();
    final pct = p.total == 0 ? null : p.done / p.total;
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: AerisCard(
        padding: const EdgeInsets.all(14),
        child: Row(children: [
          SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2.4, value: pct)),
          const SizedBox(width: 12),
          Expanded(
              child: Text('Importing bank SMS… ${p.done}/${p.total}',
                  style: const TextStyle(
                      fontSize: 13.5, fontWeight: FontWeight.w600))),
        ]),
      ),
    );
  }
}

/// First name ("Shivang") and initials ("SR") for the header.
({String name, String initials}) _who(UserProfile? profile) {
  final rawName = profile?.displayName?.trim().split(' ').first ?? '';
  final name = rawName.isEmpty
      ? 'there'
      : rawName[0].toUpperCase() + rawName.substring(1);
  final initials = (profile?.displayName ?? '?')
      .trim()
      .split(RegExp(r'\s+'))
      .take(2)
      .map((w) => w.isEmpty ? '' : w[0].toUpperCase())
      .join();
  return (name: name, initials: initials);
}

/// Height of Home's pinned top bar (and of the greeting row under it).
const _kHomeBarH = 68.0;

// ── Greeting: scrolls with the page; the pinned bar's buttons sit over its
// right side, so its text stops short of them ─────────────────────────────
class _Greeting extends ConsumerWidget {
  final bool collapsed;
  const _Greeting({required this.collapsed});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tk = context.tk;
    final profile = ref.watch(userProfileProvider).asData?.value;
    final who = _who(profile);
    final hour = DateTime.now().hour;
    final greet = hour < 12
        ? 'Good morning'
        : hour < 17
            ? 'Good afternoon'
            : 'Good evening';
    return AnimatedOpacity(
      opacity: collapsed ? 0 : 1,
      duration: reduceMotion(context) ? Duration.zero : Mo.exit,
      child: SizedBox(
        height: _kHomeBarH,
        child: Padding(
          padding: const EdgeInsets.only(right: 150),
          child: Row(children: [
            GestureDetector(
              onTap: () => Navigator.pushNamed(context, AppRoutes.editProfile),
              child: _ProfileAvatar(profile: profile, initials: who.initials),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(greet,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Ts.bodyS.copyWith(color: tk.t2)),
                  Text(who.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Ts.headline.copyWith(color: tk.t1)),
                ],
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

// ── Pinned top bar: bell · eye · Ask Aeris always; once Home scrolls it gets
// the page colour, a hairline, and a small avatar + name on the left ───────
class _Header extends ConsumerWidget {
  final bool collapsed;
  const _Header({required this.collapsed});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(userProfileProvider).asData?.value;
    final hidden = ref.watch(amountHiddenProvider);
    // The bell only shows a dot when the notifications screen actually has
    // something: imports (bank SMS, screenshots) waiting for review or a budget about to blow.
    final pendingSms = ref.watch(transactionsStreamProvider.select((a) =>
        (a.valueOrNull ?? const <Transaction>[]).any((t) => t.needsReview)));
    final riskyBudget = ref.watch(insightsProvider.select((a) =>
        (a.valueOrNull?.budgetProjections ?? const []).any((p) =>
            p.alreadyOver ||
            (p.willExceed && (p.daysUntilExceed ?? 99) <= 7))));
    final who = _who(profile);
    final tk = context.tk;
    final d = reduceMotion(context) ? Duration.zero : Mo.standard;

    return AnimatedContainer(
      duration: d,
      curve: Mo.curve,
      height: _kHomeBarH,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: collapsed ? tk.bg : tk.bg.withValues(alpha: 0),
        border: Border(
            bottom: BorderSide(
                color: collapsed ? tk.hair : tk.hair.withValues(alpha: 0))),
      ),
      child: Row(
        children: [
          Expanded(
            child: IgnorePointer(
              ignoring: !collapsed,
              child: AnimatedOpacity(
                opacity: collapsed ? 1 : 0,
                duration: d,
                child: AnimatedSlide(
                  offset: collapsed ? Offset.zero : const Offset(0, 0.15),
                  duration: d,
                  curve: Mo.curve,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () =>
                        Navigator.pushNamed(context, AppRoutes.editProfile),
                    child: Row(children: [
                      _ProfileAvatar(
                          profile: profile, initials: who.initials, size: 32),
                      const SizedBox(width: 10),
                      Flexible(
                        child: Text(who.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Ts.title.copyWith(color: tk.t1)),
                      ),
                    ]),
                  ),
                ),
              ),
            ),
          ),
          RoundIconButton(
            icon: Ph.bell,
            tooltip: 'Notifications',
            dot: pendingSms || riskyBudget,
            onTap: () => Navigator.pushNamed(context, AppRoutes.notifications),
          ),
          const SizedBox(width: 6),
          RoundIconButton(
            icon: hidden ? Ph.eyeSlash : Ph.eye,
            tooltip: hidden ? 'Show amounts' : 'Hide amounts',
            active: hidden,
            onTap: () {
              ref.read(amountHiddenProvider.notifier).toggle();
              ScaffoldMessenger.of(context).showToast(SnackBar(
                  duration: const Duration(milliseconds: 1600),
                  content: Text(hidden
                      ? 'Amounts shown'
                      : 'Amounts hidden — tap the eye again to show')));
            },
          ),
          const SizedBox(width: 6),
          RoundIconButton(
            icon: Ph.sparkle,
            tooltip: 'Ask Aeris',
            onTap: () => Navigator.pushNamed(context, AppRoutes.assistant),
          ),
        ],
      ),
    );
  }
}

// ── Profile avatar: user photo if set, else initials ──────────
class _ProfileAvatar extends StatelessWidget {
  final UserProfile? profile;
  final String initials;
  final double size;
  const _ProfileAvatar(
      {required this.profile, required this.initials, this.size = 48});

  @override
  Widget build(BuildContext context) {
    final bytes = profile?.photoBytes;
    final url = profile?.photoUrl;
    ImageProvider? img;
    if (bytes != null && bytes.isNotEmpty) {
      img = MemoryImage(bytes);
    } else if (url != null && url.isNotEmpty) {
      img = NetworkImage(url);
    }
    if (img != null) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          image: DecorationImage(image: img, fit: BoxFit.cover),
        ),
      );
    }
    return InitialAvatar('',
        initials: initials.isEmpty ? '?' : initials,
        size: size,
        color: const Color(0xFF8A7ED3));
  }
}

// ── Hero: what you've spent, and what's safe to spend ─────────
class _HeroCard extends ConsumerWidget {
  const _HeroCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(amountHiddenProvider);
    final analytics = ref.watch(analyticsProvider);
    final range = ref.watch(analyticsRangeProvider);

    return analytics.when(
      data: (s) => _card(context, s, range),
      loading: () => const SkeletonBox(height: 188, radius: 26),
      error: (_, __) => const SizedBox.shrink(),
    );
  }

  Widget _card(
      BuildContext context, AnalyticsSnapshot s, AnalyticsRange range) {
    final tk = context.tk;
    final mom = _computeMom(s);
    final isThisMonth = range.kind == RangeKind.thisMonth;
    return Semantics(
      button: true,
      label: 'Spent ${range.label}: '
          '${kAmountsHidden ? 'amount hidden' : formatRupees(s.monthExpense)}',
      child: GestureDetector(
        onTap: () => Navigator.pushNamed(context, AppRoutes.transactions,
            arguments: TxnDirection.debit),
        // The hero gradient — used on this one card and the "+" only.
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: LinearGradient(
              begin: const Alignment(-0.85, -1),
              end: const Alignment(0.85, 1),
              colors: [tk.heroA, tk.heroB],
            ),
            boxShadow: tk.shadow,
          ),
          child: DecoratedBox(
            // A soft light falling from the top-left corner.
            decoration: const BoxDecoration(
              gradient: RadialGradient(
                center: Alignment.topLeft,
                radius: 1.2,
                colors: [Color(0x2EFFFFFF), Color(0x00FFFFFF)],
                stops: [0, 0.55],
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Expanded(
                        child: Overline('Spent · ${range.label}',
                            color: tk.onHero),
                      ),
                      const SizedBox(width: 8),
                      _RangePill(label: range.label),
                    ]),
                    const SizedBox(height: 10),
                    _HeroAmount(value: s.monthExpense),
                    if (isThisMonth) ...[
                      const SizedBox(height: 14),
                      _BudgetStatus(spent: s.monthExpense),
                    ],
                    if (mom != null) ...[
                      const SizedBox(height: 14),
                      _momChip(context, mom),
                    ],
                  ]),
            ),
          ),
        ),
      ),
    );
  }

  /// "↘ 12% less than last month" on a surface pill. The arrow carries the
  /// tone (green when spending fell); the words stay plain.
  Widget _momChip(BuildContext context, ({double pct, bool down}) m) {
    final tk = context.tk;
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: tk.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(m.down ? PhBold.trendDown : PhBold.trendUp,
            size: 14, color: m.down ? tk.ok : tk.warn),
        const SizedBox(width: 6),
        Text(
            '${m.pct.toStringAsFixed(0)}% ${m.down ? 'less' : 'more'} than last month',
            style: TextStyle(
                color: tk.t1, fontSize: 12, fontWeight: FontWeight.w700)),
      ]),
    );
  }

  /// Compared against last month's total — only while viewing a month.
  ({double pct, bool down})? _computeMom(AnalyticsSnapshot s) {
    if (!s.label.toLowerCase().contains('month')) return null;
    final now = DateTime.now();
    String mk(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}';
    final cur = s.monthlyExpenseSeries[mk(now)] ?? s.monthExpense;
    final last =
        s.monthlyExpenseSeries[mk(DateTime(now.year, now.month - 1, 1))] ?? 0;
    if (last <= 0) return null;
    final pct = (cur - last) / last * 100;
    if (pct.abs() < 1) return null;
    return (pct: pct.abs(), down: cur < last);
  }
}

// ── Hero figure: count-up once per session, ₹ set smaller ─────
class _HeroAmount extends StatelessWidget {
  final double value;
  const _HeroAmount({required this.value});

  // First time Home appears this session the figure counts up from 0; after
  // that it only tweens between real changes (never re-counts on rebuild).
  @override
  Widget build(BuildContext context) => FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: CountUpMoney(
          value: value,
          counted: () => _heroCounted,
          markCounted: () => _heroCounted = true,
          color: context.tk.onHero,
        ),
      );
}

// ── Monthly budget: one thin bar + what's safe to spend per day ─
class _BudgetStatus extends ConsumerWidget {
  final double spent;
  const _BudgetStatus({required this.spent});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tk = context.tk;
    final budgets = ref.watch(effectiveBudgetsProvider);
    final total = _totalBudget(budgets);
    if (total <= 0) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 260),
          child: Text('Set a monthly budget to see what\'s safe to spend.',
              style: TextStyle(
                  color: tk.onHero,
                  fontSize: 15,
                  height: 22 / 15,
                  fontWeight: FontWeight.w500)),
        ),
        const SizedBox(height: 10),
        Material(
          color: tk.surface,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => Navigator.pushNamed(context, AppRoutes.budgets),
            child: Container(
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Ph.target, size: 16, color: tk.acc),
                const SizedBox(width: 6),
                Text('Set budget',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: tk.t1)),
              ]),
            ),
          ),
        ),
      ]);
    }

    final left = total - spent;
    final over = left < 0;
    final v = (spent / total).clamp(0.0, 1.0);
    final now = DateTime.now();
    final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
    final daysLeft = daysInMonth - now.day + 1; // including today
    final perDay = over ? 0.0 : left / daysLeft;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.pushNamed(context, AppRoutes.budgets),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Progress as the rising line that ends in a dot.
        RisingProgress(
          value: v,
          color: tk.onHero,
          track: tk.onHero.withValues(alpha: 0.22),
          stroke: 4,
          rise: 14,
          dot: 5.5,
        ),
        const SizedBox(height: 8),
        DefaultTextStyle.merge(
          style: TextStyle(
              color: tk.onHero,
              fontSize: 13,
              height: 18 / 13,
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()]),
          child: Row(children: [
            Expanded(
              child: over
                  ? Row(children: [
                      Icon(PhFill.warningCircle, size: 15, color: tk.onHero),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                            'Over by ${formatRupees(-left, compact: true)} of '
                            '${formatRupees(total, compact: true)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                      ),
                    ])
                  : Text(
                      '${formatRupees(left, compact: true)} left of '
                      '${formatRupees(total, compact: true)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
            ),
            if (!over)
              Text(
                  '${formatRupees(perDay, compact: true)}/day · '
                  '${daysLeft == 1 ? 'last day' : '$daysLeft days'}',
                  maxLines: 1),
          ]),
        ),
      ]),
    );
  }
}

// ── Momentum: the motivation panel ────────────────────────────
//
// Three live numbers that reward good behaviour — how much of your income
// you're keeping, your check-in streak, and your closest goal — plus where
// today's saving pace lands you.

class _MomentumCard extends ConsumerWidget {
  const _MomentumCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(amountHiddenProvider);
    ref.watch(incomeLockProvider); // "₹X kept" + the rate would reveal salary
    final analytics = ref.watch(analyticsProvider).asData?.value;
    final range = ref.watch(analyticsRangeProvider);
    final profile = ref.watch(userProfileProvider).asData?.value;
    final streak = ref.watch(gamificationProvider.select((g) => g.liveStreak));
    final goals = ref.watch(goalsStreamProvider).asData?.value ?? const [];
    final projection = ref.watch(projectionProvider);
    if (analytics == null) return const SizedBox.shrink();

    // Savings: income recorded in the range, else the profile's monthly
    // income while looking at this month.
    var income = analytics.monthIncome;
    if (income <= 0 && range.kind == RangeKind.thisMonth) {
      income = profile?.monthlyIncome ?? 0;
    }
    final saved = income - analytics.monthExpense;
    // Nothing recorded yet: a savings rate from profile income alone would
    // read "100% kept · On track" before the user has done anything.
    final noData = analytics.monthExpense <= 0 && analytics.monthIncome <= 0;
    final rate = income > 0 && !noData ? saved / income : null;

    // The goal closest to done (but not done yet) is the most motivating.
    final open = goals.where((g) => !g.isComplete).toList()
      ..sort((a, b) => b.progress.compareTo(a.progress));
    final goal = open.isNotEmpty ? open.first : null;

    final tk = context.tk;
    const months = [
      '',
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];

    return AerisCard(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SectionTitle('Momentum'),
        const SizedBox(height: 14),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: _Stat(
              label: 'Saved',
              value: rate == null
                  ? '—'
                  : '${(rate * 100).clamp(-999, 100).toStringAsFixed(0)}%',
              sub: rate == null
                  ? (noData && income > 0 ? 'No spends yet' : 'Add income')
                  : saved >= 0
                      ? '${formatIncome(saved, compact: true)} kept'
                      : '${formatIncome(-saved, compact: true)} over',
              color: rate != null && rate < 0 ? tk.bad : null,
              onTap: () => Navigator.pushNamed(context,
                  income <= 0 ? AppRoutes.editProfile : AppRoutes.insights),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _Stat(
              label: 'Streak',
              value: '$streak',
              sub: streak == 1 ? 'day' : 'days',
              onTap: () => _showStreakSheet(context),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _Stat(
              label: 'Goal',
              value: goal == null
                  ? '—'
                  : '${(goal.progress * 100).toStringAsFixed(0)}%',
              sub: goal == null ? 'Set one' : goal.title,
              progress: goal?.progress,
              onTap: () => Navigator.pushNamed(context, AppRoutes.goals),
            ),
          ),
        ]),
        if (projection != null) ...[
          const SizedBox(height: 14),
          // Future-you: where today's saving pace lands you.
          Semantics(
            button: true,
            child: InkWell(
              onTap: () => Navigator.pushNamed(context, AppRoutes.netWorth),
              child: Container(
                constraints: const BoxConstraints(minHeight: 48),
                padding: const EdgeInsets.only(top: 12),
                decoration: BoxDecoration(
                    border: Border(top: BorderSide(color: tk.hair))),
                child: Row(children: [
                  Icon(Ph.trendUp, size: 18, color: tk.acc),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text.rich(
                      TextSpan(children: [
                        TextSpan(
                            text:
                                'At ${formatRupees(projection.perMonth, compact: true)}/month you\'ll have '),
                        TextSpan(
                            text: formatRupees(projection.value, compact: true),
                            style:
                                const TextStyle(fontWeight: FontWeight.w700)),
                        TextSpan(
                            text:
                                ' by ${months[projection.by.month]} ${projection.by.year}'),
                      ]),
                      style: TextStyle(
                          fontSize: 13, height: 18 / 13, color: tk.t1),
                    ),
                  ),
                  Icon(Ph.arrowRight, size: 16, color: tk.t2),
                ]),
              ),
            ),
          ),
        ],
      ]),
    );
  }
}

/// One Momentum figure: overline, value, sub-line, optional progress.
class _Stat extends StatelessWidget {
  final String label;
  final String value;
  final String sub;
  final Color? color;
  final double? progress;
  final VoidCallback onTap;

  const _Stat({
    required this.label,
    required this.value,
    required this.sub,
    required this.onTap,
    this.color,
    this.progress,
  });

  @override
  Widget build(BuildContext context) {
    final tk = context.tk;
    return Semantics(
      button: true,
      label: '$label $value $sub',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Overline(label),
          const SizedBox(height: 2),
          Text(value,
              maxLines: 1, style: Ts.amountM.copyWith(color: color ?? tk.t1)),
          const SizedBox(height: 2),
          Text(sub,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style:
                  Ts.label.copyWith(fontWeight: FontWeight.w400, color: tk.t2)),
          if (progress != null) ...[
            const SizedBox(height: 6),
            RisingProgress(value: progress!, dot: 3),
          ],
        ]),
      ),
    );
  }
}

// ── "Your streak" sheet ───────────────────────────────────────
void _showStreakSheet(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => Consumer(builder: (ctx, ref2, _) {
      final g = ref2.watch(gamificationProvider);
      final streak = g.liveStreak; // lapses if a day was missed
      // The last 7 days, today on the right — never wiped by a new week.
      final days = GamificationState.recentDays();
      final week = g.recentCheckins();
      final notifier = ref2.read(gamificationProvider.notifier);
      final done = notifier.checkedInToday;
      final accent = AerisColors.accent(ctx);
      const todayIdx = 6;
      final labels = [for (final d in days) GamificationState.dayLetter(d)];
      final now = DateTime.now();
      final noSpend = noSpendWeek(
        ref2.watch(transactionsStreamProvider).valueOrNull ?? const [],
        now,
        weekStart: days.first,
      );
      final noSpendCount = noSpend.where((d) => d == true).length;

      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('$streak-day streak',
                style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5)),
            const SizedBox(height: 4),
            Text('Open AERIS and check in once a day to keep it going.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w500,
                    color: AerisColors.muted(ctx))),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (var i = 0; i < 7; i++)
                  Column(mainAxisSize: MainAxisSize.min, children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: i < week.length && week[i]
                            ? accent
                            : AerisColors.accentSoft(ctx),
                        border: i == todayIdx
                            ? Border.all(color: accent, width: 2)
                            : null,
                      ),
                      child: i < week.length && week[i]
                          ? Icon(PhBold.check,
                              size: 18, color: AerisColors.onAccent(ctx))
                          : null,
                    ),
                    const SizedBox(height: 6),
                    Text(labels[i],
                        style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: AerisColors.muted(ctx))),
                    const SizedBox(height: 4),
                    // No-spend day badge (past days with ₹0 spent).
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        color: noSpend[i] == true
                            ? AerisColors.moneyIn(ctx).withValues(alpha: 0.16)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Text('₹0',
                          style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w800,
                              color: noSpend[i] == true
                                  ? AerisColors.moneyIn(ctx)
                                  : Colors.transparent)),
                    ),
                  ]),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              noSpendCount == 0
                  ? 'No-spend days earn +10 Aura each — they show up here.'
                  : '$noSpendCount no-spend day${noSpendCount == 1 ? '' : 's'} in the last 7 days · +${noSpendCount * 10} Aura',
              style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: noSpendCount == 0
                      ? AerisColors.muted(ctx)
                      : AerisColors.moneyIn(ctx)),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: done
                    ? null
                    : () {
                        final aura = notifier.checkIn();
                        ScaffoldMessenger.of(ctx).showToast(SnackBar(
                          content: Text(aura > 0
                              ? 'Checked in · +$aura Aura'
                              : 'Already checked in today'),
                          duration: const Duration(seconds: 2),
                        ));
                      },
                child:
                    Text(done ? 'Checked in today ✓' : 'Check in · +15 Aura'),
              ),
            ),
          ]),
        ),
      );
    }),
  );
}

// Range selector pill embedded inside the hero card
class _RangePill extends ConsumerWidget {
  final String label;
  const _RangePill({required this.label});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Semantics(
      button: true,
      label: 'Change date range, currently $label',
      child: GestureDetector(
        onTap: () => _showSheet(context, ref),
        child: Container(
          height: 32,
          padding: const EdgeInsets.fromLTRB(12, 0, 10, 0),
          decoration: BoxDecoration(
              color: context.tk.onHero.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(12)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(label,
                style: TextStyle(
                    color: context.tk.onHero,
                    fontSize: 12,
                    fontWeight: FontWeight.w700)),
            const SizedBox(width: 4),
            Icon(PhBold.caretDown, color: context.tk.onHero, size: 12),
          ]),
        ),
      ),
    );
  }

  void _showSheet(BuildContext context, WidgetRef ref) {
    final options = [
      AnalyticsRange.thisMonth(),
      AnalyticsRange.lastDays(7, 'Last 7 days'),
      AnalyticsRange.lastDays(30, 'Last 30 days'),
      AnalyticsRange.thisYear(),
    ];
    showDsSheet<void>(
      context,
      title: 'Show spending for',
      builder: (ctx) => ListGroup(inset: 16, children: [
        for (final r in options)
          DsRow(
            minHeight: 52,
            title: r.label,
            trailing: r.label == label
                ? Icon(PhBold.check, size: 18, color: ctx.tk.acc)
                : null,
            onTap: () {
              ref.read(analyticsRangeProvider.notifier).state = r;
              Navigator.pop(ctx);
            },
          ),
      ]),
    );
  }
}

// ── Budget math shared by the hero bar and the attention card ─
double _totalBudget(List<Budget> budgets) {
  final explicit = budgets
      .where((b) => b.categoryId == Budget.totalId)
      .fold<double>(0, (s, b) => s + b.monthlyCap);
  final catSum = budgets
      .where((b) => b.categoryId != Budget.totalId)
      .fold<double>(0, (s, b) => s + b.monthlyCap);
  return explicit > 0 ? explicit : catSum;
}

List<Budget> _overBudget(
        List<Budget> budgets, Map<String, double> byCat) =>
    budgets
        .where((b) =>
            b.categoryId != Budget.totalId &&
            b.monthlyCap > 0 &&
            (byCat[b.categoryId] ?? 0) > b.monthlyCap)
        .toList()
      ..sort((a, b) {
        final aOver = (byCat[a.categoryId] ?? 0) - a.monthlyCap;
        final bOver = (byCat[b.categoryId] ?? 0) - b.monthlyCap;
        return bOver.compareTo(aOver);
      });

// ── Where it went: the three biggest categories ───────────────
/// "Finish setting up" — the steps that make AERIS automatic, each one tap
/// away. Hidden once all are done or the user hides it. Re-checks when the
/// app resumes (permissions are granted in Android settings).
class _SetupCard extends ConsumerStatefulWidget {
  const _SetupCard();

  @override
  ConsumerState<_SetupCard> createState() => _SetupCardState();
}

class _SetupCardState extends ConsumerState<_SetupCard>
    with WidgetsBindingObserver {
  static const _hiddenKey = 'setup_card_hidden';
  bool? _hidden;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SharedPreferences.getInstance().then((p) {
      if (mounted) setState(() => _hidden = p.getBool(_hiddenKey) ?? false);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) ref.invalidate(setupStatusProvider);
  }

  void _toast(String m) =>
      ScaffoldMessenger.of(context).showToast(SnackBar(content: Text(m)));

  Future<void> _hide() async {
    await (await SharedPreferences.getInstance()).setBool(_hiddenKey, true);
    if (mounted) setState(() => _hidden = true);
    _toast('Hidden — everything is still in Settings.');
  }

  Future<void> _sms() async {
    if (await requestSmsWithDisclosure(context)) {
      _toast('Bank SMS will be read on your phone, privately.');
    } else if (mounted) {
      // Sideloaded apps need "Allow restricted settings" first; Settings
      // explains that path.
      Navigator.pushNamed(context, AppRoutes.settings);
    }
    ref.invalidate(setupStatusProvider);
  }

  Future<void> _reminders() async {
    _toast(await turnOnReminders(ref)
        ? 'Reminders on — bills, card dues, money owed and a weekly recap.'
        : 'Notifications are off for AERIS in Android settings.');
    ref.invalidate(setupStatusProvider);
  }

  @override
  Widget build(BuildContext context) {
    if (_hidden != false) return const SizedBox.shrink();
    final s = ref.watch(setupStatusProvider).valueOrNull;
    if (s == null || s.complete) return const SizedBox.shrink();
    final tk = context.tk;

    final steps = <(bool, IconData, String, VoidCallback)>[
      (s.sms, Ph.chatText, 'Read bank SMS', _sms),
      (
        s.notifications,
        Ph.bellRinging,
        'Catch UPI app payments',
        () => NotificationIntake.instance.openSettings()
      ),
      (
        s.income,
        Ph.briefcase,
        'Add your monthly income',
        () => Navigator.pushNamed(context, AppRoutes.editProfile)
      ),
      (
        s.budget,
        Ph.target,
        'Set a monthly budget',
        () => Navigator.pushNamed(context, AppRoutes.budgets)
      ),
      (s.reminders, Ph.alarm, 'Turn on reminders', _reminders),
    ];

    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: AerisColors.cardDecoration(context),
        padding: const EdgeInsets.only(top: 16, bottom: 6),
        child: Material(
          type: MaterialType.transparency,
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 8, 6),
              child: Row(children: [
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Finish setting up',
                            style: Ts.title.copyWith(color: tk.t1)),
                        const SizedBox(height: 6),
                        Row(children: [
                          SizedBox(
                            width: 96,
                            child: RisingProgress(
                                value: s.done / SetupStatus.total,
                                rise: 4,
                                stroke: 2,
                                dot: 3),
                          ),
                          const SizedBox(width: 8),
                          Text('${s.done} of ${SetupStatus.total}',
                              style: Ts.label.copyWith(
                                  fontWeight: FontWeight.w700, color: tk.t2)),
                        ]),
                      ]),
                ),
                TextButton(
                    onPressed: _hide,
                    style: TextButton.styleFrom(
                        foregroundColor: tk.t2,
                        minimumSize: const Size(48, 48)),
                    child: const Text('Hide')),
              ]),
            ),
            for (final (done, icon, title, onTap) in steps)
              InkWell(
                onTap: done ? null : onTap,
                child: Container(
                  constraints: const BoxConstraints(minHeight: 52),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(children: [
                    Icon(done ? PhFill.checkCircle : icon,
                        size: 20, color: done ? tk.ok : tk.acc),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(title,
                          style: TextStyle(
                              fontSize: 15,
                              fontWeight:
                                  done ? FontWeight.w400 : FontWeight.w600,
                              color: done ? tk.t2 : tk.t1)),
                    ),
                    if (!done) Icon(Ph.caretRight, size: 16, color: tk.t3),
                  ]),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}

/// Bank balances as the banks last reported them in SMS, plus unpaid card
/// bills. Hidden until there's at least one of either.
class _BalancesCard extends ConsumerWidget {
  const _BalancesCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(amountHiddenProvider);
    final accounts = ref
        .watch(accountsProvider)
        .where((a) => a.bankBalance != null)
        .toList()
      ..sort((a, b) => b.bankBalanceAt!.compareTo(a.bankBalanceAt!));
    final dues = ref.watch(cardDuesProvider).valueOrNull ?? const [];
    final low = ref.watch(lowBalanceLimitProvider);
    final owed = ref.watch(owedToYouProvider);
    final owedTotal = owed.values.fold<double>(0, (s, v) => s + v);
    if (accounts.isEmpty && dues.isEmpty && owed.isEmpty) {
      return const SizedBox.shrink();
    }
    final tk = context.tk;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    // "HDFC salary ••4521" → "HD"; "SBI ••8208" → "SBI".
    String badge(String label) {
      final w = label.trim().split(RegExp(r'\s+')).first.toUpperCase();
      final letters = w.replaceAll(RegExp(r'[^A-Z]'), '');
      if (letters.isEmpty) return '••';
      return letters.length <= 3 ? letters : letters.substring(0, 2);
    }

    Widget row(Widget tile, String title, Widget sub, num value,
            {Color? valueColor, bool decimals = true, VoidCallback? onTap}) =>
        DsRow(
          leading: tile,
          title: title,
          titleMaxLines: 1,
          subWidget: sub,
          minHeight: 60,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          onTap:
              onTap ?? () => Navigator.pushNamed(context, AppRoutes.accounts),
          trailing:
              MoneyText(value, smallDecimals: decimals, color: valueColor),
        );
    Widget subText(String s) => Text(s,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Ts.label.copyWith(fontWeight: FontWeight.w400, color: tk.t2));

    final rows = <Widget>[
      for (final a in accounts.take(3))
        row(
          BadgeTile(text: badge(a.label)),
          a.label,
          subText('as of ${asOfLabel(a.bankBalanceAt!)}'),
          a.bankBalance!,
          valueColor: low > 0 && a.bankBalance! < low ? tk.bad : null,
        ),
      for (final d in dues.take(2))
        () {
          final days = DateTime(d.dueDate.year, d.dueDate.month, d.dueDate.day)
              .difference(today)
              .inDays;
          final when = days < 0
              ? 'Overdue since ${shortDate(d.dueDate)}'
              : days == 0
                  ? 'Due today'
                  : days == 1
                      ? 'Due tomorrow'
                      : 'Due ${shortDate(d.dueDate)}';
          final urgent = days <= 2;
          return row(
            BadgeTile(
                icon: Ph.creditCard,
                tint: urgent && days < 0 ? tk.bad : tk.warn),
            d.label,
            Row(children: [
              Icon(PhFill.clock, size: 13, color: days < 0 ? tk.bad : tk.warn),
              const SizedBox(width: 4),
              Flexible(
                child: subText(d.minimum == null
                    ? when
                    : '$when · min ${formatRupees(d.minimum!)}'),
              ),
            ]),
            d.total,
            decimals: false,
            valueColor: days < 0 ? tk.bad : null,
          );
        }(),
      if (owed.isNotEmpty)
        row(
          owed.length == 1
              ? InitialAvatar(owed.keys.single, color: const Color(0xFF5F9A4C))
              : BadgeTile(icon: Ph.usersThree, tint: tk.ok),
          'Owed to you',
          subText(owed.length == 1
              ? 'from ${owed.keys.single} · shared bills'
              : 'from ${owed.length} people · shared bills'),
          owedTotal,
          decimals: false,
          valueColor: tk.ok,
          onTap: () => Navigator.pushNamed(context, AppRoutes.people),
        ),
    ];

    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: AerisColors.cardDecoration(context),
        padding: const EdgeInsets.only(top: 16, bottom: 4),
        child: Material(
          type: MaterialType.transparency,
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SectionTitle('Balances',
                note: accounts.isNotEmpty ? 'from bank SMS' : null,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 4)),
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0)
                Padding(
                  padding: const EdgeInsets.only(left: 68),
                  child: Container(height: 1, color: tk.hair),
                ),
              rows[i],
            ],
          ]),
        ),
      ),
    );
  }
}

class _TopCategories extends ConsumerStatefulWidget {
  const _TopCategories();

  @override
  ConsumerState<_TopCategories> createState() => _TopCategoriesState();
}

class _TopCategoriesState extends ConsumerState<_TopCategories> {
  // Rings stay empty until Home is actually on screen, then tween in —
  // otherwise the fill would play hidden behind the splash.
  bool _ready = false;

  @override
  Widget build(BuildContext context) {
    ref.watch(amountHiddenProvider);
    final analytics = ref.watch(analyticsProvider).asData?.value;
    final budgets = ref.watch(effectiveBudgetsProvider);
    if (analytics == null) return const SizedBox(height: 128);

    if (!_ready) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_ready) setState(() => _ready = true);
      });
    }

    // Biggest three spend categories. With a category cap the ring tracks
    // used/cap (and warns); without one it shows share of total spend.
    // Monthly caps only make sense against this month's spend; for other
    // ranges the rings show share of spend instead.
    final isMonth =
        ref.watch(analyticsRangeProvider).kind == RangeKind.thisMonth;
    final capFor = <String, double>{
      if (isMonth)
        for (final b in budgets.where((b) => b.categoryId != Budget.totalId))
          b.categoryId: b.monthlyCap,
    };
    final top = analytics.byCategory.entries.where((e) => e.value > 0).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final top3 = top.take(3).toList();
    if (top3.isEmpty) return const SizedBox.shrink();
    final spendTotal = top.fold<double>(0, (s, e) => s + e.value);
    final tk = context.tk;

    return AerisCard(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SectionTitle('Where it went',
            action: 'See all',
            onAction: () => Navigator.pushNamed(context, AppRoutes.insights)),
        const SizedBox(height: 6),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final e in top3)
              Expanded(
                child: Builder(builder: (context) {
                  final cat = Categories.byId(e.key);
                  final cap = capFor[e.key];
                  final hasCap = cap != null && cap > 0;
                  final v = hasCap
                      ? e.value / cap
                      : (spendTotal == 0 ? 0.0 : e.value / spendTotal);
                  return Semantics(
                    button: true,
                    label: '${cat.label}: ${formatRupees(e.value)}',
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => Navigator.pushNamed(
                          context, AppRoutes.transactions,
                          arguments: e.key),
                      child: Column(children: [
                        CatRing(
                          value: _ready ? v : 0.0,
                          color: cat.color,
                          over: hasCap && v > 1,
                          center: CatTile.of(cat),
                        ),
                        const SizedBox(height: 6),
                        Text(cat.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: tk.t1)),
                        const SizedBox(height: 4),
                        MoneyText(e.value,
                            compact: true,
                            style: const TextStyle(
                                fontSize: 15,
                                height: 18 / 15,
                                fontWeight: FontWeight.w700)),
                        const SizedBox(height: 4),
                        if (hasCap)
                          Row(mainAxisSize: MainAxisSize.min, children: [
                            if (v > 1) ...[
                              Icon(PhFill.warningCircle,
                                  size: 12, color: tk.bad),
                              const SizedBox(width: 3),
                            ],
                            Text(
                                v > 1
                                    ? 'Over'
                                    : 'of ${formatRupees(cap, compact: true)}',
                                maxLines: 1,
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: v > 1
                                        ? FontWeight.w700
                                        : FontWeight.w400,
                                    color: v > 1 ? tk.bad : tk.t2)),
                          ])
                        else
                          Text('${(v * 100).round()}% of spend',
                              maxLines: 1,
                              style: TextStyle(fontSize: 11, color: tk.t2)),
                      ]),
                    ),
                  );
                }),
              ),
          ],
        ),
      ]),
    );
  }
}

// ── The one "needs attention" card ────────────────────────────
//
// Several things used to compete for this spot as separate cards. Now only
// the most urgent shows: over budget › budgets at risk this week › today's
// check-in › the month-end forecast.
class _AttentionSlot extends ConsumerStatefulWidget {
  const _AttentionSlot();

  @override
  ConsumerState<_AttentionSlot> createState() => _AttentionSlotState();
}

class _AttentionSlotState extends ConsumerState<_AttentionSlot> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    // Over-budget is a calendar-month question, not the selected range.
    final analytics = ref.watch(monthAnalyticsProvider);
    final budgets = ref.watch(effectiveBudgetsProvider);
    final insights = ref.watch(insightsProvider).valueOrNull;
    final hidden = ref.watch(gamificationProvider.select((g) => g.hiddenCards));
    final checkin = ref.watch(gamificationProvider.select(
        (g) => (loaded: g.loaded, done: g.checkedInOn(DateTime.now()))));
    final tk = context.tk;

    // Everything that wants the user, most urgent first: over budget ›
    // budgets at risk this week › today's check-in › the month forecast.
    final showForecast =
        insights != null && !hidden.contains(kHomeCardForecast);
    final risky = insights?.budgetProjections
            .where((p) =>
                p.alreadyOver ||
                (p.willExceed && (p.daysUntilExceed ?? 99) <= 7))
            .length ??
        0;
    final cards = <Widget>[
      if (analytics != null &&
          _overBudget(budgets, analytics.byCategory).isNotEmpty)
        const _OverBudgetCard(),
      if (showForecast && risky > 0) const _ForecastStrip(),
      if (checkin.loaded && !checkin.done && !hidden.contains(kHomeCardCheckin))
        const _CheckinStrip(),
      if (showForecast && risky == 0) const _ForecastStrip(),
    ];
    if (cards.isEmpty) return const SizedBox.shrink();
    final i = _index % cards.length;
    void step(int by) {
      HapticFeedback.selectionClick();
      setState(() => _index = (i + by) % cards.length);
    }

    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 0, 8),
          child: Row(children: [
            const Expanded(child: Overline('Needs attention')),
            // "1 of 3": tap (or swipe the card) for the next one.
            if (cards.length > 1)
              Semantics(
                button: true,
                label: 'Item ${i + 1} of ${cards.length}. Show next.',
                excludeSemantics: true,
                child: InkWell(
                  onTap: () => step(1),
                  borderRadius: BorderRadius.circular(Rad.chip),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text('${i + 1} of ${cards.length}',
                          style: Ts.label.copyWith(color: tk.t2)),
                      const SizedBox(width: 2),
                      Icon(Ph.caretRight, size: 14, color: tk.t2),
                    ]),
                  ),
                ),
              ),
          ]),
        ),
        GestureDetector(
          onHorizontalDragEnd: cards.length < 2
              ? null
              : (d) {
                  final v = d.primaryVelocity ?? 0;
                  if (v.abs() > 200) step(v < 0 ? 1 : cards.length - 1);
                },
          child: AnimatedSwitcher(
            duration: reduceMotion(context) ? Duration.zero : Mo.standard,
            switchInCurve: Mo.curve,
            child: KeyedSubtree(key: ValueKey(i), child: cards[i]),
          ),
        ),
      ]),
    );
  }
}

// ── Over-budget category card ─────────────────────────────────
class _OverBudgetCard extends ConsumerWidget {
  const _OverBudgetCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(amountHiddenProvider);
    final analytics = ref.watch(monthAnalyticsProvider);
    final budgets = ref.watch(effectiveBudgetsProvider);
    if (analytics == null) return const SizedBox.shrink();

    final byCategory = analytics.byCategory;
    final overBudget = _overBudget(budgets, byCategory);
    if (overBudget.isEmpty) return const SizedBox.shrink();

    // The worst one leads; any others are named in the line below it.
    final b = overBudget.first;
    final cat = Categories.byId(b.categoryId);
    final over = (byCategory[b.categoryId] ?? 0) - b.monthlyCap;
    final now = DateTime.now();
    final daysLeft = DateTime(now.year, now.month + 1, 0).day - now.day + 1;
    final others = overBudget
        .skip(1)
        .map((x) => Categories.byId(x.categoryId).label)
        .toList();
    return Banner2(
      tone: Tone.bad,
      icon: PhFill.warningOctagon,
      title: '${cat.label} is ${formatRupees(over)} over budget',
      body: others.isEmpty
          ? '$daysLeft day${daysLeft == 1 ? '' : 's'} to go this month.'
          : '${others.join(', ')} ${others.length == 1 ? 'is' : 'are'} over '
              'too · $daysLeft days to go.',
      action: 'See budget',
      onTap: () => Navigator.pushNamed(context, AppRoutes.budgets),
    );
  }
}

// ── Compact check-in strip ────────────────────────────────────
class _CheckinStrip extends ConsumerWidget {
  const _CheckinStrip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watch only the fields this strip renders — not the whole gamification
    // object — so aura ticks elsewhere don't rebuild it.
    final s = ref.watch(gamificationProvider.select((g) => (
          loaded: g.loaded,
          streak: g.liveStreak,
          checkedIn: g.checkedInOn(DateTime.now()),
        )));
    if (!s.loaded) return const SizedBox.shrink();

    final streak = s.streak; // lapses if a day was missed
    final checkedIn = s.checkedIn;
    final bonus = (streak * 5).clamp(0, 60);
    final accent = AerisColors.accent(context);

    return AerisCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      onTap: () => _showStreakSheet(context),
      child: Row(children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(13),
            color: AerisColors.accentSoft(context),
          ),
          child: Icon(
            checkedIn ? Ph.checkCircle : Ph.flame,
            size: 21,
            color: accent,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  checkedIn
                      ? 'Checked in · $streak day${streak == 1 ? '' : 's'}'
                      : streak > 0
                          ? 'Keep your $streak-day streak'
                          : 'Start a streak today',
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  checkedIn
                      ? 'See you tomorrow'
                      : 'Daily check-in · +${15 + bonus} Aura',
                  style: TextStyle(
                      fontSize: 12,
                      color: AerisColors.muted(context),
                      fontWeight: FontWeight.w500),
                ),
              ]),
        ),
        const SizedBox(width: 8),
        FilledButton(
          onPressed: checkedIn
              ? null
              : () {
                  final notifier = ref.read(gamificationProvider.notifier);
                  final awarded = notifier.checkIn();
                  if (awarded > 0) {
                    // Read the streak *after* check-in — never guess with +1,
                    // which was wrong whenever the streak had lapsed.
                    final newStreak =
                        ref.read(gamificationProvider).checkinStreak;
                    ScaffoldMessenger.of(context).showToast(SnackBar(
                      content: Text('+$awarded Aura · $newStreak-day streak'),
                      duration: const Duration(seconds: 2),
                    ));
                  }
                },
          style: FilledButton.styleFrom(
            minimumSize: const Size(0, 38),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            shape: const StadiumBorder(),
            textStyle: const TextStyle(
                fontFamily: kFontFamily,
                fontSize: 13,
                fontWeight: FontWeight.w800),
          ),
          child: Text(checkedIn ? 'Done' : 'Check in'),
        ),
      ]),
    );
  }
}

// ── Forecast strip ────────────────────────────────────────────
class _ForecastStrip extends ConsumerWidget {
  const _ForecastStrip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(amountHiddenProvider);
    final insights = ref.watch(insightsProvider).valueOrNull;
    if (insights == null) return const SizedBox.shrink();

    final riskyCount = insights.budgetProjections
        .where((p) =>
            p.alreadyOver || (p.willExceed && (p.daysUntilExceed ?? 99) <= 7))
        .length;
    final estimate = insights.monthEstimate.estimate;
    final tone = riskyCount > 0 ? context.tk.warn : context.tk.acc;

    return AerisCard(
      padding: const EdgeInsets.all(14),
      onTap: () => Navigator.pushNamed(context, AppRoutes.insights),
      child: Row(children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
              color: tone.withValues(alpha: 0.13),
              borderRadius: BorderRadius.circular(13)),
          child: Icon(Ph.chartLineUp, size: 22, color: tone),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text.rich(
            TextSpan(
              style: TextStyle(
                  fontSize: 13.5,
                  color: Theme.of(context).colorScheme.onSurface,
                  fontWeight: FontWeight.w500,
                  height: 1.4),
              children: [
                const TextSpan(text: 'On pace for '),
                TextSpan(
                  text: formatRupees(estimate),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const TextSpan(text: ' this month'),
                if (riskyCount > 0) ...[
                  const TextSpan(text: ' · '),
                  TextSpan(
                    text:
                        '$riskyCount budget${riskyCount == 1 ? '' : 's'} at risk',
                    style: TextStyle(
                        color: context.tk.warn, fontWeight: FontWeight.w700),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(width: 6),
        Icon(Ph.caretRight, size: 16, color: context.tk.t3),
      ]),
    );
  }
}

// ── Recent activity, grouped by day ───────────────────────────
class _RecentActivitySection extends ConsumerWidget {
  const _RecentActivitySection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(amountHiddenProvider);
    final recent = ref.watch(recentTransactionsProvider(6));
    return recent.when(
      data: (list) {
        if (list.isEmpty) return const _FirstRunCard();
        final groups = <String, List<Transaction>>{};
        for (final t in list) {
          groups.putIfAbsent(_dayLabel(t.timestamp), () => []).add(t);
        }
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SectionTitle('Recent',
              action: 'See all',
              padding: const EdgeInsets.only(left: 4),
              onAction: () =>
                  Navigator.pushNamed(context, AppRoutes.transactions)),
          for (final g in groups.entries) ...[
            DayHeader(g.key, total: _dayTotal(g.value)),
            ListGroup(children: [
              for (final t in g.value) TransactionTile(txn: t, showDate: false),
            ]),
            const SizedBox(height: 6),
          ],
        ]);
      },
      loading: () => Column(
        children: List.generate(
            4,
            (_) => const SkeletonBox(
                height: 64,
                radius: Rad.tile,
                margin: EdgeInsets.symmetric(vertical: 4))),
      ),
      error: (e, _) => const Banner2(
        tone: Tone.bad,
        icon: PhFill.cloudX,
        title: "Couldn't load your transactions",
        body: 'Pull down to try again.',
      ),
    );
  }

  static String _dayLabel(DateTime d) {
    final now = DateTime.now();
    final day = DateTime(d.year, d.month, d.day);
    final diff = DateTime(now.year, now.month, now.day).difference(day).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    return shortDate(d);
  }

  /// Net for the day: spend shows as "−₹1,686"; a day of only money in
  /// shows "+₹…". Own-account transfers and paybacks don't count.
  static String _dayTotal(List<Transaction> ts) {
    var net = 0.0;
    for (final t in ts) {
      if (t.isInternal) continue;
      net += t.isCredit ? t.amount : -t.amount;
    }
    return signedMoney(net, credit: net > 0);
  }
}

/// Shown instead of "Recent" until the first transaction exists.
class _FirstRunCard extends StatelessWidget {
  const _FirstRunCard();

  @override
  Widget build(BuildContext context) {
    final tk = context.tk;
    return AerisCard(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
              color: tk.accSoft, borderRadius: BorderRadius.circular(14)),
          child: Icon(Ph.receipt, size: 24, color: tk.acc),
        ),
        const SizedBox(height: 12),
        Text('Log your first expense', style: Ts.title.copyWith(color: tk.t1)),
        const SizedBox(height: 4),
        Text('Or just wait. New bank SMS will show up here on their own.',
            style: Ts.bodyS.copyWith(color: tk.t2)),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: FilledButton(
              onPressed: () => Navigator.pushNamed(context, AppRoutes.addTxn,
                  arguments: TxnDirection.debit),
              child: const Text('Add expense'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TonalButton('Say it',
                icon: Ph.microphone,
                onPressed: () => Navigator.pushNamed(context, AppRoutes.voice)),
          ),
        ]),
      ]),
    );
  }
}
