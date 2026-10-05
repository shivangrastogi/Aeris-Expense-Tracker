import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../models/category.dart';
import '../../models/subscription.dart';
import '../../models/transaction.dart';
import '../../providers/auth_provider.dart';
import '../../providers/subscriptions_provider.dart';
import '../../providers/transactions_provider.dart';
import '../../utils/formatters.dart';
import '../../utils/amount_input_formatter.dart';

// Quick-pick catalog of common Indian subscriptions.
const _subCatalog = <(String, String, double)>[
  ('Netflix', 'entertainment', 649),
  ('Spotify', 'entertainment', 149),
  ('Amazon Prime', 'entertainment', 299),
  ('Disney+ Hotstar', 'entertainment', 299),
  ('YouTube Premium', 'entertainment', 139),
  ('Jio Fiber', 'bills', 999),
  ('Cult.fit', 'health', 1300),
  ('Airtel Postpaid', 'bills', 599),
  ('iCloud+', 'bills', 75),
  ('ChatGPT Plus', 'entertainment', 1650),
];

// ── Full-screen route ────────────────────────────────────────────────────────
class SubscriptionsScreen extends StatelessWidget {
  const SubscriptionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: SafeArea(child: SubscriptionsBody(embed: false, showTitle: true)),
    );
  }
}

// ── Body (also embedded as the Activity → Subs tab) ──────────────────────────
class SubscriptionsBody extends ConsumerStatefulWidget {
  final bool embed;
  final bool showTitle;
  const SubscriptionsBody(
      {super.key, this.embed = true, this.showTitle = false});

  @override
  ConsumerState<SubscriptionsBody> createState() => _SubscriptionsBodyState();
}

class _SubscriptionsBodyState extends ConsumerState<SubscriptionsBody> {
  bool _selectMode = false;
  final Set<String> _picked = {};

