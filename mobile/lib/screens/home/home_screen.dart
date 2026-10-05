import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/routes.dart';
import '../../core/theme.dart';
import '../../models/budget.dart';
import '../../models/category.dart';
import '../../models/transaction.dart';
import '../../models/user_profile.dart';
import '../../providers/analytics_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/gamification_provider.dart';
import '../../providers/goals_provider.dart';
import '../../providers/insights_provider.dart';
import '../../providers/privacy_provider.dart';
import '../../providers/transactions_provider.dart';
import '../../providers/money_providers.dart';
import '../../services/money_insights.dart';
import '../../utils/formatters.dart';
import '../../utils/motion.dart';
import '../../widgets/budget_ring.dart';
import '../../widgets/skeleton.dart';
import '../../widgets/transaction_tile.dart';
import '../../widgets/aeris_toast.dart';

// Home dashboard ids the "Customize dashboard" screen can hide.
const kHomeCardForecast = 'forecast';
const kHomeCardCheckin = 'checkin';
const kHomeCardCategories = 'categories';
const kHomeCardMomentum = 'momentum';

// The hero's spend figure counts up once per app session — the single
// entrance moment on Home. Everything else paints immediately.
bool _heroCounted = false;

// Colours used on the dark ink hero, in both themes.
const _heroMuted = Color(0xB3EAF2F7); // HUD text 70%
const _heroGood = AerisColors.mint; // "down" trends, safe figures
const _heroBad = Color(0xFFFF8A98); // over budget
const _heroUp = AerisColors.amber; // spending up

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
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(transactionsStreamProvider),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
          children: [
            const SafeArea(bottom: false, child: _Header()),
            const _HeroCard(),
            if (!hidden.contains(kHomeCardMomentum)) ...[
              const SizedBox(height: 14),
              const _MomentumCard(),
            ],
            if (!hidden.contains(kHomeCardCategories)) ...[
              const SizedBox(height: 14),
              const _TopCategories(),
            ],
            const _AttentionSlot(),
            // Always rendered (an empty box when idle). Conditionally inserting
            // the banner here used to shift every keyless child below it, so
            // reconciliation re-matched them by index and churned their
            // elements mid-rebuild during SMS import. A constant slot keeps
            // every sibling at a stable index.
            _importBanner(context, importProgress),
            const SizedBox(height: 24),
            const _RecentActivitySection(),
          ],
        ),
      ),
    );
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

// ── Header: avatar · greeting · bell · eye · Ask Aeris ────────
class _Header extends ConsumerWidget {
  const _Header();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(userProfileProvider).asData?.value;
    final hidden = ref.watch(amountHiddenProvider);
    // The bell only shows a dot when the notifications screen actually has
    // something: imports (bank SMS, screenshots) waiting for review or a budget about to blow.
    final pendingSms = ref.watch(transactionsStreamProvider.select((a) =>
        (a.valueOrNull ?? const <Transaction>[])
            .any((t) => t.needsReview)));
    final riskyBudget = ref.watch(insightsProvider.select((a) =>
        (a.valueOrNull?.budgetProjections ?? const []).any((p) =>
            p.alreadyOver ||
            (p.willExceed && (p.daysUntilExceed ?? 99) <= 7))));

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

