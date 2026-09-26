import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:home_widget/home_widget.dart';

import '../../core/theme.dart';
import '../../models/budget.dart';
import '../../models/transaction.dart';
import '../../providers/analytics_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/budgets_provider.dart';
import '../../providers/gamification_provider.dart';
import '../../providers/transactions_provider.dart';
import '../../providers/village_provider.dart';
import '../../utils/formatters.dart';
import '../../widgets/aeris_avatar.dart';
import '../../widgets/budget_ring.dart';

/// Gallery of home-screen widgets, mirroring the new-GUI "Me → Widgets" screen.
/// The phone/tablet toggle from the design tool is intentionally dropped — this
/// is the phone build. Each preview matches the GUI styling; the ones backed by
/// a real Android provider pin it, the rest are visual previews.
class WidgetsScreen extends ConsumerWidget {
  const WidgetsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;

    final g = ref.watch(gamificationProvider);
    final status = ref.watch(avatarStatusProvider);
    // Live streak (lapses if a day was missed) + the real Sun→Sat week so the
    // dots reflect actual check-in days: past days stay lit, today stays empty
    // until checked in. See GamificationState.liveStreak / weekCheckins.
    final streak = g.liveStreak;
    final week = g.weekCheckins();
    final todayIdx = g.todayWeekIndex;
    final aura = g.available;

    // First-name greeting for the streak widget (matches the native widget).
    final profile = ref.watch(userProfileProvider).valueOrNull;
    final firstName = (profile?.displayName ?? '').trim().isEmpty
        ? null
        : (profile!.displayName!).trim().split(RegExp(r'\s+')).first;
    final greeting = firstName == null ? null : 'Hi, $firstName!';

    final analytics = ref.watch(analyticsProvider).valueOrNull;
    final budgets = ref.watch(budgetsStreamProvider).valueOrNull ?? const [];
    final explicitTotal = budgets
        .where((b) => b.categoryId == Budget.totalId)
        .fold<double>(0, (s, b) => s + b.monthlyCap);
    final budget = explicitTotal > 0
        ? explicitTotal
        : budgets
            .where((b) => b.categoryId != Budget.totalId)
            .fold<double>(0, (s, b) => s + b.monthlyCap);
    final spent = analytics?.monthExpense ?? 0;
    final left = budget - spent;
    final ringV = budget > 0 ? (spent / budget).clamp(0.0, 1.2) : 0.0;
    final townLvl = ref.watch(villageProvider).townLevel;

    // Today's spend (for the 1×1 "Today" widget).
    final txns = ref.watch(transactionsStreamProvider).valueOrNull ?? const [];
    final now = DateTime.now();
    final todaySpend = txns
        .where((t) =>
            t.direction == TxnDirection.debit &&
            t.timestamp.year == now.year &&
            t.timestamp.month == now.month &&
            t.timestamp.day == now.day)
        .fold<double>(0, (s, t) => s + t.amount);

