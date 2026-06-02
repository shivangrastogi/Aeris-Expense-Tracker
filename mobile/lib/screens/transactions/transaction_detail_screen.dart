import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../models/category.dart';
import '../../models/transaction.dart';
import '../../providers/auth_provider.dart';
import '../../providers/transactions_provider.dart';
import '../../services/category_rules.dart';
import '../../utils/formatters.dart';

class TransactionDetailScreen extends ConsumerStatefulWidget {
  final Transaction txn;
  const TransactionDetailScreen({super.key, required this.txn});

  @override
  ConsumerState<TransactionDetailScreen> createState() => _TxDetailState();
}

class _TxDetailState extends ConsumerState<TransactionDetailScreen> {
  late Transaction _t = widget.txn;

  Future<void> _changeCategory() async {
    final picked = await showDialog<String>(
      context: context,
      builder: (_) => SimpleDialog(
        title: const Text('Pick a category'),
        children: [
          for (final c in Categories.all)
            SimpleDialogOption(
              child: Row(children: [
                Icon(c.icon, color: c.color, size: 20),
                const SizedBox(width: 12),
                Text(c.label),
              ]),
              onPressed: () => Navigator.pop(context, c.id),
            ),
        ],
      ),
    );
    if (picked == null) return;
    await _apply(_t.copyWith(categoryId: picked, reviewed: true));
    // Learn: future SMS from this merchant auto-tag to this category.
    await CategoryRules.instance.remember(_t.merchant, picked);
  }

  Future<void> _editAmount() async {
    final v = await _promptText('Amount (₹)', _t.amount.toStringAsFixed(0));
    if (v == null) return;
    final amt = double.tryParse(v.replaceAll(',', ''));
    if (amt == null || amt <= 0) return;
    await _apply(_t.copyWith(amount: amt, reviewed: true));
  }

  Future<void> _editDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _t.timestamp,
      firstDate: DateTime(2015),
      lastDate: DateTime.now(),
    );
    if (picked == null) return;
    final t = _t.timestamp;
    await _apply(_t.copyWith(
        timestamp:
            DateTime(picked.year, picked.month, picked.day, t.hour, t.minute),
        reviewed: true));
  }

  Future<String?> _promptText(String title, String? initial) {
    final ctrl = TextEditingController(text: initial ?? '');
    return showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(d), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(d, ctrl.text.trim()),
              child: const Text('Save')),
        ],
      ),
    );
  }

  Future<void> _editMerchant() async {
    final v = await _promptText('Merchant / payee', _t.merchant);
    if (v == null || v.isEmpty) return;
    await _apply(_t.copyWith(merchant: v, reviewed: true));
  }

  Future<void> _editNote() async {
    final v = await _promptText('Note', _t.note);
    if (v == null) return;
    await _apply(_t.copyWith(note: v.isEmpty ? null : v, reviewed: true));
  }

  Future<void> _apply(Transaction updated) async {
    final uid = ref.read(currentUserIdProvider);
    if (uid == null) return;
    await ref.read(firestoreServiceProvider).updateTransaction(uid, updated);
    if (mounted) setState(() => _t = updated);
  }

  Future<void> _delete() async {
    final uid = ref.read(currentUserIdProvider);
    if (uid == null) return;
    await ref.read(firestoreServiceProvider).deleteTransaction(uid, _t.id);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final cat = Categories.byId(_t.categoryId);
    final color = _t.isCredit ? AerisColors.credit : AerisColors.debit;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Transaction'),
        actions: [
          IconButton(icon: const Icon(Icons.delete_outline), onPressed: _delete),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Row(children: [
            CircleAvatar(
              radius: 28,
              backgroundColor: cat.color.withOpacity(0.18),
              child: Icon(cat.icon, color: cat.color),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_t.merchant ?? cat.label,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          )),
                  const SizedBox(height: 4),
                  InkWell(
                    onTap: _editAmount,
                    child: Row(
                      children: [
                        Text(
                          '${_t.isCredit ? "+ " : "− "}${formatRupees(_t.amount, decimals: true)}',
                          style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                              color: color),
                        ),
                        const SizedBox(width: 8),
                        Icon(Icons.edit,
                            size: 16,
                            color: Theme.of(context).colorScheme.onSurfaceVariant),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ]),
          const SizedBox(height: 28),
          _row('Category', cat.label, onTap: _changeCategory, trailingIcon: Icons.edit),
          _row('Merchant', _t.merchant ?? 'Add merchant',
              onTap: _editMerchant, trailingIcon: Icons.edit),
          _row('When', relativeDate(_t.timestamp),
              onTap: _editDate, trailingIcon: Icons.edit),
          if (_t.account != null) _row('Account', '••${_t.account}'),
          _row('Source', _t.source.name),
          _row('Note', _t.note ?? 'Add a note',
              onTap: _editNote, trailingIcon: Icons.edit),
          if (_t.smsBody != null) ...[
            const SizedBox(height: 16),
            Text('Original SMS',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    )),
            const SizedBox(height: 6),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(_t.smsBody!,
                    style: const TextStyle(fontSize: 12, height: 1.4)),
              ),
            ),
            Text('From: ${_t.smsSender ?? "unknown sender"}',
                style: const TextStyle(fontSize: 11)),
          ],
        ],
      ),
    );
  }

  Widget _row(String label, String value,
      {VoidCallback? onTap, IconData? trailingIcon}) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      trailing: trailingIcon != null
          ? Icon(trailingIcon, size: 18)
          : const SizedBox.shrink(),
      subtitle: Text(value,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
      onTap: onTap,
    );
  }
}
