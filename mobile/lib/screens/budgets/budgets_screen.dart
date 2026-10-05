import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/routes.dart';
import '../../core/theme.dart';
import '../../models/budget.dart';
import '../../models/category.dart';
import '../../models/goal.dart';
import '../../providers/analytics_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/budgets_provider.dart';
import '../../providers/goals_provider.dart';
import '../../providers/money_providers.dart';
import '../../providers/privacy_provider.dart';
import '../../providers/transactions_provider.dart';
import '../../services/money_insights.dart';
import '../../services/prediction_service.dart';
import '../../utils/formatters.dart';
import '../../widgets/skeleton.dart';
import '../../utils/amount_input_formatter.dart';
import '../../widgets/aeris_toast.dart';

class BudgetsScreen extends ConsumerWidget {
  const BudgetsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(amountHiddenProvider);
    final budgets = ref.watch(budgetsStreamProvider);
    final analytics = ref.watch(analyticsProvider);
    // Caps as they apply this month (stored cap + any rolled-over leftover).
    final effective = {
      for (final b in ref.watch(effectiveBudgetsProvider))
        b.categoryId: b.monthlyCap
    };
    final rolled = ref.watch(rolledOverProvider);
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
          final allCats = Categories.all
              .where((c) =>
                  c.id != 'salary' && c.id != 'transfer' && c.id != 'refund')
              .toList();
          return ListView(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 80),
            children: [
              _totalCard(context, ref, total, monthSpent,
                  effectiveCap: effective[Budget.totalId],
                  rolledIn: rolled[Budget.totalId] ?? 0),
              const SizedBox(height: 8),
              const _RolloverCard(),
              const Padding(
                padding: EdgeInsets.fromLTRB(4, 14, 4, 2),
                child: Text('Per-category caps',
                    style: TextStyle(fontWeight: FontWeight.w700)),
              ),
              ...allCats.map((c) {
                final b = list.where((x) => x.categoryId == c.id).firstOrNull;
                final spent = byCat[c.id] ?? 0;
                final cap = b == null ? 0.0 : (effective[c.id] ?? b.monthlyCap);
                final extra = rolled[c.id] ?? 0;
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
                                '${extra > 0 ? ' · +${formatRupees(extra, compact: true)} rolled over' : ''}'
                            : 'No cap set — currently ${formatRupees(spent)}'),
                        const SizedBox(height: 6),
                        if (cap > 0)
                          ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: LinearProgressIndicator(
                              value: pct > 1.0 ? 1.0 : pct,
                              minHeight: 6,
                              color: overflow ? AerisColors.danger(context) : c.color,
                              backgroundColor: c.color.withValues(alpha: 0.15),
                            ),
                          ),
                      ],
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.pushNamed(
                        context, AppRoutes.budgetEdit,
                        arguments: c.id),
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
      BuildContext context, WidgetRef ref, Budget? total, double spent,
      {double? effectiveCap, double rolledIn = 0}) {
    final storedCap = total?.monthlyCap ?? 0;
    final cap = total == null ? 0.0 : (effectiveCap ?? storedCap);
    final pct = cap > 0 ? (spent / cap).clamp(0.0, 1.0) : 0.0;
    final over = cap > 0 && spent > cap;
    final left = cap - spent;
    return Card(
      color: AerisColors.accent(context).withValues(alpha: 0.08),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.account_balance_wallet, color: AerisColors.accent(context)),
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
                // Edit the stored cap, never the rolled-over figure.
                onPressed: () => _editTotal(context, ref, storedCap),
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
                  color: over ? AerisColors.danger(context) : AerisColors.accent(context),
                  backgroundColor: AerisColors.accent(context).withValues(alpha: 0.15),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                over
                    ? '${formatRupees(spent)} of ${formatRupees(cap)} · over by ${formatRupees(spent - cap)}'
                    : '${formatRupees(spent)} of ${formatRupees(cap)} · ${formatRupees(left < 0 ? 0 : left)} left',
                style: TextStyle(
                    fontSize: 13,
                    color: over ? AerisColors.danger(context) : null,
                    fontWeight: FontWeight.w600),
              ),
              if (rolledIn > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'Includes ${formatRupees(rolledIn)} rolled over from last month',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AerisColors.moneyIn(context)),
                  ),
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
    final messenger = ScaffoldMessenger.of(context);
    final ctrl = TextEditingController(
        text: current > 0 ? inrToDisplayText(current) : '');
    final v = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Total monthly budget'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
              prefixText: '${kCurrency.symbol.trim()} ',
              labelText: 'Amount per month'),
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
    final amt = displayToInr(v); // typed in display currency
    final uid = ref.read(currentUserIdProvider);
    if (uid == null || amt == null || amt <= 0) return;
    try {
      await ref.read(firestoreServiceProvider).setBudget(
            uid,
            Budget(
                id: Budget.totalId,
                categoryId: Budget.totalId,
                monthlyCap: amt,
                updatedAt: DateTime.now()),
          );
    } catch (e) {
      messenger
          .showToast(SnackBar(content: Text('Could not save budget: $e')));
    }
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
    const skip = {
      'salary', 'transfer', 'refund', 'cash', 'investment', 'other'
    };
    final preds = PredictionService.instance.predictPerCategoryNextMonth(txns);

    final suggestions = <({String cat, double cap})>[];
    for (final p in preds) {
      final cat = p.categoryId;
      if (cat == null || skip.contains(cat) || existing.contains(cat)) continue;
      final cap = _roundCap(p.estimate);
      if (cap > 0) suggestions.add((cat: cat, cap: cap));
    }
    if (suggestions.isEmpty) {
      messenger.showToast(const SnackBar(
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
                          backgroundColor: Categories.byId(s.cat)
                              .color
                              .withValues(alpha: 0.18),
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
              id: s.cat, categoryId: s.cat, monthlyCap: s.cap, updatedAt: now));
      n++;
    }
    messenger.showToast(SnackBar(
        content:
            Text('Set $n budget${n == 1 ? '' : 's'} from your spending 🎯')));
  }
}

