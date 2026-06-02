import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/category.dart';
import '../../providers/transactions_provider.dart';
import '../../services/prediction_service.dart';
import '../../utils/formatters.dart';

class SubscriptionsScreen extends ConsumerWidget {
  const SubscriptionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final txns = ref.watch(transactionsStreamProvider).valueOrNull ?? const [];
    final recurring = PredictionService.instance.detectRecurring(txns);
    final total = recurring.fold<double>(0, (s, r) => s + r.approxAmount);

    return Scaffold(
      appBar: AppBar(title: const Text('Subscriptions & bills')),
      body: recurring.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(28),
                child: Text(
                  'No recurring payments detected yet.\n'
                  'Once a merchant charges you around the same day for 3+ months '
                  '(rent, Netflix, EMIs…), it shows up here automatically.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
              children: [
                _totalCard(context, total, recurring.length),
                const SizedBox(height: 14),
                Text('Detected recurring payments',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        )),
                const SizedBox(height: 6),
                ...recurring.map((r) => _card(context, r)),
              ],
            ),
    );
  }

  Widget _totalCard(BuildContext context, double total, int count) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            const Text('🔁', style: TextStyle(fontSize: 30)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${formatRupees(total)} / month',
                      style: const TextStyle(
                          fontSize: 20, fontWeight: FontWeight.w800)),
                  Text('across $count recurring payments — audit and cancel '
                      'anything you no longer use',
                      style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurfaceVariant)),
                ],
              ),
            ),
          ],
        ),
      ),
    ).animate().fadeIn(duration: 300.ms);
  }

  Widget _card(BuildContext context, dynamic r) {
    final cat = Categories.byId(r.categoryId as String);
    final day = r.dayOfMonth as int;
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: cat.color.withOpacity(0.18),
          child: Icon(cat.icon, color: cat.color),
        ),
        title: Text(r.merchant as String,
            style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text('~${formatRupees(r.approxAmount as double)} around the '
            '$day${_ord(day)} · seen ${r.occurrences} months'),
        trailing: Text(formatRupees(r.approxAmount as double, compact: true),
            style: const TextStyle(fontWeight: FontWeight.w700)),
      ),
    ).animate().fadeIn(duration: 250.ms).slideY(begin: 0.05, end: 0);
  }

  String _ord(int n) {
    if (n >= 11 && n <= 13) return 'th';
    return switch (n % 10) { 1 => 'st', 2 => 'nd', 3 => 'rd', _ => 'th' };
  }
}
