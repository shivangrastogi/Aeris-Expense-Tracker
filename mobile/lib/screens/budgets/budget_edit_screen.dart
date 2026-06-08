import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/budget.dart';
import '../../models/category.dart';
import '../../providers/auth_provider.dart';
import '../../providers/transactions_provider.dart';

class BudgetEditScreen extends ConsumerStatefulWidget {
  final String? categoryId;
  const BudgetEditScreen({super.key, this.categoryId});
  @override
  ConsumerState<BudgetEditScreen> createState() => _BudgetEditScreenState();
}

class _BudgetEditScreenState extends ConsumerState<BudgetEditScreen> {
  final _cap = TextEditingController();
  late String _catId = widget.categoryId ?? 'other';

  Future<void> _save() async {
    final uid = ref.read(currentUserIdProvider);
    if (uid == null) return;
    final cap = double.tryParse(_cap.text);
    if (cap == null || cap <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enter a positive amount')));
      return;
    }
    final b = Budget(
        id: _catId, categoryId: _catId,
        monthlyCap: cap, updatedAt: DateTime.now());
    await ref.read(firestoreServiceProvider).setBudget(uid, b);
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
    final cat = Categories.byId(_catId);
    return Scaffold(
      appBar: AppBar(title: Text('Budget — ${cat.label}'), actions: [
        IconButton(icon: const Icon(Icons.delete_outline), onPressed: _delete),
      ]),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            CircleAvatar(
              backgroundColor: cat.color.withValues(alpha: 0.2),
              child: Icon(cat.icon, color: cat.color),
            ),
            const SizedBox(width: 12),
            Text(cat.label,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 24),
          TextField(
            controller: _cap,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Monthly cap (₹)',
              prefixIcon: Icon(Icons.currency_rupee),
            ),
          ),
          const SizedBox(height: 20),
          ElevatedButton(onPressed: _save, child: const Text('Save cap')),
        ]),
      ),
    );
  }
}