    // Widget catalog: name, size label, [w,h], builder, optional real provider.
    final widgets = <_WidgetDef>[
      _WidgetDef(
          'Streak',
          '4×2',
          4,
          2,
          (c) => _StreakW(
              streak: streak,
              week: week,
              todayIdx: todayIdx,
              big: true,
              greeting: greeting),
          provider: 'AerisStreakWidgetProvider'),
      _WidgetDef('Month spend', '2×2', 2, 2,
          (c) => _SpentW(spent: spent, budget: budget),
          provider: 'AerisSpentWidgetProvider'),
      _WidgetDef(
          'Budget ring', '2×2', 2, 2, (c) => _BudgetW(ringV: ringV, left: left),
          provider: 'AerisBudgetWidgetProvider'),
      _WidgetDef('My Village', '2×2', 2, 2,
          (c) => _VillageW(townLvl: townLvl, aura: aura),
          provider: 'AerisVillageWidgetProvider'),
      _WidgetDef(
          'Quick capture', '4×1', 4, 1, (c) => _QuickW(skin: status.skin),
          provider: 'AerisQuickWidgetProvider'),
      _WidgetDef('Today', '1×1', 1, 1, (c) => _MiniSpent(amount: todaySpend),
          provider: 'AerisTodayWidgetProvider'),
      _WidgetDef(
          'Streak mini',
          '2×1',
          2,
          1,
          (c) => _StreakW(
              streak: streak, week: week, todayIdx: todayIdx, big: false),
          provider: 'AerisStreakMiniWidgetProvider'),
    ];

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        title: const Text('Widgets'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(20),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
              child: Text('Add to your home screen',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurfaceVariant)),
            ),
          ),
        ),
      ),
      body: LayoutBuilder(builder: (context, constraints) {
        const gap = 12.0;
        // Phone uses a 4-column grid, tablet a 6-column grid (larger surface).
        final tablet = MediaQuery.of(context).size.shortestSide >= 600;
        final cols = tablet ? 6 : 4;
        final availW = constraints.maxWidth - 32; // 16 padding each side
        final cell = (availW - (cols - 1) * gap) / cols;
        Widget sized(int w, int h, Widget child) => SizedBox(
              width: (w * cell + (w - 1) * gap).clamp(0.0, availW),
              height: h * cell + (h - 1) * gap,
              child: child,
            );

        // The wallpaper preview lives inside a Container with 16px padding all
        // round, so its content box is 32px narrower than availW. Size the
        // preview widgets against that, otherwise the 2×2 Row overflows by 32px.
        final previewW = availW - 32;
        final previewCell = (previewW - (cols - 1) * gap) / cols;
        Widget sizedP(int w, int h, Widget child) => SizedBox(
              width: (w * previewCell + (w - 1) * gap).clamp(0.0, previewW),
              height: h * previewCell + (h - 1) * gap,
              child: child,
            );

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 30),
          children: [
            // ── Wallpaper live preview ──────────────────────
            Container(
              padding: const EdgeInsets.all(16),
              margin: const EdgeInsets.only(bottom: 18),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: dark
                      ? const [
                          Color(0xFF10243A),
                          Color(0xFF241A3A),
                          Color(0xFF0C1F24)
                        ]
                      : const [
                          Color(0xFFCFE9FF),
                          Color(0xFFDCD2FF),
                          Color(0xFFFFD9EC)
                        ],
                ),
              ),
              child: Column(children: [
                sizedP(
                    4,
                    2,
                    _StreakW(
                        streak: streak,
                        week: week,
                        todayIdx: todayIdx,
                        big: true,
                        greeting: greeting)),
                const SizedBox(height: gap),
                Row(children: [
                  sizedP(2, 2, _SpentW(spent: spent, budget: budget)),
                  const SizedBox(width: gap),
                  sizedP(2, 2, _BudgetW(ringV: ringV, left: left)),
                  if (tablet) ...[
                    const SizedBox(width: gap),
                    sizedP(2, 2, _VillageW(townLvl: townLvl, aura: aura)),
                  ],
                ]),
                const SizedBox(height: 12),
                Text('Live preview · your real data',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: dark
                            ? Colors.white.withValues(alpha: 0.6)
                            : const Color(0xFF142838).withValues(alpha: 0.5))),
              ]),
            ),

            // ── Gallery ─────────────────────────────────────
            Text('ALL WIDGETS',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                    color: scheme.onSurfaceVariant)),
            const SizedBox(height: 12),
            for (final w in widgets)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Text(w.name,
                          style: const TextStyle(
                              fontSize: 13.5, fontWeight: FontWeight.w800)),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                            color: scheme.onSurface.withValues(alpha: 0.06),
                            borderRadius: BorderRadius.circular(6)),
                        child: Text(w.size,
                            style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w800,
                                color: scheme.onSurfaceVariant)),
                      ),
                      const Spacer(),
                      GestureDetector(
                        onTap: () => _add(context, w),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 13, vertical: 6),
                          decoration: BoxDecoration(
                              color: AerisColors.seed.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(99)),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            const Icon(Icons.add,
                                size: 15, color: AerisColors.seed),
                            const SizedBox(width: 4),
                            Text(w.provider == null ? 'Preview' : 'Add',
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                    color: AerisColors.ink(context))),
                          ]),
                        ),
                      ),
                    ]),
                    const SizedBox(height: 8),
                    sized(w.w, w.h, w.build(context)),
                  ],
                ),
              ).animate().fadeIn(duration: 250.ms).slideY(begin: 0.04, end: 0),
          ],
        );
      }),
    );
  }

  Future<void> _add(BuildContext context, _WidgetDef w) async {
    if (w.provider == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content:
              Text('Preview only for now — coming to your home screen soon.')));
      return;
    }
    try {
      final supported = await HomeWidget.isRequestPinWidgetSupported() ?? false;
      if (supported) {
        await HomeWidget.requestPinWidget(androidName: w.provider!);
        return;
      }
    } catch (_) {}
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content:
            Text('Long-press your home screen → Widgets → AERIS to add this.'),
      ));
    }
  }
}

