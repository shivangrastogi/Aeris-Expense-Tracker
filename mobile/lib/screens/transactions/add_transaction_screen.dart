import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../core/routes.dart';
import '../../core/theme.dart';
import '../../models/budget.dart';
import '../../models/category.dart';
import '../../models/loan.dart';
import '../../models/subscription.dart';
import '../../models/transaction.dart';
import '../../providers/accounts_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/loans_provider.dart';
import '../../providers/transactions_provider.dart';
import '../../providers/money_providers.dart';
import '../../services/category_rules.dart';
import '../../services/entry_checks.dart';
import '../../services/loan_service.dart';
import '../../services/receipt_scanner.dart';
import '../../services/scan_reader.dart';
import '../../services/sms_templates.dart';
import '../../utils/amount_input_formatter.dart';
import '../../utils/formatters.dart';
import '../../widgets/discard_guard.dart';
import '../../widgets/receipt_field.dart';
import '../../widgets/aeris_toast.dart';
import '../../widgets/ds.dart';

const _kLastAccountPref = 'last_txn_account';

/// Income-first ordering for the category chips when logging money in.
const _incomeFirst = ['salary', 'transfer', 'refund', 'investment', 'other'];

/// One screen for adding **and** editing a transaction.
///
/// A plain form on the system keyboard. The amount field has a small operator
/// rail (+ − × ÷) right under it: tapping a symbol inserts it at the cursor
/// without taking focus, so the keyboard stays up, and the result shows on the
/// same line. The Save button is pinned just above the keyboard, so a typical
/// entry (amount → category → Save) never needs a scroll.
class AddTransactionScreen extends ConsumerStatefulWidget {
  /// Optionally open straight into Income or Expense mode.
  final TxnDirection? initialDirection;

  /// When set, the screen edits this transaction and pops the updated
  /// [Transaction] on save.
  final Transaction? existing;

  const AddTransactionScreen({super.key, this.initialDirection, this.existing});
  @override
  ConsumerState<AddTransactionScreen> createState() =>
      _AddTransactionScreenState();
}

class _AddTransactionScreenState extends ConsumerState<AddTransactionScreen> {
  static const _formatter = AmountInputFormatter(allowMath: true);

  final _amount = TextEditingController();
  final _amountFocus = FocusNode();
  final _merchant = TextEditingController();
  final _note = TextEditingController();
  bool _amountError = false;

  late TxnDirection _dir;
  late String _categoryId;
  bool _categoryManual = false;
  String? _account;
  late DateTime _when;
  bool _repeatMonthly = false;
  Uint8List? _receipt;
  Uint8List? _originalReceipt;
  bool _busy = false;
  bool _scanning = false; // OCR running on a just-scanned photo
  // What was read from it (UPI ID, UTR…). Saved as a generated SMS-style
  // text in place of the photo, which isn't kept.
  ScanResult? _scanned;

  // Lent / borrowed money and its repayments: neither spend nor income.
  _Kind _kind = _Kind.normal;
  String? _loanId; // the loan repaid; null = one not recorded yet
  final _loanTotal = TextEditingController(); // that new loan's full amount
  List<Loan> _loans = const [];

  // Snapshot of the data this screen needs, taken once on open so streams
  // emitting in the background never rebuild (or reshuffle) the form.
  List<Transaction> _txns = const [];
  List<Budget> _budgets = const [];
  List<AccountSummary> _accounts = const [];
  List<Transaction> _recents = const [];
  List<String> _knownMerchants = const [];
  late List<ExpenseCategory> _chips;
  late final String _initialAmount;
  String _baseline = '';
  bool _lastDirty = false;

  bool get _editing => widget.existing != null;
  String get _defaultCategory =>
      _dir == TxnDirection.credit ? 'salary' : 'other';
  double get _rate => kCurrency.rate;

  /// Amount in INR (what's stored), or null if missing / invalid.
  double? _amountInr(String expr) {
    final e = widget.existing;
    if (e != null && expr == _initialAmount) return e.amount; // no drift
    final v = evalAmount(expr);
    return v == null ? null : (v * _rate * 100).roundToDouble() / 100;
  }

  String _snapshot() => [
        _amount.text,
        _merchant.text.trim(),
        _note.text.trim(),
        _account ?? '',
        _when.millisecondsSinceEpoch ~/ 60000,
        _receipt?.length ?? 0,
        _scanned != null,
        _repeatMonthly,
        if (_editing || _categoryManual) _categoryId,
        if (_editing) _dir.name,
        _kind.name,
        _loanId ?? '',
        _loanTotal.text,
      ].join('|');

  bool get _dirty => _snapshot() != _baseline;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _dir = e?.direction ?? widget.initialDirection ?? TxnDirection.debit;
    _categoryId = e?.categoryId ?? _defaultCategory;
    _categoryManual = e != null;
    _merchant.text = e?.merchant ?? '';
    _note.text = e?.note ?? '';
    _account = e?.account;
    _when = e?.timestamp ?? DateTime.now();
    _initialAmount = e == null ? '' : _plain(e.amount / _rate);
    _amount.text = _initialAmount;
    _kind = e == null
        ? _Kind.normal
        : e.startsLoan
            ? _Kind.start
            : e.repaysLoan
                ? _Kind.repay
                : _Kind.normal;
    _loanId = e != null && e.repaysLoan ? e.loanId : null;
    // Loans may still be loading when the form opens.
    _loans = ref.read(loansStreamProvider).valueOrNull ?? const [];
    ref.listenManual(loansStreamProvider, (_, next) {
      final v = next.valueOrNull;
      if (v != null && mounted) setState(() => _loans = v);
    });

    _txns = ref.read(transactionsStreamProvider).asData?.value ?? const [];
    _budgets = ref.read(effectiveBudgetsProvider);
    _accounts = ref
        .read(accountsProvider)
        .where((a) => a.key != unassignedAccount)
        .toList();
    _knownMerchants = (<String>{
      for (final t in _txns)
        if (t.merchant != null && t.merchant!.trim().isNotEmpty)
          t.merchant!.trim(),
    }.toList()
      ..sort());
    _recents = _editing
        ? const []
        : EntryChecks.recentTemplates(_txns, direction: _dir, limit: 8);
    _chips = _chipCategories();
    _baseline = _snapshot();

    // Typing repaints only the pieces listening to these controllers; the
    // screen itself rebuilds only when the discard guard's dirty flag flips.
    _amount.addListener(_syncGuard);
    _merchant.addListener(_syncGuard);
    _note.addListener(_syncGuard);
    _loanTotal.addListener(_syncGuard);

