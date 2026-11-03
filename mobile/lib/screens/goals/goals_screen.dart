import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../utils/motion.dart';
import '../../core/theme.dart';
import '../../models/goal.dart';
import '../../providers/auth_provider.dart';
import '../../providers/goals_provider.dart';
import '../../providers/transactions_provider.dart';
import '../../utils/amount_input_formatter.dart';
import '../../utils/formatters.dart';
import '../../widgets/ds.dart';
import '../../widgets/field_editor.dart';
import '../../widgets/skeleton.dart';

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
    if (celebrate && mounted && !reduceMotion(context)) _confetti.play();
  }

  @override
  Widget build(BuildContext context) {
    final goalsAsync = ref.watch(goalsStreamProvider);
    final streak = ref.watch(streakProvider).asData?.value;
    final tk = context.tk;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Goals'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: TonalButton('New goal',
                icon: PhBold.plus, height: 40, onPressed: () => _editGoal()),
          ),
        ],
      ),
      body: Stack(
        alignment: Alignment.topCenter,
        children: [
          goalsAsync.when(
            loading: () => const GoalsSkeleton(),
            error: (e, _) => Padding(
              padding: const EdgeInsets.all(20),
              child: Banner2(
                  tone: Tone.bad,
                  icon: PhFill.cloudX,
                  title: "Couldn't load goals",
                  body: '$e'),
            ),
            data: (goals) {
              final totalSaved = goals.fold<double>(0, (s, g) => s + g.saved);
              return ListView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
                children: [
                  if (goals.isEmpty)
                    EmptyState(
                      icon: Ph.flagPennant,
                      title: 'No savings goals yet',
                      body: 'Save toward something — a trip, a gadget or an '
                          'emergency fund. Add money as you go and watch it '
                          'fill up.',
                      cta: 'New goal',
                      onCta: () => _editGoal(),
                    )
                  else
                    for (final g in goals)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _goalCard(g),
                      ),
                  const SizedBox(height: 12),
                  _streakCard(streak?.current ?? 0, streak?.best ?? 0),
                  const SizedBox(height: 16),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(4, 0, 4, 8),
                    child: Overline('Badges'),
                  ),
                  _badges(goals, totalSaved, streak?.current ?? 0),
                  const SizedBox(height: 16),
                  Text(
                    'Goals are money you save toward something. Want to limit '
                    'spending instead? Use Budgets.',
                    style: TextStyle(fontSize: 12, height: 16 / 12, color: tk.t2),
                  ),
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
    final tk = context.tk;
    return ListGroup(children: [
      DsRow(
        leading: BadgeTile(icon: PhFill.flame, tint: tk.warn),
        title: '$current-day streak',
        sub: 'Best: $best days · open daily to keep it alive',
      ),
    ]);
  }

  // ── Badges ────────────────────────────────────────────────
  Widget _badges(List<Goal> goals, double totalSaved, int streak) {
    final badges = <(IconData, String, bool)>[
      (Ph.flagPennant, 'First goal', goals.isNotEmpty),
      (Ph.trophy, 'Goal smashed', goals.any((g) => g.isComplete)),
      (Ph.flame, '7-day streak', streak >= 7),
      (Ph.coins, 'Saved ₹10k', totalSaved >= 10000),
      (Ph.medal, 'Saved ₹1L', totalSaved >= 100000),
    ];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final b in badges)
          Opacity(
            opacity: b.$3 ? 1 : 0.45,
            child: DsChip(b.$2,
                icon: b.$1, selected: b.$3, showCheck: false),
          ),
      ],
    );
  }

  // ── Goal card: progress ring around the goal's mark ───────
  Widget _goalCard(Goal g) {
    final tk = context.tk;
    final pct = g.progress;
    String? pace;
    if (!g.isComplete && g.deadline != null) {
      final days = g.deadline!.difference(DateTime.now()).inDays;
      if (days > 0) {
        final perMonth = g.remaining / (days / 30.0).clamp(1, 1200);
        pace = '${formatRupees(perMonth, compact: true)}/month to make '
            '${shortDate(g.deadline!)}';
      }
    }
    return AerisCard(
      padding: const EdgeInsets.fromLTRB(16, 16, 8, 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          CatRing(
            value: pct,
            color: g.isComplete ? tk.ok : tk.acc,
            size: 64,
            center: Text(g.emoji, style: const TextStyle(fontSize: 24)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(g.title, style: Ts.title.copyWith(color: tk.t1)),
                const SizedBox(height: 2),
                Text.rich(
                  TextSpan(children: [
                    TextSpan(text: formatRupees(g.saved)),
                    TextSpan(
                        text: ' of ${formatRupees(g.target)}',
                        style: TextStyle(
                            color: tk.t2, fontWeight: FontWeight.w500)),
                  ]),
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      fontFeatures: const [FontFeature.tabularFigures()],
                      color: tk.t1),
                ),
                const SizedBox(height: 4),
                if (g.isComplete)
                  const StatusPill('Completed',
                      icon: PhFill.checkCircle, tone: Tone.ok)
                else
                  Text(
                      pace ??
                          '${(pct * 100).toStringAsFixed(0)}% · '
                              '${formatRupees(g.remaining, compact: true)} to go',
                      style: TextStyle(fontSize: 12, color: tk.t2)),
              ],
            ),
          ),
          PopupMenuButton<String>(
            icon: Icon(Ph.dotsThreeVertical, size: 20, color: tk.t2),
            onSelected: (v) {
              if (v == 'edit') _editGoal(existing: g);
              if (v == 'delete') _delete(g);
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'edit', child: Text('Edit')),
              PopupMenuItem(value: 'delete', child: Text('Delete')),
            ],
          ),
        ]),
        if (!g.isComplete) ...[
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: TonalButton('Add money',
                icon: PhBold.plus, height: 40, onPressed: () => _contribute(g)),
          ),
        ],
      ]),
    ).animate().fadeIn(duration: Mo.standard).slideY(begin: 0.03, end: 0);
  }

  // ── New / edit goal sheet ─────────────────────────────────
  Future<void> _editGoal({Goal? existing}) async {
    final title = TextEditingController(text: existing?.title ?? '');
    // Typed in the display currency, stored in INR like every other amount.
    final target = TextEditingController(
        text: existing == null
            ? ''
            : (existing.target / kCurrency.rate).toStringAsFixed(0));
    var emoji = existing?.emoji ?? '🎯';
    const emojis = ['🎯', '✈️', '🏠', '🚗', '📱', '💍', '🎓', '🏖️', '💻', '🎁'];

    final ok = await showDsSheet<bool>(
      context,
      title: existing == null ? 'New goal' : 'Edit goal',
      scrollControlled: true,
      builder: (d) => StatefulBuilder(
        builder: (d, setLocal) {
          final tk = d.tk;
          Widget label(String s) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(s,
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: tk.t2)),
              );
          return SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                label('Name'),
                TextField(
                    controller: title,
                    autofocus: existing == null,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      hintText: 'e.g. Goa trip, New phone',
                    )),
                const SizedBox(height: 16),
                label('Target'),
                TextField(
                  controller: target,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: const [AmountInputFormatter()],
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w700),
                  decoration: InputDecoration(
                    prefixText: '${kCurrency.symbol.trim()} ',
                    hintText: '40,000',
                  ),
                ),
                const SizedBox(height: 16),
                label('Icon'),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final e in emojis)
                      InkWell(
                        borderRadius: BorderRadius.circular(Rad.tile),
                        onTap: () => setLocal(() => emoji = e),
                        child: AnimatedContainer(
                          duration: Mo.standard,
                          width: 44,
                          height: 44,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: emoji == e ? tk.accSoft2 : tk.sunken,
                            borderRadius: BorderRadius.circular(Rad.tile),
                            border: emoji == e
                                ? Border.all(color: tk.acc, width: 1.5)
                                : null,
                          ),
                          child:
                              Text(e, style: const TextStyle(fontSize: 20)),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 20),
                FilledButton(
                    onPressed: () => Navigator.pop(d, true),
                    child: Text(
                        existing == null ? 'Create goal' : 'Save goal')),
              ],
            ),
          );
        },
      ),
    );
    if (ok != true) return;
    final typed = evalAmount(target.text) ?? 0;
    final amt = (typed * kCurrency.rate * 100).roundToDouble() / 100;
    if (title.text.trim().isEmpty || amt <= 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Add a name and an amount to save the goal.')));
      }
      return;
    }
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
    final amt = await editAmountField(context,
        title: 'Add to “${g.title}”', initialInr: 0);
    if (amt == null || amt <= 0) return;
    final updated = g.copyWith(saved: g.saved + amt);
    await _save(updated, celebrate: !g.isComplete && updated.isComplete);
  }

  Future<void> _delete(Goal g) async {
    final uid = ref.read(currentUserIdProvider);
    if (uid == null) return;
    await ref.read(firestoreServiceProvider).deleteGoal(uid, g.id);
  }
}
