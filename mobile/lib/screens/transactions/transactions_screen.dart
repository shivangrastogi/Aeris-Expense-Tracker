import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/routes.dart';
import '../../core/theme.dart';
import '../../models/category.dart';
import '../../models/loan.dart';
import '../../models/transaction.dart';
import '../../providers/accounts_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/budgets_provider.dart';
import '../../providers/loans_provider.dart';
import '../../providers/privacy_provider.dart';
import '../../providers/transactions_provider.dart';
import '../../services/export_service.dart';
import '../../services/search_query.dart';
import '../../utils/formatters.dart';
import '../../widgets/ds.dart';
import '../../widgets/skeleton.dart';
import '../../widgets/transaction_tile.dart';
import 'transaction_detail_screen.dart';
import '../../widgets/txn_undo.dart';
import '../loans/loans_screen.dart' show showAddLoanSheet;
import '../subscriptions/subscriptions_screen.dart';
import '../../utils/amount_input_formatter.dart';
import '../../widgets/aeris_toast.dart';

part 'transactions_list.dart';
part 'transactions_lent_subs.dart';

// ── Sort options ─────────────────────────────────────────────
enum _SortMode { recent, highest, lowest }

// ── Activity: Transactions · Lent · Subscriptions ────────────
class TransactionsScreen extends ConsumerStatefulWidget {
  final TxnDirection? initialDir;
  final String? initialCategory;
  final String? initialAccount;
  const TransactionsScreen(
      {super.key, this.initialDir, this.initialCategory, this.initialAccount});

