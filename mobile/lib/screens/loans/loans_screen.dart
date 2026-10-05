import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/theme.dart';
import '../../models/loan.dart';
import '../../providers/auth_provider.dart';
import '../../providers/loans_provider.dart';
import '../../providers/transactions_provider.dart';
import '../../utils/amount_input_formatter.dart';
import '../../utils/formatters.dart';
import '../../widgets/discard_guard.dart';
<<<<<<< HEAD
import '../../widgets/aeris_toast.dart';
=======
import '../../widgets/field_editor.dart';
>>>>>>> 03b46533542cdba8b0b640a9e2a5977620e74684

/// "Lent" tab — money given to (or borrowed from) friends, tracked until
/// it comes back. Each entry is Pending until marked settled.
class LoansScreen extends ConsumerWidget {
  /// Route argument that opens the "add" sheet as soon as the screen shows —
  /// used by the add-transaction screen's "Lent or borrowed?" shortcut.
  static const openAddSheet = 'add';

  final bool openAdd;
  const LoansScreen({super.key, this.openAdd = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loansAsync = ref.watch(loansStreamProvider);
    final totals = ref.watch(loanTotalsProvider);
    final screen = _screen(context, ref, loansAsync, totals);
    return openAdd ? _OpenAddOnce(child: screen) : screen;
  }

  Widget _screen(BuildContext context, WidgetRef ref,
      AsyncValue<List<Loan>> loansAsync, LoanTotals totals) {
    return Scaffold(
      appBar: AppBar(title: const Text('Lent & borrowed')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showAddLoanSheet(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Add'),
      ),
      body: loansAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (loans) {
          final pending = loans.where((l) => !l.isSettled).toList();
          final settled = loans.where((l) => l.isSettled).toList();
          return ListView(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 96),
            children: [
              _summaryCard(context, totals),
              const SizedBox(height: 16),
              if (loans.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 60),
                  child: Column(
                    children: [
                      Icon(Icons.handshake_outlined,
                          size: 56,
                          color: Theme.of(context)
                              .colorScheme
                              .onSurfaceVariant
                              .withValues(alpha: 0.4)),
                      const SizedBox(height: 12),
                      Text('Nothing tracked yet',
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 4),
                      Text(
                        'Gave money to a friend? Add it here and\nmark it when you get it back.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 13,
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              if (pending.isNotEmpty) ...[
                _sectionTitle(context, 'Pending · ${pending.length}'),
                for (final l in pending) _loanTile(context, ref, l),
              ],
              if (settled.isNotEmpty) ...[
                const SizedBox(height: 10),
                _sectionTitle(context, 'Settled · ${settled.length}'),
                for (final l in settled) _loanTile(context, ref, l),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _summaryCard(BuildContext context, LoanTotals t) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Owed to you',
                      style: TextStyle(fontSize: 12, color: Colors.grey)),
                  const SizedBox(height: 2),
                  Text(formatRupees(t.owedToYou),
                      style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: AerisColors.moneyIn(context))),
                ],
              ),
            ),
            Container(
                width: 1,
                height: 36,
                color: Theme.of(context).dividerColor.withValues(alpha: 0.4)),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('You owe',
                      style: TextStyle(fontSize: 12, color: Colors.grey)),
                  const SizedBox(height: 2),
                  Text(formatRupees(t.youOwe),
                      style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: AerisColors.moneyOut(context))),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 10, 4, 6),
        child: Text(text,
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Theme.of(context).colorScheme.onSurfaceVariant)),
      );

  Widget _loanTile(BuildContext context, WidgetRef ref, Loan l) {
    final scheme = Theme.of(context).colorScheme;
    final color = l.borrowed
        ? AerisColors.moneyOut(context)
        : AerisColors.moneyIn(context);
    final initial = l.person.isEmpty ? '?' : l.person[0].toUpperCase();
    final when = '${l.createdAt.day}/${l.createdAt.month}/${l.createdAt.year}';
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        onTap: () => showLoanDetailSheet(context, ref, l),
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.18),
          child: Text(initial,
              style: TextStyle(color: color, fontWeight: FontWeight.w800)),
        ),
        title: Text(l.person,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              decoration: l.isSettled ? TextDecoration.lineThrough : null,
            )),
        subtitle: Text(
          [
            l.borrowed ? 'You borrowed' : 'You lent',
            when,
            if (l.note.isNotEmpty) l.note,
          ].join(' · '),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12),
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(formatRupees(l.amount),
                style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    color: l.isSettled ? scheme.onSurfaceVariant : color)),
            const SizedBox(height: 2),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: l.isSettled
                    ? AerisColors.moneyIn(context).withValues(alpha: 0.15)
                    : AerisColors.warning.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                l.isSettled ? 'Received' : 'Pending',
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: l.isSettled
                        ? AerisColors.moneyIn(context)
                        : const Color(0xFFB45309)),
              ),
            ),
          ],
        ),
      ),
    );
  }