  @override
  Widget build(BuildContext context) {
    final subs = ref.watch(subscriptionsStreamProvider).valueOrNull ?? const [];
    final totals = ref.watch(subscriptionTotalsProvider);
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = dark ? const Color(0xFF14221F) : Colors.white;
    final pad = widget.embed ? 20.0 : 16.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.showTitle)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 16, 4),
            child: Row(children: [
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.arrow_back_rounded),
              ),
              const SizedBox(width: 4),
              const Text('Subscriptions',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            ]),
          ),
        // Toolbar (Select / Add)
        Padding(
          padding: EdgeInsets.fromLTRB(pad, widget.showTitle ? 4 : 8, pad, 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (subs.isNotEmpty)
                _pill(
                  label: _selectMode ? '${_picked.length} selected' : 'Select',
                  icon: _selectMode ? Icons.close : Icons.checklist_rounded,
                  active: _selectMode,
                  onTap: () => setState(() {
                    _selectMode = !_selectMode;
                    _picked.clear();
                  }),
                ),
              const SizedBox(width: 8),
              _pill(
                label: 'Add',
                icon: Icons.add_rounded,
                filled: true,
                onTap: () => showAddSubSheet(context, ref),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: EdgeInsets.fromLTRB(pad, 4, pad, widget.embed ? 130 : 30),
            children: [
              // Violet recurring header
              Container(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
                decoration: BoxDecoration(
                  gradient: AerisColors.violetGradient,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                        color: const Color(0xFF8B5CF6).withValues(alpha: 0.32),
                        blurRadius: 22,
                        offset: const Offset(0, 8)),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Recurring per month',
                        style: TextStyle(
                            color: Colors.white70,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text(formatRupees(totals.monthly),
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 30,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5)),
                    const SizedBox(height: 4),
                    Text(
                      '${formatRupees(totals.yearly)} a year across '
                      '${totals.count} service${totals.count == 1 ? '' : 's'}',
                      style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              if (subs.isEmpty)
                _empty(context)
              else
                ...subs.map((s) => _subCard(s, cardBg, scheme)
                    .animate()
                    .fadeIn(duration: 220.ms)
                    .slideY(begin: 0.05, end: 0)),
            ],
          ),
        ),
        // Bulk action bar
        if (_selectMode && _picked.isNotEmpty)
          Container(
            padding: EdgeInsets.fromLTRB(pad, 10, pad, widget.embed ? 16 : 16),
            decoration: BoxDecoration(
              color: scheme.surface,
              border: Border(
                  top: BorderSide(
                      color: scheme.onSurface.withValues(alpha: 0.08))),
            ),
            child: Row(children: [
              _bulkBtn(
                label: 'Remove (${_picked.length})',
                icon: Icons.delete_outline_rounded,
                color: AerisColors.moneyOut(context),
                onTap: () async {
                  final uid = ref.read(currentUserIdProvider);
                  final fs = ref.read(firestoreServiceProvider);
                  if (uid != null) {
                    for (final id in _picked) {
                      await fs.deleteSubscription(uid, id);
                    }
                  }
                  setState(() {
                    _picked.clear();
                    _selectMode = false;
                  });
                },
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _bulkBtn(
                  label: 'Log payments (${_picked.length})',
                  icon: Icons.add_card_rounded,
                  color: AerisColors.seed,
                  filled: true,
                  onTap: () async {
                    final picked = subs.where((s) => _picked.contains(s.id));
                    // Ones already paid this month (logged or from the bank
                    // SMS) are skipped rather than counted twice.
                    var n = 0, skipped = 0;
                    for (final s in picked) {
                      if (subscriptionPaidThisMonth(ref, s) != null) {
                        skipped++;
                        continue;
                      }
                      await _logSubscriptionPayment(ref, s);
                      n++;
                    }
                    setState(() {
                      _picked.clear();
                      _selectMode = false;
                    });
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text(
                              'Logged $n payment${n == 1 ? '' : 's'}'
                              '${skipped == 0 ? '' : ' · $skipped already paid this month'}')));
                    }
                  },
                ),
              ),
            ]),
          ),
      ],
    );
  }

  Widget _subCard(Subscription s, Color cardBg, ColorScheme scheme) {
    final cat = Categories.byId(s.categoryId);
    final on = _picked.contains(s.id);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        onTap: _selectMode
            ? () =>
                setState(() => on ? _picked.remove(s.id) : _picked.add(s.id))
            : null,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
                color: on
                    ? AerisColors.seed
                    : scheme.onSurface.withValues(alpha: 0.08),
                width: on ? 1.5 : 1),
          ),
          child: Row(children: [
            if (_selectMode) ...[
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: on ? AerisColors.seed : Colors.transparent,
                  border: on
                      ? null
                      : Border.all(
                          color: scheme.onSurface.withValues(alpha: 0.3),
                          width: 2),
                ),
                child: on
                    ? const Icon(Icons.check, size: 16, color: Colors.white)
                    : null,
              ),
              const SizedBox(width: 12),
            ],
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: cat.color.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(cat.icon, size: 22, color: cat.color),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(s.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 14.5, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 2),
                  Text(_renew(s.day),
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: scheme.onSurfaceVariant)),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(formatRupees(s.amount),
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w800)),
                Text('monthly',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: scheme.onSurface.withValues(alpha: 0.4))),
              ],
            ),
            if (!_selectMode)
              IconButton(
                onPressed: () => showSubActionsSheet(context, ref, s),
                icon: Icon(Icons.more_vert,
                    size: 20, color: scheme.onSurfaceVariant),
              ),
          ]),
        ),
      ),
    );
  }

  Widget _empty(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(children: [
        Container(
          width: 68,
          height: 68,
          decoration: BoxDecoration(
              color: scheme.onSurface.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(22)),
          child: Icon(Icons.autorenew_rounded,
              size: 34, color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 14),
        const Text('No subscriptions yet',
            style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800)),
        const SizedBox(height: 5),
        Text('Track Netflix, Spotify, rent and more.',
            style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: () => showAddSubSheet(context, ref),
          style: FilledButton.styleFrom(
            backgroundColor: AerisColors.seed,
            foregroundColor: Colors.white,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
          ),
          child: const Text('Add subscription'),
        ),
      ]),
    );
  }

  Widget _pill(
      {required String label,
      required IconData icon,
      bool active = false,
      bool filled = false,
      required VoidCallback onTap}) {
    final scheme = Theme.of(context).colorScheme;
    final bg = filled
        ? AerisColors.seed
        : active
            ? AerisColors.seed.withValues(alpha: 0.14)
            : scheme.onSurface.withValues(alpha: 0.06);
    final fg = filled
        ? Colors.white
        : active
            ? AerisColors.seed
            : scheme.onSurface;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
        decoration:
            BoxDecoration(color: bg, borderRadius: BorderRadius.circular(99)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 16, color: fg),
          const SizedBox(width: 5),
          Text(label,
              style: TextStyle(
                  fontSize: 12.5, fontWeight: FontWeight.w700, color: fg)),
        ]),
      ),
    );
  }

  Widget _bulkBtn(
      {required String label,
      required IconData icon,
      required Color color,
      bool filled = false,
      required VoidCallback onTap}) {
    final child = Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: filled ? color : color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(icon, size: 17, color: filled ? Colors.white : color),
        const SizedBox(width: 6),
        Text(label,
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: filled ? Colors.white : color)),
      ]),
    );
    return GestureDetector(onTap: onTap, child: child);
  }
}

