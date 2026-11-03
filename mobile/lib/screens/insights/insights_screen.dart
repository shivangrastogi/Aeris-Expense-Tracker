import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/routes.dart';
import '../../core/theme.dart';
import '../../models/category.dart';
import '../../models/insight.dart';
import '../../providers/insights_provider.dart';
import '../../utils/formatters.dart';
import '../../widgets/ds.dart';
import '../../widgets/mascot/mascot_card.dart';
import '../../widgets/skeleton.dart';

class InsightsScreen extends ConsumerWidget {
  const InsightsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final b = ref.watch(insightsProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI insights'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: RoundIconButton(
              icon: Ph.sparkle,
              tooltip: 'Ask Aeris',
              onTap: () => Navigator.pushNamed(context, AppRoutes.assistant),
            ),
          ),
        ],
      ),
      body: b.when(
        // Keep showing the previous insights while a recompute is running —
        // without this the whole tab flashes back to skeletons on every
        // transaction/budget change.
        skipLoadingOnReload: true,
        loading: () => const InsightsSkeleton(),
        error: (e, _) => Padding(
          padding: const EdgeInsets.all(20),
          child: Banner2(
              tone: Tone.bad,
              icon: PhFill.cloudX,
              title: "Couldn't load insights",
              body: '$e'),
        ),
        data: (bundle) => ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            const MascotCard(),
            const SizedBox(height: 16),
            _PredictionCard(p: bundle.monthEstimate, hero: true),
            if (bundle.budgetProjections.isNotEmpty) ...[
              const _SectionTitle('Budget projections'),
              for (final bp in bundle.budgetProjections)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _BudgetProjectionCard(bp: bp),
                ),
            ],
            const _SectionTitle('Ways to save'),
            for (final r in bundle.recommendations)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _RecCard(r),
              ),
            if (bundle.recommendations.isEmpty)
              const _Note('Nothing to flag yet — keep using the app, '
                  'I\'ll have tips once you have a few weeks of data.'),
            const _SectionTitle('Next month: per-category forecast'),
            if (bundle.categoryForecasts.isNotEmpty)
              ListGroup(children: [
                for (final p in bundle.categoryForecasts.take(6))
                  _ForecastRow(p: p),
              ]),
            const _SectionTitle('Recurring payments found'),
            if (bundle.recurring.isEmpty)
              const _Note('No recurring patterns detected yet.')
            else
              ListGroup(children: [
                for (final r in bundle.recurring) _RecurringRow(r: r),
              ]),
            const _SectionTitle('Unusual activity'),
            if (bundle.anomalies.isEmpty)
              const _Note('Nothing unusual in recent activity.'),
            for (final a in bundle.anomalies)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Banner2(
                  tone: Tone.warn,
                  icon: PhFill.warningCircle,
                  title:
                      '${a.merchant ?? 'Unknown'} · ${formatRupees(a.amount, compact: true)}',
                  body: a.reason,
                ),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String label;
  const _SectionTitle(this.label);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 24, 4, 8),
        child: Overline(label),
      );
}

class _Note extends StatelessWidget {
  final String text;
  const _Note(this.text);
  @override
  Widget build(BuildContext context) => AerisCard(
        child: Text(text,
            style: TextStyle(fontSize: 13, height: 18 / 13, color: context.tk.t2)),
      );
}

class _PredictionCard extends StatelessWidget {
  final Prediction p;
  final bool hero;
  const _PredictionCard({required this.p, this.hero = false});

  @override
  Widget build(BuildContext context) {
    final tk = context.tk;
    return AerisCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Overline(p.label),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            crossAxisAlignment: WrapCrossAlignment.end,
            children: [
              MoneyText(p.estimate, style: hero ? Ts.amountL : Ts.amountM),
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text(
                    'likely ${formatRupees(p.low, compact: true)}–'
                    '${formatRupees(p.high, compact: true)}',
                    style: TextStyle(fontSize: 13, color: tk.t2)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(p.basis, style: Ts.bodyS.copyWith(color: tk.t2)),
        ],
      ),
    );
  }
}

class _ForecastRow extends StatelessWidget {
  final Prediction p;
  const _ForecastRow({required this.p});

  @override
  Widget build(BuildContext context) {
    final tk = context.tk;
    final cat = p.categoryId == null ? null : Categories.byId(p.categoryId!);
    return DsRow(
      leading: cat == null
          ? BadgeTile(icon: Ph.trendUp, tint: tk.acc)
          : CatTile.of(cat),
      title: cat?.label ?? p.label,
      sub: '${formatRupees(p.low, compact: true)}–'
          '${formatRupees(p.high, compact: true)} · ${p.basis}',
      trailing: MoneyText(p.estimate),
    );
  }
}

