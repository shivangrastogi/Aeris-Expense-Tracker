import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/routes.dart';
import '../../core/theme.dart';
import '../../models/category.dart';
import '../../models/insight.dart';
import '../../providers/insights_provider.dart';
import '../../utils/formatters.dart';
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
          TextButton.icon(
            onPressed: () => Navigator.pushNamed(context, AppRoutes.assistant),
            icon: const Icon(Icons.chat_bubble_outline, size: 18),
            label: const Text('Ask Aeris'),
          ),
        ],
      ),
      body: b.when(
        loading: () => const InsightsSkeleton(),
        error: (e, _) => Center(child: Text('$e')),
        data: (bundle) => ListView(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 32),
          children: [
            const MascotCard(),
            const SizedBox(height: 12),
            _PredictionCard(p: bundle.monthEstimate, hero: true),
            if (bundle.budgetProjections.isNotEmpty) ...[
              const SizedBox(height: 16),
              _SectionTitle('Budget projections'),
              for (final bp in bundle.budgetProjections)
                _BudgetProjectionCard(bp: bp),
            ],
            const SizedBox(height: 16),
            _SectionTitle('Recommendations'),
            ...bundle.recommendations.map(_RecCard.new),
            if (bundle.recommendations.isEmpty)
              const Card(child: Padding(padding: EdgeInsets.all(14),
                  child: Text('Nothing to flag yet — keep using the app, '
                      'I\'ll have tips once you have a few weeks of data.'))),
            const SizedBox(height: 16),
            _SectionTitle('Next month: per-category forecast'),
            ...bundle.categoryForecasts.take(6).map(
              (p) => _PredictionCard(p: p),
            ),
            const SizedBox(height: 16),
            _SectionTitle('Recurring payments detected'),
            if (bundle.recurring.isEmpty)
              const Card(child: Padding(padding: EdgeInsets.all(14),
                  child: Text('No recurring patterns detected yet.'))),
            for (final r in bundle.recurring) _RecurringCard(r: r),
            const SizedBox(height: 16),
            _SectionTitle('Recent anomalies'),
            if (bundle.anomalies.isEmpty)
              const Card(child: Padding(padding: EdgeInsets.all(14),
                  child: Text('Nothing anomalous in recent activity.'))),
            for (final a in bundle.anomalies) _AnomalyCard(a: a),
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
        padding: const EdgeInsets.only(top: 10, bottom: 6, left: 4),
        child: Text(label,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                )),
      );
}

class _PredictionCard extends StatelessWidget {
  final Prediction p;
  final bool hero;
  const _PredictionCard({required this.p, this.hero = false});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: hero ? AerisColors.info.withValues(alpha: 0.10) : null,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(p.categoryId == null
                  ? Icons.trending_up
                  : Categories.byId(p.categoryId!).icon,
                color: p.categoryId == null
                    ? AerisColors.info
                    : Categories.byId(p.categoryId!).color),
              const SizedBox(width: 8),
              Expanded(child: Text(p.label,
                  style: const TextStyle(fontWeight: FontWeight.w700))),
              Text(formatRupees(p.estimate),
                  style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: hero ? 20 : 16)),
            ]),
            const SizedBox(height: 4),
            Text('Range: ${formatRupees(p.low, compact: true)} – '
                '${formatRupees(p.high, compact: true)}',
                style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 2),
            Text(p.basis, style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}

class _BudgetProjectionCard extends StatelessWidget {
  final BudgetProjection bp;
  const _BudgetProjectionCard({required this.bp});

  @override
  Widget build(BuildContext context) {
    final cat = Categories.byId(bp.categoryId);
    final (Color color, IconData icon, String status) = bp.alreadyOver
        ? (AerisColors.debit, Icons.error_outline,
            'Over budget by ${formatRupees(bp.spentSoFar - bp.cap, compact: true)}')
        : bp.willExceed
            ? (AerisColors.warning, Icons.trending_up,
                bp.daysUntilExceed != null
                    ? 'On pace to exceed in ~${bp.daysUntilExceed} day${bp.daysUntilExceed == 1 ? '' : 's'} '
                        '(≈${formatRupees(bp.projectedMonthEnd, compact: true)} by month-end)'
                    : 'Projected ≈${formatRupees(bp.projectedMonthEnd, compact: true)} by month-end')
            : (AerisColors.credit, Icons.check_circle_outline,
                'On track — projected ≈${formatRupees(bp.projectedMonthEnd, compact: true)} of ${formatRupees(bp.cap, compact: true)}');
    final pct = bp.cap <= 0 ? 0.0 : (bp.spentSoFar / bp.cap).clamp(0.0, 1.0);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(cat.icon, color: cat.color, size: 20),
              const SizedBox(width: 8),
              Expanded(
                  child: Text(cat.label,
                      style: const TextStyle(fontWeight: FontWeight.w700))),
              Text(
                  '${formatRupees(bp.spentSoFar, compact: true)} / ${formatRupees(bp.cap, compact: true)}',
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w700)),
            ]),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: pct,
                minHeight: 8,
                color: color,
                backgroundColor: color.withValues(alpha: 0.12),
              ),
            ),
            const SizedBox(height: 8),
            Row(children: [
              Icon(icon, size: 15, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(status,
                    style: TextStyle(
                        fontSize: 12, color: color, fontWeight: FontWeight.w600)),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}

class _RecCard extends StatelessWidget {
  final Recommendation r;
  const _RecCard(this.r);

  @override
  Widget build(BuildContext context) {
    final color = switch (r.severity) {
      InsightSeverity.alert => AerisColors.debit,
      InsightSeverity.warning => AerisColors.warning,
      InsightSeverity.positive => AerisColors.credit,
      InsightSeverity.info => AerisColors.info,
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Container(width: 4, height: 18, color: color),
              const SizedBox(width: 8),
              Expanded(child: Text(r.title,
                  style: const TextStyle(fontWeight: FontWeight.w700))),
              if (r.potentialSaving != null && r.potentialSaving! > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AerisColors.credit.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'Save ${formatRupees(r.potentialSaving!, compact: true)}',
                    style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: AerisColors.credit),
                  ),
                ),
            ]),
            const SizedBox(height: 6),
            Text(r.body, style: const TextStyle(fontSize: 12, height: 1.4)),
          ],
        ),
      ),
    );
  }
}

class _RecurringCard extends StatelessWidget {
  final RecurringPayment r;
  const _RecurringCard({required this.r});

  @override
  Widget build(BuildContext context) {
    final cat = Categories.byId(r.categoryId);
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: cat.color.withValues(alpha: 0.18),
          child: Icon(cat.icon, color: cat.color),
        ),
        title: Text(r.merchant,
            style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text('~₹${r.approxAmount.toStringAsFixed(0)} on the '
            '${r.dayOfMonth}${_ordinal(r.dayOfMonth)} of the month '
            '(${r.occurrences} months)'),
        trailing: Text(formatRupees(r.approxAmount, compact: true),
            style: const TextStyle(fontWeight: FontWeight.w700)),
      ),
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

class _AnomalyCard extends StatelessWidget {
  final Anomaly a;
  const _AnomalyCard({required this.a});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: AerisColors.warning.withValues(alpha: 0.06),
      child: ListTile(
        leading: const Icon(Icons.warning_amber_rounded, color: AerisColors.warning),
        title: Text(a.merchant ?? 'Unknown',
            style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(a.reason),
        trailing: Text(formatRupees(a.amount, compact: true),
            style: const TextStyle(fontWeight: FontWeight.w700)),
      ),
    );
  }
}