    final hour = DateTime.now().hour;
    final greet = hour < 12
        ? 'Good morning'
        : hour < 17
            ? 'Good afternoon'
            : 'Good evening';

    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 10, 0, 18),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pushNamed(context, AppRoutes.editProfile),
            child: _ProfileAvatar(profile: profile, initials: initials),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(greet,
                    style: TextStyle(
                        fontSize: 13,
                        color: AerisColors.muted(context),
                        fontWeight: FontWeight.w500)),
                const SizedBox(height: 1),
                Text(name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                        height: 1.15)),
              ],
            ),
          ),
          _RoundIconBtn(
            icon: Icons.notifications_none_rounded,
            tooltip: 'Notifications',
            badge: pendingSms || riskyBudget,
            onTap: () => Navigator.pushNamed(context, AppRoutes.notifications),
          ),
          const SizedBox(width: 8),
          _RoundIconBtn(
            icon: hidden
                ? Icons.visibility_off_outlined
                : Icons.visibility_outlined,
            tooltip: hidden ? 'Show amounts' : 'Hide amounts',
            active: hidden,
            onTap: () => ref.read(amountHiddenProvider.notifier).toggle(),
          ),
          const SizedBox(width: 8),
          _RoundIconBtn(
            icon: Icons.auto_awesome_rounded,
            tooltip: 'Ask Aeris',
            active: true,
            onTap: () => Navigator.pushNamed(context, AppRoutes.assistant),
          ),
        ],
      ),
    );
  }
}

class _RoundIconBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool active;
  final bool badge;
  const _RoundIconBtn({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.active = false,
    this.badge = false,
  });

  @override
  Widget build(BuildContext context) {
    final accent = AerisColors.accent(context);
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        child: GestureDetector(
          onTap: onTap,
          child: Stack(clipBehavior: Clip.none, children: [
            Container(
              width: 42,
              height: 42,
              decoration: active
                  ? BoxDecoration(
                      shape: BoxShape.circle,
                      color: AerisColors.accentSoft(context))
                  : AerisColors.cardDecoration(context, radius: 21),
              child: Icon(icon,
                  size: 20,
                  color: active
                      ? accent
                      : Theme.of(context).colorScheme.onSurface),
            ),
            if (badge)
              Positioned(
                top: 1,
                right: 1,
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AerisColors.danger(context),
                    border: Border.all(
                        color: AerisColors.canvas(context), width: 2),
                  ),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}

// ── Profile avatar: user photo if set, else initials ──────────
class _ProfileAvatar extends StatelessWidget {
  final UserProfile? profile;
  final String initials;
  const _ProfileAvatar({required this.profile, required this.initials});

  @override
  Widget build(BuildContext context) {
    const size = 44.0;
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
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
          shape: BoxShape.circle, color: AerisColors.accentSoft(context)),
      child: Center(
        child: Text(
          initials.isEmpty ? '?' : initials,
          style: TextStyle(
              color: AerisColors.accent(context),
              fontSize: size * 0.36,
              fontWeight: FontWeight.w800),
        ),
      ),
    );
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
    final dark = Theme.of(context).brightness == Brightness.dark;
    final mom = _computeMom(s);
    final isThisMonth = range.kind == RangeKind.thisMonth;
    return Semantics(
      button: true,
      label: 'Spent ${range.label}: ${formatRupees(s.monthExpense)}',
      child: GestureDetector(
        onTap: () => Navigator.pushNamed(context, AppRoutes.transactions,
            arguments: TxnDirection.debit),
        child: Container(
          clipBehavior: Clip.antiAlias,
          // A HUD slab: deep navy, a hairline arc edge and an arc glow.
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(26),
            gradient: AerisColors.inkGradient,
            border: Border.all(color: AerisColors.arc.withValues(alpha: 0.22)),
            boxShadow: [
              BoxShadow(
                  color: dark
                      ? AerisColors.arc.withValues(alpha: 0.14)
                      : const Color(0x330B1220),
                  blurRadius: 28,
                  offset: const Offset(0, 12)),
            ],
          ),
          child: Stack(children: [
            // Soft arc/violet glows in the corners — the "screen" feel.
            const Positioned(
                right: -70, top: -80, child: _Glow(AerisColors.arc, 220)),
            const Positioned(
                left: -60, bottom: -110, child: _Glow(AerisColors.violet, 200)),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: AerisColors.arc,
                            boxShadow: [
                              BoxShadow(color: AerisColors.arc, blurRadius: 6)
                            ]),
                      ),
                      const SizedBox(width: 8),
                      // Flexible: on 320dp phones the wide-tracked caption
                      // must give way to the range pill, not overflow.
                      Expanded(
                        child: Text('SPENT · ${range.label.toUpperCase()}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: hudLabel(context, color: _heroMuted)),
                      ),
                      const SizedBox(width: 8),
                      _RangePill(label: range.label),
                    ]),
                    const SizedBox(height: 8),
                    _HeroAmount(value: s.monthExpense),
                    if (isThisMonth) ...[
                      const SizedBox(height: 16),
                      _BudgetStatus(spent: s.monthExpense),
                    ],
                    if (mom != null) ...[
                      const SizedBox(height: 14),
                      _momChip(mom),
                    ],
                  ]),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _momChip(({double pct, bool down}) m) {
    final color = m.down ? _heroGood : _heroUp;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(m.down ? Icons.trending_down_rounded : Icons.trending_up_rounded,
            size: 15, color: color),
        const SizedBox(width: 5),
        Text(
            '${m.pct.toStringAsFixed(0)}% ${m.down ? 'less' : 'more'} than last month',
            style: TextStyle(
                color: color, fontSize: 12.5, fontWeight: FontWeight.w700)),
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
class _HeroAmount extends StatefulWidget {
  final double value;
  const _HeroAmount({required this.value});

  @override
  State<_HeroAmount> createState() => _HeroAmountState();
}

class _HeroAmountState extends State<_HeroAmount> {
  // First time Home appears this session the figure counts up from 0; after
  // that it only tweens between real changes (never re-counts on rebuild).
  late double _from = _heroCounted ? widget.value : 0;

  @override
  void initState() {
    super.initState();
    _heroCounted = true;
  }

  @override
  void didUpdateWidget(_HeroAmount old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value) _from = old.value;
  }

  @override
  Widget build(BuildContext context) {
    final still = reduceMotion(context) || _from == widget.value;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: still ? widget.value : _from, end: widget.value),
      duration: still ? Duration.zero : const Duration(milliseconds: 900),
      curve: Curves.easeOutCubic,
      builder: (_, v, __) {
        final text = formatRupees(v);
        // "₹12,340" → symbol + number, so the symbol can sit smaller.
        final m = RegExp(r'^([^\d•]*)(.*)$').firstMatch(text)!;
        return Text.rich(
          TextSpan(children: [
            TextSpan(
              text: m[1],
              style: const TextStyle(
                  fontSize: 26, fontWeight: FontWeight.w600, color: _heroMuted),
            ),
            TextSpan(text: m[2]),
          ]),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
              color: Colors.white,
              fontSize: 44,
              fontWeight: FontWeight.w800,
              letterSpacing: -1.5,
              height: 1.05),
        );
      },
    );
  }
}

