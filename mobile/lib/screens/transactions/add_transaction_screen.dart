import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../core/routes.dart';
import '../../core/theme.dart';
import '../../models/budget.dart';
import '../../models/category.dart';
import '../../models/subscription.dart';
import '../../models/transaction.dart';
import '../../providers/accounts_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/transactions_provider.dart';
import '../../providers/money_providers.dart';
import '../../services/category_rules.dart';
import '../../services/entry_checks.dart';
import '../../services/receipt_scanner.dart';
import '../../utils/amount_input_formatter.dart';
import '../../utils/formatters.dart';
import '../../widgets/discard_guard.dart';
import '../../widgets/receipt_field.dart';
import '../loans/loans_screen.dart';
import '../../widgets/aeris_toast.dart';

const _kLastAccountPref = 'last_txn_account';

/// Income-first ordering for the category chips when logging money in.
const _incomeFirst = ['salary', 'transfer', 'investment', 'other'];

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
  bool _scanning = false; // OCR running on a just-attached receipt

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
        _repeatMonthly,
        if (_editing || _categoryManual) _categoryId,
        if (_editing) _dir.name,
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
    final cat = learned ?? Categories.classify(m);
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
              if (c.id != 'salary') c,
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
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (s) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: GridView.count(
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
      if (!_categoryManual && wasDefault) _categoryId = _defaultCategory;
      _chips = _chipCategories();
      _recents = _editing
          ? const []
          : EntryChecks.recentTemplates(_txns, direction: _dir, limit: 8);
    });
    _syncGuard();
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

  Future<void> _attachReceipt() async {
    final picked = await pickReceipt(context);
    if (picked == null || !mounted) return;
    setState(() {
      _receipt = picked;
      _scanning = true;
    });
    _syncGuard();
    // Read the bill on-device and fill whatever is still empty — never
    // overwrite something the user already typed.
    final info = await ReceiptScanner.scan(picked);
    if (!mounted) return;
    setState(() => _scanning = false);
    if (info == null) return;
    // A payment screenshot knows whether the money came in or went out.
    if (info.direction != null && !_editing) _setDirection(info.direction!);
    final filled = <String>[];
    if (info.total != null && _amount.text.trim().isEmpty) {
      final s = _plain(info.total! / _rate);
      _amount.value = TextEditingValue(
          text: s, selection: TextSelection.collapsed(offset: s.length));
      filled.add(formatRupees(info.total!, decimals: info.total! % 1 != 0));
    }
    if (info.merchant != null && _merchant.text.trim().isEmpty) {
      _merchant.text = info.merchant!;
      _autoCategorizeFor(info.merchant!);
      filled.add(info.merchant!);
    }
    final d = info.date;
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
    if (filled.isNotEmpty) {
      ScaffoldMessenger.of(context).showToast(
          SnackBar(content: Text('Read from receipt: ${filled.join(' · ')}')));
    }
  }

  // ── Build ──────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
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
                        height: 34,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: _recents.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 8),
                          itemBuilder: (_, i) {
                            final t = _recents[i];
                            final c = Categories.byId(t.categoryId);
                            return ActionChip(
                              avatar: Icon(c.icon, size: 16, color: c.color),
                              label: Text(
                                  '${t.merchant} · ${formatRupees(t.amount)}'),
                              visualDensity: VisualDensity.compact,
                              onPressed: () => _applyRecent(t),
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
                    gap,
                    const _SectionLabel('Category'),
                    const SizedBox(height: 6),
                    SizedBox(
                      height: 40,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: [
                          for (final c in _chips) ...[
                            ChoiceChip(
                              avatar: Icon(c.icon, size: 16, color: c.color),
                              label: Text(_short(c.label)),
                              selected: c.id == _categoryId,
                              showCheckmark: false,
                              selectedColor: c.color.withValues(alpha: 0.18),
                              side: BorderSide(
                                  color: c.id == _categoryId
                                      ? c.color
                                      : scheme.outlineVariant),
                              onSelected: (_) => _pickCategory(c.id),
                            ),
                            const SizedBox(width: 8),
                          ],
                          ActionChip(
                            avatar:
                                const Icon(Icons.grid_view_rounded, size: 16),
                            label: const Text('All'),
                            onPressed: _openAllCategories,
                          ),
                        ],
                      ),
                    ),
                    gap,
                    const _SectionLabel('When'),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        ChoiceChip(
                          label: const Text('Today'),
                          selected: _sameDay(_when, now),
                          onSelected: (_) => _setDay(now),
                        ),
                        ChoiceChip(
                          label: const Text('Yesterday'),
                          selected: _sameDay(_when, yesterday),
                          onSelected: (_) => _setDay(yesterday),
                        ),
                        ChoiceChip(
                          avatar: Icon(Icons.calendar_today_rounded,
                              size: 16,
                              color: customDay
                                  ? scheme.onSecondaryContainer
                                  : scheme.onSurfaceVariant),
                          label: Text(customDay
                              ? DateFormat('d MMM yyyy').format(_when)
                              : 'Pick date'),
                          selected: customDay,
                          showCheckmark: false,
                          onSelected: (_) => _pickDate(),
                        ),
                        ActionChip(
                          avatar: const Icon(Icons.schedule_rounded, size: 16),
                          label: Text(
                              TimeOfDay.fromDateTime(_when).format(context)),
                          onPressed: _pickTime,
                        ),
                      ],
                    ),
                    gap,
                    if (_accounts.isNotEmpty) ...[
                      DropdownButtonFormField<String?>(
                        initialValue: _account,
                        isExpanded: true,
                        decoration: const InputDecoration(
                            labelText: 'Account (optional)',
                            prefixIcon: Icon(Icons.account_balance_rounded)),
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
                    TextField(
                      controller: _note,
                      maxLength: 200,
                      textCapitalization: TextCapitalization.sentences,
                      textInputAction: TextInputAction.done,
                      decoration: const InputDecoration(
                        labelText: 'Note (optional)',
                        prefixIcon: Icon(Icons.notes_rounded),
                        counterText: '',
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        if (_receipt == null)
                          ActionChip(
                            avatar: const Icon(Icons.document_scanner_outlined,
                                size: 16),
                            label: const Text('Scan receipt'),
                            onPressed: _attachReceipt,
                          )
                        else
                          InputChip(
                            avatar: _scanning
                                ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2))
                                : const Icon(Icons.receipt_long_rounded,
                                    size: 16),
                            label: Text(_scanning ? 'Reading…' : 'Receipt'),
                            onPressed: () =>
                                showReceiptViewer(context, _receipt!),
                            onDeleted: () {
                              setState(() => _receipt = null);
                              _syncGuard();
                            },
                          ),
                        if (!_editing && !income)
                          FilterChip(
                            avatar: const Icon(Icons.event_repeat_rounded,
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
                        // Money lent to / borrowed from a friend isn't a
                        // spend — it lives in "Lent & borrowed" until settled.
                        if (!_editing && !_dirty)
                          ActionChip(
                            avatar:
                                const Icon(Icons.handshake_outlined, size: 16),
                            label: const Text('Lent or borrowed?'),
                            onPressed: () => Navigator.pushReplacementNamed(
                                context, AppRoutes.loans,
                                arguments: LoansScreen.openAddSheet),
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
                color: AerisColors.accent(context),
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
          icon: Icons.copy_all_outlined,
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
        icon: Icons.priority_high_rounded,
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
    if (!await _passesChecks(amt) || !mounted) return;

    setState(() => _busy = true);
    final fs = ref.read(firestoreServiceProvider);
    final e = widget.existing;
    final merchant = _merchant.text.trim();
    final note = _note.text.trim();
    final t = Transaction(
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
      smsBody: e?.smsBody,
      smsSender: e?.smsSender,
      reviewed: true,
      reference: e?.reference,
      upiVpa: e?.upiVpa,
      hasReceipt: _receipt != null,
    );
    try {
      // Returns once queued locally — works offline via the sync outbox.
      await fs.addTransaction(uid, t);
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
    if (merchant.isNotEmpty) {
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
      content: Text(_editing
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

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) => Text(text,
      style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: Theme.of(context).colorScheme.onSurfaceVariant));
}

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
    final scheme = Theme.of(context).colorScheme;
    Widget seg(TxnDirection d, String label, IconData icon, Color color) {
      final on = d == dir;
      return Expanded(
        child: Semantics(
          button: true,
          selected: on,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => onDirection(d),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              decoration: on
                  ? AerisColors.cardDecoration(context, radius: 11)
                  : const BoxDecoration(),
              alignment: Alignment.center,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon,
                      size: 16, color: on ? color : scheme.onSurfaceVariant),
                  const SizedBox(width: 6),
                  // Flexible: narrow phones + large system font must shrink
                  // the label, never overflow the header.
                  Flexible(
                    child: Text(label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: on ? color : scheme.onSurfaceVariant)),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.fromLTRB(4, 4, showVoice ? 4 : 16, 0),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Close',
            icon: const Icon(Icons.close_rounded),
            onPressed: onClose,
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Container(
              height: 42,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  seg(TxnDirection.debit, 'Expense', Icons.south_west_rounded,
                      AerisColors.moneyOut(context)),
                  seg(TxnDirection.credit, 'Income', Icons.north_east_rounded,
                      AerisColors.moneyIn(context)),
                ],
              ),
            ),
          ),
          if (showVoice) ...[
            const SizedBox(width: 4),
            IconButton(
              tooltip: 'Say it instead',
              icon: const Icon(Icons.mic_none_rounded),
              color: AerisColors.accent(context),
              onPressed: onVoice,
            ),
          ],
        ],
      ),
    );
  }
}

