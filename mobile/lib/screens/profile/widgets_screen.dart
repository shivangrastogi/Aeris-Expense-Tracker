import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:home_widget/home_widget.dart';

import '../../core/theme.dart';
import '../../models/budget.dart';
import '../../providers/auth_provider.dart';
import '../../providers/gamification_provider.dart';
import '../../providers/money_providers.dart';
import '../../providers/transactions_provider.dart';
import '../../providers/village_provider.dart';
import '../../services/widget_service.dart';
import '../../utils/formatters.dart';
import '../../widgets/aeris_toast.dart';

/// Gallery of the AERIS home-screen widgets. Every preview is a Flutter
/// replica of the native widget (android/.../res/layout/aeris_*_widget.xml +
/// WidgetData.kt) fed with the same numbers, in the same light/dark colours,
/// so what you see here is what lands on the home screen.
class WidgetsScreen extends ConsumerWidget {
  const WidgetsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final g = ref.watch(gamificationProvider);
    final profile = ref.watch(userProfileProvider).valueOrNull;
    final name = (profile?.displayName ?? '').trim().split(RegExp(r'\s+')).first;

    final budgets = ref.watch(effectiveBudgetsProvider);
    final explicitTotal =
        budgets.where((b) => b.categoryId == Budget.totalId).fold<double>(0, (s, b) => s + b.monthlyCap);
    final budget = explicitTotal > 0
        ? explicitTotal
        : budgets.where((b) => b.categoryId != Budget.totalId).fold<double>(0, (s, b) => s + b.monthlyCap);
    final txns = ref.watch(transactionsStreamProvider).valueOrNull ?? const [];
    final snap = WidgetSnapshot.compute(txns, DateTime.now());
    final m = _Model(
      spent: snap.monthSpent,
      today: snap.todaySpent,
      budget: budget,
      streak: g.liveStreak,
      week: g.weekCheckins(),
      todayIdx: g.todayWeekIndex,
      aura: g.available,
      town: ref.watch(villageProvider).townLevel,
      name: name,
    );

    final defs = <_Def>[
      _Def('Overview', '3×2', 3, 2, (c) => _OverviewW(m), 'AerisWidgetProvider'),
      _Def('Streak', '4×2', 4, 2, (c) => _StreakW(m), 'AerisStreakWidgetProvider'),
      _Def('Month spend', '2×2', 2, 2, (c) => _SpentW(m), 'AerisSpentWidgetProvider'),
      _Def('Budget ring', '2×2', 2, 2, (c) => _BudgetW(m), 'AerisBudgetWidgetProvider'),
      _Def('Aeris Town', '2×2', 2, 2, (c) => _TownW(m), 'AerisVillageWidgetProvider'),
      _Def('Quick capture', '4×1', 4, 1, (c) => const _QuickW(), 'AerisQuickWidgetProvider'),
      _Def('Today', '1×1', 1, 1, (c) => _TodayW(m), 'AerisTodayWidgetProvider'),
      _Def('Streak mini', '2×1', 2, 1, (c) => _StreakMiniW(m), 'AerisStreakMiniWidgetProvider'),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Widgets')),
      body: LayoutBuilder(builder: (context, constraints) {
        const gap = 12.0;
        final availW = constraints.maxWidth - 32;
        final cell = (availW - 3 * gap) / 4;
        Widget sized(int w, int h, Widget child) => SizedBox(
              width: (w * cell + (w - 1) * gap).clamp(0.0, availW),
              height: h * cell + (h - 1) * gap,
              child: child,
            );
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
          children: [
            Text(
              'Widgets update by themselves — when a bank SMS arrives, at midnight and on the 1st — '
              'and follow your phone\'s light or dark mode.',
              style: TextStyle(color: AerisColors.muted(context), fontSize: 13, height: 1.45),
            ),
            const SizedBox(height: 18),
            for (final d in defs)
              Padding(
                padding: const EdgeInsets.only(bottom: 20),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Text(d.name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                    const SizedBox(width: 8),
                    Text(d.size, style: TextStyle(fontSize: 12, color: AerisColors.muted(context))),
                    const Spacer(),
                    FilledButton.tonalIcon(
                      onPressed: () => _add(context, d),
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Add'),
                    ),
                  ]),
                  const SizedBox(height: 10),
                  sized(d.w, d.h, d.build(context)),
                ]),
              ).animate().fadeIn(duration: 220.ms),
          ],
        );
      }),
    );
  }

  Future<void> _add(BuildContext context, _Def d) async {
    try {
      if (await HomeWidget.isRequestPinWidgetSupported() ?? false) {
        await HomeWidget.requestPinWidget(androidName: d.provider);
        await WidgetService.refresh();
        return;
      }
    } catch (_) {}
    if (context.mounted) {
      ScaffoldMessenger.of(context).showToast(const SnackBar(
        content: Text('Long-press your home screen → Widgets → AERIS to add this.'),
      ));
    }
  }
}