    if (e == null) {
      _restoreLastAccount();
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _focusAfterTransition());
    } else if (e.hasReceipt) {
      _loadReceipt(e);
    }
  }

  /// Raises the keyboard only once this route has finished animating in.
  /// Opening it mid-transition resized the page on every frame of the
  /// animation — the stutter people saw when tapping +.
  void _focusAfterTransition() {
    if (!mounted) return;
    final anim = ModalRoute.of(context)?.animation;
    if (anim == null || anim.isCompleted) {
      _amountFocus.requestFocus();
      return;
    }
    void onStatus(AnimationStatus s) {
      if (s != AnimationStatus.completed) return;
      anim.removeStatusListener(onStatus);
      if (mounted) _amountFocus.requestFocus();
    }

    anim.addStatusListener(onStatus);
  }

  void _syncGuard() {
    final d = _dirty;
    if (d != _lastDirty && mounted) setState(() => _lastDirty = d);
  }

  @override
  void dispose() {
    _amount.dispose();
    _amountFocus.dispose();
    _merchant.dispose();
    _note.dispose();
    _loanTotal.dispose();
    super.dispose();
  }

  static String _plain(double v) =>
      v % 1 == 0 ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

  Future<void> _restoreLastAccount() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final last = prefs.getString(_kLastAccountPref);
      if (last == null || !mounted || _account != null) return;
      if (!_accounts.any((a) => a.key == last)) return;
      final wasClean = !_dirty;
      setState(() => _account = last);
      if (wasClean) _baseline = _snapshot(); // pre-fill, not user input
    } catch (_) {}
  }

  Future<void> _loadReceipt(Transaction t) async {
    final uid = ref.read(currentUserIdProvider);
    if (uid == null) return;
    final bytes =
        await ref.read(firestoreServiceProvider).fetchReceipt(uid, t.id);
    if (!mounted || bytes == null) return;
    final wasClean = !_dirty;
    setState(() {
      _receipt = Uint8List.fromList(bytes);
      _originalReceipt = _receipt;
    });
    if (wasClean) _baseline = _snapshot();
  }

  Future<void> _autoCategorizeFor(String merchant) async {
    if (_categoryManual) return;
    final m = merchant.trim();
    if (m.isEmpty) return;
    final learned = await CategoryRules.instance.categoryFor(m);
    var cat = learned ?? Categories.classify(m);
    // Hindi / Hinglish words the keywords don't know: "sabzi", "दवा".
    if (cat == 'other') cat = ScanReader.categoryHint(m) ?? cat;
    if (cat != 'other' && mounted && !_categoryManual && cat != _categoryId) {
      setState(() {
        _categoryId = cat;
        if (!_chips.any((c) => c.id == cat)) _chips = _chipCategories();
      });
    }
  }

  // ── Operator rail ──────────────────────────────────────────

  /// Inserts [op] at the cursor. The rail never takes focus, so the keyboard
  /// stays open and typing continues right after the symbol.
  void _insertOp(String op) {
    HapticFeedback.selectionClick();
    final v = _amount.value;
    if (v.text.isEmpty) {
      _amountFocus.requestFocus();
      return; // nothing to operate on yet
    }
    final sel = v.selection.isValid
        ? v.selection
        : TextSelection.collapsed(offset: v.text.length);
    final next = v.text.replaceRange(sel.start, sel.end, op);
    _amount.value = _formatter.formatEditUpdate(
      v,
      TextEditingValue(
        text: next,
        selection: TextSelection.collapsed(offset: sel.start + op.length),
      ),
    );
    if (!_amountFocus.hasFocus) _amountFocus.requestFocus();
  }

  /// Replaces "120+45" with "165".
  void _collapseResult() {
    final v = evalAmount(_amount.text);
    if (v == null) return;
    HapticFeedback.selectionClick();
    final s = _plain(v);
    _amount.value = TextEditingValue(
        text: s, selection: TextSelection.collapsed(offset: s.length));
  }

  // ── Categories ─────────────────────────────────────────────

  /// The user's most-used categories for this direction first (so the usual
  /// pick is one tap away), always including the current selection.
  List<ExpenseCategory> _chipCategories() {
    final counts = <String, int>{};
    for (final t in _txns) {
      if (t.direction == _dir) {
        counts[t.categoryId] = (counts[t.categoryId] ?? 0) + 1;
      }
    }
    final base = _dir == TxnDirection.credit
        ? [
            for (final id in _incomeFirst) Categories.byId(id),
            for (final c in Categories.all)
              if (!_incomeFirst.contains(c.id)) c,
          ]
        : [
            for (final c in Categories.all)
              if (c.id != 'salary' && c.id != 'refund') c,
          ];
    // Stable sort by usage: ties keep the default order.
    final indexed = [for (var i = 0; i < base.length; i++) (i, base[i])];
    indexed.sort((a, b) {
      final byUse = (counts[b.$2.id] ?? 0).compareTo(counts[a.$2.id] ?? 0);
      return byUse != 0 ? byUse : a.$1.compareTo(b.$1);
    });
    final top = [for (final e in indexed) e.$2].take(8).toList();
    if (!top.any((c) => c.id == _categoryId)) {
      top.insert(0, Categories.byId(_categoryId));
    }
    return top;
  }

  void _pickCategory(String id) {
    HapticFeedback.selectionClick();
    setState(() {
      _categoryId = id;
      _categoryManual = true;
      if (!_chips.any((c) => c.id == id)) _chips = _chipCategories();
    });
    _syncGuard();
  }

  Future<void> _openAllCategories() async {
    final picked = await showDsSheet<String>(
      context,
      title: 'Category',
      builder: (s) => SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.zero,
          child: GridView.count(
            physics: const NeverScrollableScrollPhysics(),
            shrinkWrap: true,
            crossAxisCount: 4,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 1.05,
            children: [
              for (final c in Categories.all)
                _CategoryTile(
                  category: c,
                  selected: c.id == _categoryId,
                  onTap: () => Navigator.pop(s, c.id),
                ),
            ],
          ),
        ),
      ),
    );
    if (picked != null) _pickCategory(picked);
  }

  void _setDirection(TxnDirection d) {
    if (d == _dir) return;
    HapticFeedback.selectionClick();
    setState(() {
      final wasDefault = _categoryId == _defaultCategory;
      _dir = d;
      if (d == TxnDirection.credit) _repeatMonthly = false;
      if (!_repayable.any((l) => l.id == _loanId)) _loanId = null;
      if (!_categoryManual && wasDefault) _categoryId = _defaultCategory;
      _chips = _chipCategories();
      _recents = _editing
          ? const []
          : EntryChecks.recentTemplates(_txns, direction: _dir, limit: 8);
    });
    _syncGuard();
  }

  /// A split bill, or a friend's share of one paid back, has its own link
  /// (on the detail screen) — no loan choice for those.
  bool get _loanable {
    final e = widget.existing;
    return e == null || (e.split == null && (e.isLoan || !e.isSettlement));
  }

  /// Open loans this payment can pay back: money in repays what you lent,
  /// money out what you borrowed. The one it already repays stays listed.
  List<Loan> get _repayable {
    final e = widget.existing;
    final own = e != null && e.repaysLoan ? e.loanId : null;
    return [
      for (final l in _loans)
        if ((!l.isSettled || l.id == own) &&
            l.borrowed == (_dir == TxnDirection.debit))
          l
    ];
  }

  void _setKind(_Kind k) {
    if (k == _kind) return;
    HapticFeedback.selectionClick();
    setState(() {
      _kind = k;
      if (k != _Kind.normal) _repeatMonthly = false;
      final list = _repayable;
      if (k == _Kind.repay && !list.any((l) => l.id == _loanId)) {
        // The payer's own loan if there is one, else the newest.
        final who = _merchant.text.trim().toLowerCase();
        _loanId = (list
                    .where((l) =>
                        who.isNotEmpty &&
                        who.contains(l.person.toLowerCase().split(' ').first))
                    .firstOrNull ??
                list.firstOrNull)
            ?.id;
      }
    });
    _syncGuard();
  }

  /// "What is it?": ordinary spend/income, or money lent / borrowed, or a
  /// repayment of a loan (with which one).
  List<Widget> _loanSection(bool income) {
    final tk = context.tk;
    final repayable = _repayable;
    final hint = switch ((_kind, income)) {
      (_Kind.start, false) => 'Not counted as spending. The person you paid '
          'owes it back; track it in Activity → Lent.',
      (_Kind.start, true) => 'Not counted as income. You owe it back to the '
          'person who sent it; track it in Activity → Lent.',
      (_Kind.repay, true) =>
        'Not counted as income. It comes off what they owe you, so you can '
            'record a loan paid back in parts.',
      (_Kind.repay, false) =>
        'Not counted as spending. It comes off what you owe them.',
      _ => null,
    };
    return [
      const _SectionLabel('What is it?'),
      const SizedBox(height: 6),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final (k, label) in [
          (_Kind.normal, income ? 'Income' : 'Spending'),
          (_Kind.start, income ? 'Borrowed' : 'Lent'),
          (_Kind.repay, income ? 'Loan paid back' : 'Repaying a loan'),
        ])
          DsChip(label, selected: _kind == k, onTap: () => _setKind(k)),
      ]),
      if (hint != null) ...[
        const SizedBox(height: 8),
        Text(hint, style: Ts.bodyS.copyWith(color: tk.t2)),
      ],
      if (_kind == _Kind.repay) ...[
        const SizedBox(height: 12),
        _SectionLabel(income ? 'Which loan?' : 'Which loan are you repaying?'),
        const SizedBox(height: 6),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final l in repayable)
            DsChip('${l.person} · ${formatRupees(l.outstanding)} left',
                selected: _loanId == l.id, onTap: () {
              setState(() => _loanId = l.id);
              _syncGuard();
            }),
          DsChip('Not listed',
              icon: Ph.plus,
              selected: _loanId == null,
              onTap: () {
                setState(() => _loanId = null);
                _syncGuard();
              }),
        ]),
        if (_loanId == null) ...[
          const SizedBox(height: 10),
          TextField(
            controller: _loanTotal,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: const [_formatter],
            decoration: InputDecoration(
              prefixText: '${kCurrency.symbol} ',
              hintText: income
                  ? 'How much did you lend them in total?'
                  : 'How much did they lend you in total?',
            ),
          ),
        ],
      ],
    ];
  }

  void _applyRecent(Transaction t) {
    HapticFeedback.selectionClick();
    final amt = _plain(t.amount / _rate);
    _amount.value = TextEditingValue(
        text: amt, selection: TextSelection.collapsed(offset: amt.length));
    _merchant.text = t.merchant ?? '';
    setState(() {
      _amountError = false;
      _categoryId = t.categoryId;
      _categoryManual = true;
      if (t.account != null && _accounts.any((a) => a.key == t.account)) {
        _account = t.account;
      }
      if (!_chips.any((c) => c.id == _categoryId)) _chips = _chipCategories();
    });
    _syncGuard();
  }

  // ── Date & time ────────────────────────────────────────────

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  void _setDay(DateTime day) {
    var next = DateTime(day.year, day.month, day.day, _when.hour, _when.minute);
    if (next.isAfter(DateTime.now())) next = DateTime.now();
    HapticFeedback.selectionClick();
    setState(() => _when = next);
    _syncGuard();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _when,
      firstDate: DateTime(2015),
      lastDate: DateTime.now(),
    );
    if (picked != null) _setDay(picked);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
        context: context, initialTime: TimeOfDay.fromDateTime(_when));
    if (picked == null || !mounted) return;
    final next = DateTime(
        _when.year, _when.month, _when.day, picked.hour, picked.minute);
    if (next.isAfter(DateTime.now())) {
      ScaffoldMessenger.of(context).showToast(
          const SnackBar(content: Text("Time can't be in the future")));
      return;
    }
    setState(() => _when = next);
    _syncGuard();
  }

  /// The text saved in place of the scanned photo, from the form as it is
  /// now — corrections made after scanning are in it. Null without a scan.
  String? _scanText(double amount) {
    final s = _scanned;
    if (s == null) return null;
    final merchant = _merchant.text.trim();
    final note = _note.text.trim();
    return ScanSms.compose(
      amount: amount,
      direction: _dir,
      when: _when,
      kindLabel: s.kindLabel,
      name: merchant.isEmpty ? null : merchant,
      upiVpa: s.upiVpa,
      reference: s.reference,
      account: _account ?? s.account,
      phone: s.phone,
      note: note.isEmpty ? null : note,
    );
  }

  void _showScanText() {
    final text = _scanText(_amountInr(_amount.text) ?? 0);
    if (text == null) return;
    showDialog<void>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Saved instead of the photo'),
        content: Text(text,
            style: const TextStyle(
                fontFamily: 'monospace', fontSize: 13, height: 1.4)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(d), child: const Text('OK')),
        ],
      ),
    );
  }

  Future<void> _scanPhoto() async {
    final path = await pickScanImage(context);
    if (path == null || !mounted) return;
    setState(() => _scanning = true);
    // Read it on-device (payment screen, bill or handwritten note) and fill
    // whatever is still empty — never overwrite something the user already
    // typed. The photo itself isn't kept.
    final info = await ReceiptScanner.read(path);
    await ReceiptScanner.forget(path); // the text is kept, not the photo
    if (!mounted) return;
    setState(() {
      _scanning = false;
      _scanned = info;
      // The account it was paid from, if it's one already tracked.
      if (_account == null && _accounts.any((a) => a.key == info?.account)) {
        _account = info!.account;
      }
    });
    if (info == null) {
      ScaffoldMessenger.of(context).showToast(SnackBar(
          content: Text(ReceiptScanner.modelDownloading
              ? 'The text reader is still downloading. Stay online and try '
                  'again in a minute.'
              : "Couldn't read any text in that photo.")));
      return;
    }
    // A payment screenshot knows whether the money came in or went out.
    if (info.direction != null && !_editing) _setDirection(info.direction!);
    final filled = <String>[];
    // What it was for ("Category: food", "sabzi ke liye"); the name's own
    // category, below, wins when it has one.
    final purpose = [info.category, info.note].whereType<String>().join(' ');
    if (purpose.isNotEmpty) await _autoCategorizeFor(purpose);
    if (!mounted) return;
    if (info.amount != null && _amount.text.trim().isEmpty) {
      final s = _plain(info.amount! / _rate);
      _amount.value = TextEditingValue(
          text: s, selection: TextSelection.collapsed(offset: s.length));
      filled.add(formatRupees(info.amount!, decimals: info.amount! % 1 != 0));
    }
    if (info.name != null && _merchant.text.trim().isEmpty) {
      _merchant.text = info.name!;
      _autoCategorizeFor(info.name!);
      filled.add(info.name!);
    }
    if (info.note != null && _note.text.trim().isEmpty) {
      _note.text = info.note!;
    }
    final d = info.when;
    if (d != null &&
        !d.isAfter(DateTime.now()) &&
        DateTime.now().difference(d).inDays < 120 &&
        !_editing) {
      // A screenshot's date carries its own time; a bill's is midnight.
      final timed = d.hour != 0 || d.minute != 0;
      setState(() => _when = timed
          ? d
          : DateTime(d.year, d.month, d.day, _when.hour, _when.minute));
    }
    _syncGuard();
    // Ask for what the photo didn't have, and flag what was only guessed.
    final missing = [
      if (_amount.text.trim().isEmpty) 'the amount',
      if (_merchant.text.trim().isEmpty) 'who it was ${_dir == TxnDirection.credit ? 'from' : 'paid to'}',
      if (info.direction == null && !_editing) 'whether it was paid or received',
    ];
    final guessed = [
      if (info.unsure.contains(ScanField.amount) && filled.isNotEmpty) 'amount',
      if (info.unsure.contains(ScanField.name)) 'name',
    ];
    if (_amount.text.trim().isEmpty) _amountFocus.requestFocus();
    ScaffoldMessenger.of(context).showToast(SnackBar(
        content: Text([
      filled.isEmpty ? 'Read the photo' : 'Read: ${filled.join(' · ')}',
      if (missing.isNotEmpty) 'please enter ${missing.join(', ')}',
      if (missing.isEmpty && guessed.isNotEmpty)
        'check the ${guessed.join(' and ')}',
    ].join(' — '))));
  }

  // ── Build ──────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final income = _dir == TxnDirection.credit;
    // Spend is typed in plain ink, income in green; Save is always the accent.
    final money =
        income ? AerisColors.moneyIn(context) : AerisColors.moneyOut(context);
    final now = DateTime.now();
    final yesterday = now.subtract(const Duration(days: 1));
    final customDay = !_sameDay(_when, now) && !_sameDay(_when, yesterday);

    const gap = SizedBox(height: 14);

    return DiscardGuard(
      dirty: _dirty && !_busy,
      title: _editing
          ? 'Discard your changes?'
          : (income ? 'Discard this income?' : 'Discard this expense?'),
      child: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              _Header(
                dir: _dir,
                onDirection: _setDirection,
                onClose: () => Navigator.maybePop(context),
                showVoice: !_editing,
                // Voice replaces this screen, so it only works while the form
                // is still empty — never throw away typed input.
                onVoice: _dirty
                    ? null
                    : () => Navigator.pushReplacementNamed(
                        context, AppRoutes.voice),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  children: [
                    _AmountField(
                      controller: _amount,
                      focusNode: _amountFocus,
                      formatter: _formatter,
                      color: money,
                      autofocus:
                          false, // focused after the route settles — see _focusAfterTransition
                      error: _amountError,
                      onChanged: () {
                        if (_amountError) setState(() => _amountError = false);
                      },
                      onOp: _insertOp,
                      onCollapse: _collapseResult,
                      helper: _BudgetHint(
                        amount: _amount,
                        amountInr: _amountInr,
                        categoryId: _categoryId,
                        income: income,
                        when: _when,
                        txns: _txns,
                        budgets: _budgets,
                        excludeId: widget.existing?.id,
                      ),
                    ),
                    if (_recents.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      SizedBox(
                        height: 36,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: _recents.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 8),
                          itemBuilder: (_, i) {
                            final t = _recents[i];
                            final c = Categories.byId(t.categoryId);
                            return DsChip(
                              '${t.merchant} · ${formatRupees(t.amount)}',
                              icon: c.icon,
                              onTap: () => _applyRecent(t),
                            );
                          },
                        ),
                      ),
                    ],
                    gap,
                    _MerchantField(
                      controller: _merchant,
                      income: income,
                      known: _knownMerchants,
                      onChanged: _autoCategorizeFor,
                    ),
                    if (_loanable) ...[gap, ..._loanSection(income)],
                    // A loan isn't spending or income, so it has no category.
                    if (_kind == _Kind.normal) ...[
                      gap,
                      const _SectionLabel('Category'),
                      const SizedBox(height: 6),
                      SizedBox(
                        height: 40,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          children: [
                            for (final c in _chips) ...[
                              _CatChip(
                                category: c,
                                selected: c.id == _categoryId,
                                onTap: () => _pickCategory(c.id),
                              ),
                              const SizedBox(width: 8),
                            ],
                            DsChip('All',
                                icon: Ph.squaresFour,
                                onTap: _openAllCategories),
                          ],
                        ),
                      ),
                    ],
                    gap,
                    const _SectionLabel('When'),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        DsChip('Today',
                            selected: _sameDay(_when, now),
                            onTap: () => _setDay(now)),
                        DsChip('Yesterday',
                            selected: _sameDay(_when, yesterday),
                            onTap: () => _setDay(yesterday)),
                        DsChip(
                            customDay
                                ? DateFormat('d MMM yyyy').format(_when)
                                : 'Pick date',
                            icon: Ph.calendarBlank,
                            selected: customDay,
                            onTap: _pickDate),
                        DsChip(TimeOfDay.fromDateTime(_when).format(context),
                            icon: Ph.clock, onTap: _pickTime),
                      ],
                    ),
                    gap,
                    if (_accounts.isNotEmpty) ...[
                      const _SectionLabel('Account'),
                      const SizedBox(height: 6),
                      DropdownButtonFormField<String?>(
                        initialValue: _account,
                        isExpanded: true,
                        decoration: const InputDecoration(),
                        items: [
                          const DropdownMenuItem(
                              value: null, child: Text('No account')),
                          for (final a in _accounts)
                            DropdownMenuItem(
                                value: a.key, child: Text(a.label)),
                          if (_account != null &&
                              !_accounts.any((a) => a.key == _account))
                            DropdownMenuItem(
                                value: _account, child: Text('••$_account')),
                        ],
                        onChanged: (v) {
                          setState(() => _account = v);
                          _syncGuard();
                        },
                      ),
                      const SizedBox(height: 12),
                    ],
                    const _SectionLabel('Note'),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _note,
                      maxLength: 200,
                      textCapitalization: TextCapitalization.sentences,
                      textInputAction: TextInputAction.done,
                      decoration: const InputDecoration(
                        hintText: 'Optional',
                        counterText: '',
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        if (_scanning)
                          const Chip(
                            avatar: SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2)),
                            label: Text('Reading…'),
                          )
                        else if (_scanned != null)
                          InputChip(
                            avatar: const Icon(Ph.chatText, size: 16),
                            label: const Text('Scanned'),
                            onPressed: _showScanText,
                            onDeleted: () {
                              setState(() => _scanned = null);
                              _syncGuard();
                            },
                          )
                        else if (_receipt == null)
                          ActionChip(
                            avatar: const Icon(Ph.scan,
                                size: 16),
                            label: const Text('Scan photo'),
                            onPressed: _scanPhoto,
                          )
                        else
                          InputChip(
                            avatar: const Icon(Ph.receipt,
                                size: 16),
                            label: const Text('Receipt'),
                            onPressed: () =>
                                showReceiptViewer(context, _receipt!),
                            onDeleted: () {
                              setState(() => _receipt = null);
                              _syncGuard();
                            },
                          ),
                        if (!_editing && !income && _kind == _Kind.normal)
                          FilterChip(
                            avatar: const Icon(Ph.repeat,
                                size: 16),
                            label: Text(_repeatMonthly
                                ? 'Repeats monthly (day ${_when.day.clamp(1, 28)})'
                                : 'Repeats monthly'),
                            selected: _repeatMonthly,
                            showCheckmark: false,
                            onSelected: (v) {
                              setState(() => _repeatMonthly = v);
                              _syncGuard();
                            },
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              // Pinned above the keyboard: the body resizes with it, so Save
              // is always one tap away without scrolling.
              _SaveBar(
                label: _editing
                    ? 'Update'
                    : (income ? 'Save income' : 'Save expense'),
                amount: _amount,
                amountInr: _amountInr,
                busy: _busy,
                onSave: _save,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Save ───────────────────────────────────────────────────

  Future<bool> _confirm({
    required IconData icon,
    required String title,
    required String body,
    required String confirm,
    String cancel = 'Go back',
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        icon: Icon(icon),
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(d, false), child: Text(cancel)),
          FilledButton(
              onPressed: () => Navigator.pop(d, true), child: Text(confirm)),
        ],
      ),
    );
    return ok ?? false;
  }

  /// Duplicate + typo checks. Returns false if the user wants to fix things.
  Future<bool> _passesChecks(double amt) async {
    final txns = ref.read(transactionsStreamProvider).asData?.value ?? _txns;
    final e = widget.existing;
    final merchant = _merchant.text.trim();
    final changedKey = e == null ||
        e.amount != amt ||
        !_sameDay(e.timestamp, _when) ||
        e.direction != _dir;
    if (changedKey) {
      final dup = EntryChecks.likelyDuplicate(txns,
          amount: amt,
          direction: _dir,
          when: _when,
          merchant: merchant,
          excludeId: e?.id);
      if (dup != null) {
        final from =
            dup.source == TxnSource.sms ? ' (auto-imported from SMS)' : '';
        final ok = await _confirm(
          icon: Ph.copy,
          title: 'Possible duplicate',
          body: 'You already have '
              '${formatRupees(dup.amount, decimals: true, raw: true)}'
              '${dup.merchant == null ? '' : ' at ${dup.merchant}'} '
              '${relativeDate(dup.timestamp).toLowerCase()} at '
              '${TimeOfDay.fromDateTime(dup.timestamp).format(context)}$from.'
              '\n\nSave this one as well?',
          confirm: 'Save anyway',
        );
        if (!ok) return false;
      }
    }
    final typical = EntryChecks.typicalAmount(txns,
        categoryId: _categoryId, direction: _dir, excludeId: e?.id);
    if ((e == null || e.amount != amt) &&
        EntryChecks.isUnusuallyLarge(amt, typical) &&
        mounted) {
      final ok = await _confirm(
        icon: Ph.warningCircle,
        title: 'That looks unusually high',
        body: '${formatRupees(amt, raw: true)} is much more than your usual '
            '${Categories.byId(_categoryId).label} '
            '${_dir == TxnDirection.credit ? 'income' : 'spend'} '
            '(typically ${formatRupees(typical!, raw: true)}).\n\n'
            'Is the amount right?',
        confirm: 'Yes, save it',
        cancel: 'Fix amount',
      );
      if (!ok) return false;
    }
    return true;
  }

  /// The loan choice as a [LoanLink], or null (after saying why) when it's
  /// missing who the loan is with or how much it was.
  LoanLink? _loanLink(String person) {
    if (!_loanable || _kind == _Kind.normal) return const LoanNone();
    String? problem;
    LoanLink? link;
    if (person.isEmpty) {
      problem = _dir == TxnDirection.debit
          ? 'Add who you paid: the loan is with them.'
          : 'Add who paid you: the loan is with them.';
    } else if (_kind == _Kind.start) {
      link = LoanStart(person);
    } else if (_loanId != null) {
      final loan = _loans.where((l) => l.id == _loanId).firstOrNull;
      if (loan != null) link = LoanRepay(loan);
    } else {
      final v = evalAmount(_loanTotal.text);
      if (v != null && v > 0) {
        link = LoanRepayNew(person, (v * _rate * 100).roundToDouble() / 100);
      } else {
        problem = 'Enter how much the whole loan was.';
      }
    }
    if (link == null) {
      HapticFeedback.heavyImpact();
      ScaffoldMessenger.of(context).showToast(SnackBar(
          content: Text(problem ?? 'Pick the loan this pays back.')));
    }
    return link;
  }

  String _loanSaved(String person) {
    final income = _dir == TxnDirection.credit;
    final what = switch ((_kind, income)) {
      (_Kind.start, false) => 'Lent to $person',
      (_Kind.start, true) => 'Borrowed from $person',
      (_, true) => 'Payback from $person saved',
      (_, false) => 'Repayment to $person saved',
    };
    return '$what · not counted as ${income ? 'income' : 'spending'}';
  }

  Future<void> _save() async {
    final uid = ref.read(currentUserIdProvider);
    if (uid == null) return;
    final amt = _amountInr(_amount.text);
    if (amt == null) {
      setState(() => _amountError = true);
      _amountFocus.requestFocus();
      HapticFeedback.heavyImpact();
      return;
    }
    final merchant = _merchant.text.trim();
    final link = _loanLink(merchant);
    if (link == null) return;
    if (!await _passesChecks(amt) || !mounted) return;

    setState(() => _busy = true);
    final fs = ref.read(firestoreServiceProvider);
    final e = widget.existing;
    final note = _note.text.trim();
    // A scanned photo is kept as generated SMS-style text, rewritten when an
    // earlier scan's entry is edited. A real bank SMS is never replaced.
    final ownSms = e?.smsBody != null && !e!.scanGenerated;
    final scanBody = ownSms
        ? null
        : _scanned != null
            ? _scanText(amt)
            : (e?.scanGenerated ?? false)
                ? ScanSms.recompose(e!.smsBody!,
                    amount: amt,
                    direction: _dir,
                    when: _when,
                    name: merchant.isEmpty ? null : merchant,
                    upiVpa: e.upiVpa,
                    reference: e.reference,
                    account: _account,
                    note: note.isEmpty ? null : note)
                : null;
    var t = Transaction(
      id: e?.id ?? const Uuid().v4(),
      amount: amt,
      direction: _dir,
      timestamp: _when,
      merchant: merchant.isEmpty ? null : merchant,
      account: _account,
      categoryId: _categoryId,
      note: note.isEmpty ? null : note,
      // Editing keeps provenance (SMS text, UPI ref…) intact.
      source: e?.source ?? TxnSource.manual,
      smsBody: scanBody ?? e?.smsBody,
      smsSender: scanBody != null ? Transaction.scanSender : e?.smsSender,
      reviewed: true,
      reference: e?.reference ?? _scanned?.reference,
      upiVpa: e?.upiVpa ?? _scanned?.upiVpa,
      hasReceipt: _receipt != null,
      balance: e?.balance,
      linkId: e?.linkId,
      selfTransfer: e?.selfTransfer ?? false,
      // A split's shares are amounts, so they stay valid unless the user
      // changes the bill amount below them (then your share just shrinks).
      split: e?.split,
      settles: e?.settles,
      settlesMember: e?.settlesMember,
    );
    try {
      // Returns once queued locally — works offline via the sync outbox.
      await fs.addTransaction(uid, t);
      // A fixed amount / type / category on an SMS import teaches the parser
      // this bank's message format.
      if (e != null) await SmsTemplates.instance.learn(e, t);
      if (_loanable && (_kind != _Kind.normal || (e?.isLoan ?? false))) {
        t = await LoanService.instance.relink(uid, e, t, link, _loans);
      }
      if (_receipt != null && !identical(_receipt, _originalReceipt)) {
        await fs.setReceipt(uid, t.id, _receipt!);
      } else if (_receipt == null && (e?.hasReceipt ?? false)) {
        await fs.deleteReceipt(uid, t.id);
      }
      if (_repeatMonthly && !_editing) {
        await fs.setSubscription(
          uid,
          Subscription(
            id: const Uuid().v4(),
            name: merchant.isEmpty
                ? Categories.byId(_categoryId).label
                : merchant,
            amount: amt,
            categoryId: _categoryId,
            day: _when.day.clamp(1, 28),
          ),
        );
      }
    } catch (err) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context)
          .showToast(SnackBar(content: Text('Could not save: $err')));
      return;
    }
    if (merchant.isNotEmpty && _kind == _Kind.normal) {
      await CategoryRules.instance.remember(merchant, _categoryId);
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_account == null) {
        await prefs.remove(_kLastAccountPref);
      } else {
        await prefs.setString(_kLastAccountPref, _account!);
      }
    } catch (_) {}
    if (!mounted) return;

    HapticFeedback.mediumImpact();
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    final dir = _dir;
    messenger.hideToast();
    messenger.showToast(SnackBar(
      content: Text(_kind != _Kind.normal
          ? _loanSaved(merchant)
          : _editing
              ? 'Transaction updated'
              : '${dir == TxnDirection.credit ? 'Income' : 'Expense'} of '
                  '${formatRupees(amt, decimals: amt % 1 != 0, raw: true)} saved'
                  '${_repeatMonthly ? ' · added to Subscriptions' : ''}'),
      action: _editing
          ? null
          : SnackBarAction(
              label: 'Add another',
              onPressed: () => nav.pushNamed(AppRoutes.addTxn, arguments: dir),
            ),
    ));
    nav.pop(t);
  }
}

