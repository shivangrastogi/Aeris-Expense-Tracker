import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/routes.dart';
import '../../core/theme.dart';
import '../../models/budget.dart';
import '../../models/category.dart';
import '../../providers/analytics_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/budgets_provider.dart';
import '../../providers/transactions_provider.dart';
import '../../services/prediction_service.dart';
import '../../utils/formatters.dart';
import '../../widgets/skeleton.dart';

class BudgetsScreen extends ConsumerWidget {
  const BudgetsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final budgets = ref.watch(budgetsStreamProvider);
    final analytics = ref.watch(analyticsProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Budgets'),
        actions: [
          IconButton(
            tooltip: 'Suggest budgets from my spending',
            icon: const Icon(Icons.auto_awesome),
            onPressed: () => _autoSuggest(context, ref),
          ),
        ],
      ),
      body: budgets.when(
        loading: () => const BudgetListSkeleton(),
        error: (e, _) => Center(child: Text('$e')),
        data: (list) {
          final snap = analytics.asData?.value;
          final byCat = snap?.byCategory ?? const {};
          final monthSpent = snap?.monthExpense ?? 0;
          final total =
              list.where((b) => b.categoryId == Budget.totalId).firstOrNull;
          final allCats = Categories.all.where((c) => c.id != 'salary' && c.id != 'transfer').toList();
          return ListView(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 80),
            children: [
              _totalCard(context, ref, total, monthSpent),
              const Padding(
                padding: EdgeInsets.fromLTRB(4, 14, 4, 2),
                child: Text('Per-category caps',
                    style: TextStyle(fontWeight: FontWeight.w700)),
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
                      backgroundColor: c.color.withValues(alpha: 0.18),
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
                              backgroundColor: c.color.withValues(alpha: 0.15),
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

  // ── Total monthly budget (one overall cap, not per-category) ──
  Widget _totalCard(
      BuildContext context, WidgetRef ref, Budget? total, double spent) {
    final cap = total?.monthlyCap ?? 0;
    final pct = cap > 0 ? (spent / cap).clamp(0.0, 1.0) : 0.0;
    final over = cap > 0 && spent > cap;
    final left = cap - spent;
    return Card(
      color: AerisColors.seed.withValues(alpha: 0.08),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.account_balance_wallet, color: AerisColors.seed),
              const SizedBox(width: 10),
              const Expanded(
                child: Text('Total monthly budget',
                    style:
                        TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              ),
              if (cap > 0)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Remove',
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () {
                    final uid = ref.read(currentUserIdProvider);
                    if (uid != null) {
                      ref
                          .read(firestoreServiceProvider)
                          .deleteBudget(uid, Budget.totalId);
                    }
                  },
                ),
              TextButton(
                onPressed: () => _editTotal(context, ref, cap),
                child: Text(cap > 0 ? 'Edit' : 'Set'),
              ),
            ]),
            if (cap > 0) ...[
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: pct,
                  minHeight: 10,
                  color: over ? AerisColors.debit : AerisColors.seed,
                  backgroundColor: AerisColors.seed.withValues(alpha: 0.15),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                over
                    ? '${formatRupees(spent)} of ${formatRupees(cap)} · over by ${formatRupees(spent - cap)}'
                    : '${formatRupees(spent)} of ${formatRupees(cap)} · ${formatRupees(left < 0 ? 0 : left)} left',
                style: TextStyle(
                    fontSize: 13,
                    color: over ? AerisColors.debit : null,
                    fontWeight: FontWeight.w600),
              ),
            ] else
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text(
                  'Set one overall cap for the whole month — independent of '
                  'categories. Your dashboard ring tracks against it.',
                  style: TextStyle(fontSize: 12),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _editTotal(
      BuildContext context, WidgetRef ref, double current) async {
    final ctrl = TextEditingController(
        text: current > 0 ? current.toStringAsFixed(0) : '');
    final v = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Total monthly budget'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
              prefixText: '₹ ', labelText: 'Amount per month'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(d), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(d, ctrl.text),
              child: const Text('Save')),
        ],
      ),
    );
    if (v == null) return;
    final amt = double.tryParse(v.replaceAll(',', ''));
    final uid = ref.read(currentUserIdProvider);
    if (uid == null || amt == null || amt <= 0) return;
    await ref.read(firestoreServiceProvider).setBudget(
          uid,
          Budget(
              id: Budget.totalId,
              categoryId: Budget.totalId,
              monthlyCap: amt,
              updatedAt: DateTime.now()),
        );
  }

  // Round a raw forecast up to a tidy cap (₹100/₹500/₹1000 steps).
  double _roundCap(double v) {
    if (v <= 0) return 0;
    final step = v < 2000 ? 100 : (v < 10000 ? 500 : 1000);
    return (v / step).ceil() * step.toDouble();
  }

  /// Propose monthly caps from spending history (EMA per category) for any
  /// category that doesn't already have a budget, and let the user pick which
  /// to apply.
  Future<void> _autoSuggest(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final txns = ref.read(transactionsStreamProvider).valueOrNull ?? const [];
    final existing = (ref.read(budgetsStreamProvider).valueOrNull ?? const [])
        .map((b) => b.categoryId)
        .toSet();
    const skip = {'salary', 'transfer', 'cash', 'investment', 'other'};
    final preds = PredictionService.instance.predictPerCategoryNextMonth(txns);

    final suggestions = <({String cat, double cap})>[];
    for (final p in preds) {
      final cat = p.categoryId;
      if (cat == null || skip.contains(cat) || existing.contains(cat)) continue;
      final cap = _roundCap(p.estimate);
      if (cap > 0) suggestions.add((cat: cat, cap: cap));
    }
    if (suggestions.isEmpty) {
      messenger.showSnackBar(const SnackBar(
          content: Text(
              'Not enough spending history yet to suggest budgets — check back after a couple of months.')));
      return;
    }

    final selected = {for (final s in suggestions) s.cat};
    final apply = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setLocal) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 4, 20, 0),
                child: Text('Suggested budgets',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 2, 20, 8),
                child: Text(
                    'Based on your recent spending. Adjust later anytime.',
                    style: TextStyle(fontSize: 12)),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final s in suggestions)
                      CheckboxListTile(
                        value: selected.contains(s.cat),
                        onChanged: (v) => setLocal(() => v == true
                            ? selected.add(s.cat)
                            : selected.remove(s.cat)),
                        secondary: CircleAvatar(
                          backgroundColor:
                              Categories.byId(s.cat).color.withValues(alpha: 0.18),
                          child: Icon(Categories.byId(s.cat).icon,
                              color: Categories.byId(s.cat).color, size: 20),
                        ),
                        title: Text(Categories.byId(s.cat).label),
                        subtitle: Text('Cap ${formatRupees(s.cap)} / month'),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: selected.isEmpty
                        ? null
                        : () => Navigator.pop(ctx, true),
                    child: Text('Apply ${selected.length} budget'
                        '${selected.length == 1 ? '' : 's'}'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (apply != true) return;
    final uid = ref.read(currentUserIdProvider);
    if (uid == null) return;
    final fs = ref.read(firestoreServiceProvider);
    final now = DateTime.now();
    var n = 0;
    for (final s in suggestions.where((s) => selected.contains(s.cat))) {
      await fs.setBudget(
          uid,
          Budget(
              id: s.cat,
              categoryId: s.cat,
              monthlyCap: s.cap,
              updatedAt: now));
      n++;
    }
    messenger.showSnackBar(SnackBar(
        content: Text('Set $n budget${n == 1 ? '' : 's'} from your spending 🎯')));
  }
}

extension on Iterable<Budget> {
  Budget? get firstOrNull => isEmpty ? null : first;
}
