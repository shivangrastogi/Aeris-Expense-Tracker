import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../models/category.dart';
import '../../models/transaction.dart';
import '../../providers/accounts_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/transactions_provider.dart';
import '../../services/category_rules.dart';

class AddTransactionScreen extends ConsumerStatefulWidget {
  /// Optionally open straight into Income or Expense mode.
  final TxnDirection? initialDirection;
  const AddTransactionScreen({super.key, this.initialDirection});
  @override
  ConsumerState<AddTransactionScreen> createState() => _AddTransactionScreenState();
}

class _AddTransactionScreenState extends ConsumerState<AddTransactionScreen> {
  final _amount = TextEditingController();
  final _note = TextEditingController();
  TextEditingController? _merchantCtrl; // owned by the Autocomplete field
  late TxnDirection _dir = widget.initialDirection ?? TxnDirection.debit;
  String _categoryId = 'other';
  bool _categoryManual = false; // user picked a category → stop auto-overriding
  String? _account; // account key, null = no account
  DateTime _when = DateTime.now();
  bool _busy = false;

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  /// Auto-pick a category from the merchant — first from what the user has
  /// taught the app (learned merchant→category rules), then from built-in
  /// keyword matching. Skips once the user has manually chosen a category.
  Future<void> _autoCategorizeFor(String merchant) async {
    if (_categoryManual) return;
    final m = merchant.trim();
    if (m.isEmpty) return;
    final learned = await CategoryRules.instance.categoryFor(m);
    final cat = learned ?? Categories.classify(m);
    if (cat != 'other' && cat != _categoryId && mounted) {
      setState(() => _categoryId = cat);
    }
  }

  @override
  Widget build(BuildContext context) {
    final income = _dir == TxnDirection.credit;
    // Real accounts (exclude the synthetic 'unassigned' bucket) for the picker.
    final accounts = ref
        .watch(accountsProvider)
        .where((a) => a.key != unassignedAccount)
        .toList();
    // Distinct past merchant names, for the autofill suggestions.
    final txns = ref.watch(transactionsStreamProvider).asData?.value ?? const [];
    final knownMerchants = (<String>{
      for (final t in txns)
        if (t.merchant != null && t.merchant!.trim().isNotEmpty)
          t.merchant!.trim(),
    }.toList()
      ..sort());
    return Scaffold(
      appBar: AppBar(title: Text(income ? 'Add income' : 'Add transaction')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            SegmentedButton<TxnDirection>(
              segments: const [
                ButtonSegment(
                    value: TxnDirection.debit,
                    label: Text('Expense'), icon: Icon(Icons.south)),
                ButtonSegment(
                    value: TxnDirection.credit,
                    label: Text('Income'), icon: Icon(Icons.north)),
              ],
              selected: {_dir},
              onSelectionChanged: (s) => setState(() {
                _dir = s.first;
                // Sensible default category when switching to income.
                if (_dir == TxnDirection.credit && _categoryId == 'other') {
                  _categoryId = 'salary';
                }
              }),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _amount,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Amount (₹)', prefixIcon: Icon(Icons.currency_rupee)),
            ),
            const SizedBox(height: 12),
            Autocomplete<String>(
              optionsBuilder: (v) {
                final q = v.text.trim().toLowerCase();
                if (q.isEmpty) return const Iterable<String>.empty();
                return knownMerchants
                    .where((m) => m.toLowerCase().contains(q))
                    .take(6);
              },
              onSelected: _autoCategorizeFor,
              fieldViewBuilder: (context, controller, focusNode, onSubmit) {
                _merchantCtrl = controller;
                return TextField(
                  controller: controller,
                  focusNode: focusNode,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(
                    labelText: income ? 'Source / payer' : 'Merchant / payee',
                    prefixIcon: const Icon(Icons.store),
                  ),
                  onChanged: _autoCategorizeFor,
                  onSubmitted: (_) => onSubmit(),
                );
              },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _categoryId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Category'),
              items: [
                for (final c in Categories.all)
                  DropdownMenuItem(value: c.id, child: Row(children: [
                    Icon(c.icon, color: c.color, size: 18),
                    const SizedBox(width: 10),
                    Text(c.label),
                  ])),
              ],
              onChanged: (v) => setState(() {
                _categoryId = v ?? 'other';
                _categoryManual = true;
              }),
            ),
            const SizedBox(height: 12),
            // Account picker (so manual entries feed the Accounts view).
            DropdownButtonFormField<String?>(
              value: _account,
              isExpanded: true,
              decoration: const InputDecoration(
                  labelText: 'Account (optional)',
                  prefixIcon: Icon(Icons.account_balance)),
              items: [
                const DropdownMenuItem(value: null, child: Text('No account')),
                for (final a in accounts)
                  DropdownMenuItem(value: a.key, child: Text(a.label)),
              ],
              onChanged: (v) => setState(() => _account = v),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _note,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Note (optional)', prefixIcon: Icon(Icons.note_outlined)),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                    leading: const Icon(Icons.calendar_today),
                    title: const Text('Date',
                        style: TextStyle(fontSize: 12, color: Colors.grey)),
                    subtitle: Text('${_when.day}/${_when.month}/${_when.year}',
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w600)),
                    onTap: _pickDate,
                  ),
                ),
                Expanded(
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                    leading: const Icon(Icons.access_time),
                    title: const Text('Time (optional)',
                        style: TextStyle(fontSize: 12, color: Colors.grey)),
                    subtitle: Text(TimeOfDay.fromDateTime(_when).format(context),
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w600)),
                    onTap: _pickTime,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              icon: const Icon(Icons.save),
              label: Text(income ? 'Save income' : 'Save transaction'),
              onPressed: _busy ? null : _save,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _when,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      // Keep whatever time-of-day was already set.
      setState(() => _when = DateTime(
          picked.year, picked.month, picked.day, _when.hour, _when.minute));
    }
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_when),
    );
    if (picked != null) {
      // Keep the selected date, just swap the time.
      setState(() => _when = DateTime(
          _when.year, _when.month, _when.day, picked.hour, picked.minute));
    }
  }

  Future<void> _save() async {
    final uid = ref.read(currentUserIdProvider);
    if (uid == null) return;
    final amt = double.tryParse(_amount.text);
    if (amt == null || amt <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enter a valid amount')));
      return;
    }
    setState(() => _busy = true);
    final merchant = (_merchantCtrl?.text ?? '').trim();
    final t = Transaction(
      id: const Uuid().v4(),
      amount: amt,
      direction: _dir,
      timestamp: _when,
      merchant: merchant.isEmpty ? null : merchant,
      account: _account,
      categoryId: _categoryId,
      note: _note.text.trim().isEmpty ? null : _note.text.trim(),
      source: TxnSource.manual,
    );
    await ref.read(firestoreServiceProvider).addTransaction(uid, t);
    // Teach the app this merchant → category so next time it auto-fills both
    // the merchant suggestion and the category.
    if (merchant.isNotEmpty) {
      await CategoryRules.instance.remember(merchant, _categoryId);
    }
    if (mounted) Navigator.pop(context);
  }
}