// ═══════════════════════════════════════════════════════════════
// Pieces
// ═══════════════════════════════════════════════════════════════

String _short(String label) => label.split(RegExp(r' [&/] ')).first;

/// Field label, set above the field (12/600, secondary).
class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) =>
      Text(text, style: Ts.label.copyWith(color: context.tk.t2));
}

/// × · Expense | Income · mic.
class _Header extends StatelessWidget {
  final TxnDirection dir;
  final ValueChanged<TxnDirection> onDirection;
  final VoidCallback onClose;
  final bool showVoice;
  final VoidCallback? onVoice;
  const _Header({
    required this.dir,
    required this.onDirection,
    required this.onClose,
    this.showVoice = false,
    this.onVoice,
  });

  @override
  Widget build(BuildContext context) {
    final tk = context.tk;
    return SizedBox(
      height: 56,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          children: [
            IconButton(
              tooltip: 'Close',
              icon: Icon(Ph.x, size: 22, color: tk.t1),
              onPressed: onClose,
            ),
            Expanded(
              child: Center(
                child: SizedBox(
                  width: 180,
                  child: DsSegmented(
                    height: 36,
                    labels: const ['Expense', 'Income'],
                    index: dir == TxnDirection.debit ? 0 : 1,
                    onChanged: (i) => onDirection(
                        i == 0 ? TxnDirection.debit : TxnDirection.credit),
                  ),
                ),
              ),
            ),
            if (showVoice)
              IconButton(
                tooltip: 'Say it instead',
                icon: Icon(Ph.microphone, size: 22, color: tk.t1),
                onPressed: onVoice,
              )
            else
              const SizedBox(width: 48),
          ],
        ),
      ),
    );
  }
}

