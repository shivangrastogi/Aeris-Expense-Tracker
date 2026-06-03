import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/theme.dart';
import '../../models/category.dart';
import '../../models/challenge.dart';
import '../../providers/gamification_provider.dart';
import '../../providers/transactions_provider.dart';

class ChallengesScreen extends ConsumerWidget {
  const ChallengesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final g = ref.watch(gamificationProvider);
    final txns = ref.watch(transactionsStreamProvider).valueOrNull ?? const [];
    final now = DateTime.now();
    final ctrl = ref.read(gamificationProvider.notifier);

    final items = [...g.challenges]..sort((a, b) => b.start.compareTo(a.start));

    return Scaffold(
      appBar: AppBar(title: const Text('Challenges')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _newChallenge(context, ctrl),
        icon: const Icon(Icons.add),
        label: const Text('New challenge'),
      ),
      body: items.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(28),
                child: Text(
                  'No challenges yet.\n\nStart one and AERIS verifies it for you '
                  'automatically from your bank SMS — no check-ins needed.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 90),
              children: [
                for (final c in items)
                  _ChallengeCard(
                    challenge: c,
                    status: c.evaluate(txns, now),
                    onDelete: () => ctrl.removeChallenge(c.id),
                  ),
              ],
            ),
    );
  }

  void _newChallenge(BuildContext context, GamificationController ctrl) {
    var type = ChallengeType.noSpend;
    var days = 5;
    var cap = 300.0;
    var categoryId = 'food';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          int reward() => switch (type) {
                ChallengeType.noSpend => days * 30,
                ChallengeType.noCategory => days * 20,
                ChallengeType.dailyCap => days * 15,
              };
          return Padding(
            padding: EdgeInsets.fromLTRB(
                18, 4, 18, MediaQuery.of(ctx).viewInsets.bottom + 18),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('New challenge',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
              const SizedBox(height: 12),
              SegmentedButton<ChallengeType>(
                segments: const [
                  ButtonSegment(value: ChallengeType.noSpend, label: Text('No-spend')),
                  ButtonSegment(value: ChallengeType.dailyCap, label: Text('Daily cap')),
                  ButtonSegment(value: ChallengeType.noCategory, label: Text('No category')),
                ],
                selected: {type},
                onSelectionChanged: (s) => setS(() => type = s.first),
              ),
              const SizedBox(height: 16),
              Row(children: [
                const Text('Duration'),
                Expanded(
                  child: Slider(
                    value: days.toDouble(),
                    min: 1, max: 30, divisions: 29,
                    label: '$days days',
                    onChanged: (v) => setS(() => days = v.round()),
                  ),
                ),
                Text('$days d'),
              ]),
              if (type == ChallengeType.dailyCap)
                TextField(
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                      labelText: 'Daily cap (₹)', prefixIcon: Icon(Icons.currency_rupee)),
                  onChanged: (v) => cap = double.tryParse(v) ?? cap,
                ),
              if (type == ChallengeType.noCategory)
                DropdownButtonFormField<String>(
                  value: categoryId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Avoid category'),
                  items: [
                    for (final c in Categories.all)
                      DropdownMenuItem(value: c.id, child: Text(c.label)),
                  ],
                  onChanged: (v) => setS(() => categoryId = v ?? 'food'),
                ),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.auto_awesome, size: 16),
                  const SizedBox(width: 6),
                  Text('Reward: ${reward()} Aura',
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () {
                    final start = DateTime.now();
                    final end = DateTime(start.year, start.month,
                        start.day + days - 1, 23, 59, 59);
                    final title = switch (type) {
                      ChallengeType.noSpend => 'No-spend · $days days',
                      ChallengeType.dailyCap =>
                        'Under ₹${cap.toStringAsFixed(0)}/day · $days days',
                      ChallengeType.noCategory =>
                        'No ${Categories.byId(categoryId).label} · $days days',
                    };
                    ctrl.addChallenge(Challenge(
                      id: const Uuid().v4(),
                      type: type,
                      title: title,
                      start: start,
                      end: end,
                      param: type == ChallengeType.dailyCap ? cap : 0,
                      categoryId: type == ChallengeType.noCategory ? categoryId : null,
                      reward: reward(),
                    ));
                    Navigator.pop(ctx);
                  },
                  child: const Text('Start challenge'),
                ),
              ),
            ]),
          );
        },
      ),
    );
  }
}

class _ChallengeCard extends StatelessWidget {
  final Challenge challenge;
  final ChallengeStatus status;
  final VoidCallback onDelete;
  const _ChallengeCard({
    required this.challenge,
    required this.status,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final (Color color, IconData icon) = switch (status.state) {
      ChallengeState.won => (AerisColors.credit, Icons.emoji_events),
      ChallengeState.failed => (AerisColors.debit, Icons.heart_broken),
      ChallengeState.active => (AerisColors.info, Icons.bolt),
      ChallengeState.upcoming => (AerisColors.warning, Icons.schedule),
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(icon, color: color),
              const SizedBox(width: 8),
              Expanded(
                  child: Text(challenge.title,
                      style: const TextStyle(fontWeight: FontWeight.w700))),
              Row(children: [
                const Icon(Icons.auto_awesome, size: 14),
                const SizedBox(width: 2),
                Text('${challenge.reward}',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
              ]),
              IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: onDelete),
            ]),
            if (status.state == ChallengeState.active) ...[
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                    value: status.progress, minHeight: 7, color: color),
              ),
            ],
            const SizedBox(height: 6),
            Text(status.detail, style: TextStyle(fontSize: 12, color: color)),
          ],
        ),
      ),
    );
  }
}