// ── Monthly budget: one thin bar + what's safe to spend per day ─
class _BudgetStatus extends ConsumerWidget {
  final double spent;
  const _BudgetStatus({required this.spent});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final budgets = ref.watch(effectiveBudgetsProvider);
    final total = _totalBudget(budgets);
    if (total <= 0) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => Navigator.pushNamed(context, AppRoutes.budgets),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Row(children: [
            Icon(Icons.savings_outlined, size: 18, color: _heroGood),
            SizedBox(width: 8),
            Expanded(
              child: Text('Set a monthly budget to see what\'s safe to spend',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600)),
            ),
            Icon(Icons.chevron_right_rounded, size: 18, color: _heroMuted),
          ]),
        ),
      );
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
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: v),
            duration: reduceMotion(context)
                ? Duration.zero
                : const Duration(milliseconds: 900),
            curve: Curves.easeOutCubic,
            builder: (_, x, __) => _GlowBar(value: x, over: over),
          ),
        ),
        const SizedBox(height: 10),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(
            child: Text(
              over
                  ? '${formatRupees(-left, compact: true)} over your '
                      '${formatRupees(total, compact: true)} budget'
                  : '${formatRupees(left, compact: true)} left of '
                      '${formatRupees(total, compact: true)}',
              style: TextStyle(
                  color: over ? _heroBad : Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w700),
            ),
          ),
          if (!over)
            Text.rich(
              TextSpan(children: [
                TextSpan(
                    text: formatRupees(perDay, compact: true),
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w800)),
                TextSpan(
                    text: daysLeft == 1
                        ? '/day · last day'
                        : '/day · $daysLeft days'),
              ]),
              style: const TextStyle(
                  color: _heroMuted,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600),
            ),
        ]),
      ]),
    );
  }
}

