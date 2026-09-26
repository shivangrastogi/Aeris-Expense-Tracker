import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../models/category.dart';
import '../../models/transaction.dart';
import '../../providers/auth_provider.dart';
import '../../providers/gamification_provider.dart';
import '../../providers/transactions_provider.dart';
import '../../services/category_rules.dart';
import '../../services/merchant_directory.dart';
import '../../utils/formatters.dart';
import '../../core/routes.dart';
import '../../widgets/field_editor.dart';
import '../../widgets/receipt_field.dart';
import '../../widgets/txn_undo.dart';

class TransactionDetailScreen extends ConsumerStatefulWidget {
  final Transaction txn;
  const TransactionDetailScreen({super.key, required this.txn});

  @override
  ConsumerState<TransactionDetailScreen> createState() => _TxDetailState();
}

class _TxDetailState extends ConsumerState<TransactionDetailScreen> {
  late Transaction _t = widget.txn;

  Future<void> _changeCategory() async {
    final picked = await editCategoryField(context, selected: _t.categoryId);
    if (picked == null || picked == _t.categoryId) return;
    await _apply(_t.copyWith(categoryId: picked, reviewed: true));
    // Learn: future SMS from this merchant auto-tag to this category.
    await CategoryRules.instance.remember(_t.merchant, picked);
    // Reward categorising this transaction (once per transaction).
    final awarded =
        ref.read(gamificationProvider.notifier).rewardCategorization(_t.id);
    if (awarded > 0 && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('+$awarded Aura for categorising 🎉'),
          duration: const Duration(seconds: 2)));
    }
  }

  // Each row edits just its own field in a small sheet — tapping "Note"
  // never opens the whole add form.

  Future<void> _editAmount() async {
    final v = await editAmountField(context,
        title: _t.isCredit ? 'Income amount' : 'Expense amount',
        initialInr: _t.amount);
    if (v == null || v == _t.amount) return;
    await _apply(_t.copyWith(amount: v));
  }

  Future<void> _editMerchant() async {
    final v = await editTextField(context,
        title: _t.isCredit ? 'Payer / source' : 'Merchant / payee',
        initial: _t.merchant ?? '',
        icon: Icons.storefront_rounded,
        maxLength: 80,
        capitalization: TextCapitalization.words);
    if (v == null || v == (_t.merchant ?? '')) return;
    await _apply(v.isEmpty
        ? _t.copyWith(clearMerchant: true)
        : _t.copyWith(merchant: v));
  }

  Future<void> _editNote() async {
    final v = await editTextField(context,
        title: 'Note',
        initial: _t.note ?? '',
        hint: 'e.g. dinner with friends',
        icon: Icons.notes_rounded,
        multiline: true);
    if (v == null || v == (_t.note ?? '')) return;
    await _apply(
        v.isEmpty ? _t.copyWith(clearNote: true) : _t.copyWith(note: v));
  }

  Future<void> _editWhen() async {
    final v = await editDateTimeField(context, initial: _t.timestamp);
    if (v == null || v == _t.timestamp) return;
    await _apply(_t.copyWith(timestamp: v));
  }

  Future<void> _editType() async {
    final picked = await showModalBottomSheet<TxnDirection>(
      context: context,
      showDragHandle: true,
      builder: (s) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (d, label, icon, color) in [
              (
                TxnDirection.debit,
                'Expense (money out)',
                Icons.south_west_rounded,
                AerisColors.moneyOut(context)
              ),
              (
                TxnDirection.credit,
                'Income (money in)',
                Icons.north_east_rounded,
                AerisColors.moneyIn(context)
              ),
            ])
              ListTile(
                leading: Icon(icon, color: color),
                title: Text(label),
                trailing: d == _t.direction
                    ? Icon(Icons.check_rounded,
                        color: Theme.of(context).colorScheme.primary)
                    : null,
                onTap: () => Navigator.pop(s, d),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (picked == null || picked == _t.direction) return;
    await _apply(_t.copyWith(direction: picked));
  }

  /// Opens the full form — only from the app bar's "Edit all details",
  /// for things without their own row (account, receipt…).
  Future<void> _openEditor() async {
    final updated =
        await Navigator.pushNamed(context, AppRoutes.addTxn, arguments: _t);
    if (updated is Transaction && mounted) {
      setState(() {
        _t = updated;
        _receiptFuture = null;
      });
    }
  }

  Future<List<int>?>? _receiptFuture;

  Future<void> _apply(Transaction updated) async {
    final uid = ref.read(currentUserIdProvider);
    if (uid == null) return;
    final previous = _t;
    setState(() => _t = updated);
    try {
      await ref.read(firestoreServiceProvider).updateTransaction(uid, updated);
    } catch (err) {
      if (!mounted) return;
      setState(() => _t = previous);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not save: $err')));
      return;
    }
    if (mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(
            content: Text('Saved'), duration: Duration(seconds: 1)));
    }
  }

  /// Deletes straight away but offers UNDO on the next screen.
  Future<void> _delete() async {
    await deleteTransactionsWithUndo(context, ref, [_t]);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final cat = Categories.byId(_t.categoryId);
    final color = _t.isCredit ? AerisColors.moneyIn(context) : AerisColors.moneyOut(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Transaction'),
        actions: [
          IconButton(
              tooltip: 'Edit all details',
              icon: const Icon(Icons.edit_outlined),
              onPressed: _openEditor),
          IconButton(
              tooltip: 'Delete',
              icon: const Icon(Icons.delete_outline),
              onPressed: _delete),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Row(children: [
            CircleAvatar(
              radius: 28,
              backgroundColor: cat.color.withValues(alpha: 0.18),
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
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ]),
          const SizedBox(height: 28),
          _row('Category', cat.label,
              onTap: _changeCategory, trailingIcon: Icons.edit),
          _row('Type', _t.isCredit ? 'Income' : 'Expense',
              onTap: _editType, trailingIcon: Icons.edit),
          _row(_t.isCredit ? 'Payer' : 'Merchant',
              _t.merchant ?? (_t.isCredit ? 'Add payer' : 'Add merchant'),
              onTap: _editMerchant, trailingIcon: Icons.edit),
          _row(
              'When',
              '${relativeDate(_t.timestamp)} · '
                  '${TimeOfDay.fromDateTime(_t.timestamp).format(context)}',
              onTap: _editWhen,
              trailingIcon: Icons.edit),
          if (_t.account != null) _row('Account', '••${_t.account}'),
          if (MerchantDirectory.appFor(_t.upiVpa) != null)
            _row('Paid via', MerchantDirectory.appFor(_t.upiVpa)!),
          if (_t.upiVpa != null) _row('UPI ID', _t.upiVpa!),
          if (_t.reference != null) _row('Reference', _t.reference!),
          _row('Source', _t.source.name),
          _row('Note', _t.note ?? 'Add a note',
              onTap: _editNote, trailingIcon: Icons.edit),
          if (_t.hasReceipt) _receiptSection(),
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

  Widget _receiptSection() {
    final uid = ref.read(currentUserIdProvider);
    _receiptFuture ??= uid == null
        ? Future.value(null)
        : ref.read(firestoreServiceProvider).fetchReceipt(uid, _t.id);
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Receipt',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          FutureBuilder<List<int>?>(
            future: _receiptFuture,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const SizedBox(
                    height: 120,
                    child: Center(child: CircularProgressIndicator()));
              }
              final data = snap.data;
              if (data == null) {
                return const Text(
                    "Receipt isn't available offline on this device yet.");
              }
              final bytes = Uint8List.fromList(data);
              return GestureDetector(
                onTap: () => showReceiptViewer(context, bytes),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Image.memory(bytes,
                      height: 180, width: double.infinity, fit: BoxFit.cover),
                ),
              );
            },
          ),
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