/// The amount input with its operator rail attached underneath.
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
    final scheme = Theme.of(context).colorScheme;
    return TextFieldTapRegion(
      child: Container(
        // The amount is the one thing this screen is about: a raised white
        // card, outlined in red only when Save found it missing.
        decoration: AerisColors.cardDecoration(context, radius: 20).copyWith(
          border: error ? Border.all(color: scheme.error, width: 1.6) : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                autofocus: autofocus,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                textInputAction: TextInputAction.next,
                inputFormatters: [formatter],
                onChanged: (_) => onChanged(),
                style: TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w700,
                  color: color,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
                decoration: InputDecoration(
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 8),
                  hintText: '0',
                  hintStyle: TextStyle(
                      fontSize: 34,
                      fontWeight: FontWeight.w700,
                      color: scheme.onSurfaceVariant.withValues(alpha: 0.4)),
                  prefixIcon: Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Text(kCurrency.symbol.trim(),
                        style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w700,
                            color: scheme.onSurfaceVariant)),
                  ),
                  prefixIconConstraints:
                      const BoxConstraints(minWidth: 0, minHeight: 0),
                ),
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 6, 12, 6),
              child: Row(
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
            ),
          ],
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
        color: scheme.surfaceContainer,
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
            if ((used + amt) / cap > 0.8) color = AerisColors.warning;
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

