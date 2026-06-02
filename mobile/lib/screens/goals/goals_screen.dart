import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/theme.dart';
import '../../models/goal.dart';
import '../../providers/auth_provider.dart';
import '../../providers/goals_provider.dart';
import '../../providers/transactions_provider.dart';
import '../../utils/formatters.dart';

class GoalsScreen extends ConsumerStatefulWidget {
  const GoalsScreen({super.key});
  @override
  ConsumerState<GoalsScreen> createState() => _GoalsScreenState();
}

class _GoalsScreenState extends ConsumerState<GoalsScreen> {
  final _confetti = ConfettiController(duration: const Duration(seconds: 2));

  @override
  void dispose() {
    _confetti.dispose();
    super.dispose();
  }

  Future<void> _save(Goal g, {bool celebrate = false}) async {
    final uid = ref.read(currentUserIdProvider);
    if (uid == null) return;
    await ref.read(firestoreServiceProvider).setGoal(uid, g);
    if (celebrate) _confetti.play();
  }

  @override
  Widget build(BuildContext context) {
    final goalsAsync = ref.watch(goalsStreamProvider);
    final streak = ref.watch(streakProvider).asData?.value;

    return Scaffold(
      appBar: AppBar(title: const Text('Goals & streaks')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _editGoal(),
        icon: const Icon(Icons.add),
        label: const Text('New goal'),
      ),
      body: Stack(
        alignment: Alignment.topCenter,
        children: [
          goalsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('$e')),
            data: (goals) {
              final totalSaved = goals.fold<double>(0, (s, g) => s + g.saved);
              return ListView(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 100),
                children: [
                  _streakCard(streak?.current ?? 0, streak?.best ?? 0),
                  const SizedBox(height: 12),
                  _badges(goals, totalSaved, streak?.current ?? 0),
                  const SizedBox(height: 16),
                  _explainer(),
                  const SizedBox(height: 14),
                  Text('Your savings goals',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          )),
                  Text(
                    'Save toward something — add money as you go and watch it fill up.',
                    style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 8),
                  if (goals.isEmpty)
                    _empty()
                  else
                    ...goals.map(_goalCard),
                ],
              );
            },
          ),
          ConfettiWidget(
            confettiController: _confetti,
            blastDirectionality: BlastDirectionality.explosive,
            numberOfParticles: 24,
            maxBlastForce: 22,
            minBlastForce: 8,
            gravity: 0.25,
            colors: AerisColors.categoryPalette,
          ),
        ],
      ),
    );
  }

  // ── Streak ────────────────────────────────────────────────
  Widget _streakCard(int current, int best) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Text('🔥', style: TextStyle(fontSize: 34))
                .animate(onPlay: (c) => c.repeat(reverse: true))
                .scaleXY(end: 1.15, duration: 800.ms),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('$current-day streak',
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w800)),
                  Text('Best: $best days · open daily to keep it alive',
                      style: TextStyle(
                          fontSize: 12,
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Badges ────────────────────────────────────────────────
  Widget _badges(List<Goal> goals, double totalSaved, int streak) {
    final badges = <(String, String, bool)>[
      ('🥅', 'First goal', goals.isNotEmpty),
      ('🏆', 'Goal smashed', goals.any((g) => g.isComplete)),
      ('🔥', '7-day streak', streak >= 7),
      ('💰', 'Saved ₹10k', totalSaved >= 10000),
      ('⭐', 'Saved ₹1L', totalSaved >= 100000),
    ];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final b in badges)
          Opacity(
            opacity: b.$3 ? 1 : 0.35,
            child: Chip(
              avatar: Text(b.$1),
              label: Text(b.$2, style: const TextStyle(fontSize: 12)),
              backgroundColor: b.$3
                  ? AerisColors.seed.withOpacity(0.15)
                  : Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.4),
            ),
          ),
      ],
    );
  }

  // ── Explainer ─────────────────────────────────────────────
  Widget _explainer() {
    return Card(
      color: AerisColors.seed.withOpacity(0.08),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('💡', style: TextStyle(fontSize: 20)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'What are goals?',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'A goal is money you want to SAVE toward something — a trip, '
                    'a phone, an emergency fund. Set the amount, then add money '
                    'as you save until it\'s full.',
                    style: TextStyle(
                        fontSize: 12,
                        height: 1.35,
                        color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Want to LIMIT spending instead? Use Budgets (Budgets tab).',
                    style: TextStyle(
                        fontSize: 11.5,
                        fontStyle: FontStyle.italic,
                        color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Goal card ─────────────────────────────────────────────
  Widget _goalCard(Goal g) {
    final pct = g.progress;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(g.emoji, style: const TextStyle(fontSize: 22)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(g.title,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w700)),
                ),
                if (g.isComplete)
                  const Icon(Icons.verified, color: AerisColors.credit),
                PopupMenuButton<String>(
                  onSelected: (v) {
                    if (v == 'edit') _editGoal(existing: g);
                    if (v == 'delete') _delete(g);
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'edit', child: Text('Edit')),
                    PopupMenuItem(value: 'delete', child: Text('Delete')),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: pct),
                duration: const Duration(milliseconds: 700),
                curve: Curves.easeOutCubic,
                builder: (_, v, __) => LinearProgressIndicator(
                  value: v,
                  minHeight: 12,
                  color: g.isComplete ? AerisColors.credit : AerisColors.seed,
                  backgroundColor: AerisColors.seed.withOpacity(0.12),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text('${formatRupees(g.saved)} of ${formatRupees(g.target)}',
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600)),
                const Spacer(),
                Text('${(pct * 100).toStringAsFixed(0)}%',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: g.isComplete
                            ? AerisColors.credit
                            : AerisColors.seed)),
              ],
            ),
            if (!g.isComplete) ...[
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.tonalIcon(
                  onPressed: () => _contribute(g),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add money'),
                ),
              ),
            ] else
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('Completed — well done! 🎉',
                    style: TextStyle(
                        color: AerisColors.credit,
                        fontWeight: FontWeight.w600)),
              ),
          ],
        ),
      ),
    ).animate().fadeIn(duration: 300.ms).slideY(begin: 0.06, end: 0);
  }

  Widget _empty() => Padding(
        padding: const EdgeInsets.symmetric(vertical: 30),
        child: Center(
          child: Column(
            children: [
              const Text('🎯', style: TextStyle(fontSize: 40)),
              const SizedBox(height: 10),
              const Text(
                'No savings goals yet.\n'
                'Tap “New goal” to save toward something —\n'
                'a trip, a gadget, or an emergency fund.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );

  // ── Dialogs ───────────────────────────────────────────────
  Future<void> _editGoal({Goal? existing}) async {
    final title = TextEditingController(text: existing?.title ?? '');
    final target =
        TextEditingController(text: existing?.target.toStringAsFixed(0) ?? '');
    var emoji = existing?.emoji ?? '🎯';
    const emojis = ['🎯', '✈️', '🏠', '🚗', '📱', '💍', '🎓', '🏖️', '💻', '🎁'];

    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (d, setLocal) => AlertDialog(
          title: Text(existing == null ? 'New savings goal' : 'Edit goal'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                    controller: title,
                    decoration: const InputDecoration(
                      labelText: 'What are you saving for?',
                      hintText: 'e.g. Goa trip, New phone',
                    )),
                const SizedBox(height: 10),
                TextField(
                  controller: target,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Amount to save (₹)',
                    hintText: 'e.g. 50000',
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 6,
                  children: [
                    for (final e in emojis)
                      GestureDetector(
                        onTap: () => setLocal(() => emoji = e),
                        child: CircleAvatar(
                          backgroundColor: emoji == e
                              ? AerisColors.seed.withOpacity(0.25)
                              : Colors.transparent,
                          child: Text(e, style: const TextStyle(fontSize: 18)),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(d, false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(d, true),
                child: const Text('Save')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final amt = double.tryParse(target.text.trim()) ?? 0;
    if (title.text.trim().isEmpty || amt <= 0) return;
    final goal = (existing ??
            Goal(
                id: const Uuid().v4(),
                title: '',
                target: 0,
                createdAt: DateTime.now()))
        .copyWith(title: title.text.trim(), target: amt, emoji: emoji);
    await _save(goal);
  }

  Future<void> _contribute(Goal g) async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text('Add to “${g.title}”'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Amount (₹)'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(d, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(d, true), child: const Text('Add')),
        ],
      ),
    );
    if (ok != true) return;
    final amt = double.tryParse(ctrl.text.trim()) ?? 0;
    if (amt <= 0) return;
    final updated = g.copyWith(saved: g.saved + amt);
    await _save(updated, celebrate: !g.isComplete && updated.isComplete);
  }

  Future<void> _delete(Goal g) async {
    final uid = ref.read(currentUserIdProvider);
    if (uid == null) return;
    await ref.read(firestoreServiceProvider).deleteGoal(uid, g.id);
  }
}
