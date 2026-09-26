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
import '../../providers/budgets_provider.dart';
import '../../providers/gamification_provider.dart';
import '../../providers/insights_provider.dart';
import '../../providers/privacy_provider.dart';
import '../../providers/transactions_provider.dart';
import '../../utils/formatters.dart';
import '../../utils/motion.dart';
import '../../widgets/aeris_avatar.dart';
import '../../widgets/budget_ring.dart';
import '../../widgets/skeleton.dart';
import '../../widgets/transaction_tile.dart';

// Home dashboard ids the "Customize dashboard" screen can hide.
const kHomeCardForecast = 'forecast';
const kHomeCardCheckin = 'checkin';
const kHomeCardCategories = 'categories';

// The hero's spend figure counts up once per app session — the single
// entrance moment on Home. Everything else paints immediately.
bool _heroCounted = false;

// ── Home Screen ──────────────────────────────────────────────
//
// Three zones: this month (hero + top categories), one "needs attention"
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
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          children: [
            const SafeArea(bottom: false, child: _FlowHeader()),
            const _HeroCard(),
            if (!hidden.contains(kHomeCardCategories)) ...[
              const SizedBox(height: 16),
              const _TopCategories(),
            ],
            const SizedBox(height: 16),
            const _AttentionCard(),
            // Always rendered (an empty box when idle). Conditionally inserting
            // the banner here used to shift every keyless child below it, so
            // reconciliation re-matched them by index and churned their
            // elements mid-rebuild during SMS import. A constant slot keeps
            // every sibling at a stable index.
            _importBanner(importProgress),
            const SizedBox(height: 22),
            const _RecentActivitySection(),
          ],
        ),
      ),
    );
  }

  Widget _importBanner(({int done, int total})? p) {
    if (p == null) return const SizedBox.shrink();
    final pct = p.total == 0 ? null : p.done / p.total;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Card(
        color: AerisColors.info.withValues(alpha: 0.10),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2.4, value: pct)),
            const SizedBox(width: 12),
            Expanded(
                child: Text('Importing SMS… ${p.done}/${p.total}',
                    style: const TextStyle(fontSize: 13))),
          ]),
        ),
      ),
    );
  }
}

// ── Flow header: avatar · greeting · eye · mascot ─────────────
class _FlowHeader extends ConsumerWidget {
  const _FlowHeader();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(userProfileProvider).asData?.value;
    final hidden = ref.watch(amountHiddenProvider);
    final aeris = ref.watch(avatarStatusProvider);

    final rawName = profile?.displayName?.split(' ').first ?? 'there';
    final name = rawName.isEmpty
        ? 'there'
        : rawName[0].toUpperCase() + rawName.substring(1);
    final initials = (profile?.displayName ?? '?')
        .split(' ')
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
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Profile avatar — shows the user's photo if set, else initials.
          GestureDetector(
            onTap: () => Navigator.pushNamed(context, AppRoutes.editProfile),
            child: _ProfileAvatar(profile: profile, initials: initials),
          ),
          const SizedBox(width: 12),
          // Greeting + name
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(greet,
                    style: TextStyle(
                        fontSize: 12.5,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600)),
                Text(name,
                    style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                        height: 1.1)),
              ],
            ),
          ),
          // Notifications — glass icon button with an unread dot
          _GlassIconBtn(
            icon: Icons.notifications_none_rounded,
            onTap: () => Navigator.pushNamed(context, AppRoutes.notifications),
            badge: true,
          ),
          const SizedBox(width: 8),
          // Privacy eye — glass icon button
          _GlassIconBtn(
            icon: hidden
                ? Icons.visibility_off_outlined
                : Icons.visibility_outlined,
            onTap: () => ref.read(amountHiddenProvider.notifier).toggle(),
            active: hidden,
          ),
          const SizedBox(width: 8),
          // Mascot button — opens AI assistant. The new-GUI header wraps it in
          // a neutral frosted-glass circle (glassStyle, not a teal plate) with
          // the avatar clipped inside. TickerMode (in RootShell) pauses the
          // animation whenever Home isn't the visible tab, so it's cheap.
          GestureDetector(
            onTap: () => Navigator.pushNamed(context, AppRoutes.assistant),
            child: Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              clipBehavior: Clip.hardEdge,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Theme.of(context).brightness == Brightness.dark
                    ? Colors.white.withValues(alpha: 0.07)
                    : Colors.black.withValues(alpha: 0.05),
                border: Border.all(
                    color: Colors.white.withValues(alpha: 0.12), width: 1),
              ),
              child: AerisAvatar(
                  skin: aeris.skin,
                  stage: aeris.stage,
                  mood: aeris.mood,
                  size: 36,
                  glow: false,
                  animate: true),
            ),
          ),
        ],
      ),
    );
  }
}