class _BudgetProjectionCard extends StatelessWidget {
  final BudgetProjection bp;
  const _BudgetProjectionCard({required this.bp});

  @override
  Widget build(BuildContext context) {
    final tk = context.tk;
    final cat = Categories.byId(bp.categoryId);
    final (Tone tone, Color color, IconData icon, String pill, String status) =
        bp.alreadyOver
            ? (
                Tone.bad,
                tk.bad,
                PhFill.warningOctagon,
                'Over',
                'Over budget by ${formatRupees(bp.spentSoFar - bp.cap, compact: true)}'
              )
            : bp.willExceed
                ? (
                    Tone.warn,
                    tk.warn,
                    PhFill.warning,
                    'At risk',
                    bp.daysUntilExceed != null
                        ? 'On pace to go over in ~${bp.daysUntilExceed} day${bp.daysUntilExceed == 1 ? '' : 's'} '
                            '(≈${formatRupees(bp.projectedMonthEnd, compact: true)} by month-end)'
                        : 'Projected ≈${formatRupees(bp.projectedMonthEnd, compact: true)} by month-end'
                  )
                : (
                    Tone.ok,
                    tk.ok,
                    PhFill.checkCircle,
                    'On track',
                    'Projected ≈${formatRupees(bp.projectedMonthEnd, compact: true)} of ${formatRupees(bp.cap, compact: true)}'
                  );
    final pct = bp.cap <= 0 ? 0.0 : bp.spentSoFar / bp.cap;
    return AerisCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            CatTile.of(cat),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(cat.label, style: Ts.rowTitle.copyWith(color: tk.t1)),
                  Text(
                      '${formatRupees(bp.spentSoFar, compact: true)} of '
                      '${formatRupees(bp.cap, compact: true)}',
                      style: Ts.bodyS.copyWith(color: tk.t2)),
                ],
              ),
            ),
            StatusPill(pill, icon: icon, tone: tone),
          ]),
          const SizedBox(height: 12),
          RisingProgress(
              value: pct, color: pct > 1 ? tk.bad : null, rise: 3, dot: 3),
          const SizedBox(height: 8),
          Text(status,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: tone == Tone.ok ? tk.t2 : color)),
        ],
      ),
    );
  }
}

class _RecCard extends StatelessWidget {
  final Recommendation r;
  const _RecCard(this.r);

  @override
  Widget build(BuildContext context) {
    final tk = context.tk;
    final (Color color, IconData icon) = switch (r.severity) {
      InsightSeverity.alert => (tk.bad, Ph.warningOctagon),
      InsightSeverity.warning => (tk.warn, Ph.warning),
      InsightSeverity.positive => (tk.ok, Ph.piggyBank),
      InsightSeverity.info => (tk.acc, Ph.lightbulb),
    };
    final saving = r.potentialSaving;
    return AerisCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        BadgeTile(
            icon: r.categoryId != null
                ? Categories.byId(r.categoryId!).icon
                : icon,
            tint: color),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(r.title, style: Ts.rowTitle.copyWith(color: tk.t1)),
              const SizedBox(height: 2),
              Text(r.body,
                  style: TextStyle(fontSize: 12, height: 16 / 12, color: tk.t2)),
            ],
          ),
        ),
        if (saving != null && saving > 0) ...[
          const SizedBox(width: 12),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            MoneyText(saving,
                compact: true,
                color: tk.ok,
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w700)),
            Text('per month', style: TextStyle(fontSize: 11, color: tk.t2)),
          ]),
        ],
      ]),
    );
  }
}

class _RecurringRow extends StatelessWidget {
  final RecurringPayment r;
  const _RecurringRow({required this.r});

  @override
  Widget build(BuildContext context) {
    final cat = Categories.byId(r.categoryId);
    return DsRow(
      leading: CatTile.of(cat),
      title: r.merchant,
      sub: 'Around the ${r.dayOfMonth}${_ordinal(r.dayOfMonth)} · '
          '${r.occurrences} months',
      trailing: MoneyText(r.approxAmount),
    );
  }

  String _ordinal(int n) {
    if (n >= 11 && n <= 13) return 'th';
    return switch (n % 10) {
      1 => 'st',
      2 => 'nd',
      3 => 'rd',
      _ => 'th',
    };
  }
}