/// A soft radial light, for HUD panels.
class _Glow extends StatelessWidget {
  final Color color;
  final double size;
  const _Glow(this.color, this.size);

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(colors: [
              color.withValues(alpha: 0.22),
              color.withValues(alpha: 0.0),
            ]),
          ),
        ),
      );
}

/// Budget bar: an arc → violet gradient with a soft glow on a dim track;
/// turns coral when over budget.
class _GlowBar extends StatelessWidget {
  final double value;
  final bool over;
  const _GlowBar({required this.value, required this.over});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 7,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(99),
      ),
      alignment: Alignment.centerLeft,
      child: FractionallySizedBox(
        widthFactor: value.clamp(0.0, 1.0),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(99),
            gradient: over
                ? const LinearGradient(colors: [_heroBad, AerisColors.coral])
                : const LinearGradient(
                    colors: [AerisColors.mint, AerisColors.arc]),
            boxShadow: [
              BoxShadow(
                  color: (over ? AerisColors.coral : AerisColors.arc)
                      .withValues(alpha: 0.55),
                  blurRadius: 8),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Momentum: the motivation panel ────────────────────────────
//
// Three live numbers that reward good behaviour — how much of your income
// you're keeping, your check-in streak, and your closest goal — plus one
// money line that changes every day.
const _quotes = <(String, String)>[
  (
    'Do not save what is left after spending; spend what is left after saving.',
    'Warren Buffett'
  ),
  (
    'A budget is telling your money where to go instead of wondering where it went.',
    'Dave Ramsey'
  ),
  ('Small daily wins compound into big results.', 'AERIS'),
  (
    'Beware of little expenses. A small leak will sink a great ship.',
    'Benjamin Franklin'
  ),
  ('Wealth is what you don\'t see — the cars not bought.', 'Morgan Housel'),
  ('The habit of saving is itself an education.', 'T.T. Munger'),
  ('Every rupee you track is a rupee you control.', 'AERIS'),
  (
    'It\'s not your salary that makes you rich, it\'s your spending habits.',
    'Charles A. Jaffe'
  ),
  (
    'Financial freedom is available to those who learn about it and work for it.',
    'Robert Kiyosaki'
  ),
  (
    'Rich people plan for three generations. Poor people plan for Saturday night.',
    'Gloria Steinem'
  ),
  (
    'Too many people spend money they haven\'t earned to impress people they don\'t like.',
    'Will Rogers'
  ),
  ('Discipline today, freedom tomorrow.', 'AERIS'),
  (
    'The best time to start was yesterday. The next best time is today.',
    'Proverb'
  ),
  ('An investment in knowledge pays the best interest.', 'Benjamin Franklin'),
];

class _MomentumCard extends ConsumerWidget {
  const _MomentumCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(amountHiddenProvider);
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
    final rate = income > 0 ? saved / income : null;

    // The goal closest to done (but not done yet) is the most motivating.
    final open = goals.where((g) => !g.isComplete).toList()
      ..sort((a, b) => b.progress.compareTo(a.progress));
    final goal = open.isNotEmpty ? open.first : null;

    final now = DateTime.now();
    final dayOfYear = now.difference(DateTime(now.year)).inDays;
    final (quote, author) = _quotes[dayOfYear % _quotes.length];
    final muted = AerisColors.muted(context);
    final accent = AerisColors.accent(context);

    return AerisCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.bolt_rounded, size: 15, color: accent),
          const SizedBox(width: 6),
          Text('MOMENTUM', style: hudLabel(context, color: accent)),
          const Spacer(),
          if (rate != null && rate >= 0.2)
            Text('On track',
                style: hudLabel(context, color: AerisColors.moneyIn(context))),
        ]),
        const SizedBox(height: 14),
        IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(
              child: _Stat(
                label: 'SAVED',
                value: rate == null
                    ? '—'
                    : '${(rate * 100).clamp(-999, 100).toStringAsFixed(0)}%',
                sub: rate == null
                    ? 'Add income'
                    : saved >= 0
                        ? '${formatRupees(saved, compact: true)} kept'
                        : '${formatRupees(-saved, compact: true)} over',
                color: rate == null
                    ? muted
                    : rate >= 0
                        ? AerisColors.moneyIn(context)
                        : AerisColors.danger(context),
                onTap: () => Navigator.pushNamed(context,
                    rate == null ? AppRoutes.editProfile : AppRoutes.insights),
              ),
            ),
            VerticalDivider(width: 1, color: AerisColors.line(context)),
            Expanded(
              child: _Stat(
                label: 'STREAK',
                value: '$streak',
                sub: streak == 1 ? 'day' : 'days',
                color: AerisColors.amber,
                icon: Icons.local_fire_department_rounded,
                onTap: () => _showStreakSheet(context),
              ),
            ),
            VerticalDivider(width: 1, color: AerisColors.line(context)),
            Expanded(
              child: _Stat(
                label: 'GOAL',
                value: goal == null
                    ? '+'
                    : '${(goal.progress * 100).toStringAsFixed(0)}%',
                sub: goal == null ? 'Set one' : goal.title,
                color: AerisColors.violet,
                progress: goal?.progress,
                onTap: () => Navigator.pushNamed(context, AppRoutes.goals),
              ),
            ),
          ]),
        ),
        if (projection != null) ...[
          const SizedBox(height: 12),
          // Future-you: where today's saving pace lands you.
          Semantics(
            button: true,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.pushNamed(context, AppRoutes.netWorth),
              child: Row(children: [
                const Icon(Icons.rocket_launch_outlined,
                    size: 16, color: AerisColors.violet),
                const SizedBox(width: 8),
                Expanded(
                  child: Text.rich(
                    TextSpan(children: [
                      TextSpan(
                          text:
                              'At ${formatRupees(projection.perMonth, compact: true)}/month you\'ll have '),
                      TextSpan(
                          text: formatRupees(projection.value, compact: true),
                          style: const TextStyle(fontWeight: FontWeight.w800)),
                      TextSpan(
                          text:
                              ' by ${const ['', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][projection.by.month]} ${projection.by.year}'),
                    ]),
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                        color: Theme.of(context).colorScheme.onSurface),
                  ),
                ),
                Icon(Icons.chevron_right_rounded, size: 18, color: muted),
              ]),
            ),
          ),
        ],
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(
            color: AerisColors.accentSoft(context),
            borderRadius: BorderRadius.circular(14),
            border: Border(left: BorderSide(color: accent, width: 3)),
          ),
          child: Text.rich(
            TextSpan(children: [
              TextSpan(
                  text: '“$quote”',
                  style: TextStyle(
                      fontSize: 13,
                      height: 1.4,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onSurface)),
              TextSpan(
                  text: '\n— $author',
                  style: TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w500, color: muted)),
            ]),
          ),
        ),
      ]),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  final String sub;
  final Color color;
  final IconData? icon;
  final double? progress;
  final VoidCallback onTap;

  const _Stat({
    required this.label,
    required this.value,
    required this.sub,
    required this.color,
    required this.onTap,
    this.icon,
    this.progress,
  });

  @override
  Widget build(BuildContext context) {
    final muted = AerisColors.muted(context);
    return Semantics(
      button: true,
      label: '$label $value $sub',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Column(children: [
            Text(label, style: hudLabel(context, size: 10)),
            const SizedBox(height: 6),
            Row(mainAxisSize: MainAxisSize.min, children: [
              if (icon != null) ...[
                Icon(icon, size: 18, color: color),
                const SizedBox(width: 2),
              ],
              Text(value,
                  style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                      color: color)),
            ]),
            const SizedBox(height: 2),
            Text(sub,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 11.5, fontWeight: FontWeight.w500, color: muted)),
            if (progress != null) ...[
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 3,
                  color: color,
                  backgroundColor: color.withValues(alpha: 0.15),
                ),
              ),
            ],
          ]),
        ),
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
      final week = g.weekCheckins(); // real Sun→Sat check-in days
      final notifier = ref2.read(gamificationProvider.notifier);
      final done = notifier.checkedInToday;
      final accent = AerisColors.accent(ctx);
      final todayIdx = g.todayWeekIndex; // Sun=0 … Sat=6
      const labels = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];
      final now = DateTime.now();
      final noSpend = noSpendWeek(
        ref2.watch(transactionsStreamProvider).valueOrNull ?? const [],
        now,
        weekStart: DateTime(now.year, now.month, now.day)
            .subtract(Duration(days: todayIdx)),
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
                          ? Icon(Icons.check_rounded,
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
                  : '$noSpendCount no-spend day${noSpendCount == 1 ? '' : 's'} this week · +${noSpendCount * 10} Aura',
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
          padding: const EdgeInsets.fromLTRB(10, 5, 6, 5),
          decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(99)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(label,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w700)),
            const SizedBox(width: 2),
            const Icon(Icons.expand_more_rounded,
                color: Colors.white, size: 16),
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
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Padding(
              padding: EdgeInsets.only(bottom: 6),
              child: Text('Show spending for',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            ),
            ...options.map((r) {
              final on = r.label == label;
              return ListTile(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                title: Text(r.label,
                    style: TextStyle(
                        fontWeight: on ? FontWeight.w700 : FontWeight.w500)),
                trailing: on
                    ? Icon(Icons.check_rounded, color: AerisColors.accent(ctx))
                    : null,
                onTap: () {
                  ref.read(analyticsRangeProvider.notifier).state = r;
                  Navigator.pop(ctx);
                },
              );
            }),
          ]),
        ),
      ),
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
    final capFor = <String, double>{
      for (final b in budgets.where((b) => b.categoryId != Budget.totalId))
        b.categoryId: b.monthlyCap,
    };
    final top = analytics.byCategory.entries.where((e) => e.value > 0).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final top3 = top.take(3).toList();
    if (top3.isEmpty) return const SizedBox.shrink();
    final spendTotal = top.fold<double>(0, (s, e) => s + e.value);
    final muted = AerisColors.muted(context);

    return AerisCard(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Text('Where it went',
              style: TextStyle(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3)),
          const Spacer(),
          Text(analytics.label,
              style: TextStyle(
                  fontSize: 12.5, fontWeight: FontWeight.w600, color: muted)),
        ]),
        const SizedBox(height: 16),
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
                        BudgetRing(
                          progress: _ready ? v : 0.0,
                          size: 54,
                          strokeWidth: 5,
                          color: cat.color,
                          warnOverflow: hasCap,
                          center: Icon(cat.icon, size: 20, color: cat.color),
                        ),
                        const SizedBox(height: 10),
                        Text(cat.label.split(RegExp(r' [&/] ')).first,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: muted)),
                        const SizedBox(height: 2),
                        Text(formatRupees(e.value, compact: true),
                            maxLines: 1,
                            style: const TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w800)),
                        if (hasCap)
                          Text('of ${formatRupees(cap, compact: true)}',
                              maxLines: 1,
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: v >= 1
                                      ? AerisColors.danger(context)
                                      : muted)),
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
class _AttentionSlot extends ConsumerWidget {
  const _AttentionSlot();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final analytics = ref.watch(analyticsProvider).asData?.value;
    final budgets = ref.watch(effectiveBudgetsProvider);
    final insights = ref.watch(insightsProvider).valueOrNull;
    final hidden = ref.watch(gamificationProvider.select((g) => g.hiddenCards));
    final checkin = ref.watch(gamificationProvider.select(
        (g) => (loaded: g.loaded, done: g.checkedInOn(DateTime.now()))));