<<<<<<< HEAD

  // ── Actions ───────────────────────────────────────────────

  void _detailSheet(BuildContext context, WidgetRef ref, Loan l) {
    final messenger = ScaffoldMessenger.of(context);
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(l.person,
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 17)),
              subtitle: Text(
                  '${l.borrowed ? 'You borrowed' : 'You lent'} ${formatRupees(l.amount)}'
                  '${l.note.isNotEmpty ? ' · ${l.note}' : ''}'),
            ),
            if (!l.isSettled)
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Color(0x3322C55E),
                  child: Icon(Icons.check, color: Color(0xFF22C55E)),
                ),
                title:
                    Text(l.borrowed ? 'Mark as paid back' : 'Mark as received'),
                subtitle: const Text('Moves it to Settled'),
                onTap: () async {
                  Navigator.pop(ctx);
                  await _saveLoan(ref, l.copyWith(settledAt: DateTime.now()));
                  messenger.showToast(SnackBar(
                      content: Text(l.borrowed
                          ? 'Marked as paid back ✓'
                          : 'Marked as received ✓')));
                },
              )
            else
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Color(0x33F59E0B),
                  child: Icon(Icons.undo, color: Color(0xFFF59E0B)),
                ),
                title: const Text('Mark as pending again'),
                onTap: () async {
                  Navigator.pop(ctx);
                  await _saveLoan(ref, l.copyWith(settledAt: null));
                },
              ),
            ListTile(
              leading: const CircleAvatar(
                backgroundColor: Color(0x33EF4444),
                child: Icon(Icons.delete_outline, color: Color(0xFFEF4444)),
              ),
              title: const Text('Delete'),
              onTap: () async {
                Navigator.pop(ctx);
                final uid = ref.read(currentUserIdProvider);
                if (uid == null) return;
                await ref.read(firestoreServiceProvider).deleteLoan(uid, l.id);
              },
            ),
          ],
        ),
      ),
    );
  }
=======
>>>>>>> 03b46533542cdba8b0b640a9e2a5977620e74684
}

/// Saves [l]; a failure is shown on [messenger] instead of being lost.
Future<void> _saveLoan(
    WidgetRef ref, Loan l, ScaffoldMessengerState messenger) async {
  final uid = ref.read(currentUserIdProvider);
  if (uid == null) return;
  try {
    await ref.read(firestoreServiceProvider).setLoan(uid, l);
  } catch (err) {
    messenger.showSnackBar(SnackBar(content: Text('Could not save: $err')));
  }
}

/// Opens the "Add entry" sheet for tracking a new lent/borrowed payment —
/// reachable both from the Lent screen's FAB and the home radial FAB.
/// Opens the add sheet once, right after the screen's first frame. Its own
/// [ref] outlives the sheet (it lives as long as the Loans screen), so the
/// sheet's save callback always has a live ref.
class _OpenAddOnce extends ConsumerStatefulWidget {
  final Widget child;
  const _OpenAddOnce({required this.child});

  @override
  ConsumerState<_OpenAddOnce> createState() => _OpenAddOnceState();
}

class _OpenAddOnceState extends ConsumerState<_OpenAddOnce> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) showAddLoanSheet(context, ref);
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

void showAddLoanSheet(BuildContext context, WidgetRef ref) {
  final messenger = ScaffoldMessenger.of(context);
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    // Swipe-to-dismiss bypasses the discard guard, so it's off here; the
    // close button, back gesture and scrim tap all ask before discarding.
    enableDrag: false,
    builder: (_) => _AddLoanSheet(onSave: (l) => _saveLoan(ref, l, messenger)),
  );
}

class _AddLoanSheet extends StatefulWidget {
  final Future<void> Function(Loan) onSave;
  const _AddLoanSheet({required this.onSave});

  @override
  State<_AddLoanSheet> createState() => _AddLoanSheetState();
}

class _AddLoanSheetState extends State<_AddLoanSheet> {
  final _person = TextEditingController();
  final _amount = TextEditingController();
  final _note = TextEditingController();
  bool _borrowed = false;
  bool _tried = false; // show field errors only after a save attempt

