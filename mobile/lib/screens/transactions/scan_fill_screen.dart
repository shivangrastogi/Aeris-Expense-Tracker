import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../core/theme.dart';
import '../../models/transaction.dart';
import '../../services/scan_reader.dart';
import '../../utils/formatters.dart';
import '../../widgets/discard_guard.dart';
import '../../widgets/ds.dart';

/// A scanned photo that was missing something (or only guessed it): every
/// field it did read is prefilled, the missing ones are marked, and nothing
/// saves until they're filled. Pops the completed [ScanResult], or null to
/// skip this photo.
class ScanFillScreen extends StatefulWidget {
  final ScanResult scan;

  /// "2 of 3" when a batch had several photos to check.
  final int index, count;

  const ScanFillScreen(
      {super.key, required this.scan, this.index = 1, this.count = 1});

  @override
  State<ScanFillScreen> createState() => _ScanFillScreenState();
}

class _ScanFillScreenState extends State<ScanFillScreen> {
  late final _amount = TextEditingController(
      text: widget.scan.amount == null ? '' : _plain(widget.scan.amount!));
  late final _name = TextEditingController(text: widget.scan.name ?? '');
  late final _upi = TextEditingController(text: widget.scan.upiVpa ?? '');
  late final _note = TextEditingController(text: widget.scan.note ?? '');
  late TxnDirection? _dir = widget.scan.direction;
  late DateTime _when = widget.scan.when ?? DateTime.now();
  bool _tried = false; // Save was pressed: show what's still empty
  late final String _start = _snapshot();

  static final _vpaRe =
      RegExp(r'^[a-z0-9][a-z0-9._\-]{1,48}@[a-z][a-z0-9]{1,20}$');

  static String _plain(double v) =>
      v % 1 == 0 ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

  String _snapshot() => [
        _amount.text,
        _name.text,
        _upi.text,
        _note.text,
        _dir?.name ?? '',
        _when.millisecondsSinceEpoch,
      ].join('|');

  double? get _amountValue {
    final v = double.tryParse(_amount.text.replaceAll(',', '').trim());
    return v == null || v <= 0 ? null : v;
  }

  /// The UPI ID box: empty is fine, anything else must look like one.
  bool get _upiOk {
    final u = _upi.text.trim().toLowerCase();
    return u.isEmpty || _vpaRe.hasMatch(u);
  }

  bool _missing(ScanField f) => widget.scan.missing.contains(f);

  /// The date was read, but so long ago it's more likely a misread year.
  bool get _oldDate =>
      widget.scan.unsure.contains(ScanField.date) && _when == widget.scan.when;

  @override
  void dispose() {
    _amount.dispose();
    _name.dispose();
    _upi.dispose();
    _note.dispose();
    super.dispose();
  }