class _GlassIconBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool active;
  final bool badge;
  const _GlassIconBtn(
      {required this.icon,
      required this.onTap,
      this.active = false,
      this.badge = false});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = Theme.of(context).colorScheme.surface;
    return GestureDetector(
      onTap: onTap,
      child: Stack(clipBehavior: Clip.none, children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: active
                ? AerisColors.seed.withValues(alpha: 0.15)
                : (isDark
                    ? Colors.white.withValues(alpha: 0.07)
                    : Colors.black.withValues(alpha: 0.05)),
            border: Border.all(
              color: active
                  ? AerisColors.seed.withValues(alpha: 0.35)
                  : Colors.white.withValues(alpha: 0.12),
              width: 1,
            ),
          ),
          child: Icon(icon,
              size: 21,
              color: active
                  ? AerisColors.seed
                  : Theme.of(context).colorScheme.onSurface),
        ),
        if (badge)
          Positioned(
            top: 2,
            right: 3,
            child: Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AerisColors.moneyOut(context),
                border: Border.all(color: surface, width: 1.5),
              ),
            ),
          ),
      ]),
    );
  }
}

// ── Profile avatar: user photo if set, else gradient initials ─────────────────
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
          border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
        ),
      );
    }
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
          shape: BoxShape.circle, gradient: AerisColors.heroGradient),
      child: Center(
        child: Text(
          initials.isEmpty ? '?' : initials,
          style: TextStyle(
              color: Colors.white,
              fontSize: size * 0.36,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5),
        ),
      ),
    );
  }
}

// ── Hero spend card ───────────────────────────────────────────
class _HeroCard extends ConsumerWidget {
  const _HeroCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(amountHiddenProvider);
    final analytics = ref.watch(analyticsProvider);
    final range = ref.watch(analyticsRangeProvider);
    final streak = ref.watch(gamificationProvider.select((g) => g.liveStreak));