/// The amount, large and centred, with its operator rail underneath.
///
/// The rail sits inside a [TextFieldTapRegion] and its keys can't take focus,
/// so tapping + − × ÷ keeps the keyboard open and the cursor in place.
class _AmountField extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final TextInputFormatter formatter;
  final Color color;
  final bool autofocus;
  final bool error;
  final VoidCallback onChanged;
  final ValueChanged<String> onOp;
  final VoidCallback onCollapse;
  final Widget helper;

  const _AmountField({
    required this.controller,
    required this.focusNode,
    required this.formatter,
    required this.color,
    required this.autofocus,
    required this.error,
    required this.onChanged,
    required this.onOp,
    required this.onCollapse,
    required this.helper,
  });

  @override
  Widget build(BuildContext context) {
    final tk = context.tk;
    const size = 40.0;
    return TextFieldTapRegion(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // "₹" + the field, centred as one unit. The field is sized to its
          // text so the pair stays centred while typing.
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (context, v, field) {
              const style = TextStyle(
                  fontFamily: kFontFamily,
                  fontSize: size,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -1,
                  fontFeatures: [FontFeature.tabularFigures()]);
              final tp = TextPainter(
                text: TextSpan(text: v.text.isEmpty ? '0' : v.text, style: style),
                textDirection: TextDirection.ltr,
                textScaler: MediaQuery.textScalerOf(context),
                maxLines: 1,
              )..layout();
              final textW = tp.width;
              tp.dispose();
              return LayoutBuilder(builder: (context, c) {
                final w = (textW + 12).clamp(40.0, c.maxWidth - 40);
                return Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(kCurrency.symbol.trim(),
                        style: TextStyle(
                            fontSize: size * 0.64,
                            fontWeight: FontWeight.w600,
                            color: color.withValues(alpha: 0.62))),
                    const SizedBox(width: 2),
                    SizedBox(width: w, child: field),
                  ],
                );
              });
            },
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              autofocus: autofocus,
              textAlign: TextAlign.center,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              textInputAction: TextInputAction.next,
              inputFormatters: [formatter],
              onChanged: (_) => onChanged(),
              style: TextStyle(
                fontSize: size,
                height: 44 / size,
                fontWeight: FontWeight.w700,
                letterSpacing: -1,
                color: color,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
              decoration: InputDecoration(
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                errorBorder: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 4),
                hintText: '0',
                hintStyle: TextStyle(
                    fontSize: size,
                    fontWeight: FontWeight.w700,
                    color: tk.t3),
              ),
            ),
          ),
          if (error)
            Center(
              child: Container(
                  width: 120, height: 2, color: tk.bad),
            ),
          const SizedBox(height: 8),
          Row(
            children: [
              for (final op in const ['+', '−', '×', '÷'])
                _OpKey(op: op, onTap: () => onOp(op)),
              const SizedBox(width: 6),
              Expanded(
                child: _ResultText(
                  controller: controller,
                  color: color,
                  error: error,
                  onCollapse: onCollapse,
                  fallback: helper,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A category choice chip: tile-tinted when selected, with a check.
class _CatChip extends StatelessWidget {
  final ExpenseCategory category;
  final bool selected;
  final VoidCallback onTap;
  const _CatChip(
      {required this.category, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final tk = context.tk;
    final c = category.color;
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Rad.chip),
        child: AnimatedContainer(
          duration: Mo.standard,
          curve: Mo.curve,
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: selected ? c.withValues(alpha: 0.14) : Colors.transparent,
            borderRadius: BorderRadius.circular(Rad.chip),
            border: Border.all(color: selected ? c : tk.hair2),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(selected ? PhBold.check : category.icon,
                size: 16, color: c),
            const SizedBox(width: 6),
            Text(_short(category.label),
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: tk.t1)),
          ]),
        ),
      ),
    );
  }
}