  void _save() {
    final amount = _amountValue;
    final name = _name.text.trim();
    if (amount == null || name.isEmpty || _dir == null || !_upiOk) {
      HapticFeedback.heavyImpact();
      setState(() => _tried = true);
      return;
    }
    final s = widget.scan;
    final upi = _upi.text.trim().toLowerCase();
    final note = _note.text.trim();
    Navigator.pop(
      context,
      ScanResult(
        kind: s.kind,
        amount: amount,
        direction: _dir,
        name: name,
        upiVpa: upi.isEmpty ? null : upi,
        when: _when,
        reference: s.reference,
        account: s.account,
        phone: s.phone,
        note: note.isEmpty ? null : note,
        category: s.category,
      ),
    );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _when.isAfter(DateTime(2015)) ? _when : DateTime.now(),
      firstDate: DateTime(2015),
      lastDate: DateTime.now(),
    );
    if (picked == null) return;
    setState(() => _when = DateTime(
        picked.year, picked.month, picked.day, _when.hour, _when.minute));
  }

  /// Under a field: where its value came from, or that it's needed.
  String? _helper(ScanField f, bool filled) {
    if (_missing(f)) return filled ? null : 'Not on the photo — please enter';
    if (widget.scan.unsure.contains(f)) return 'Read from the photo — check it';
    return 'Read from the photo';
  }

  String? _error(bool filled) => _tried && !filled ? 'Needed to save' : null;

  @override
  Widget build(BuildContext context) {
    final s = widget.scan;
    final muted = AerisColors.muted(context);
    final danger = AerisColors.danger(context);
    final missing = [
      for (final f in s.missing)
        switch (f) {
          ScanField.amount => 'amount',
          ScanField.name => 'name',
          ScanField.direction => 'paid or received',
          ScanField.date => 'date',
        },
    ];
    final whoLabel = switch (_dir) {
      TxnDirection.debit => 'Paid to',
      TxnDirection.credit => 'Received from',
      null => 'Name',
    };

    return DiscardGuard(
      dirty: _snapshot() != _start,
      title: 'Discard this scan?',
      message: "What you've typed here hasn't been saved.",
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.count > 1
              ? 'Check scan ${widget.index} of ${widget.count}'
              : 'Check scan'),
          actions: [
            TextButton(
              // maybePop, so typed-in details get the discard prompt.
              onPressed: () => Navigator.maybePop(context),
              child: Text(widget.count > 1 ? 'Skip' : 'Cancel'),
            ),
          ],
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AerisColors.accentSoft(context),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(missing.isEmpty ? Ph.checkCircle : Ph.warningCircle,
                          size: 20, color: AerisColors.accent(context)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          missing.isEmpty
                              ? 'Read from your ${s.kindLabel}. Some of it '
                                  'was guessed — check it before saving.'
                              : 'Read from your ${s.kindLabel}, but it has no '
                                  '${missing.join(', ')}. Fill that in below '
                                  '— everything else is prefilled.',
                          style: const TextStyle(height: 1.35),
                        ),
                      ),
                    ]),
              ),
              const SizedBox(height: 18),
              const SectionLabel('Paid or received'),
              SegmentedButton<TxnDirection>(
                segments: const [
                  ButtonSegment(
                      value: TxnDirection.debit,
                      icon: Icon(Ph.arrowUpRight, size: 16),
                      label: Text('Paid')),
                  ButtonSegment(
                      value: TxnDirection.credit,
                      icon: Icon(Ph.arrowDownLeft, size: 16),
                      label: Text('Received')),
                ],
                selected: {if (_dir != null) _dir!},
                emptySelectionAllowed: true,
                showSelectedIcon: false,
                onSelectionChanged: (v) =>
                    setState(() => _dir = v.isEmpty ? _dir : v.first),
              ),
              if (_dir == null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
                  child: Text(
                      _tried
                          ? 'Needed to save'
                          : "The photo didn't say — pick one",
                      style: TextStyle(
                          fontSize: 12, color: _tried ? danger : muted)),
                ),
              const SizedBox(height: 18),
              TextField(
                controller: _amount,
                autofocus: _missing(ScanField.amount),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                ],
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: 'Amount',
                  prefixText: '₹ ',
                  helperText: _helper(ScanField.amount, _amountValue != null),
                  errorText: _error(_amountValue != null),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _name,
                autofocus:
                    !_missing(ScanField.amount) && _missing(ScanField.name),
                textCapitalization: TextCapitalization.words,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: whoLabel,
                  helperText:
                      _helper(ScanField.name, _name.text.trim().isNotEmpty),
                  errorText: _error(_name.text.trim().isNotEmpty),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _upi,
                keyboardType: TextInputType.emailAddress,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: 'UPI ID',
                  hintText: 'Optional · name@bank',
                  errorText:
                      _upiOk ? null : 'Not a UPI ID — e.g. ravi@okaxis',
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _note,
                textCapitalization: TextCapitalization.sentences,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                    labelText: 'Note', hintText: 'Optional'),
              ),
              const SizedBox(height: 6),
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                leading: const Icon(Ph.calendarBlank),
                title: Text(DateFormat('EEE, d MMM yyyy').format(_when)),
                subtitle: Text(
                  s.when == null
                      ? 'No date on the photo — today is used'
                      : _oldDate
                          ? 'That is months ago — check the year'
                          : 'Read from the photo',
                  style: _oldDate ? TextStyle(color: danger) : null,
                ),
                trailing: const Icon(Ph.pencilSimple, size: 18),
                onTap: _pickDate,
              ),
              if (s.reference != null || s.phone != null || s.account != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
                  child: Text(
                    [
                      if (s.reference != null) 'Ref ${s.reference}',
                      if (s.account != null) 'A/c ••${s.account}',
                      if (s.phone != null) 'Ph ${s.phone}',
                    ].join(' · '),
                    style: TextStyle(fontSize: 12, color: muted),
                  ),
                ),
              const SizedBox(height: 22),
              FilledButton(
                style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(50)),
                onPressed: _save,
                child: const Text('Save'),
              ),
              const SizedBox(height: 8),
              Text(
                'The photo is not kept. AERIS saves a short text in the style '
                'of a bank SMS instead, marked as generated from a scan.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: muted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A page that lists several entries ("Ravi 500 / Neha 300"): asks once
/// whether they are separate payments or one purchase, and — if the page
/// didn't say — whether they were paid or received. Returns the entries to
/// save (one, with no name, when it's a single total), or null to skip it.
Future<List<ScanResult>?> showScanListChoice(
    BuildContext context, List<ScanResult> list) {
  return showModalBottomSheet<List<ScanResult>>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _ListChoice(list: list),
  );
}