String _renew(int day) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  var next = DateTime(now.year, now.month, day);
  if (next.isBefore(today)) next = DateTime(now.year, now.month + 1, day);
  final diff = next.difference(today).inDays;
  final when = diff == 0
      ? 'today'
      : diff == 1
          ? 'tomorrow'
          : 'in $diff days';
  return 'Renews $when · day $day';
}

// ── Add / edit subscription sheet ────────────────────────────────────────────
void showAddSubSheet(BuildContext context, WidgetRef ref,
    {Subscription? edit}) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (_) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: _AddSubSheet(edit: edit),
    ),
  );
}

class _AddSubSheet extends ConsumerStatefulWidget {
  final Subscription? edit;
  const _AddSubSheet({this.edit});
  @override
  ConsumerState<_AddSubSheet> createState() => _AddSubSheetState();
}

class _AddSubSheetState extends ConsumerState<_AddSubSheet> {
  late final TextEditingController _name =
      TextEditingController(text: widget.edit?.name ?? '');
  late final TextEditingController _amount = TextEditingController(
      text: inrToDisplayText(widget.edit?.amount));
  late final TextEditingController _day =
      TextEditingController(text: '${widget.edit?.day ?? 1}');
  late String _cat = widget.edit?.categoryId ?? 'bills';

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    _day.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final amount = displayToInr(_amount.text) ?? 0; // display currency → INR
    if (name.isEmpty || amount <= 0) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Add a name and amount')));
      return;
    }
    final day = (int.tryParse(_day.text.trim()) ?? 1).clamp(1, 28);
    final uid = ref.read(currentUserIdProvider);
    if (uid == null) return;
    final sub = (widget.edit ??
            Subscription(
                id: 'sb_${DateTime.now().microsecondsSinceEpoch}',
                name: name,
                amount: amount,
                categoryId: _cat,
                day: day))
        .copyWith(name: name, amount: amount, categoryId: _cat, day: day);
    await ref.read(firestoreServiceProvider).setSubscription(uid, sub);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 4, 18, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(widget.edit == null ? 'Add subscription' : 'Edit subscription',
              style:
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 14),
          _label('Quick pick'),
          const SizedBox(height: 8),
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final c in _subCatalog)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: GestureDetector(
                      onTap: () => setState(() {
                        _name.text = c.$1;
                        _cat = c.$2;
                        _amount.text = c.$3.toStringAsFixed(0);
                      }),
                      child: Container(
                        alignment: Alignment.center,
                        padding: const EdgeInsets.symmetric(horizontal: 13),
                        decoration: BoxDecoration(
                          color: _name.text == c.$1
                              ? AerisColors.seed.withValues(alpha: 0.14)
                              : scheme.onSurface.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(99),
                          border: Border.all(
                              color: _name.text == c.$1
                                  ? AerisColors.seed
                                  : scheme.onSurface.withValues(alpha: 0.1)),
                        ),
                        child: Text(c.$1,
                            style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                color: _name.text == c.$1
                                    ? AerisColors.ink(context)
                                    : scheme.onSurface)),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _field(_name, Icons.subscriptions_outlined, 'Service name'),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: _field(_amount, Icons.payments_outlined, 'Amount',
                  number: true),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 110,
              child: _field(_day, Icons.event_outlined, 'Day', number: true),
            ),
          ]),
          const SizedBox(height: 16),
          _label('Category'),
          const SizedBox(height: 8),
          SizedBox(
            height: 76,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final c in Categories.all)
                  Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: GestureDetector(
                      onTap: () => setState(() => _cat = c.id),
                      child: SizedBox(
                        width: 58,
                        child: Column(children: [
                          Container(
                            width: 46,
                            height: 46,
                            decoration: BoxDecoration(
                              color: _cat == c.id
                                  ? c.color
                                  : scheme.onSurface.withValues(alpha: 0.05),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Icon(c.icon,
                                size: 22,
                                color: _cat == c.id
                                    ? Colors.white
                                    : scheme.onSurfaceVariant),
                          ),
                          const SizedBox(height: 4),
                          Text(c.label.split(' ').first,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w700,
                                  color: _cat == c.id
                                      ? scheme.onSurface
                                      : scheme.onSurfaceVariant)),
                        ]),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _save,
              style: FilledButton.styleFrom(
                backgroundColor: AerisColors.seed,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                textStyle:
                    const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
              ),
              child: Text(
                  widget.edit == null ? 'Add subscription' : 'Save changes'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _label(String s) => Text(s.toUpperCase(),
      style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.5,
          color: Theme.of(context).colorScheme.onSurfaceVariant));

  Widget _field(TextEditingController c, IconData icon, String hint,
      {bool number = false}) {
    final scheme = Theme.of(context).colorScheme;
    return TextField(
      controller: c,
      keyboardType: number ? TextInputType.number : TextInputType.text,
      onChanged: (_) => setState(() {}),
      style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600),
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: Icon(icon, size: 19, color: scheme.onSurfaceVariant),
        filled: true,
        fillColor: scheme.onSurface.withValues(alpha: 0.05),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(13),
            borderSide:
                BorderSide(color: scheme.onSurface.withValues(alpha: 0.1))),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(13),
            borderSide:
                BorderSide(color: scheme.onSurface.withValues(alpha: 0.1))),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(13),
            borderSide: const BorderSide(color: AerisColors.seed, width: 1.4)),
      ),
    );
  }
}