class _Def {
  final String name, size, provider;
  final int w, h;
  final Widget Function(BuildContext) build;
  const _Def(this.name, this.size, this.w, this.h, this.build, this.provider);
}

/// The same numbers WidgetData.kt shows.
class _Model {
  final double spent, today, budget;
  final int streak, todayIdx, aura, town;
  final List<bool> week;
  final String name;
  const _Model({
    required this.spent,
    required this.today,
    required this.budget,
    required this.streak,
    required this.week,
    required this.todayIdx,
    required this.aura,
    required this.town,
    required this.name,
  });
  double get left => budget - spent;
  bool get hasBudget => budget > 0;
  bool get over => hasBudget && left < 0;
  int get pct => hasBudget ? (spent / budget * 100).round().clamp(0, 999) : 0;
  bool get checkedIn => todayIdx >= 0 && todayIdx < week.length && week[todayIdx];
}

/// Colours from res/values(-night)/colors.xml.
class _W {
  final Color bg, line, text, muted, accent, onAccent, ok, warn, danger, track;
  const _W(this.bg, this.line, this.text, this.muted, this.accent, this.onAccent, this.ok, this.warn, this.danger,
      this.track);
  static const _dark = _W(Color(0xF0181B21), Color(0xFF272B33), Color(0xFFE6E8EB), Color(0xFF9199A5),
      Color(0xFF7AA6DA), Color(0xFF0E141C), Color(0xFF63B98F), Color(0xFFD2A35A), Color(0xFFD9786F), Color(0xFF272B33));
  static const _light = _W(Color(0xF5FFFFFF), Color(0x1A151A22), Color(0xFF151A22), Color(0xFF5E6978),
      Color(0xFF2B5F9E), Color(0xFFFFFFFF), Color(0xFF2E8656), Color(0xFFA9711C), Color(0xFFBF433A), Color(0xFFE6E9ED));
  static _W of(BuildContext c) => Theme.of(c).brightness == Brightness.dark ? _dark : _light;
}

class _Shell extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  const _Shell({required this.child, this.padding = const EdgeInsets.all(16)});
  @override
  Widget build(BuildContext context) {
    final w = _W.of(context);
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: w.bg,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: w.line),
      ),
      child: child,
    );
  }
}

Widget _label(BuildContext c, String s) => Text(s.toUpperCase(),
    style: TextStyle(fontSize: 10, letterSpacing: 1.2, fontWeight: FontWeight.w600, color: _W.of(c).muted));

Widget _fire(BuildContext c, int streak, double size) =>
    Icon(Icons.local_fire_department, size: size, color: streak > 0 ? _W.of(c).warn : _W.of(c).muted);