  @override
  ConsumerState<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends ConsumerState<TransactionsScreen> {
  int _tab = 0; // 0=Transactions, 1=Lent, 2=Subs
  /// Tablet list–detail: the transaction open in the right pane.
  Transaction? _selected;
  String _query = '';
  Timer? _queryDebounce; // filter after typing pauses, not on every key
  TxnDirection? _filterDir;
  String? _filterCat;
  String? _filterAcct;
  _SortMode _sort = _SortMode.recent;
  double? _minAmount;
  double? _maxAmount;
  DateTimeRange? _dateRange;
  bool _exporting = false;
  final ScrollController _scroll = ScrollController();
  int _visible = 50;
  int _lastCount = 0;

  @override
  void initState() {
    super.initState();
    _filterDir = widget.initialDir;
    _filterCat = widget.initialCategory;
    _filterAcct = widget.initialAccount;
    _scroll.addListener(() {
      if (_scroll.hasClients &&
          _scroll.position.pixels >= _scroll.position.maxScrollExtent - 300 &&
          _visible < _lastCount) {
        setState(() => _visible += 50);
      }
    });
  }

  @override
  void dispose() {
    _queryDebounce?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  bool _inRange(DateTime t) {
    if (_dateRange == null) return true;
    final s = DateTime(
        _dateRange!.start.year, _dateRange!.start.month, _dateRange!.start.day);
    final e = DateTime(_dateRange!.end.year, _dateRange!.end.month,
        _dateRange!.end.day, 23, 59, 59);
    return !t.isBefore(s) && !t.isAfter(e);
  }

  void _clearAll() => setState(() {
        _sort = _SortMode.recent;
        _minAmount = null;
        _maxAmount = null;
        _dateRange = null;
        _filterDir = null;
        _filterCat = null;
        _filterAcct = null;
      });

  Future<void> _export() async {
    final messenger = ScaffoldMessenger.of(context);
    final txns = ref.read(transactionsStreamProvider).valueOrNull ?? const [];
    final budgets = ref.read(budgetsStreamProvider).valueOrNull ?? const [];
    if (txns.isEmpty) {
      messenger.showToast(
          const SnackBar(content: Text('No transactions to export yet.')));
      return;
    }
    setState(() => _exporting = true);
    try {
      await ExportService.instance.buildAndShare(txns: txns, budgets: budgets);
    } catch (e) {
      messenger.showToast(SnackBar(content: Text('Export failed: $e')));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  /// Removable chips for what's filtered beyond the quick row.
  List<(String, VoidCallback)> _activeChips() => [
        if (_filterCat != null)
          (
            Categories.byId(_filterCat!).label,
            () => setState(() => _filterCat = null)
          ),
        if (_dateRange != null)
          (
            '${shortDate(_dateRange!.start)} – ${shortDate(_dateRange!.end)}',
            () => setState(() => _dateRange = null)
          ),
        if (_minAmount != null || _maxAmount != null)
          (
            _minAmount != null && _maxAmount != null
                ? '${formatRupees(_minAmount!, compact: true)}–${formatRupees(_maxAmount!, compact: true)}'
                : _minAmount != null
                    ? 'Above ${formatRupees(_minAmount!, compact: true)}'
                    : 'Below ${formatRupees(_maxAmount!, compact: true)}',
            () => setState(() {
                  _minAmount = null;
                  _maxAmount = null;
                })
          ),
        if (_sort != _SortMode.recent)
          (
            _sort == _SortMode.highest ? 'Highest first' : 'Lowest first',
            () => setState(() => _sort = _SortMode.recent)
          ),
      ];

  @override
  Widget build(BuildContext context) {
    ref.watch(amountHiddenProvider);
    final tk = context.tk;
    final chips = _activeChips();

    final page = Scaffold(
      body: SafeArea(
        bottom: false,
        // The large title collapses into a slim bar once the list scrolls
        // (keyed by tab, so switching tabs starts expanded again).
        child: CollapseOnScroll(
          key: ValueKey(_tab),
          builder: (context, collapsed) => Column(
            children: [
              CollapsingHeader(
                title: 'Activity',
                collapsed: collapsed,
                actions: [
                  if (_tab == 0) ...[
                    IconButton(
                      icon: Icon(Ph.downloadSimple, size: 20, color: tk.t2),
                      tooltip: 'Import statement',
                      onPressed: () => Navigator.pushNamed(
                          context, AppRoutes.importStatement),
                    ),
                    const SizedBox(width: 4),
                    _ExportPill(busy: _exporting, onTap: _export),
                  ],
                ],
              ),
              // ── Transactions · Lent · Subscriptions ─────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                child: DsSegmented(
                  labels: const ['Transactions', 'Lent', 'Subscriptions'],
                  index: _tab,
                  height: 44,
                  onChanged: (i) => setState(() => _tab = i),
                ),
              ),
              Expanded(
                child: IndexedStack(
                  index: _tab,
                  children: [
                    _TransactionsTab(
                      query: _query,
                      filterDir: _filterDir,
                      filterCat: _filterCat,
                      filterAcct: _filterAcct,
                      sortMode: _sort,
                      minAmount: _minAmount,
                      maxAmount: _maxAmount,
                      inRange: _inRange,
                      visible: _visible,
                      scroll: _scroll,
                      onCountChange: (n) => _lastCount = n,
                      onQueryChange: (q) {
                        _queryDebounce?.cancel();
                        _queryDebounce =
                            Timer(const Duration(milliseconds: 200), () {
                          if (mounted) setState(() => _query = q);
                        });
                      },
                      onDirChange: (d) => setState(() => _filterDir = d),
                      onCatChange: (c) => setState(() => _filterCat = c),
                      onAcctChange: (a) => setState(() => _filterAcct = a),
                      onFilterTap: _showFilterSheet,
                      onClearAll: _clearAll,
                      activeChips: chips,
                      filterCount: chips.length,
                    ),
                    const _LentTab(),
                    const _SubsTab(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    // Tablets / unfolded foldables: list on the left, the picked transaction
    // on the right.
    return LayoutBuilder(builder: (context, box) {
      if (box.maxWidth < 760) return page;
      final tk = context.tk;
      final sel = _selected;
      return Row(children: [
        SizedBox(
          width: 420,
          child: TxnOpener(
            open: (t) => setState(() => _selected = t),
            child: page,
          ),
        ),
        Container(width: 1, color: tk.hair),
        Expanded(
          child: sel == null
              ? const Scaffold(
                  body: Center(
                    child: EmptyState(
                      icon: Ph.receipt,
                      title: 'Pick a transaction',
                      body: 'Its details, split and original SMS show here.',
                    ),
                  ),
                )
              : TransactionDetailScreen(
                  key: ValueKey(sel.id),
                  txn: sel,
                  onClose: () => setState(() => _selected = null),
                ),
        ),
      ]);
    });
  }

  void _showFilterSheet() {
    // Snapshot the current values into sheet-local state.
    var sheetSort = _sort;
    var sheetCat = _filterCat;
    final minCtrl = TextEditingController(text: inrToDisplayText(_minAmount));
    final maxCtrl = TextEditingController(text: inrToDisplayText(_maxAmount));
    var sheetRange = _dateRange;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final presets = <(String, DateTimeRange)>[
      (
        'This month',
        DateTimeRange(start: DateTime(now.year, now.month), end: today)
      ),
      (
        'Last month',
        DateTimeRange(
            start: DateTime(now.year, now.month - 1),
            end: DateTime(now.year, now.month, 0))
      ),
      (
        'Last 3 months',
        DateTimeRange(start: DateTime(now.year, now.month - 2), end: today)
      ),
      ('This year', DateTimeRange(start: DateTime(now.year), end: today)),
    ];
    bool same(DateTimeRange? a, DateTimeRange b) =>
        a != null &&
        DateUtils.isSameDay(a.start, b.start) &&
        DateUtils.isSameDay(a.end, b.end);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          final tk = ctx.tk;
          final isPreset = presets.any((p) => same(sheetRange, p.$2));
          final custom = sheetRange != null && !isPreset;
          Widget label(String s) => Padding(
                padding: const EdgeInsets.only(top: 14, bottom: 8),
                child: Overline(s),
              );
          return Padding(
            padding: EdgeInsets.fromLTRB(
                20, 0, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
            // The filters scroll; "Show results" stays pinned at the bottom.
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Expanded(
                            child: Text('Filters',
                                style: Ts.title.copyWith(color: tk.t1))),
                        TextLink('Reset', onTap: () {
                          Navigator.pop(ctx);
                          _clearAll();
                        }),
                      ]),
                      label('Date'),
                      Wrap(spacing: 8, runSpacing: 8, children: [
                        DsChip('Any time',
                            selected: sheetRange == null,
                            showCheck: true,
                            onTap: () => setSheet(() => sheetRange = null)),
                        for (final p in presets)
                          DsChip(p.$1,
                              selected: same(sheetRange, p.$2),
                              showCheck: true,
                              onTap: () => setSheet(() => sheetRange = p.$2)),
                        DsChip('Custom',
                            selected: custom,
                            showCheck: true,
                            onTap: () => setSheet(() => sheetRange =
                                DateTimeRange(
                                    start:
                                        today.subtract(const Duration(days: 6)),
                                    end: today))),
                      ]),
                      if (custom) ...[
                        const SizedBox(height: 10),
                        Row(children: [
                          Expanded(
                            child: _DateField(
                              label: 'From',
                              value: sheetRange?.start,
                              onTap: () async {
                                final picked = await showDatePicker(
                                  context: ctx,
                                  initialDate: sheetRange?.start ?? now,
                                  firstDate: DateTime(now.year - 5),
                                  lastDate: now,
                                );
                                if (picked != null) {
                                  setSheet(() => sheetRange = DateTimeRange(
                                        start: picked,
                                        end: sheetRange?.end ?? now,
                                      ));
                                }
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _DateField(
                              label: 'To',
                              value: sheetRange?.end,
                              onTap: () async {
                                final picked = await showDatePicker(
                                  context: ctx,
                                  initialDate: sheetRange?.end ?? now,
                                  firstDate: DateTime(now.year - 5),
                                  lastDate: now,
                                );
                                if (picked != null) {
                                  setSheet(() => sheetRange = DateTimeRange(
                                        start: sheetRange?.start ?? picked,
                                        end: picked,
                                      ));
                                }
                              },
                            ),
                          ),
                        ]),
                      ],
                      label('Amount'),
                      Row(children: [
                        Expanded(
                          child: TextField(
                            controller: minCtrl,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                                hintText: 'Min',
                                prefixText: '${kCurrency.symbol} '),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: maxCtrl,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                                hintText: 'Max',
                                prefixText: '${kCurrency.symbol} '),
                          ),
                        ),
                      ]),
                      label('Sort'),
                      Wrap(spacing: 8, runSpacing: 8, children: [
                        for (final (m, l) in const [
                          (_SortMode.recent, 'Most recent'),
                          (_SortMode.highest, 'Highest amount'),
                          (_SortMode.lowest, 'Lowest amount'),
                        ])
                          DsChip(l,
                              selected: sheetSort == m,
                              showCheck: true,
                              onTap: () => setSheet(() => sheetSort = m)),
                      ]),
                      label('Categories'),
                      GridView.count(
                        crossAxisCount: 4,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        mainAxisSpacing: 8,
                        crossAxisSpacing: 8,
                        childAspectRatio: 0.95,
                        children: [
                          for (final c in Categories.all)
                            _CatPick(
                              category: c,
                              selected: sheetCat == c.id,
                              onTap: () => setSheet(() =>
                                  sheetCat = sheetCat == c.id ? null : c.id),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.only(top: 12),
                decoration: BoxDecoration(
                    border: Border(top: BorderSide(color: tk.hair))),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      setState(() {
                        _sort = sheetSort;
                        _filterCat = sheetCat;
                        // Typed in display currency; amounts are INR.
                        _minAmount = displayToInr(minCtrl.text);
                        _maxAmount = displayToInr(maxCtrl.text);
                        _dateRange = sheetRange;
                      });
                    },
                    child: const Text('Show results'),
                  ),
                ),
              ),
            ]),
          );
        },
      ),
    );
  }
}

// ── "Export" outline pill ─────────────────────────────────────
class _ExportPill extends StatelessWidget {
  final bool busy;
  final VoidCallback onTap;
  const _ExportPill({required this.busy, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final tk = context.tk;
    return Material(
      color: tk.surface,
      shape: StadiumBorder(
          side: tk.isDark ? BorderSide(color: tk.hair) : BorderSide.none),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: busy ? null : onTap,
        child: Container(
          height: 40,
          padding: const EdgeInsets.fromLTRB(12, 0, 14, 0),
          decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20), boxShadow: tk.shadow),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            busy
                ? const RisingLoader(width: 18)
                : Icon(Ph.export, size: 18, color: tk.t1),
            const SizedBox(width: 6),
            Text('Export',
                style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600, color: tk.t1)),
          ]),
        ),
      ),
    );
  }
}