class _OpKey extends StatelessWidget {
  final String op;
  final VoidCallback onTap;
  const _OpKey({required this.op, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Material(
        color: context.tk.sunken,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          canRequestFocus: false, // keep focus (and the keyboard) on amount
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: SizedBox(
            width: 40,
            height: 34,
            child: Center(
              child: Text(op,
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: scheme.onSurface)),
            ),
          ),
        ),
      ),
    );
  }
}

/// Right side of the rail: "= ₹ 165" while there's a calculation (tap to
/// replace the expression with the result), the error, or [fallback].
class _ResultText extends StatelessWidget {
  final TextEditingController controller;
  final Color color;
  final bool error;
  final VoidCallback onCollapse;
  final Widget fallback;
  const _ResultText({
    required this.controller,
    required this.color,
    required this.error,
    required this.onCollapse,
    required this.fallback,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        final s = value.text;
        if (error && evalAmount(s) == null) {
          return Text('Enter an amount to save',
              textAlign: TextAlign.end,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: scheme.error));
        }
        if (!isAmountExpression(s)) return fallback;
        final v = evalAmount(s);
        final text = v == null
            ? 'Finish the calculation'
            : '= ${kCurrency.symbol.trim()} '
                '${v % 1 == 0 ? v.toStringAsFixed(0) : v.toStringAsFixed(2)}';
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: v == null ? null : onCollapse,
          child: Text(text,
              textAlign: TextAlign.end,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: v == null ? scheme.onSurfaceVariant : color)),
        );
      },
    );
  }
}