class _OverviewW extends StatelessWidget {
  final _Model m;
  const _OverviewW(this.m);
  @override
  Widget build(BuildContext context) {
    final w = _W.of(context);
    return _Shell(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: _label(context, !m.hasBudget ? 'Spent this month' : (m.over ? 'Over budget' : 'Left to spend'))),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: w.track, borderRadius: BorderRadius.circular(99)),
            child: Row(children: [
              _fire(context, m.streak, 13),
              const SizedBox(width: 3),
              Text('${m.streak}', style: TextStyle(color: w.text, fontSize: 11, fontWeight: FontWeight.w600)),
            ]),
          ),
        ]),
        Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            child: FittedBox(
              child: Text(formatRupees(m.hasBudget ? m.left.abs() : m.spent),
                  style: TextStyle(color: m.over ? w.danger : w.text, fontSize: 30, fontWeight: FontWeight.w600)),
            ),
          ),
        ),
        if (m.hasBudget)
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              minHeight: 6,
              value: (m.pct / 100).clamp(0.0, 1.0),
              backgroundColor: w.track,
              valueColor: AlwaysStoppedAnimation(m.over ? w.danger : w.accent),
            ),
          ),
        const SizedBox(height: 8),
        Text(
          m.hasBudget
              ? '${formatRupees(m.spent, compact: true)} of ${formatRupees(m.budget, compact: true)} · today ${formatRupees(m.today, compact: true)}'
              : 'Today ${formatRupees(m.today, compact: true)} · set a budget in AERIS',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: w.muted, fontSize: 11.5),
        ),
      ]),
    );
  }
}

class _BudgetW extends StatelessWidget {
  final _Model m;
  const _BudgetW(this.m);
  @override
  Widget build(BuildContext context) {
    final w = _W.of(context);
    final ring = m.pct >= 100 ? w.danger : (m.pct >= 80 ? w.warn : w.accent);
    return _Shell(
      padding: const EdgeInsets.all(12),
      child: Column(children: [
        Expanded(
          child: AspectRatio(
            aspectRatio: 1,
            child: Stack(alignment: Alignment.center, children: [
              Positioned.fill(
                child: CircularProgressIndicator(
                  value: m.hasBudget ? (m.pct / 100).clamp(0.0, 1.0) : 0,
                  strokeWidth: 8,
                  strokeCap: StrokeCap.round,
                  backgroundColor: w.track,
                  valueColor: AlwaysStoppedAnimation(ring),
                ),
              ),
              Text(m.hasBudget ? '${m.pct}%' : '—',
                  style: TextStyle(color: w.text, fontSize: 17, fontWeight: FontWeight.w600)),
            ]),
          ),
        ),
        const SizedBox(height: 6),
        Text(m.hasBudget ? formatRupees(m.left.abs(), compact: true) : 'No budget',
            style: TextStyle(color: m.over ? w.danger : w.text, fontSize: 14, fontWeight: FontWeight.w600)),
        Text(!m.hasBudget ? 'tap to set one' : (m.over ? 'over budget' : 'left this month'),
            style: TextStyle(color: w.muted, fontSize: 10.5)),
      ]),
    );
  }
}

class _SpentW extends StatelessWidget {
  final _Model m;
  const _SpentW(this.m);
  @override
  Widget build(BuildContext context) {
    final w = _W.of(context);
    return _Shell(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _label(context, 'Spent this month'),
        Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            child: FittedBox(
              child: Text(formatRupees(m.spent),
                  style: TextStyle(color: w.text, fontSize: 26, fontWeight: FontWeight.w600)),
            ),
          ),
        ),
        Text(m.hasBudget ? 'of ${formatRupees(m.budget, compact: true)} budget (${m.pct}%)' : 'No budget set',
            maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: w.muted, fontSize: 11.5)),
        Text('Today ${formatRupees(m.today, compact: true)}',
            maxLines: 1, style: TextStyle(color: w.accent, fontSize: 11.5)),
      ]),
    );
  }
}

class _TodayW extends StatelessWidget {
  final _Model m;
  const _TodayW(this.m);
  @override
  Widget build(BuildContext context) => _Shell(
        padding: const EdgeInsets.all(8),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          _label(context, 'Today'),
          const SizedBox(height: 2),
          FittedBox(
            child: Text(formatRupees(m.today, compact: true),
                style: TextStyle(color: _W.of(context).text, fontSize: 18, fontWeight: FontWeight.w600)),
          ),
        ]),
      );
}