    return analytics.when(
      data: (s) => _card(context, ref, s, range, streak),
      loading: () => const SkeletonBox(height: 160, radius: 24),
      error: (_, __) => const SizedBox.shrink(),
    );
  }

  Widget _card(BuildContext context, WidgetRef ref, AnalyticsSnapshot s,
      AnalyticsRange range, int streak) {
    final mom = _computeMom(s);
    return GestureDetector(
      onTap: () => Navigator.pushNamed(context, AppRoutes.transactions,
          arguments: TxnDirection.debit),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
                color: const Color(0xFF0F766E).withValues(alpha: 0.35),
                blurRadius: 30,
                offset: const Offset(0, 12))
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: Container(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
            decoration: const BoxDecoration(
              gradient: AerisColors.heroGradient,
            ),
            child: Stack(clipBehavior: Clip.none, children: [
              // Decorative circles — clipped by the ClipRRect above
              Positioned(
                right: -40,
                top: -55,
                child: Container(
                  width: 200,
                  height: 200,
                  decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.09)),
                ),
              ),
              Positioned(
                right: -10,
                bottom: -60,
                child: Container(
                  width: 140,
                  height: 140,
                  decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.05)),
                ),
              ),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                // Row: label | range pill
                Row(children: [
                  Text('Spent · ${range.label}',
                      style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                          fontWeight: FontWeight.w600)),
                  const Spacer(),
                  _RangePill(label: range.label),
                ]),
                const SizedBox(height: 8),
                _HeroAmount(value: s.monthExpense),
                if (range.label == AnalyticsRange.thisMonth().label) ...[
                  const SizedBox(height: 14),
                  _BudgetBar(spent: s.monthExpense),
                ],
                const SizedBox(height: 14),
                // MoM badge (informational, matches the GUI's non-tappable span)
                // + streak chip (tappable → "Your streak" sheet, like the GUI).
                Row(children: [
                  if (mom != null) ...[
                    _momBadge(mom),
                    const SizedBox(width: 8)
                  ],
                  GestureDetector(
                    onTap: () => _showStreakSheet(context, ref),
                    child: _streakBadge(streak),
                  ),
                ]),
              ]),
            ]),
          ), // gradient Container
        ), // ClipRRect
      ), // shadow Container
    );
  }

  Widget _momBadge(({double pct, bool down}) m) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: m.down
            ? Colors.white.withValues(alpha: 0.92)
            : Colors.black.withValues(alpha: 0.20),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(m.down ? Icons.trending_down : Icons.trending_up,
            size: 15, color: m.down ? const Color(0xFF0F766E) : Colors.white),
        const SizedBox(width: 3),
        Text('${m.pct.toStringAsFixed(0)}% vs last month',
            style: TextStyle(
                color: m.down ? const Color(0xFF0F766E) : Colors.white,
                fontSize: 12.5,
                fontWeight: FontWeight.w800)),
      ]),
    );
  }

  Widget _streakBadge(int streak) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(99)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.local_fire_department,
            size: 15, color: Color(0xFFFFD9A8)),
        const SizedBox(width: 4),
        Text('${streak > 0 ? streak : 0}-day',
            style: const TextStyle(
                color: Colors.white,
                fontSize: 12.5,
                fontWeight: FontWeight.w800)),
      ]),
    );
  }

  ({double pct, bool down})? _computeMom(AnalyticsSnapshot s) {
    if (!s.label.toLowerCase().contains('month')) return null;
    final now = DateTime.now();
    String mk(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}';
    final cur = s.monthlyExpenseSeries[mk(now)] ?? s.monthExpense;
    final last =
        s.monthlyExpenseSeries[mk(DateTime(now.year, now.month - 1, 1))] ?? 0;
    if (last <= 0) return null;
    final pct = (cur - last) / last * 100;
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
              style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  color: Colors.white.withValues(alpha: 0.75)),
            ),
            TextSpan(text: m[2]),
          ]),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
              color: Colors.white,
              fontSize: 46,
              fontWeight: FontWeight.w800,
              letterSpacing: -1.5,
              height: 1.0),
        );
      },
    );
  }
}

// ── Monthly budget, folded into the hero as one thin bar ──────
class _BudgetBar extends ConsumerWidget {
  final double spent;
  const _BudgetBar({required this.spent});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final budgets = ref.watch(budgetsStreamProvider).asData?.value ?? const [];
    final total = _totalBudget(budgets);
    const label = TextStyle(
        color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w700);
    if (total <= 0) {
      return GestureDetector(
        onTap: () => Navigator.pushNamed(context, AppRoutes.budgets),
        child: Row(children: [
          Icon(Icons.add_circle_outline,
              size: 16, color: Colors.white.withValues(alpha: 0.85)),
          const SizedBox(width: 6),
          const Text('Set a monthly budget', style: label),
        ]),
      );
    }
    final left = total - spent;
    final over = left < 0;
    final v = (spent / total).clamp(0.0, 1.0);
    return GestureDetector(
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
            builder: (_, x, __) => LinearProgressIndicator(
              value: x,
              minHeight: 6,
              backgroundColor: Colors.white.withValues(alpha: 0.22),
              color: over ? const Color(0xFFFFC9C9) : Colors.white,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          over
              ? '${formatRupees(-left, compact: true)} over your '
                  '${formatRupees(total, compact: true)} budget'
              : '${formatRupees(left, compact: true)} left of '
                  '${formatRupees(total, compact: true)}',
          style: label.copyWith(color: Colors.white.withValues(alpha: 0.85)),
        ),
      ]),
    );
  }
}