    Widget? card;
    if (analytics != null &&
        _overBudget(budgets, analytics.byCategory).isNotEmpty) {
      card = const _OverBudgetCard();
    } else {
      final showForecast =
          insights != null && !hidden.contains(kHomeCardForecast);
      final risky = insights?.budgetProjections
              .where((p) =>
                  p.alreadyOver ||
                  (p.willExceed && (p.daysUntilExceed ?? 99) <= 7))
              .length ??
          0;
      if (showForecast && risky > 0) {
        card = const _ForecastStrip();
      } else if (checkin.loaded &&
          !checkin.done &&
          !hidden.contains(kHomeCardCheckin)) {
        card = const _CheckinStrip();
      } else if (showForecast) {
        card = const _ForecastStrip();
      }
    }
    if (card == null) return const SizedBox.shrink();
    return Padding(padding: const EdgeInsets.only(top: 14), child: card);
  }
}

// ── Over-budget category card ─────────────────────────────────
class _OverBudgetCard extends ConsumerWidget {
  const _OverBudgetCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(amountHiddenProvider);
    final analytics = ref.watch(analyticsProvider).asData?.value;
    final budgets = ref.watch(effectiveBudgetsProvider);
    if (analytics == null) return const SizedBox.shrink();

    final byCategory = analytics.byCategory;
    final overBudget = _overBudget(budgets, byCategory);
    if (overBudget.isEmpty) return const SizedBox.shrink();