class _StreakW extends StatelessWidget {
  final _Model m;
  const _StreakW(this.m);
  @override
  Widget build(BuildContext context) {
    final w = _W.of(context);
    const days = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];
    return _Shell(
      child: Column(children: [
        Expanded(
          child: Row(children: [
            _fire(context, m.streak, 32),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                Text('${m.streak} day${m.streak == 1 ? '' : 's'}',
                    style: TextStyle(color: w.text, fontSize: 22, fontWeight: FontWeight.w600)),
                Text(
                    m.checkedIn
                        ? 'Checked in today. See you tomorrow.'
                        : m.streak > 0
                            ? '${m.name.isNotEmpty ? '${m.name}, c' : 'C'}heck in to keep it going'
                            : 'Check in daily to build a streak',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: w.muted, fontSize: 11.5)),
              ]),
            ),
            if (!m.checkedIn)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(color: w.accent, borderRadius: BorderRadius.circular(12)),
                child: Text('Check in', style: TextStyle(color: w.onAccent, fontSize: 12, fontWeight: FontWeight.w600)),
              ),
          ]),
        ),
        Row(children: [
          for (var i = 0; i < 7; i++)
            Expanded(
              child: Column(children: [
                Container(
                  width: 24,
                  height: 24,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: m.week[i] ? w.accent : (i == m.todayIdx ? Colors.transparent : w.track),
                    border: i == m.todayIdx && !m.week[i] ? Border.all(color: w.accent, width: 2) : null,
                  ),
                  child: m.week[i] ? Icon(Icons.check, size: 14, color: w.onAccent) : null,
                ),
                const SizedBox(height: 4),
                Text(days[i],
                    style: TextStyle(color: i == m.todayIdx ? w.text : w.muted, fontSize: 10)),
              ]),
            ),
        ]),
      ]),
    );
  }
}

class _StreakMiniW extends StatelessWidget {
  final _Model m;
  const _StreakMiniW(this.m);
  @override
  Widget build(BuildContext context) {
    final w = _W.of(context);
    return _Shell(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(children: [
        _fire(context, m.streak, 26),
        const SizedBox(width: 8),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
            Text('${m.streak} day${m.streak == 1 ? '' : 's'}',
                style: TextStyle(color: w.text, fontSize: 16, fontWeight: FontWeight.w600)),
            Text(m.checkedIn ? 'streak · done today' : 'streak · tap to check in',
                maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: w.muted, fontSize: 10.5)),
          ]),
        ),
      ]),
    );
  }
}

class _TownW extends StatelessWidget {
  final _Model m;
  const _TownW(this.m);
  @override
  Widget build(BuildContext context) {
    final w = _W.of(context);
    return _Shell(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _label(context, 'Aeris Town'),
        Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text('Level ${m.town}', style: TextStyle(color: w.text, fontSize: 22, fontWeight: FontWeight.w600)),
          ),
        ),
        Text('${m.aura} Aura', style: TextStyle(color: w.accent, fontSize: 13, fontWeight: FontWeight.w600)),
        Text(m.checkedIn ? 'Spend Aura to grow your town' : 'Check in today for Aura',
            maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: w.muted, fontSize: 11)),
      ]),
    );
  }
}

class _QuickW extends StatelessWidget {
  const _QuickW();
  @override
  Widget build(BuildContext context) {
    final w = _W.of(context);
    return _Shell(
      padding: const EdgeInsets.only(left: 16, right: 10),
      child: Row(children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(colors: [Colors.white, w.accent, w.accent.withValues(alpha: 0)], stops: const [0, 0.45, 1]),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(child: Text('Spent something?', style: TextStyle(color: w.muted, fontSize: 13.5))),
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(color: w.track, borderRadius: BorderRadius.circular(12)),
          child: Icon(Icons.mic_none, size: 20, color: w.text),
        ),
        const SizedBox(width: 8),
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(color: w.accent, borderRadius: BorderRadius.circular(12)),
          child: Icon(Icons.add, size: 20, color: w.onAccent),
        ),
      ]),
    );
  }
}