// ── "Your streak" sheet (ports the new GUI StreakSheet) ───────────────────────
void _showStreakSheet(BuildContext context, WidgetRef ref) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (ctx) => Consumer(builder: (ctx, ref2, _) {
      final g = ref2.watch(gamificationProvider);
      final streak = g.liveStreak; // lapses if a day was missed
      final week = g.weekCheckins(); // real Sun→Sat check-in days
      final notifier = ref2.read(gamificationProvider.notifier);
      final done = notifier.checkedInToday;
      final scheme = Theme.of(ctx).colorScheme;

      final todayIdx = g.todayWeekIndex; // Sun=0 … Sat=6
      const labels = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];

      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          // Orange streak hero
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFEA580C), Color(0xFFF97316)],
              ),
            ),
            child: Stack(clipBehavior: Clip.none, children: [
              Positioned(
                right: -16,
                bottom: -28,
                child: Icon(Icons.local_fire_department,
                    size: 140, color: Colors.white.withValues(alpha: 0.18)),
              ),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Icons.local_fire_department,
                    size: 34, color: Color(0xFFFFE0B2)),
                const SizedBox(height: 6),
                Text('$streak-day streak',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 30,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5)),
                const SizedBox(height: 2),
                Text('Keep checking in to grow your Aura',
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.88),
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    for (var i = 0; i < 7; i++)
                      _streakDay(
                        label: labels[i],
                        checked: i < week.length && week[i],
                        isToday: i == todayIdx,
                      ),
                  ],
                ),
              ]),
            ]),
          ),
          const SizedBox(height: 16),
          Text(
            'Check in daily to keep your streak alive. Each day earns Aura '
            'that grows your Aeris garden. Prefer it on your home screen? Add '
            'the streak widget from Me → Widgets.',
            style: TextStyle(
                fontSize: 13,
                height: 1.5,
                fontWeight: FontWeight.w600,
                color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: done
                  ? null
                  : () {
                      final aura = notifier.checkIn();
                      final messenger = ScaffoldMessenger.of(ctx);
                      messenger.showSnackBar(SnackBar(
                        content: Text(aura > 0
                            ? 'Checked in · +$aura Aura 🔥'
                            : 'Already checked in today'),
                        duration: const Duration(seconds: 2),
                      ));
                    },
              style: FilledButton.styleFrom(
                backgroundColor: AerisColors.seed,
                foregroundColor: Colors.white,
                disabledBackgroundColor:
                    scheme.onSurface.withValues(alpha: 0.12),
                padding: const EdgeInsets.symmetric(vertical: 15),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15)),
                textStyle:
                    const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
              ),
              child:
                  Text(done ? 'Checked in today ✓' : 'Check in · +15 ✦ Aura'),
            ),
          ),
        ]),
      );
    }),
  );
}

Widget _streakDay(
    {required String label, required bool checked, required bool isToday}) {
  return Column(mainAxisSize: MainAxisSize.min, children: [
    Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: checked ? Colors.white : Colors.white.withValues(alpha: 0.18),
        border: isToday ? Border.all(color: Colors.white, width: 2) : null,
      ),
      child: checked
          ? const Icon(Icons.check, size: 17, color: Color(0xFFEA580C))
          : null,
    ),
    const SizedBox(height: 5),
    Text(label,
        style: TextStyle(
            color: Colors.white.withValues(alpha: 0.85),
            fontSize: 10.5,
            fontWeight: FontWeight.w700)),
  ]);
}

