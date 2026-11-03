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
import '../../widgets/ds.dart';

class BudgetsScreen extends ConsumerWidget {
  const BudgetsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(amountHiddenProvider);
    final tk = context.tk;
    final budgets = ref.watch(budgetsStreamProvider);
    // Calendar month — caps are monthly, whatever range Insights shows.
    final snap = ref.watch(monthAnalyticsProvider);
    // Caps as they apply this month (stored cap + any rolled-over leftover).
    final effective = {
      for (final b in ref.watch(effectiveBudgetsProvider))
        b.categoryId: b.monthlyCap
    };
    final rolled = ref.watch(rolledOverProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Budgets')),
      body: budgets.when(
        loading: () => const BudgetListSkeleton(),
        error: (e, _) => Padding(
          padding: const EdgeInsets.all(20),
          child: Banner2(
              tone: Tone.bad,
              icon: PhFill.cloudX,
              title: "Couldn't load budgets",
              body: '$e'),
        ),
        data: (list) {
          final byCat = snap?.byCategory ?? const {};
          final monthSpent = snap?.monthExpense ?? 0;
          final total =
              list.where((b) => b.categoryId == Budget.totalId).firstOrNull;
          final allCats = Categories.all
              .where((c) =>
                  c.id != 'salary' && c.id != 'transfer' && c.id != 'refund')
              .toList();
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
            children: [
              _totalCard(context, ref, total, monthSpent,
                  effectiveCap: effective[Budget.totalId],
                  rolledIn: rolled[Budget.totalId] ?? 0),
              const SizedBox(height: 16),
              const _RolloverCard(),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerLeft,
                child: TonalButton('Suggest caps from my spending',
                    icon: Ph.sparkle,
                    height: 40,
                    onPressed: () => _autoSuggest(context, ref)),
              ),
              const SizedBox(height: 16),
              const Padding(
                padding: EdgeInsets.fromLTRB(4, 0, 4, 8),
                child: Overline('Per-category caps'),
              ),
              ListGroup(children: [
                for (final c in allCats)
                  _capRow(context, tk, c,
                      budget:
                          list.where((x) => x.categoryId == c.id).firstOrNull,
                      spent: byCat[c.id] ?? 0,
                      effectiveCap: effective[c.id],
                      extra: rolled[c.id] ?? 0),
              ]),
            ],
          );
        },
      ),
    );
  }

  /// One per-category cap: tile, name, spent / cap, the rising line and a
  /// status line (over budget → red with a word and an icon).
  Widget _capRow(BuildContext context, AerisTokens tk, ExpenseCategory c,
      {required Budget? budget,
      required double spent,
      required double? effectiveCap,
      required double extra}) {
    final cap = budget == null ? 0.0 : (effectiveCap ?? budget.monthlyCap);
    final pct = cap > 0 ? spent / cap : 0.0;
    final over = cap > 0 && spent > cap;
    final near = !over && pct >= 0.85;
    final tone = over
        ? tk.bad
        : near
            ? tk.warn
            : tk.t2;
    return InkWell(
      onTap: () =>
          Navigator.pushNamed(context, AppRoutes.budgetEdit, arguments: c.id),
      child: Container(
        constraints: const BoxConstraints(minHeight: 68),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(children: [
          CatTile.of(c),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(
                    child: Text(c.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Ts.rowTitle.copyWith(color: tk.t1)),
                  ),
                  Text(
                      cap > 0
                          ? '${formatRupees(spent, compact: true)} / ${formatRupees(cap, compact: true)}'
                          : formatRupees(spent, compact: true),
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          fontFeatures: const [FontFeature.tabularFigures()],
                          color: over ? tk.bad : tk.t1)),
                ]),
                const SizedBox(height: 6),
                if (cap > 0) ...[
                  RisingProgress(
                      value: pct,
                      color: over
                          ? tk.bad
                          : near
                              ? tk.warn
                              : c.color,
                      stroke: 4,
                      dot: 3.5),
                  const SizedBox(height: 4),
                  Row(children: [
                    if (over) ...[
                      Icon(PhFill.warningCircle, size: 13, color: tk.bad),
                      const SizedBox(width: 4),
                    ],
                    Expanded(
                      child: Text(
                          over
                              ? 'Over by ${formatRupees(spent - cap, compact: true)}'
                              : '${(pct * 100).round()}% · '
                                  '${formatRupees(cap - spent, compact: true)} left'
                                  '${extra > 0 ? ' · +${formatRupees(extra, compact: true)} rolled over' : ''}',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: over || near
                                  ? FontWeight.w700
                                  : FontWeight.w400,
                              color: tone)),
                    ),
                  ]),
                ] else
                  Text('No cap set',
                      style: TextStyle(fontSize: 12, color: tk.t2)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Icon(Ph.caretRight, size: 16, color: tk.t3),
        ]),
      ),
    );
  }

  // ── Total monthly budget (one overall cap, not per-category) ──
  // The screen's one hero-gradient card.
  Widget _totalCard(
      BuildContext context, WidgetRef ref, Budget? total, double spent,
      {double? effectiveCap, double rolledIn = 0}) {
    final tk = context.tk;
    final storedCap = total?.monthlyCap ?? 0;
    final cap = total == null ? 0.0 : (effectiveCap ?? storedCap);
    final over = cap > 0 && spent > cap;
    final left = cap - spent;
    final now = DateTime.now();
    final daysLeft = DateTime(now.year, now.month + 1, 0).day - now.day + 1;
    final onHero = tk.onHero;
    final heroText = TextStyle(
        fontSize: 13, fontWeight: FontWeight.w600, color: onHero);

    Widget pillBtn(IconData icon, String label, VoidCallback onTap) =>
        Material(
          color: onHero.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onTap,
            child: Container(
              height: 32,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(icon, size: 12, color: onHero),
                const SizedBox(width: 4),
                Text(label,
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: onHero)),
              ]),
            ),
          ),
        );

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: const Alignment(-0.85, -1),
          end: const Alignment(0.85, 1),
          colors: [tk.heroA, tk.heroB],
        ),
        boxShadow: tk.shadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(child: Overline('Total monthly budget', color: onHero)),
            if (cap > 0) ...[
              pillBtn(PhBold.x, 'Remove', () {
                final uid = ref.read(currentUserIdProvider);
                if (uid != null) {
                  ref
                      .read(firestoreServiceProvider)
                      .deleteBudget(uid, Budget.totalId);
                }
              }),
              const SizedBox(width: 6),
            ],
            // Edit the stored cap, never the rolled-over figure.
            pillBtn(cap > 0 ? PhBold.pencilSimple : PhBold.plus,
                cap > 0 ? 'Edit' : 'Set',
                () => _editTotal(context, ref, storedCap)),
          ]),
          const SizedBox(height: 10),
          if (cap > 0) ...[
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.end,
              spacing: 8,
              children: [
                MoneyText(spent, style: Ts.display, color: onHero),
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text('of ${formatRupees(cap)}',
                      style: heroText.copyWith(fontSize: 15)),
                ),
              ],
            ),
            const SizedBox(height: 10),
            RisingProgress(
              value: cap == 0 ? 0 : spent / cap,
              color: onHero,
              track: onHero.withValues(alpha: 0.22),
              stroke: 4,
              rise: 14,
              dot: 5.5,
            ),
            const SizedBox(height: 8),
            Row(children: [
              if (over) ...[
                Icon(PhFill.warningCircle, size: 15, color: onHero),
                const SizedBox(width: 4),
              ],
              Expanded(
                child: Text(
                    over
                        ? 'Over by ${formatRupees(spent - cap)}'
                        : '${formatRupees(left)} left',
                    style: heroText),
              ),
              Text('$daysLeft day${daysLeft == 1 ? '' : 's'} to go',
                  style: heroText),
            ]),
            if (rolledIn > 0)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                    'Includes ${formatRupees(rolledIn)} rolled over from last month',
                    style: heroText.copyWith(fontSize: 12)),
              ),
          ] else
            Text(
              'Set one overall cap for the whole month — independent of '
              'categories. Your Home card tracks against it.',
              style: heroText.copyWith(
                  fontSize: 15, height: 22 / 15, fontWeight: FontWeight.w500),
            ),
        ],
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
                        secondary: CatTile.of(Categories.byId(s.cat)),
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
    final tk = context.tk;
    final on = ref.watch(rolloverProvider);
    final left = _leftover();
    final swept = _sweptMonth == _monthKey;
    return ListGroup(children: [
      SettingsRow(
        icon: Ph.arrowBendDownRight,
        title: 'Roll unused budget into next month',
        sub: left > 0
            ? 'Last month you had ${formatRupees(left)} left over'
            : 'Unspent budget carries over (up to one month\'s cap)',
        trailing: Switch(
          value: on,
          onChanged: (v) => ref.read(rolloverProvider.notifier).set(v),
        ),
        onTap: () => ref.read(rolloverProvider.notifier).set(!on),
      ),
      if (!on && left > 0 && !swept)
        InkWell(
          onTap: () => _sweep(left),
          child: Container(
            constraints: const BoxConstraints(minHeight: 52),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(children: [
              SizedBox(
                  width: 36, child: Icon(Ph.target, size: 20, color: tk.acc)),
              const SizedBox(width: 12),
              Expanded(
                child: Text('Or move ${formatRupees(left)} into a goal',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: tk.acc)),
              ),
              Icon(Ph.arrowRight, size: 16, color: tk.acc),
            ]),
          ),
        ),
      if (swept)
        Container(
          constraints: const BoxConstraints(minHeight: 52),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(children: [
            SizedBox(
                width: 36,
                child: Icon(PhFill.checkCircle, size: 20, color: tk.ok)),
            const SizedBox(width: 12),
            Expanded(
              child: Text('Last month\'s leftover is already in a goal',
                  style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600, color: tk.t2)),
            ),
          ]),
        ),
    ]);
  }
}
