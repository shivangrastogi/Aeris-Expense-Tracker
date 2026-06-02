import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/routes.dart';
import '../../core/theme.dart';
import '../../models/budget.dart';
import '../../models/category.dart';
import '../../providers/analytics_provider.dart';
import '../../providers/budgets_provider.dart';
import '../../utils/formatters.dart';

class BudgetsScreen extends ConsumerWidget {
  const BudgetsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final budgets = ref.watch(budgetsStreamProvider);
    final analytics = ref.watch(analyticsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Budgets')),
      body: budgets.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (list) {
          final byCat = analytics.asData?.value.byCategory ?? const {};
          final allCats = Categories.all.where((c) => c.id != 'salary' && c.id != 'transfer').toList();
          return ListView(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 80),
            children: [
              if (list.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(18),
                    child: Text('No budgets yet. Tap any category below to set '
                        'a monthly cap. AERIS will warn you on the dashboard '
                        'when you\'re on track to exceed it.'),
                  ),
                ),
              ...allCats.map((c) {
                final b = list.where((x) => x.categoryId == c.id).firstOrNull;
                final spent = byCat[c.id] ?? 0;
                final cap = b?.monthlyCap ?? 0;
                final pct = (cap > 0 ? spent / cap : 0.0).clamp(0.0, 1.5);
                final overflow = pct > 1.0;
                return Card(
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: c.color.withOpacity(0.18),
                      child: Icon(c.icon, color: c.color),
                    ),
                    title: Text(c.label),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(cap > 0
                            ? '${formatRupees(spent)} of ${formatRupees(cap)}'
                            : 'No cap set — currently ${formatRupees(spent)}'),
                        const SizedBox(height: 6),
                        if (cap > 0)
                          ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: LinearProgressIndicator(
                              value: pct > 1.0 ? 1.0 : pct,
                              minHeight: 6,
                              color: overflow ? AerisColors.debit : c.color,
                              backgroundColor: c.color.withOpacity(0.15),
                            ),
                          ),
                      ],
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.pushNamed(
                        context, AppRoutes.budgetEdit, arguments: c.id),
                  ),
                );
              }),
            ],
          );
        },
      ),
    );
  }
}

extension on Iterable<Budget> {
  Budget? get firstOrNull => isEmpty ? null : first;
}