class _ListChoice extends StatefulWidget {
  final List<ScanResult> list;
  const _ListChoice({required this.list});

  @override
  State<_ListChoice> createState() => _ListChoiceState();
}

class _ListChoiceState extends State<_ListChoice> {
  late TxnDirection? _dir = widget.list.first.direction;
  bool _tried = false;

  double get _total =>
      widget.list.fold(0.0, (sum, r) => sum + (r.amount ?? 0));

  static String _plain(double v) =>
      v % 1 == 0 ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

  ScanResult _with(ScanResult r, {double? amount, String? name, String? note}) =>
      ScanResult(
        kind: r.kind,
        amount: amount ?? r.amount,
        direction: _dir,
        name: name,
        when: r.when,
        note: note,
        fromList: true,
      );

  void _done(bool separate) {
    if (_dir == null) {
      HapticFeedback.heavyImpact();
      setState(() => _tried = true);
      return;
    }
    final list = widget.list;
    Navigator.pop(
      context,
      separate
          ? [for (final r in list) _with(r, name: r.name)]
          // One purchase: the total, with the lines kept as the note; the
          // name (the shop) is asked for next.
          : [
              _with(list.first,
                  amount: _total,
                  note: list
                      .map((r) => '${r.name} ${_plain(r.amount ?? 0)}')
                      .join(', ')),
            ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final muted = AerisColors.muted(context);
    final list = widget.list;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('${list.length} entries on this page',
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text('Total ${formatRupees(_total, decimals: _total % 1 != 0)}',
                style: TextStyle(color: muted)),
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220),
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final r in list)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(children: [
                        Expanded(child: Text(r.name ?? '')),
                        Text(formatRupees(r.amount ?? 0,
                            decimals: (r.amount ?? 0) % 1 != 0)),
                      ]),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            SegmentedButton<TxnDirection>(
              segments: const [
                ButtonSegment(
                    value: TxnDirection.debit,
                    icon: Icon(Ph.arrowUpRight, size: 16),
                    label: Text('All paid')),
                ButtonSegment(
                    value: TxnDirection.credit,
                    icon: Icon(Ph.arrowDownLeft, size: 16),
                    label: Text('All received')),
              ],
              selected: {if (_dir != null) _dir!},
              emptySelectionAllowed: true,
              showSelectedIcon: false,
              onSelectionChanged: (v) =>
                  setState(() => _dir = v.isEmpty ? _dir : v.first),
            ),
            if (_dir == null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text("The page didn't say — pick one",
                    style: TextStyle(
                        fontSize: 12,
                        color: _tried ? AerisColors.danger(context) : muted)),
              ),
            const SizedBox(height: 16),
            FilledButton(
              style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48)),
              onPressed: () => _done(true),
              child: Text('Save ${list.length} separate entries'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48)),
              onPressed: () => _done(false),
              child: const Text('One purchase — save the total'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Skip this page'),
            ),
          ],
        ),
      ),
    );
  }
}
