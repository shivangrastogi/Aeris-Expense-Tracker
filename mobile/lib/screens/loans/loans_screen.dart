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

/// "Lent" tab — money given to (or borrowed from) friends, tracked until
/// it comes back. Each entry is Pending until marked settled.
class LoansScreen extends ConsumerWidget {
  const LoansScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loansAsync = ref.watch(loansStreamProvider);
    final totals = ref.watch(loanTotalsProvider);
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
    final color = l.borrowed ? AerisColors.moneyOut(context) : AerisColors.moneyIn(context);
    final initial = l.person.isEmpty ? '?' : l.person[0].toUpperCase();
    final when = '${l.createdAt.day}/${l.createdAt.month}/${l.createdAt.year}';
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        onTap: () => _detailSheet(context, ref, l),
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
                  messenger.showSnackBar(SnackBar(
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
}

Future<void> _saveLoan(WidgetRef ref, Loan l) async {
  final uid = ref.read(currentUserIdProvider);
  if (uid == null) return;
  await ref.read(firestoreServiceProvider).setLoan(uid, l);
}

/// Opens the "Add entry" sheet for tracking a new lent/borrowed payment —
/// reachable both from the Lent screen's FAB and the home radial FAB.
void showAddLoanSheet(BuildContext context, WidgetRef ref) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    // Swipe-to-dismiss bypasses the discard guard, so it's off here; the
    // close button, back gesture and scrim tap all ask before discarding.
    enableDrag: false,
    builder: (_) => _AddLoanSheet(onSave: (l) => _saveLoan(ref, l)),
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
    messenger.showSnackBar(SnackBar(
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
                border: const OutlineInputBorder(),
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
                border: const OutlineInputBorder(),
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
                border: OutlineInputBorder(),
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