/// What this entry does to the category's monthly budget (or, for a foreign
/// display currency, what gets stored). Shown in the rail when there's no
/// calculation going on.
class _BudgetHint extends StatelessWidget {
  final TextEditingController amount;
  final double? Function(String) amountInr;
  final String categoryId;
  final bool income;
  final DateTime when;
  final List<Transaction> txns;
  final List<Budget> budgets;
  final String? excludeId;

  const _BudgetHint({
    required this.amount,
    required this.amountInr,
    required this.categoryId,
    required this.income,
    required this.when,
    required this.txns,
    required this.budgets,
    required this.excludeId,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Month spend is computed once per category/date change, not per key.
    final spent = _monthSpent();
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: amount,
      builder: (context, value, _) {
        final s = value.text;
        var text = '';
        var color = scheme.onSurfaceVariant;
        if (!income && spent != null) {
          final (cap, used) = spent;
          final amt = amountInr(s) ?? 0;
          final left = cap - used - amt;
          final name = _short(Categories.byId(categoryId).label);
          if (left < 0) {
            text = '${formatRupees(-left)} over $name budget';
            color = scheme.error;
          } else {
            text = '${formatRupees(left)} left in $name';
            if ((used + amt) / cap > 0.8) color = context.tk.warn;
          }
        }
        if (text.isEmpty && kCurrency.code != 'INR') {
          final inr = amountInr(s);
          if (inr != null) {
            text = 'Saved as ₹${inr.toStringAsFixed(inr % 1 == 0 ? 0 : 2)}';
          }
        }
        return Text(text,
            textAlign: TextAlign.end,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontSize: 12.5, fontWeight: FontWeight.w600, color: color));
      },
    );
  }

  /// (cap, spent so far) for this month's category budget, or null.
  (double, double)? _monthSpent() {
    final now = DateTime.now();
    if (when.year != now.year || when.month != now.month) return null;
    final b = budgets
        .where((b) => b.categoryId == categoryId && b.monthlyCap > 0)
        .firstOrNull;
    if (b == null) return null;
    final used = txns
        .where((t) =>
            t.id != excludeId &&
            t.isDebit &&
            t.categoryId == categoryId &&
            t.timestamp.year == now.year &&
            t.timestamp.month == now.month)
        .fold(0.0, (s, t) => s + t.amount);
    return (b.monthlyCap, used);
  }
}