// Range selector pill embedded inside hero card
class _RangePill extends ConsumerWidget {
  final String label;
  const _RangePill({required this.label});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      onTap: () => _showSheet(context, ref),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(99)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(label,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w700)),
          const SizedBox(width: 3),
          const Icon(Icons.expand_more, color: Colors.white, size: 16),
        ]),
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
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('Date range',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            ...options.map((r) => ListTile(
                  title: Text(r.label,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  leading: Icon(
                    r.label == label
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    color: r.label == label ? AerisColors.seed : null,
                  ),
                  onTap: () {
                    ref.read(analyticsRangeProvider.notifier).state = r;
                    Navigator.pop(ctx);
                  },
                )),
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

// ── Top categories: three rings, no card chrome ───────────────
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
    final analytics = ref.watch(analyticsProvider).asData?.value;
    final budgets = ref.watch(budgetsStreamProvider).asData?.value ?? const [];
    if (analytics == null) return const SizedBox(height: 86);

    if (!_ready) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_ready) setState(() => _ready = true);
      });
    }

    // Biggest three spend categories. With a category cap the ring tracks
    // used/cap; without one it tracks share of the largest category.
    final capFor = <String, double>{
      for (final b in budgets.where((b) => b.categoryId != Budget.totalId))
        b.categoryId: b.monthlyCap,
    };
    final top = analytics.byCategory.entries.where((e) => e.value > 0).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final top3 = top.take(3).toList();
    if (top3.isEmpty) return const SizedBox.shrink();
    final maxSpend = top3.first.value;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;

    return Row(
      children: [
        for (final e in top3)
          Expanded(
            child: Builder(builder: (context) {
              final cat = Categories.byId(e.key);
              final cap = capFor[e.key];
              final hasCap = cap != null && cap > 0;
              final v = hasCap ? e.value / cap : e.value / maxSpend;
              final ringColor = !hasCap
                  ? cat.color
                  : v >= 1
                      ? AerisColors.moneyOut(context)
                      : v > 0.8
                          ? AerisColors.warning
                          : cat.color;
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.pushNamed(
                    context, AppRoutes.transactions,
                    arguments: e.key),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    BudgetRing(
                      progress: _ready ? v.clamp(0.0, 1.0) : 0.0,
                      size: 38,
                      strokeWidth: 4.5,
                      color: ringColor,
                      center: Icon(cat.icon, size: 15, color: cat.color),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(cat.label.split(' ').first,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                  color: muted)),
                          Text(formatRupees(e.value, compact: true),
                              maxLines: 1,
                              style: const TextStyle(
                                  fontSize: 13.5, fontWeight: FontWeight.w800)),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }),
          ),
      ],
    );
  }
}

// ── The one "needs attention" card ────────────────────────────
//
// Several things used to compete for this spot as separate cards. Now only
// the most urgent shows: over budget › budgets at risk this week › today's
// check-in › the month-end forecast.
class _AttentionCard extends ConsumerWidget {
  const _AttentionCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final analytics = ref.watch(analyticsProvider).asData?.value;
    final budgets = ref.watch(budgetsStreamProvider).asData?.value ?? const [];
    final insights = ref.watch(insightsProvider).valueOrNull;
    final hidden = ref.watch(gamificationProvider.select((g) => g.hiddenCards));
    final checkin = ref.watch(gamificationProvider.select(
        (g) => (loaded: g.loaded, done: g.checkedInOn(DateTime.now()))));

    if (analytics != null &&
        _overBudget(budgets, analytics.byCategory).isNotEmpty) {
      return const _OverBudgetCard();
    }
    final showForecast =
        insights != null && !hidden.contains(kHomeCardForecast);
    final risky = insights?.budgetProjections
            .where((p) =>
                p.alreadyOver ||
                (p.willExceed && (p.daysUntilExceed ?? 99) <= 7))
            .length ??
        0;
    if (showForecast && risky > 0) return const _ForecastStrip();
    if (checkin.loaded && !checkin.done && !hidden.contains(kHomeCardCheckin)) {
      return const _CheckinStrip();
    }
    if (showForecast) return const _ForecastStrip();
    return const SizedBox.shrink();
  }
}

// ── Over-budget category card ─────────────────────────────────
class _OverBudgetCard extends ConsumerWidget {
  const _OverBudgetCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final analytics = ref.watch(analyticsProvider).asData?.value;
    final budgets = ref.watch(budgetsStreamProvider).asData?.value ?? const [];
    if (analytics == null) return const SizedBox.shrink();

    final byCategory = analytics.byCategory;
    final overBudget = _overBudget(budgets, byCategory);

