import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../models/budget.dart';
import '../../models/category.dart';
import '../../providers/analytics_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/budgets_provider.dart';
import '../../providers/transactions_provider.dart';
import '../../utils/amount_input_formatter.dart';
import '../../utils/formatters.dart';
import '../../widgets/aeris_toast.dart';
import '../../widgets/discard_guard.dart';
import '../../widgets/ds.dart';

class BudgetEditScreen extends ConsumerStatefulWidget {
  final String? categoryId;
  const BudgetEditScreen({super.key, this.categoryId});
  @override
  ConsumerState<BudgetEditScreen> createState() => _BudgetEditScreenState();
}

class _BudgetEditScreenState extends ConsumerState<BudgetEditScreen> {
  final _cap = TextEditingController();
  late final String _catId = widget.categoryId ?? 'other';
  String _initial = '';
  bool _seeded = false;

  @override
  void dispose() {
    _cap.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final uid = ref.read(currentUserIdProvider);
    if (uid == null) return;
    final cap = displayToInr(_cap.text); // typed in display currency
    if (cap == null || cap <= 0) {
      ScaffoldMessenger.of(context).showToast(
          const SnackBar(content: Text('Enter a positive amount')));
      return;
    }
    final b = Budget(
        id: _catId, categoryId: _catId,
        monthlyCap: cap, updatedAt: DateTime.now());
    await ref.read(firestoreServiceProvider).setBudget(uid, b);
    _initial = _cap.text;
    if (mounted) Navigator.pop(context);
  }

  Future<void> _delete() async {
    final uid = ref.read(currentUserIdProvider);
    if (uid == null) return;
    await ref.read(firestoreServiceProvider).deleteBudget(uid, _catId);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final tk = context.tk;
    final cat = Categories.byId(_catId);
    final existing = (ref.watch(budgetsStreamProvider).valueOrNull ?? const [])
        .where((b) => b.categoryId == _catId)
        .toList();
    // Start from the current cap, once it has loaded.
    if (!_seeded && existing.isNotEmpty) {
      _seeded = true;
      _initial = inrToDisplayText(existing.first.monthlyCap);
      _cap.text = _initial;
    }
    final spent = ref.watch(monthAnalyticsProvider)?.byCategory[_catId] ?? 0;
    final typed = displayToInr(_cap.text) ?? 0;
    final pct = typed > 0 ? spent / typed : 0.0;
    final over = typed > 0 && spent > typed;

    return DiscardGuard(
      dirty: _cap.text != _initial,
      title: 'Discard this change?',
      message: 'The new cap for ${cat.label} hasn\'t been saved.',
      child: Scaffold(
        appBar: AppBar(title: const Text('Edit cap'), actions: [
          if (existing.isNotEmpty)
            IconButton(
                tooltip: 'Remove cap',
                icon: Icon(Ph.trash, color: tk.bad),
                onPressed: _delete),
        ]),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            Row(children: [
              CatTile.of(cat, size: 56),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(cat.label, style: Ts.headline.copyWith(color: tk.t1)),
                    Text('Spent ${formatRupees(spent)} so far this month',
                        style: TextStyle(fontSize: 13, color: tk.t2)),
                  ],
                ),
              ),
            ]),
            const SizedBox(height: 24),
            AerisCard(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
              child: Column(children: [
                const Overline('Monthly cap'),
                const SizedBox(height: 12),
                IntrinsicWidth(
                  child: TextField(
                    controller: _cap,
                    onChanged: (_) => setState(() {}),
                    autofocus: existing.isEmpty,
                    textAlign: TextAlign.center,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    style: Ts.display.copyWith(color: tk.t1),
                    decoration: InputDecoration(
                      filled: false,
                      hintText: '0',
                      prefixText: '${kCurrency.symbol.trim()} ',
                      prefixStyle: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w600,
                          color: tk.t2),
                      contentPadding: const EdgeInsets.only(bottom: 8),
                      border: UnderlineInputBorder(
                          borderSide: BorderSide(color: tk.acc, width: 2)),
                      enabledBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: tk.acc, width: 2)),
                      focusedBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: tk.acc, width: 2)),
                    ),
                  ),
                ),
                if (typed > 0) ...[
                  const SizedBox(height: 20),
                  RisingProgress(
                      value: pct, color: over ? tk.bad : cat.color, stroke: 4),
                  const SizedBox(height: 8),
                  Row(children: [
                    if (over) ...[
                      Icon(PhFill.warningCircle, size: 14, color: tk.bad),
                      const SizedBox(width: 4),
                    ],
                    Expanded(
                      child: Text(
                          over
                              ? 'Already over this cap by ${formatRupees(spent - typed)}'
                              : '${(pct * 100).round()}% used · ${formatRupees(typed - spent)} left this month',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight:
                                  over ? FontWeight.w700 : FontWeight.w400,
                              color: over ? tk.bad : tk.t2)),
                    ),
                  ]),
                ],
              ]),
            ),
            const SizedBox(height: 24),
            FilledButton(onPressed: _save, child: const Text('Save cap')),
          ],
        ),
      ),
    );
  }
}
