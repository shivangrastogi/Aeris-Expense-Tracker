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
import '../../widgets/field_editor.dart';
import '../../widgets/aeris_toast.dart';
import '../../widgets/ds.dart';

/// "Lent" tab — money given to (or borrowed from) friends, tracked until
/// it comes back. Each entry is Pending until marked settled.
class LoansScreen extends ConsumerWidget {
  /// Route argument that opens the "add" sheet as soon as the screen shows —
  /// used by the add-transaction screen's "Lent or borrowed?" shortcut.
  static const openAddSheet = 'add';

  final bool openAdd;

  /// Shown as a tab inside People (no title bar of its own).
  final bool embedded;
  const LoansScreen({super.key, this.openAdd = false, this.embedded = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loansAsync = ref.watch(loansStreamProvider);
    final totals = ref.watch(loanTotalsProvider);
    final screen = _screen(context, ref, loansAsync, totals);
    return openAdd ? _OpenAddOnce(child: screen) : screen;
  }

  Widget _screen(BuildContext context, WidgetRef ref,
      AsyncValue<List<Loan>> loansAsync, LoanTotals totals) {
    final tk = context.tk;
    return Scaffold(
      appBar: embedded ? null : AppBar(title: const Text('Lent and borrowed')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showAddLoanSheet(context, ref),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Rad.button)),
        icon: const Icon(PhBold.plus, size: 20),
        label: const Text('Add',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
      ),
      body: loansAsync.when(
        loading: () => const Center(child: RisingLoader()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Banner2(
                tone: Tone.bad,
                icon: PhFill.cloudX,
                title: "Couldn't load lent and borrowed",
                body: '$e'),
          ),
        ),
        data: (loans) {
          final pending = loans.where((l) => !l.isSettled).toList();
          final settled = loans.where((l) => l.isSettled).toList();
          final lentPending = pending.where((l) => !l.borrowed).length;
          final borrowedPending = pending.where((l) => l.borrowed).length;
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 96),
            children: [
              _summaryCard(context, totals, lentPending, borrowedPending),
              const SizedBox(height: 16),
              if (loans.isEmpty)
                const EmptyState(
                  icon: Ph.handshake,
                  title: 'Nothing tracked yet',
                  body: 'Gave money to a friend? Add it here and mark it when '
                      'you get it back.',
                ),
              if (pending.isNotEmpty) ...[
                _sectionTitle('Pending'),
                ListGroup(children: [
                  for (final l in pending) _loanTile(context, ref, l),
                ]),
              ],
              if (settled.isNotEmpty) ...[
                const SizedBox(height: 16),
                _sectionTitle('Settled'),
                ListGroup(children: [
                  for (final l in settled) _loanTile(context, ref, l),
                ]),
              ],
              if (loans.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text('Tap an entry to record a part payment or edit it.',
                    style: Ts.label.copyWith(
                        fontWeight: FontWeight.w400, color: tk.t3)),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _summaryCard(
      BuildContext context, LoanTotals t, int lentPending, int borrowedPending) {
    final tk = context.tk;
    Widget half(String label, double v, Color c, String sub) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: Ts.bodyS.copyWith(color: tk.t2)),
              MoneyText(v, color: c, smallSymbol: false, style: Ts.amountL),
              Text(sub,
                  style: Ts.label
                      .copyWith(fontWeight: FontWeight.w400, color: tk.t2)),
            ],
          ),
        );
    return AerisCard(
      padding: const EdgeInsets.all(16),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            half('You lent', t.owedToYou, t.owedToYou > 0 ? tk.ok : tk.t1,
                lentPending == 0 ? 'All clear' : '$lentPending pending'),
            Container(
                width: 1,
                margin: const EdgeInsets.symmetric(horizontal: 16),
                color: tk.hair),
            half('You borrowed', t.youOwe, tk.t1,
                borrowedPending == 0 ? 'All clear' : '$borrowedPending pending'),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
        child: Overline(text),
      );

  Widget _loanTile(BuildContext context, WidgetRef ref, Loan l) {
    final tk = context.tk;
    final when = shortDate(l.settledAt ?? l.createdAt);
    final what = l.note.isNotEmpty
        ? l.note
        : (l.borrowed ? 'You borrowed' : 'You lent');
    // Settled rows stay plain (never struck through) — a check marks them.
    return DsRow(
      onTap: () => showLoanDetailSheet(context, ref, l),
      leading: InitialAvatar(l.person),
      title: l.person.isEmpty ? '?' : l.person,
      titleMaxLines: 1,
      sub: l.isSettled ? '$what · settled $when' : '$what · $when',
      trailing: l.isSettled
          ? Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(PhBold.check, size: 14, color: tk.ok),
              const SizedBox(width: 6),
              MoneyText(l.amount,
                  color: tk.t2,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w600)),
            ])
          : Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                MoneyText(l.amount - l.paid,
                    color: l.borrowed ? tk.t1 : tk.ok,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w700)),
                InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => _saveLoan(
                      ref,
                      l.copyWith(paid: l.amount, settledAt: DateTime.now()),
                      ScaffoldMessenger.of(context)),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                    child: Text('Mark settled',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: tk.acc)),
                  ),
                ),
              ],
            ),
    );
  }

  // ── Actions ───────────────────────────────────────────────
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
                  icon: const Icon(Ph.x),
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
                    icon: Icon(Ph.arrowUpRight, size: 16)),
                ButtonSegment(
                    value: true,
                    label: Text('I borrowed'),
                    icon: Icon(Ph.arrowDownLeft, size: 16)),
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
                prefixIcon: const Icon(Ph.user),
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
                prefixIcon: const Icon(Ph.money),
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
                prefixIcon: Icon(Ph.note),
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
        icon: Ph.user,
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
        icon: Ph.note,
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
              (false, 'I gave money', Ph.arrowUpRight),
              (true, 'I borrowed', Ph.arrowDownLeft),
            ])
              ListTile(
                leading: Icon(icon),
                title: Text(label),
                trailing: borrowed == _l.borrowed
                    ? Icon(Ph.check,
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
        trailing: const Icon(Ph.pencilSimple, size: 18),
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
                        color: context.tk.acc,
                      ),
                    ),
                  ],
                ),
              ),
            const Divider(height: 16),
            if (!l.isSettled) ...[
              _action(
                Ph.check,
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
              _action(Ph.creditCard, context.tk.acc,
                  'Record partial repayment', _recordPartial),
            ] else
              _action(Ph.arrowCounterClockwise, context.tk.warn, 'Mark as pending again',
                  () async {
                Navigator.pop(context);
                await widget.onSave(l.copyWith(paid: 0, settledAt: null));
              }),
            _action(Ph.trash, scheme.error, 'Delete', () async {
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