  @override
  void initState() {
    super.initState();
    for (final c in [_person, _amount, _note]) {
      c.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    _person.dispose();
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  bool get _dirty =>
      _person.text.trim().isNotEmpty ||
      _amount.text.trim().isNotEmpty ||
      _note.text.trim().isNotEmpty;

  /// Typed in the display currency, stored in INR like every other amount.
  double? get _amountValue {
    final v = evalAmount(_amount.text);
    return v == null ? null : (v * kCurrency.rate * 100).roundToDouble() / 100;
  }

  void _submit() {
    final name = _person.text.trim();
    final amt = _amountValue;
    if (name.isEmpty || amt == null) {
      setState(() => _tried = true);
      HapticFeedback.heavyImpact();
      return;
    }
    final loan = Loan(
      id: const Uuid().v4(),
      person: name,
      amount: amt,
      note: _note.text.trim(),
      borrowed: _borrowed,
      createdAt: DateTime.now(),
    );
    final messenger = ScaffoldMessenger.of(context);
    Navigator.pop(context);
    widget.onSave(loan);
    HapticFeedback.mediumImpact();
    messenger.showToast(SnackBar(
        content: Text(_borrowed
            ? 'Noted: you owe $name ${formatRupees(amt, raw: true)}'
            : 'Noted: $name owes you ${formatRupees(amt, raw: true)}')));
  }

  @override
  Widget build(BuildContext context) {
    return DiscardGuard(
      dirty: _dirty,
      title: 'Discard this entry?',
      child: Padding(
        padding: EdgeInsets.fromLTRB(
            20, 8, 20, MediaQuery.of(context).viewInsets.bottom + 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text('Add entry',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                ),
                IconButton(
                  tooltip: 'Close',
                  icon: const Icon(Icons.close),
                  // maybePop → goes through the discard guard.
                  onPressed: () => Navigator.maybePop(context),
                ),
              ],
            ),
            const SizedBox(height: 6),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(
                    value: false,
                    label: Text('I gave money'),
                    icon: Icon(Icons.north_east, size: 16)),
                ButtonSegment(
                    value: true,
                    label: Text('I borrowed'),
                    icon: Icon(Icons.south_west, size: 16)),
              ],
              selected: {_borrowed},
              onSelectionChanged: (s) => setState(() => _borrowed = s.first),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _person,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: "Friend's name",
                prefixIcon: const Icon(Icons.person_outline),
                errorText:
                    _tried && _person.text.trim().isEmpty ? 'Who is it?' : null,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _amount,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: const [AmountInputFormatter()],
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: 'Amount',
                prefixText: '${kCurrency.symbol.trim()} ',
                prefixIcon: const Icon(Icons.payments_outlined),
                errorText: _tried && _amountValue == null
                    ? 'Enter an amount greater than 0'
                    : null,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _note,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
              decoration: const InputDecoration(
                labelText: 'Note (optional)',
                hintText: 'e.g. movie tickets, trip',
                prefixIcon: Icon(Icons.notes),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(50)),
              onPressed: _submit,
              child: const Text('Add entry'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Details for one lent/borrowed entry — used by the Lent tab and the
/// Lent & borrowed screen. Each row (name, amount, note, type) opens a small
/// editor for just that field; the actions below settle or delete it.
void showLoanDetailSheet(BuildContext context, WidgetRef ref, Loan loan) {
  final messenger = ScaffoldMessenger.of(context);
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => _LoanDetailSheet(
      loan: loan,
      onSave: (l) => _saveLoan(ref, l, messenger),
      onDelete: () async {
        final uid = ref.read(currentUserIdProvider);
        if (uid == null) return;
        try {
          await ref.read(firestoreServiceProvider).deleteLoan(uid, loan.id);
        } catch (err) {
          messenger
              .showSnackBar(SnackBar(content: Text('Could not delete: $err')));
        }
      },
      messenger: messenger,
    ),
  );
}

class _LoanDetailSheet extends StatefulWidget {
  final Loan loan;
  final Future<void> Function(Loan) onSave;
  final Future<void> Function() onDelete;
  final ScaffoldMessengerState messenger;
  const _LoanDetailSheet({
    required this.loan,
    required this.onSave,
    required this.onDelete,
    required this.messenger,
  });

  @override
  State<_LoanDetailSheet> createState() => _LoanDetailSheetState();
}

class _LoanDetailSheetState extends State<_LoanDetailSheet> {
  late Loan _l = widget.loan;

  Future<void> _update(Loan next) async {
    setState(() => _l = next);
    await widget.onSave(next);
  }

  Future<void> _editPerson() async {
    final v = await editTextField(context,
        title: "Friend's name",
        initial: _l.person,
        icon: Icons.person_outline,
        maxLength: 60,
        required: true,
        capitalization: TextCapitalization.words);
    if (v == null || v.isEmpty || v == _l.person) return;
    await _update(_l.copyWith(person: v));
  }

  Future<void> _editAmount() async {
    final v = await editAmountField(context,
        title: _l.borrowed ? 'Amount borrowed' : 'Amount lent',
        initialInr: _l.amount);
    if (v == null || v == _l.amount) return;
    await _update(_l.copyWith(amount: v, paid: _l.paid.clamp(0.0, v)));
  }

  Future<void> _editNote() async {
    final v = await editTextField(context,
        title: 'Note',
        initial: _l.note,
        hint: 'e.g. movie tickets, trip',
        icon: Icons.notes_rounded,
        multiline: true);
    if (v == null || v == _l.note) return;
    await _update(_l.copyWith(note: v));
  }

  Future<void> _editType() async {
    final picked = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (s) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (borrowed, label, icon) in const [
              (false, 'I gave money', Icons.north_east),
              (true, 'I borrowed', Icons.south_west),
            ])
              ListTile(
                leading: Icon(icon),
                title: Text(label),
                trailing: borrowed == _l.borrowed
                    ? Icon(Icons.check_rounded,
                        color: Theme.of(context).colorScheme.primary)
                    : null,
                onTap: () => Navigator.pop(s, borrowed),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (picked == null || picked == _l.borrowed) return;
    await _update(_l.copyWith(borrowed: picked));
  }

  Future<void> _recordPartial() async {
    final entered = await editAmountField(context,
        title: 'Record repayment · ${formatRupees(_l.outstanding)} left',
        initialInr: _l.outstanding);
    if (entered == null || entered <= 0) return;
    final newPaid = (_l.paid + entered).clamp(0.0, _l.amount);
    final fully = newPaid >= _l.amount;
    await _update(
        _l.copyWith(paid: newPaid, settledAt: fully ? DateTime.now() : null));
    widget.messenger.showSnackBar(SnackBar(
        content: Text(fully
            ? 'Settled in full 🎉'
            : 'Recorded ${formatRupees(entered)}')));
  }

  Widget _row(String label, String value, VoidCallback onTap) => ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20),
        title: Text(label),
        subtitle: Text(value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        trailing: const Icon(Icons.edit, size: 18),
        onTap: onTap,
      );

  Widget _action(IconData icon, Color color, String title, VoidCallback onTap,
          {String? subtitle}) =>
      ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20),
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.18),
          child: Icon(icon, color: color),
        ),
        title: Text(title),
        subtitle: subtitle == null ? null : Text(subtitle),
        onTap: onTap,
      );

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l = _l;
    return SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _row("Friend's name", l.person, _editPerson),
            _row('Type', l.borrowed ? 'I borrowed' : 'I gave money',
                _editType),
            _row('Amount', formatRupees(l.amount, decimals: true),
                _editAmount),
            _row('Note', l.note.isEmpty ? 'Add a note' : l.note, _editNote),
            if (!l.isSettled && l.paid > 0)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Text(
                          '${formatRupees(l.paid)} of ${formatRupees(l.amount)} back',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: scheme.onSurfaceVariant)),
                      const Spacer(),
                      Text('${(l.paid / l.amount * 100).round()}%',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: AerisColors.ink(context))),
                    ]),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(99),
                      child: LinearProgressIndicator(
                        value: (l.paid / l.amount).clamp(0.0, 1.0),
                        minHeight: 6,
                        backgroundColor: scheme.surfaceContainerHighest,
                        color: AerisColors.seed,
                      ),
                    ),
                  ],
                ),
              ),
            const Divider(height: 16),
            if (!l.isSettled) ...[
              _action(
                Icons.check,
                AerisColors.moneyIn(context),
                l.borrowed ? 'Mark as paid back' : 'Mark as received',
                subtitle: 'Moves it to Settled',
                () async {
                  Navigator.pop(context);
                  await widget.onSave(
                      l.copyWith(paid: l.amount, settledAt: DateTime.now()));
                  widget.messenger.showSnackBar(SnackBar(
                      content: Text(l.borrowed
                          ? 'Marked as paid back ✓'
                          : 'Marked as received ✓')));
                },
              ),
              _action(Icons.add_card, AerisColors.seed,
                  'Record partial repayment', _recordPartial),
            ] else
              _action(Icons.undo, AerisColors.warning, 'Mark as pending again',
                  () async {
                Navigator.pop(context);
                await widget.onSave(l.copyWith(paid: 0, settledAt: null));
              }),
            _action(Icons.delete_outline, scheme.error, 'Delete', () async {
              Navigator.pop(context);
              await widget.onDelete();
            }),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