class _WidgetDef {
  final String name;
  final String size;
  final int w;
  final int h;
  final Widget Function(BuildContext) build;
  final String? provider;
  const _WidgetDef(this.name, this.size, this.w, this.h, this.build,
      {this.provider});
}

// ── Glass shell (frosted card that reads on the wallpaper) ───────────────────
Widget _glass(BuildContext context, Widget child, {double radius = 22}) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  return Container(
    decoration: BoxDecoration(
      color: dark
          ? Colors.white.withValues(alpha: 0.10)
          : Colors.white.withValues(alpha: 0.78),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
      boxShadow: [
        BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 10,
            offset: const Offset(0, 4)),
      ],
    ),
    child: child,
  );
}

// ── Streak (4×2 big / 2×1 mini) ──────────────────────────────────────────────
class _StreakW extends StatelessWidget {
  final int streak;

  /// Real Sun→Saturday check-in state (index 0=Sun … 6=Sat). A `true` entry is
  /// a day that was actually checked in, so the dots track the calendar instead
  /// of just filling left-to-right.
  final List<bool> week;

  /// Index of today inside [week] — rendered with a ring so it reads as "now",
  /// and left empty when today hasn't been checked in yet.
  final int todayIdx;
  final bool big;
  final String? greeting;
  const _StreakW({
    required this.streak,
    required this.week,
    required this.todayIdx,
    required this.big,
    this.greeting,
  });

  @override
  Widget build(BuildContext context) {
    // Sunday-first labels — fixes the old duplicated 'S S M T W T F'.
    const labels = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];
    final body = Stack(clipBehavior: Clip.none, children: [
      Positioned(
        right: -14,
        bottom: -20,
        child: Icon(Icons.local_fire_department,
            size: big ? 96 : 70, color: Colors.white.withValues(alpha: 0.22)),
      ),
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          if (big && greeting != null) ...[
            Text(greeting!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.2)),
            const SizedBox(height: 10),
          ],
          Row(children: [
            Icon(Icons.local_fire_department,
                size: big ? 28 : 22, color: const Color(0xFFFFE0B2)),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('$streak day${streak == 1 ? '' : 's'}',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: big ? 26 : 20,
                        fontWeight: FontWeight.w700,
                        height: 1)),
                Text('Streak',
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600)),
              ],
            ),
          ]),
          if (big) ...[
            const Spacer(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (var i = 0; i < 7; i++)
                  () {
                    final done = i < week.length && week[i];
                    final isToday = i == todayIdx;
                    final isFuture = i > todayIdx;
                    return Column(mainAxisSize: MainAxisSize.min, children: [
                      Container(
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: done
                              ? Colors.white
                              : Colors.white
                                  .withValues(alpha: isFuture ? 0.12 : 0.22),
                          // Ring today so it reads as "now" even before
                          // the user has checked in.
                          border: isToday && !done
                              ? Border.all(color: Colors.white, width: 2)
                              : null,
                        ),
                        child: done
                            ? const Icon(Icons.check,
                                size: 13, color: Color(0xFFEA580C))
                            : null,
                      ),
                      const SizedBox(height: 4),
                      Text(labels[i],
                          style: TextStyle(
                              color: Colors.white
                                  .withValues(alpha: isToday ? 1 : 0.8),
                              fontSize: 9,
                              fontWeight: FontWeight.w700)),
                    ]);
                  }(),
              ],
            ),
          ],
        ],
      ),
    ]);
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFEA580C), Color(0xFFF97316)],
          ),
        ),
        // The big variant renders at a fixed design size and scales to its
        // cell — so it never overflows whether shown small (gallery/wallpaper
        // preview) or large, and stays visually identical.
        child: big
            ? FittedBox(
                fit: BoxFit.contain,
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: SizedBox(width: 300, height: 138, child: body),
                ),
              )
            : Padding(padding: const EdgeInsets.all(14), child: body),
      ),
    );
  }
}

