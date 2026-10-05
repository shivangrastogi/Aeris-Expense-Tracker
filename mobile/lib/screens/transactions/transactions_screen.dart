import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/routes.dart';
import '../../core/theme.dart';
import '../../models/category.dart';
import '../../models/loan.dart';
import '../../models/transaction.dart';
import '../../providers/auth_provider.dart';
import '../../providers/loans_provider.dart';
import '../../providers/privacy_provider.dart';
import '../../providers/transactions_provider.dart';
import '../../services/search_query.dart';
import '../../utils/motion.dart';
import '../../utils/formatters.dart';
import '../../widgets/transaction_tile.dart';
import '../../widgets/txn_undo.dart';
import '../subscriptions/subscriptions_screen.dart';
import '../../utils/amount_input_formatter.dart';
import '../../widgets/aeris_toast.dart';

part 'transactions_list.dart';
part 'transactions_lent_subs.dart';

// ── Sort options ─────────────────────────────────────────────
enum _SortMode { recent, highest, lowest }

// ── Transactions Screen with embedded Lent + Subs tabs ───────
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
  String _query = '';
  Timer? _queryDebounce; // filter after typing pauses, not on every key
  TxnDirection? _filterDir;
  String? _filterCat;
  _SortMode _sort = _SortMode.recent;
  double? _minAmount;
  double? _maxAmount;
  DateTimeRange? _dateRange;
  final ScrollController _scroll = ScrollController();
  int _visible = 50;
  int _lastCount = 0;

  @override
  void initState() {
    super.initState();
    _filterDir = widget.initialDir;
    _filterCat = widget.initialCategory;
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

  @override
  Widget build(BuildContext context) {
    ref.watch(amountHiddenProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Activity',
            style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5)),
        actions: [
          if (_tab == 0)
            IconButton(
              icon: const Icon(Icons.upload_file_outlined),
              tooltip: 'Import statement',
              onPressed: () =>
                  Navigator.pushNamed(context, AppRoutes.importStatement),
            ),
        ],
      ),
      body: Column(
        children: [
          // ── Tab bar ─────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: _TabBar(
              selected: _tab,
              onTap: (i) => setState(() => _tab = i),
              isDark: isDark,
            ),
          ),
          // ── Tab content ──────────────────────────────────────
          Expanded(
            child: IndexedStack(
              index: _tab,
              children: [
                _TransactionsTab(
                  query: _query,
                  filterDir: _filterDir,
                  filterCat: _filterCat,
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
                  onFilterTap: () => _showFilterSheet(),
                  hasActiveFilter: _minAmount != null ||
                      _maxAmount != null ||
                      _dateRange != null ||
                      _sort != _SortMode.recent,
                ),
                const _LentTab(),
                const _SubsTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showFilterSheet() {
    // snapshot current values to sheet-local state
    var sheetSort = _sort;
    final minCtrl =
        TextEditingController(text: inrToDisplayText(_minAmount));
    final maxCtrl =
        TextEditingController(text: inrToDisplayText(_maxAmount));
    var sheetRange = _dateRange;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).brightness == Brightness.dark
          ? AerisColors.cardDark
          : Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.fromLTRB(
              20, 4, 20, MediaQuery.of(ctx).viewInsets.bottom + 24),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Filter & sort',
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5)),
                const SizedBox(height: 18),
                Text('SORT BY',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                        color: AerisColors.ink(context))),
                const SizedBox(height: 8),
                _sortOption(ctx, sheetSort, _SortMode.recent, Icons.access_time,
                    'Most recent', (v) => setSheet(() => sheetSort = v)),
                const SizedBox(height: 6),
                _sortOption(
                    ctx,
                    sheetSort,
                    _SortMode.highest,
                    Icons.arrow_downward,
                    'Highest amount',
                    (v) => setSheet(() => sheetSort = v)),
                const SizedBox(height: 6),
                _sortOption(
                    ctx,
                    sheetSort,
                    _SortMode.lowest,
                    Icons.arrow_upward,
                    'Lowest amount',
                    (v) => setSheet(() => sheetSort = v)),
                const SizedBox(height: 20),
                Text('AMOUNT RANGE (₹)',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                        color: AerisColors.ink(context))),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: minCtrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        hintText: 'Min',
                        hintStyle: TextStyle(
                            color: Theme.of(ctx).colorScheme.onSurfaceVariant),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(
                                color:
                                    Theme.of(ctx).colorScheme.outlineVariant)),
                        enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(
                                color:
                                    Theme.of(ctx).colorScheme.outlineVariant)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: maxCtrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        hintText: 'Max',
                        hintStyle: TextStyle(
                            color: Theme.of(ctx).colorScheme.onSurfaceVariant),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(
                                color:
                                    Theme.of(ctx).colorScheme.outlineVariant)),
                        enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(
                                color:
                                    Theme.of(ctx).colorScheme.outlineVariant)),
                      ),
                    ),
                  ),
                ]),
                const SizedBox(height: 20),
                Text('DATE RANGE',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                        color: AerisColors.ink(context))),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                    child: _DateField(
                      label: 'From',
                      value: sheetRange?.start,
                      onTap: () async {
                        final now = DateTime.now();
                        final picked = await showDatePicker(
                          context: ctx,
                          initialDate: sheetRange?.start ?? now,
                          firstDate: DateTime(now.year - 5),
                          lastDate: now,
                        );
                        if (picked != null) {
                          setSheet(() {
                            sheetRange = DateTimeRange(
                              start: picked,
                              end: sheetRange?.end ?? now,
                            );
                          });
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _DateField(
                      label: 'To',
                      value: sheetRange?.end,
                      onTap: () async {
                        final now = DateTime.now();
                        final picked = await showDatePicker(
                          context: ctx,
                          initialDate: sheetRange?.end ?? now,
                          firstDate: DateTime(now.year - 5),
                          lastDate: now,
                        );
                        if (picked != null) {
                          setSheet(() {
                            sheetRange = DateTimeRange(
                              start: sheetRange?.start ?? picked,
                              end: picked,
                            );
                          });
                        }
                      },
                    ),
                  ),
                ]),
                const SizedBox(height: 28),
                Row(children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        Navigator.pop(ctx);
                        setState(() {
                          _sort = _SortMode.recent;
                          _minAmount = null;
                          _maxAmount = null;
                          _dateRange = null;
                          _filterDir = null;
                        });
                      },
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      child: const Text('Reset',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: FilledButton(
                      onPressed: () {
                        Navigator.pop(ctx);
                        setState(() {
                          _sort = sheetSort;
                          // Typed in display currency; amounts are INR.
                          _minAmount = displayToInr(minCtrl.text);
                          _maxAmount = displayToInr(maxCtrl.text);
                          _dateRange = sheetRange;
                        });
                      },
                      style: FilledButton.styleFrom(
                        backgroundColor: AerisColors.accent(context),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      child: const Text('Apply filters',
                          style: TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 15)),
                    ),
                  ),
                ]),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _sortOption(
    BuildContext ctx,
    _SortMode current,
    _SortMode value,
    IconData icon,
    String label,
    void Function(_SortMode) onSelect,
  ) {
    final selected = current == value;
    final isDark = Theme.of(ctx).brightness == Brightness.dark;
    return GestureDetector(
      onTap: () => onSelect(value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: selected
              ? AerisColors.accent(context)
                  .withValues(alpha: isDark ? 0.18 : 0.10)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected
                ? AerisColors.accent(context).withValues(alpha: 0.60)
                : Theme.of(ctx)
                    .colorScheme
                    .outlineVariant
                    .withValues(alpha: 0.5),
          ),
        ),
        child: Row(children: [
          Icon(icon,
              size: 18,
              color: selected
                  ? AerisColors.accent(context)
                  : Theme.of(ctx).colorScheme.onSurfaceVariant),
          const SizedBox(width: 12),
          Text(label,
              style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected
                      ? AerisColors.ink(context)
                      : Theme.of(ctx).colorScheme.onSurface)),
          const Spacer(),
          if (selected)
            Icon(Icons.check_circle,
                color: AerisColors.accent(context), size: 20),
        ]),
      ),
    );
  }
}