extension on Iterable<Budget> {
  Budget? get firstOrNull => isEmpty ? null : first;
}

/// Budget rollover: carry last month's unspent budget into this month, or
/// move it into a savings goal (once per month).
class _RolloverCard extends ConsumerStatefulWidget {
  const _RolloverCard();

  @override
  ConsumerState<_RolloverCard> createState() => _RolloverCardState();
}

class _RolloverCardState extends ConsumerState<_RolloverCard> {
  String? _sweptMonth;

  String get _monthKey {
    final now = DateTime.now();
    return '${now.year}-${now.month}';
  }

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      if (mounted) setState(() => _sweptMonth = p.getString('leftover_swept'));
    });
  }

  double _leftover() {
    final budgets = ref.read(budgetsStreamProvider).valueOrNull ?? const [];
    final txns = ref.read(transactionsStreamProvider).valueOrNull ?? const [];
    final left = BudgetRollover.leftovers(budgets, txns, DateTime.now());
    // The overall budget if there is one, else the per-category leftovers.
    return left[Budget.totalId] ??
        left.entries
            .where((e) => e.key != Budget.totalId)
            .fold<double>(0, (s, e) => s + e.value);
  }

  Future<void> _sweep(double amount) async {
    final messenger = ScaffoldMessenger.of(context);
    final goals = (ref.read(goalsStreamProvider).valueOrNull ?? const [])
        .where((g) => !g.isComplete)
        .toList();
    if (goals.isEmpty) {
      messenger.showToast(const SnackBar(
          content: Text('Create a savings goal first (Me → Goals).')));
      return;
    }
    final goal = await showModalBottomSheet<Goal>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Move ${formatRupees(amount)} into…',
              style:
                  const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          for (final g in goals)
            ListTile(
              leading: Text(g.emoji, style: const TextStyle(fontSize: 22)),
              title: Text(g.title),
              subtitle: Text(
                  '${formatRupees(g.saved)} of ${formatRupees(g.target)}'),
              onTap: () => Navigator.pop(ctx, g),
            ),
          const SizedBox(height: 8),
        ]),
      ),
    );
    if (goal == null) return;
    final uid = ref.read(currentUserIdProvider);
    if (uid == null) return;
    await ref
        .read(firestoreServiceProvider)
        .setGoal(uid, goal.copyWith(saved: goal.saved + amount));
    (await SharedPreferences.getInstance()).setString('leftover_swept', _monthKey);
    if (mounted) setState(() => _sweptMonth = _monthKey);
    messenger.showToast(SnackBar(
        content: Text('${formatRupees(amount)} moved to ${goal.title}')));
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(transactionsStreamProvider);
    ref.watch(budgetsStreamProvider);
    final on = ref.watch(rolloverProvider);
    final left = _leftover();
    final swept = _sweptMonth == _monthKey;
    return AerisCard(
      padding: const EdgeInsets.fromLTRB(16, 6, 8, 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: on,
          onChanged: (v) => ref.read(rolloverProvider.notifier).set(v),
          title: const Text('Roll unused budget into next month',
              style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700)),
          subtitle: Text(left > 0
              ? 'Last month you had ${formatRupees(left)} left over'
              : 'Unspent budget carries over (up to one month\'s cap)'),
        ),
        if (!on && left > 0 && !swept)
          TextButton.icon(
            onPressed: () => _sweep(left),
            icon: const Icon(Icons.savings_outlined, size: 18),
            label: Text('Or move ${formatRupees(left)} into a goal'),
          ),
        if (swept)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text('Last month\'s leftover is already in a goal ✓',
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: AerisColors.moneyIn(context))),
          ),
      ]),
    );
  }
}