    final danger = AerisColors.danger(context);
    final dark = Theme.of(context).brightness == Brightness.dark;

    return AerisCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      color: dark ? const Color(0xFF2A1718) : const Color(0xFFFFF6F5),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.error_outline_rounded, size: 18, color: danger),
          const SizedBox(width: 6),
          Text(
              overBudget.length == 1
                  ? 'Over budget'
                  : '${overBudget.length} budgets over',
              style: TextStyle(
                  fontSize: 14.5, fontWeight: FontWeight.w800, color: danger)),
        ]),
        const SizedBox(height: 10),
        for (final b in overBudget.take(3)) _tile(context, b, byCategory),
      ]),
    );
  }

  Widget _tile(BuildContext context, Budget b, Map<String, double> byCategory) {
    final cat = Categories.byId(b.categoryId);
    final spent = byCategory[b.categoryId] ?? 0;
    final over = spent - b.monthlyCap;
    final danger = AerisColors.danger(context);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.pushNamed(context, AppRoutes.transactions,
          arguments: b.categoryId),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(children: [
          _CategoryPlate(category: cat, size: 34),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(cat.label,
                    style: const TextStyle(
                        fontSize: 13.5, fontWeight: FontWeight.w700),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                Text(
                    '${formatRupees(spent, compact: true)} of '
                    '${formatRupees(b.monthlyCap, compact: true)}',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: AerisColors.muted(context))),
              ],
            ),
          ),
          Text('+${formatRupees(over, compact: true)}',
              style: TextStyle(
                  fontSize: 13.5, fontWeight: FontWeight.w800, color: danger)),
          const SizedBox(width: 2),
          Icon(Icons.chevron_right_rounded,
              size: 18, color: AerisColors.muted(context)),
        ]),
      ),
    );
  }
}