// ── Top tab bar ───────────────────────────────────────────────
class _TabBar extends StatelessWidget {
  final int selected;
  final ValueChanged<int> onTap;
  final bool isDark;
  const _TabBar(
      {required this.selected, required this.onTap, required this.isDark});

  @override
  Widget build(BuildContext context) {
    // A quiet segmented control: the selected segment is a raised card, not
    // a solid accent block — the accent stays reserved for actions.
    return Container(
      height: 42,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          _tab(context, 0, 'Transactions'),
          _tab(context, 1, 'Lent'),
          _tab(context, 2, 'Subscriptions'),
        ],
      ),
    );
  }

  Widget _tab(BuildContext context, int idx, String label) {
    final sel = selected == idx;
    return Expanded(
      child: Semantics(
        button: true,
        selected: sel,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => onTap(idx),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            decoration: sel
                ? AerisColors.cardDecoration(context, radius: 11)
                : const BoxDecoration(),
            child: Center(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                  color: sel
                      ? Theme.of(context).colorScheme.onSurface
                      : AerisColors.muted(context),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Date field for filter sheet ───────────────────────────────
class _DateField extends StatelessWidget {
  final String label;
  final DateTime? value;
  final VoidCallback onTap;
  const _DateField(
      {required this.label, required this.value, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label,
          style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurfaceVariant)),
      const SizedBox(height: 4),
      GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
          decoration: BoxDecoration(
            border: Border.all(
                color: Theme.of(context)
                    .colorScheme
                    .outlineVariant
                    .withValues(alpha: 0.5)),
            borderRadius: BorderRadius.circular(14),
            color: isDark
                ? Colors.white.withValues(alpha: 0.04)
                : Colors.black.withValues(alpha: 0.03),
          ),
          child: Row(children: [
            Expanded(
              child: Text(
                value == null
                    ? 'dd-mm-yyyy'
                    : '${value!.day.toString().padLeft(2, '0')}-'
                        '${value!.month.toString().padLeft(2, '0')}-'
                        '${value!.year}',
                style: TextStyle(
                  fontSize: 13,
                  color: value == null
                      ? Theme.of(context).colorScheme.onSurfaceVariant
                      : Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ),
            Icon(Icons.calendar_month_outlined,
                size: 17,
                color: Theme.of(context).colorScheme.onSurfaceVariant),
          ]),
        ),
      ),
    ]);
  }
}
