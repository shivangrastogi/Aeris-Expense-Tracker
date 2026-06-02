import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../models/category.dart';
import '../../models/transaction.dart';
import '../../providers/auth_provider.dart';
import '../../providers/transactions_provider.dart';

class AddTransactionScreen extends ConsumerStatefulWidget {
  const AddTransactionScreen({super.key});
  @override
  ConsumerState<AddTransactionScreen> createState() => _AddTransactionScreenState();
}

class _AddTransactionScreenState extends ConsumerState<AddTransactionScreen> {
  final _amount = TextEditingController();
  final _merchant = TextEditingController();
  final _note = TextEditingController();
  TxnDirection _dir = TxnDirection.debit;
  String _categoryId = 'other';
  DateTime _when = DateTime.now();
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add transaction')),
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
              onSelectionChanged: (s) => setState(() => _dir = s.first),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _amount,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Amount (₹)', prefixIcon: Icon(Icons.currency_rupee)),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _merchant,
              decoration: const InputDecoration(
                labelText: 'Merchant / payee', prefixIcon: Icon(Icons.store)),
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
              onChanged: (v) => setState(() => _categoryId = v ?? 'other'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _note,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Note (optional)', prefixIcon: Icon(Icons.note_outlined)),
            ),
            const SizedBox(height: 12),
            ListTile(
              leading: const Icon(Icons.calendar_today),
              title: Text('${_when.day}/${_when.month}/${_when.year}'),
              trailing: const Icon(Icons.edit),
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _when,
                  firstDate: DateTime(2020),
                  lastDate: DateTime.now(),
                );
                if (picked != null) setState(() => _when = picked);
              },
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              icon: const Icon(Icons.save),
              label: const Text('Save transaction'),
              onPressed: _busy ? null : _save,
            ),
          ],
        ),
      ),
    );
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
    final t = Transaction(
      id: const Uuid().v4(),
      amount: amt,
      direction: _dir,
      timestamp: _when,
      merchant: _merchant.text.trim().isEmpty ? null : _merchant.text.trim(),
      categoryId: _categoryId,
      note: _note.text.trim().isEmpty ? null : _note.text.trim(),
      source: TxnSource.manual,
    );
    await ref.read(firestoreServiceProvider).addTransaction(uid, t);
    if (mounted) Navigator.pop(context);
  }
}