// ── Subscription actions sheet ───────────────────────────────────────────────
void showSubActionsSheet(BuildContext context, WidgetRef ref, Subscription s) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (ctx) {
      Widget row(IconData icon, String label, VoidCallback onTap,
          {bool danger = false}) {
        final color =
            danger ? AerisColors.moneyOut(context) : Theme.of(ctx).colorScheme.onSurface;
        return ListTile(
          leading:
              Icon(icon, color: danger ? AerisColors.moneyOut(context) : AerisColors.seed),
          title: Text(label,
              style: TextStyle(fontWeight: FontWeight.w700, color: color)),
          onTap: onTap,
        );
      }

      return SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: CircleAvatar(
              backgroundColor:
                  Categories.byId(s.categoryId).color.withValues(alpha: 0.16),
              child: Icon(Categories.byId(s.categoryId).icon,
                  color: Categories.byId(s.categoryId).color),
            ),
            title: Text(s.name,
                style: const TextStyle(fontWeight: FontWeight.w800)),
            subtitle: Text('${formatRupees(s.amount)} · day ${s.day}'),
          ),
          const Divider(height: 1),
          row(Icons.add_card_rounded, "Log this month's payment", () async {
            Navigator.pop(ctx);
            final already = subscriptionPaidThisMonth(ref, s);
            if (already != null) {
              final again = await showDialog<bool>(
                context: context,
                builder: (d) => AlertDialog(
                  icon: const Icon(Icons.copy_all_outlined),
                  title: const Text('Already paid this month?'),
                  content: Text('There is already a '
                      '${formatRupees(s.amount, raw: true)} payment to '
                      '${already.merchant ?? s.name} on '
                      '${relativeDate(already.timestamp).toLowerCase()}.\n\n'
                      'Log another one?'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(d, false),
                        child: const Text('Cancel')),
                    FilledButton(
                        onPressed: () => Navigator.pop(d, true),
                        child: const Text('Log again')),
                  ],
                ),
              );
              if (again != true) return;
            }
            await _logSubscriptionPayment(ref, s);
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Payment logged')));
            }
          }),
          row(Icons.edit_outlined, 'Edit subscription', () {
            Navigator.pop(ctx);
            showAddSubSheet(context, ref, edit: s);
          }),
          row(Icons.delete_outline_rounded, 'Remove subscription', () async {
            Navigator.pop(ctx);
            final uid = ref.read(currentUserIdProvider);
            if (uid != null) {
              await ref
                  .read(firestoreServiceProvider)
                  .deleteSubscription(uid, s.id);
            }
          }, danger: true),
          const SizedBox(height: 8),
        ]),
      );
    },
  );
}

/// This month's payment for [s] if one is already recorded — logged by hand
/// or imported from the bank SMS (same amount, name matching the merchant).
Transaction? subscriptionPaidThisMonth(WidgetRef ref, Subscription s) {
  final now = DateTime.now();
  final name = s.name.trim().toLowerCase();
  final txns = ref.read(transactionsStreamProvider).valueOrNull ?? const [];
  for (final t in txns) {
    if (!t.isDebit ||
        t.timestamp.year != now.year ||
        t.timestamp.month != now.month ||
        (t.amount - s.amount).abs() >= 0.01) {
      continue;
    }
    final m = (t.merchant ?? '').trim().toLowerCase();
    if (m.isNotEmpty && (m.contains(name) || name.contains(m))) return t;
  }
  return null;
}

Future<void> _logSubscriptionPayment(WidgetRef ref, Subscription s) async {
  final uid = ref.read(currentUserIdProvider);
  if (uid == null) return;
  await ref.read(firestoreServiceProvider).addTransaction(
        uid,
        Transaction(
          id: 'sub_${DateTime.now().microsecondsSinceEpoch}',
          amount: s.amount,
          direction: TxnDirection.debit,
          timestamp: DateTime.now(),
          categoryId: s.categoryId,
          merchant: s.name,
          note: 'Subscription',
          source: TxnSource.recurring,
        ),
      );
}