/// Category icon on a soft tinted plate — the house style for categories.
class _CategoryPlate extends StatelessWidget {
  final ExpenseCategory category;
  final double size;
  const _CategoryPlate({required this.category, this.size = 40});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
          color: category.color.withValues(alpha: dark ? 0.20 : 0.13),
          borderRadius: BorderRadius.circular(size * 0.32)),
      child: Icon(category.icon, size: size * 0.5, color: category.color),
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
            checkedIn
                ? Icons.task_alt_rounded
                : Icons.local_fire_department_rounded,
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
    final tone =
        riskyCount > 0 ? AerisColors.warning : AerisColors.accent(context);

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
          child: Icon(Icons.insights_rounded, size: 21, color: tone),
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
                    style: const TextStyle(
                        color: AerisColors.warning,
                        fontWeight: FontWeight.w700),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(width: 6),
        Icon(Icons.chevron_right_rounded, color: AerisColors.muted(context)),
      ]),
    );
  }
}

// ── Section header ────────────────────────────────────────────
class _SectionHeader extends StatelessWidget {
  final String title;
  final String action;
  final VoidCallback onAction;
  const _SectionHeader(
      {required this.title, required this.action, required this.onAction});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6, left: 2),
      child: Row(children: [
        Text(title,
            style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.4)),
        const Spacer(),
        TextButton(
          onPressed: onAction,
          style: TextButton.styleFrom(
            minimumSize: const Size(0, 36),
            padding: const EdgeInsets.symmetric(horizontal: 8),
          ),
          child: Text(action),
        ),
      ]),
    );
  }
}