// ── Category cell in the filter sheet / category picker ───────
class _CatPick extends StatelessWidget {
  final ExpenseCategory category;
  final bool selected;
  final VoidCallback onTap;
  const _CatPick(
      {required this.category, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final tk = context.tk;
    return Semantics(
      button: true,
      selected: selected,
      label: category.label,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Rad.tile),
        child: AnimatedContainer(
          duration: Mo.standard,
          curve: Mo.curve,
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          decoration: BoxDecoration(
            color: selected ? tk.accSoft : Colors.transparent,
            borderRadius: BorderRadius.circular(Rad.tile),
            border: Border.all(
                color: selected ? tk.acc : Colors.transparent, width: 1.5),
          ),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            CatTile.of(category, size: 36),
            const SizedBox(height: 6),
            Text(category.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: selected ? tk.acc : tk.t1)),
          ]),
        ),
      ),
    );
  }
}

// ── Date field for the filter sheet ───────────────────────────
class _DateField extends StatelessWidget {
  final String label;
  final DateTime? value;
  final VoidCallback onTap;
  const _DateField(
      {required this.label, required this.value, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final tk = context.tk;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Rad.input),
      child: Container(
        height: 52,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: tk.field,
          borderRadius: BorderRadius.circular(Rad.input),
          border: Border.all(color: tk.hair),
        ),
        child: Row(children: [
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(fontSize: 11, color: tk.t2)),
                Text(value == null ? 'Pick a date' : shortDate(value!),
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: value == null ? tk.t3 : tk.t1)),
              ],
            ),
          ),
          Icon(Ph.calendarBlank, size: 18, color: tk.t2),
        ]),
      ),
    );
  }
}