// ── Month spend (2×2) ────────────────────────────────────────────────────────
class _SpentW extends StatelessWidget {
  final double spent;
  final double budget;
  const _SpentW({required this.spent, required this.budget});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0EA5A4), Color(0xFF0F766E)],
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Spent this month',
              style: TextStyle(
                  color: Colors.white70,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(formatRupees(spent, compact: true),
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.5)),
          const SizedBox(height: 2),
          Text('of ${formatRupees(budget, compact: true)} budget',
              style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 10,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

// ── Budget ring (2×2, glass) ─────────────────────────────────────────────────
class _BudgetW extends StatelessWidget {
  final double ringV;
  final double left;
  const _BudgetW({required this.ringV, required this.left});

  @override
  Widget build(BuildContext context) {
    return _glass(
      context,
      Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            BudgetRing(
              progress: ringV.clamp(0.0, 1.0),
              size: 64,
              strokeWidth: 8,
              color: AerisColors.seed,
              center: Text('${(ringV * 100).round()}%',
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w700)),
            ),
            const SizedBox(height: 8),
            Text(formatRupees(left.abs(), compact: true),
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: left >= 0 ? AerisColors.moneyIn(context) : AerisColors.moneyOut(context))),
            Text(left >= 0 ? 'left' : 'over',
                style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}

// ── My Village (2×2) ─────────────────────────────────────────────────────────
class _VillageW extends StatelessWidget {
  final int townLvl;
  final int aura;
  const _VillageW({required this.townLvl, required this.aura});

  @override
  Widget build(BuildContext context) {
    Widget chip(Widget child) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
          decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(99)),
          child: child,
        );
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF7CC9EC), Color(0xFF86C84C)],
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              chip(Text('🏰 Lv $townLvl',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800))),
              chip(Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.bolt, size: 12, color: Color(0xFFFCD34D)),
                const SizedBox(width: 3),
                Text('$aura',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800)),
              ])),
            ],
          ),
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('🏡', style: TextStyle(fontSize: 26)),
              Text('🏛️', style: TextStyle(fontSize: 30)),
              Text('🌳', style: TextStyle(fontSize: 26)),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Quick capture (4×1, glass) ───────────────────────────────────────────────
class _QuickW extends StatelessWidget {
  final dynamic skin;
  const _QuickW({required this.skin});

  @override
  Widget build(BuildContext context) {
    return _glass(
      context,
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(children: [
          SizedBox(
            width: 34,
            height: 34,
            child:
                AerisAvatar(skin: skin, size: 34, glow: false, animate: false),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text('Add expense…',
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ),
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
                color: const Color(0xFF8B5CF6),
                borderRadius: BorderRadius.circular(11)),
            child: const Icon(Icons.mic, size: 19, color: Colors.white),
          ),
          const SizedBox(width: 8),
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
                color: AerisColors.seed,
                borderRadius: BorderRadius.circular(11)),
            child: const Icon(Icons.add, size: 21, color: Colors.white),
          ),
        ]),
      ),
    );
  }
}

// ── Today mini (1×1, glass) ──────────────────────────────────────────────────
class _MiniSpent extends StatelessWidget {
  final double amount;
  const _MiniSpent({required this.amount});

  @override
  Widget build(BuildContext context) {
    return _glass(
      context,
      radius: 20,
      Padding(
        padding: const EdgeInsets.all(12),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Today',
                  style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                      color: Theme.of(context).colorScheme.onSurfaceVariant)),
              Text(formatRupees(amount, compact: true),
                  style: const TextStyle(
                      fontSize: 19, fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ),
    );
  }
}