// ── Recent activity section ───────────────────────────────────
class _RecentActivitySection extends ConsumerWidget {
  const _RecentActivitySection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(amountHiddenProvider);
    final recent = ref.watch(recentTransactionsProvider(5));
    return recent.when(
      data: (list) {
        if (list.isEmpty) return const _FirstRunCard();
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _SectionHeader(
            title: 'Recent',
            action: 'See all',
            onAction: () =>
                Navigator.pushNamed(context, AppRoutes.transactions),
          ),
          AerisCard(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              children: [
                for (int i = 0; i < list.length; i++) ...[
                  TransactionTile(txn: list[i]),
                  if (i < list.length - 1)
                    const Divider(height: 1, indent: 70, endIndent: 16),
                ],
              ],
            ),
          ),
        ]);
      },
      loading: () => Column(
        children: List.generate(
            4,
            (_) => const SkeletonBox(
                height: 56,
                radius: 12,
                margin: EdgeInsets.symmetric(vertical: 4))),
      ),
      error: (e, _) => AerisCard(
        child: Text('Could not load your transactions.\n$e',
            style: TextStyle(color: AerisColors.muted(context))),
      ),
    );
  }
}

/// Shown instead of "Recent" until the first transaction exists: a new user
/// gets the ways in, not an empty list.
class _FirstRunCard extends StatelessWidget {
  const _FirstRunCard();

  @override
  Widget build(BuildContext context) {
    final muted = AerisColors.muted(context);
    return AerisCard(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
              color: AerisColors.accentSoft(context),
              borderRadius: BorderRadius.circular(15)),
          child: Icon(Icons.receipt_long_rounded,
              color: AerisColors.accent(context)),
        ),
        const SizedBox(height: 14),
        const Text('Log your first expense',
            style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3)),
        const SizedBox(height: 4),
        Text(
            'Tap + to add one, hold + for voice and more, or bring in your '
            'history from a bank statement.',
            style: TextStyle(
                fontSize: 13.5,
                height: 1.45,
                fontWeight: FontWeight.w500,
                color: muted)),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(
            child: FilledButton(
              onPressed: () => Navigator.pushNamed(context, AppRoutes.addTxn,
                  arguments: TxnDirection.debit),
              child: const Text('Add expense'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: OutlinedButton(
              onPressed: () =>
                  Navigator.pushNamed(context, AppRoutes.importStatement),
              child: const Text('Import'),
            ),
          ),
        ]),
      ]),
    );
  }
}
