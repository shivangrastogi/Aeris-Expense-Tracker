import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../models/category.dart';
import '../../models/transaction.dart';
import '../../providers/auth_provider.dart';
import '../../providers/transactions_provider.dart';
import '../../services/category_rules.dart';
import '../../services/entry_checks.dart';
import '../../services/nlu_parser.dart';
import '../../utils/amount_input_formatter.dart';
import '../../utils/formatters.dart';
import '../../widgets/discard_guard.dart';
import '../../widgets/aeris_toast.dart';

/// Type (or dictate via the keyboard mic) one sentence — "spent 200 on chai
/// yesterday", "got 5000 salary" — and AERIS extracts the amount,
/// income/expense, merchant, category and date on-device. The user confirms the
/// parsed preview before saving.
class QuickAddScreen extends ConsumerStatefulWidget {
  const QuickAddScreen({super.key});
  @override
  ConsumerState<QuickAddScreen> createState() => _QuickAddScreenState();
}

class _QuickAddScreenState extends ConsumerState<QuickAddScreen> {
  final _sentence = TextEditingController();
  final _amount = TextEditingController();
  final _merchant = TextEditingController();
  TxnDirection _dir = TxnDirection.debit;
  String _categoryId = 'other';
  DateTime _when = DateTime.now();
  bool _parsed = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // Rebuild so the discard guard tracks what has been typed.
    _sentence.addListener(_onFieldChanged);
    _amount.addListener(_onFieldChanged);
    _merchant.addListener(_onFieldChanged);
  }

  void _onFieldChanged() {
    if (mounted) setState(() {});
  }

  bool get _dirty =>
      _sentence.text.trim().isNotEmpty ||
      _amount.text.trim().isNotEmpty ||
      _merchant.text.trim().isNotEmpty;

  @override
  void dispose() {
    _sentence.dispose();
    _amount.dispose();
    _merchant.dispose();
    super.dispose();
  }

  void _understand() {
    if (_sentence.text.trim().isEmpty) return;
    _apply(NluParser.parse(_sentence.text));
  }

  void _apply(NluResult r) {
    setState(() {
      if (r.amount != null) {
        _amount.text = r.amount! % 1 == 0
            ? r.amount!.toStringAsFixed(0)
            : r.amount!.toStringAsFixed(2);
      }
      _dir = r.direction;
      _categoryId = r.categoryId;
      _when = r.when;
      if (r.merchant != null && r.merchant!.isNotEmpty) {
        _merchant.text = r.merchant!;
      }
      _parsed = true;
    });
    _refineCategory(r.merchant);
  }

  Future<void> _refineCategory(String? merchant) async {
    if (merchant == null || merchant.trim().isEmpty) return;
    final learned = await CategoryRules.instance.categoryFor(merchant);
    if (learned != null && mounted) setState(() => _categoryId = learned);
  }

  Future<void> _save() async {
    final uid = ref.read(currentUserIdProvider);
    if (uid == null) return;
    final typed = double.tryParse(_amount.text.replaceAll(',', ''));
    if (typed == null || typed <= 0) {
      ScaffoldMessenger.of(context)
          .showToast(const SnackBar(content: Text('Enter a valid amount')));
      return;
    }
    // Typed in the display currency; stored in INR.
    final amt = (typed * kCurrency.rate * 100).roundToDouble() / 100;
    final merchant = _merchant.text.trim();
    final dup = EntryChecks.likelyDuplicate(
      ref.read(transactionsStreamProvider).asData?.value ?? const [],
      amount: amt,
      direction: _dir,
      when: _when,
      merchant: merchant,
    );
    if (dup != null) {
      final go = await showDialog<bool>(
        context: context,
        builder: (d) => AlertDialog(
          icon: const Icon(Icons.copy_all_outlined),
          title: const Text('Possible duplicate'),
          content: Text('You already have '
              '${formatRupees(dup.amount, decimals: true, raw: true)}'
              '${dup.merchant == null ? '' : ' at ${dup.merchant}'} '
              '${relativeDate(dup.timestamp).toLowerCase()}'
              '${dup.source == TxnSource.sms ? ' (auto-imported from SMS)' : ''}.'
              '\n\nSave this one as well?'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(d, false),
                child: const Text('Go back')),
            FilledButton(
                onPressed: () => Navigator.pop(d, true),
                child: const Text('Save anyway')),
          ],
        ),
      );
      if (go != true || !mounted) return;
    }
    setState(() => _busy = true);
    final t = Transaction(
      id: const Uuid().v4(),
      amount: amt,
      direction: _dir,
      timestamp: _when,
      merchant: merchant.isEmpty ? null : merchant,
      categoryId: _categoryId,
      source: TxnSource.manual,
    );
    // Returns once queued locally (offline-safe via the sync outbox).
    try {
      await ref.read(firestoreServiceProvider).addTransaction(uid, t);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context)
          .showToast(SnackBar(content: Text('Could not save: $e')));
      return;
    }
    if (merchant.isNotEmpty) {
      await CategoryRules.instance.remember(merchant, _categoryId);
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DiscardGuard(
      dirty: _dirty && !_busy,
      child: Scaffold(
        appBar: AppBar(title: const Text('Quick add')),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // ── The sentence (typed, or dictated via the keyboard mic) ──
              TextField(
                controller: _sentence,
                minLines: 1,
                maxLines: 3,
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _understand(),
                decoration: const InputDecoration(
                  labelText: 'Say or type what happened',
                  hintText: 'e.g. spent 200 on chai yesterday',
                  prefixIcon: Icon(Icons.bolt),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Tip: tap the 🎤 on your keyboard to speak it.',
                      style: TextStyle(
                          fontSize: 12, color: scheme.onSurfaceVariant),
                    ),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: _understand,
                    icon: const Icon(Icons.auto_awesome, size: 18),
                    label: const Text('Understand'),
                  ),
                ],
              ),
              const Divider(height: 28),

              // ── Parsed preview (editable) ───────────────────────
              if (!_parsed)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Column(
                    children: [
                      Icon(Icons.graphic_eq,
                          size: 40, color: scheme.onSurfaceVariant),
                      const SizedBox(height: 10),
                      Text(
                        'Try: "paid 1200 to amazon for shopping"\n'
                        '"got 5000 salary"  ·  "petrol 2000 yesterday"',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 12, color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                )
              else ...[
                Text('Here\'s what I understood — tweak if needed',
                    style: TextStyle(
                        fontSize: 12, color: scheme.onSurfaceVariant)),
                const SizedBox(height: 12),
                SegmentedButton<TxnDirection>(
                  segments: const [
                    ButtonSegment(
                        value: TxnDirection.debit,
                        label: Text('Expense'),
                        icon: Icon(Icons.south)),
                    ButtonSegment(
                        value: TxnDirection.credit,
                        label: Text('Income'),
                        icon: Icon(Icons.north)),
                  ],
                  selected: {_dir},
                  onSelectionChanged: (s) => setState(() => _dir = s.first),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _amount,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: const [AmountInputFormatter()],
                  decoration: InputDecoration(
                      labelText: 'Amount (${kCurrency.symbol.trim()})',
                      prefixIcon: const Icon(Icons.payments_outlined)),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _merchant,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(
                      labelText: _dir == TxnDirection.credit
                          ? 'Source / payer'
                          : 'Merchant / payee',
                      prefixIcon: const Icon(Icons.store)),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _categoryId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Category'),
                  items: [
                    for (final c in Categories.all)
                      DropdownMenuItem(
                          value: c.id,
                          child: Row(children: [
                            Icon(c.icon, color: c.color, size: 18),
                            const SizedBox(width: 10),
                            Text(c.label),
                          ])),
                  ],
                  onChanged: (v) => setState(() => _categoryId = v ?? 'other'),
                ),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                  leading: const Icon(Icons.calendar_today),
                  title: const Text('When',
                      style: TextStyle(fontSize: 12, color: Colors.grey)),
                  subtitle: Text('${_when.day}/${_when.month}/${_when.year}',
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600)),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _when,
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now(),
                    );
                    if (picked != null) {
                      setState(() => _when = DateTime(picked.year, picked.month,
                          picked.day, _when.hour, _when.minute));
                    }
                  },
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  icon: const Icon(Icons.save),
                  label: const Text('Save transaction'),
                  onPressed: _busy ? null : _save,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