/// Merchant / payer field with suggestions from past entries, shown as a
/// raised list under the field (matched part in bold, category on the right).
class _MerchantField extends StatelessWidget {
  final TextEditingController controller;
  final bool income;
  final List<String> known;
  final ValueChanged<String> onChanged;
  const _MerchantField({
    required this.controller,
    required this.income,
    required this.known,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final tk = context.tk;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionLabel(income ? 'Payer' : 'Merchant'),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.done,
          onChanged: onChanged,
          style: TextStyle(fontSize: 15, color: tk.t1),
          decoration: InputDecoration(
            hintText: income ? 'Who paid you?' : 'Where did you spend?',
          ),
        ),
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: controller,
          builder: (context, value, _) {
            final q = value.text.trim().toLowerCase();
            final hits = q.isEmpty
                ? const <String>[]
                : known
                    .where((m) =>
                        m.toLowerCase().contains(q) && m.toLowerCase() != q)
                    .take(4)
                    .toList();
            if (hits.isEmpty) return const SizedBox.shrink();
            return Container(
              margin: const EdgeInsets.only(top: 8),
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: tk.raised,
                borderRadius: BorderRadius.circular(Rad.button),
                border: tk.isDark ? Border.all(color: tk.hair) : null,
                boxShadow: tk.shadowRaised,
              ),
              child: Material(
                type: MaterialType.transparency,
                child: Column(children: [
                  for (var i = 0; i < hits.length; i++) ...[
                    if (i > 0) Container(height: 1, color: tk.hair),
                    InkWell(
                      onTap: () {
                        final s = hits[i];
                        controller.value = TextEditingValue(
                            text: s,
                            selection:
                                TextSelection.collapsed(offset: s.length));
                        onChanged(s);
                      },
                      child: Container(
                        constraints: const BoxConstraints(minHeight: 46),
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        alignment: Alignment.centerLeft,
                        child: _boldMatch(hits[i], q, tk),
                      ),
                    ),
                  ],
                ]),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _boldMatch(String s, String q, AerisTokens tk) {
    final i = s.toLowerCase().indexOf(q);
    final base = TextStyle(fontSize: 15, color: tk.t1);
    if (i < 0) return Text(s, style: base);
    return Text.rich(TextSpan(style: base, children: [
      TextSpan(text: s.substring(0, i)),
      TextSpan(
          text: s.substring(i, i + q.length),
          style: const TextStyle(fontWeight: FontWeight.w700)),
      TextSpan(text: s.substring(i + q.length)),
    ]));
  }
}

/// Pinned above the keyboard: "Save expense · ₹486".
class _SaveBar extends StatelessWidget {
  final String label;
  final TextEditingController amount;
  final double? Function(String) amountInr;
  final bool busy;
  final VoidCallback onSave;
  const _SaveBar({
    required this.label,
    required this.amount,
    required this.amountInr,
    required this.busy,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    final tk = context.tk;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      decoration: BoxDecoration(
        color: tk.bg,
        border: Border(top: BorderSide(color: tk.hair)),
      ),
      child: SizedBox(
        height: 48,
        child: FilledButton(
          onPressed: busy ? null : onSave,
          style: busy
              ? FilledButton.styleFrom(
                  disabledBackgroundColor: tk.acc,
                  disabledForegroundColor: tk.onAcc)
              : null,
          child: busy
              ? RisingLoader(color: tk.onAcc)
              : ValueListenableBuilder<TextEditingValue>(
                  valueListenable: amount,
                  builder: (_, v, __) {
                    final inr = amountInr(v.text);
                    return Text(inr == null || inr <= 0
                        ? label
                        : '$label · ${formatRupees(inr)}');
                  },
                ),
        ),
      ),
    );
  }
}

/// One cell of the "All categories" sheet: the tile and the short name.
class _CategoryTile extends StatelessWidget {
  final ExpenseCategory category;
  final bool selected;
  final VoidCallback onTap;
  const _CategoryTile({
    required this.category,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tk = context.tk;
    return Material(
      color: selected ? category.color.withValues(alpha: 0.10) : Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Rad.button),
        side: BorderSide(
            color: selected ? category.color : Colors.transparent, width: 1.5),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(Rad.button),
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CatTile.of(category),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(_short(category.label),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                    color: selected ? tk.t1 : tk.t2,
                  )),
            ),
          ],
        ),
      ),
    );
  }
}

/// What the money is: ordinary spend / income, money lent or borrowed
/// ([start]), or a repayment of a loan ([repay]).
enum _Kind { normal, start, repay }