    if (overBudget.isEmpty) return const SizedBox.shrink();

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor =
        isDark ? const Color(0xFF1F1209) : const Color(0xFFFFF7ED);
    final borderColor =
        AerisColors.moneyOut(context).withValues(alpha: isDark ? 0.35 : 0.25);

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 6),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
              color: AerisColors.moneyOut(context)
                  .withValues(alpha: isDark ? 0.12 : 0.06),
              blurRadius: 8,
              offset: const Offset(0, 3))
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.warning_amber_rounded,
              size: 16, color: AerisColors.moneyOut(context)),
          const SizedBox(width: 6),
          Text('Over budget',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: AerisColors.moneyOut(context))),
        ]),
        const SizedBox(height: 8),
        for (final b in overBudget.take(4)) _tile(context, b, byCategory),
      ]),
    );
  }

  Widget _tile(BuildContext context, Budget b, Map<String, double> byCategory) {
    final cat = Categories.byId(b.categoryId);
    final spent = byCategory[b.categoryId] ?? 0;
    final over = spent - b.monthlyCap;
    final pct = b.monthlyCap > 0 ? (spent / b.monthlyCap).clamp(0.0, 2.0) : 1.0;

    return GestureDetector(
      onTap: () => Navigator.pushNamed(context, AppRoutes.transactions,
          arguments: b.categoryId),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
                color: cat.color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10)),
            child: Icon(cat.icon, size: 17, color: cat.color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(
                    child: Text(cat.label,
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w700),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ),
                  Text('+${formatRupees(over, compact: true)} over',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AerisColors.moneyOut(context))),
                ]),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: pct.clamp(0.0, 1.0),
                    minHeight: 4,
                    backgroundColor:
                        AerisColors.moneyOut(context).withValues(alpha: 0.15),
                    color: AerisColors.moneyOut(context),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Icon(Icons.chevron_right,
              size: 16, color: AerisColors.moneyOut(context)),
        ]),
      ),
    );
  }
}

// ── Compact check-in strip ────────────────────────────────────
class _CheckinStrip extends ConsumerStatefulWidget {
  const _CheckinStrip();

  @override
  ConsumerState<_CheckinStrip> createState() => _CheckinStripState();
}

