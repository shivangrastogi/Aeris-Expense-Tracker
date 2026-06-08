import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/routes.dart';
import '../../core/theme.dart';
import '../../models/category.dart';
import '../../providers/analytics_provider.dart';
import '../../providers/budgets_provider.dart';
import '../../utils/formatters.dart';

/// Each budgeted category is a "boss". Your budget is the shield; spending
/// chips it away. Keep spend under the cap all month → you defeat the boss.
class BossesScreen extends ConsumerWidget {
  const BossesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final analytics = ref.watch(analyticsProvider).valueOrNull;
    final budgets = (ref.watch(budgetsStreamProvider).valueOrNull ?? const [])
        .where((b) => b.monthlyCap > 0 && b.categoryId != '__total__')
        .toList();
    final byCat = analytics?.byCategory ?? const {};

    return Scaffold(
      appBar: AppBar(title: const Text('Boss battles')),
      body: budgets.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('⚔️', style: TextStyle(fontSize: 48)),
                    const SizedBox(height: 12),
                    const Text('No bosses spawned yet',
                        style: TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 18)),
                    const SizedBox(height: 6),
                    const Text(
                        'Set a budget on a category and it becomes a boss you '
                        'fight all month by staying under the cap.',
                        textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: () =>
                          Navigator.pushNamed(context, AppRoutes.budgetEdit),
                      child: const Text('Set a budget'),
                    ),
                  ],
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 24),
              children: [
                for (final b in budgets)
                  _BossCard(
                    categoryId: b.categoryId,
                    cap: b.monthlyCap,
                    spent: (byCat[b.categoryId] ?? 0).toDouble(),
                  ),
              ],
            ),
    );
  }
}

class _BossCard extends StatelessWidget {
  final String categoryId;
  final double cap, spent;
  const _BossCard(
      {required this.categoryId, required this.cap, required this.spent});

  @override
  Widget build(BuildContext context) {
    final cat = Categories.byId(categoryId);
    final remaining = cap - spent;
    final shield = (remaining / cap).clamp(0.0, 1.0);
    final broken = spent >= cap;
    final color = broken
        ? AerisColors.debit
        : shield < 0.25
            ? AerisColors.warning
            : AerisColors.credit;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              CircleAvatar(
                backgroundColor: cat.color.withValues(alpha: 0.18),
                child: Icon(cat.icon, color: cat.color),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${cat.label} Beast',
                        style: const TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 16)),
                    Text(broken ? 'Broke through your shield 💥' : 'Shield holding 🛡️',
                        style: TextStyle(fontSize: 12, color: color)),
                  ],
                ),
              ),
              Text(broken ? 'LOST' : '${(shield * 100).round()}%',
                  style: TextStyle(
                      fontWeight: FontWeight.w900, color: color, fontSize: 16)),
            ]),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: shield,
                minHeight: 12,
                color: color,
                backgroundColor: AerisColors.debit.withValues(alpha: 0.18),
              ),
            ),
            const SizedBox(height: 6),
            Text(
                '${formatRupees(spent)} spent · ${formatRupees(remaining.clamp(0, cap))} shield left of ${formatRupees(cap)}',
                style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}