/// Merchant / payer field with inline suggestions from past entries.
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: controller,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.done,
          onChanged: onChanged,
          decoration: InputDecoration(
            labelText: income ? 'Payer / source' : 'Merchant / payee',
            prefixIcon: const Icon(Icons.storefront_rounded),
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
            return Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final s in hits)
                    ActionChip(
                      label: Text(s),
                      visualDensity: VisualDensity.compact,
                      onPressed: () {
                        controller.value = TextEditingValue(
                            text: s,
                            selection:
                                TextSelection.collapsed(offset: s.length));
                        onChanged(s);
                      },
                    ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}

class _SaveBar extends StatelessWidget {
  final String label;
  final Color color;
  final bool busy;
  final VoidCallback onSave;
  const _SaveBar({
    required this.label,
    required this.color,
    required this.busy,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
      decoration: BoxDecoration(
        color: AerisColors.canvas(context),
        border: Border(
            top: BorderSide(
                color: scheme.outlineVariant.withValues(alpha: 0.5))),
      ),
      child: FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: color,
          foregroundColor: AerisColors.onAccent(context),
          minimumSize: const Size.fromHeight(50),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        onPressed: busy ? null : onSave,
        child: busy
            ? SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2.4, color: AerisColors.onAccent(context)))
            : Text(label,
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      ),
    );
  }
}

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
    final scheme = Theme.of(context).colorScheme;
    final c = category.color;
    return Material(
      color:
          selected ? c.withValues(alpha: 0.16) : scheme.surfaceContainerLowest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: selected ? c : scheme.outlineVariant.withValues(alpha: 0.5),
          width: selected ? 1.6 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(category.icon, size: 22, color: c),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(_short(category.label),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                    color:
                        selected ? scheme.onSurface : scheme.onSurfaceVariant,
                  )),
            ),
          ],
        ),
      ),
    );
  }
}