class _CheckinStripState extends ConsumerState<_CheckinStrip> {
  @override
  Widget build(BuildContext context) {
    // Watch only the fields this strip renders — not the whole gamification
    // object — so aura ticks, avatar changes and garden edits elsewhere don't
    // rebuild it. The record compares by value, so a rebuild fires only when one
    // of these three actually changes.
    final s = ref.watch(gamificationProvider.select((g) => (
          loaded: g.loaded,
          streak: g.liveStreak,
          checkedIn: g.checkedInOn(DateTime.now()),
        )));
    final ctrl = ref.read(gamificationProvider.notifier);
    if (!s.loaded) return const SizedBox.shrink();

    final streak = s.streak; // lapses if a day was missed
    final checkedIn = s.checkedIn;
    final bonus = (streak * 5).clamp(0, 60);

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? const Color(0xFF14221F) : Colors.white;
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.09)
        : Colors.black.withValues(alpha: 0.08);

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.06),
              blurRadius: isDark ? 12 : 8,
              offset: const Offset(0, 3))
        ],
      ),
      child: Row(children: [
        // Flame / check icon box
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: checkedIn
                ? AerisColors.moneyIn(context).withValues(alpha: 0.15)
                : const Color(0xFFF97316).withValues(alpha: 0.85),
          ),
          child: Icon(
            checkedIn ? Icons.task_alt : Icons.local_fire_department,
            size: 22,
            color: checkedIn ? AerisColors.moneyIn(context) : Colors.white,
          ),
        ),
        const SizedBox(width: 12),
        // Text
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
                          : 'Start your streak today',
                  style: const TextStyle(
                      fontSize: 13.5, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 2),
                Text(
                  checkedIn
                      ? 'See you tomorrow'
                      : 'Daily check-in · claim Aura',
                  style: TextStyle(
                      fontSize: 11.5,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600),
                ),
              ]),
        ),
        const SizedBox(width: 8),
        // Claim / Done button
        GestureDetector(
          onTap: checkedIn
              ? null
              : () {
                  final awarded = ctrl.checkIn();
                  if (awarded > 0 && mounted) {
                    // Read the streak *after* check-in — never guess with +1,
                    // which was wrong whenever the streak had lapsed.
                    final newStreak =
                        ref.read(gamificationProvider).checkinStreak;
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content:
                          Text('+$awarded Aura · $newStreak-day streak 🔥'),
                      duration: const Duration(seconds: 2),
                    ));
                  }
                },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
            decoration: BoxDecoration(
              color: checkedIn
                  ? Theme.of(context)
                      .colorScheme
                      .surfaceContainerHighest
                      .withValues(alpha: 0.6)
                  : AerisColors.seed,
              borderRadius: BorderRadius.circular(99),
            ),
            child: Text(
              checkedIn ? 'Done ✓' : '+${15 + bonus} ✦',
              style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: checkedIn
                      ? Theme.of(context).colorScheme.onSurfaceVariant
                      : Colors.white),
            ),
          ),
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
    final insights = ref.watch(insightsProvider).valueOrNull;
    if (insights == null) return const SizedBox.shrink();

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? const Color(0xFF14221F) : Colors.white;
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.09)
        : Colors.black.withValues(alpha: 0.08);

    final riskyCount = insights.budgetProjections
        .where((p) =>
            p.alreadyOver || (p.willExceed && (p.daysUntilExceed ?? 99) <= 7))
        .length;

    final estimate = insights.monthEstimate.estimate;

    return GestureDetector(
      onTap: () => Navigator.pushNamed(context, AppRoutes.insights),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: borderColor),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.06),
                blurRadius: isDark ? 12 : 8,
                offset: const Offset(0, 3))
          ],
        ),
        child: Row(children: [
          // Icon box
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
                color: AerisColors.warning.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(12)),
            child: const Icon(Icons.online_prediction,
                size: 22, color: AerisColors.warning),
          ),
          const SizedBox(width: 13),
          // Text
          Expanded(
            child: RichText(
              text: TextSpan(
                style: TextStyle(
                    fontSize: 13,
                    color: Theme.of(context).colorScheme.onSurface,
                    fontWeight: FontWeight.w600,
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
                          fontWeight: FontWeight.w800),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          Icon(Icons.chevron_right,
              color: Theme.of(context).colorScheme.onSurfaceVariant),
        ]),
      ),
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
      padding: const EdgeInsets.only(bottom: 11),
      child: Row(children: [
        Text(title,
            style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5)),
        const Spacer(),
        GestureDetector(
          onTap: onAction,
          child: Row(children: [
            Text(action,
                style: TextStyle(
                    color: AerisColors.ink(context),
                    fontSize: 13,
                    fontWeight: FontWeight.w700)),
            const Icon(Icons.chevron_right, size: 17, color: AerisColors.seed),
          ]),
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
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _SectionHeader(
        title: 'Recent activity',
        action: 'All',
        onAction: () => Navigator.pushNamed(context, AppRoutes.transactions),
      ),
      const _RecentActivityList(),
    ]);
  }
}

class _RecentActivityList extends ConsumerWidget {
  const _RecentActivityList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? const Color(0xFF14221F) : Colors.white;
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.09)
        : Colors.black.withValues(alpha: 0.08);

    final recent = ref.watch(recentTransactionsProvider(5));
    return recent.when(
      data: (list) {
        if (list.isEmpty) return _empty(context);
        return Container(
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: borderColor),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.06),
                  blurRadius: isDark ? 12 : 8,
                  offset: const Offset(0, 3))
            ],
          ),
          child: Column(
            children: [
              for (int i = 0; i < list.length; i++) ...[
                TransactionTile(txn: list[i]),
                if (i < list.length - 1)
                  Divider(
                    height: 1,
                    indent: 16,
                    endIndent: 16,
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.06)
                        : Colors.black.withValues(alpha: 0.05),
                  ),
              ],
            ],
          ),
        );
      },
      loading: () => Column(
        children: List.generate(
            4,
            (_) => const SkeletonBox(
                height: 56,
                radius: 12,
                margin: EdgeInsets.symmetric(vertical: 4))),
      ),
      error: (e, _) => Text('Could not load: $e'),
    );
  }

  Widget _empty(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 30),
        child: Column(children: [
          Icon(Icons.receipt_long_outlined,
              size: 44, color: Theme.of(context).colorScheme.onSurfaceVariant),
          const SizedBox(height: 10),
          const Text(
            'No transactions yet.\nTap + to add one.',
            textAlign: TextAlign.center,
          ),
        ]),
      ),
    );
  }
}
