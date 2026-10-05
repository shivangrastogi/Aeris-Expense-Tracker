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
import '../../utils/motion.dart';
import '../../utils/formatters.dart';
import '../../widgets/transaction_tile.dart';
import '../../widgets/txn_undo.dart';
import '../loans/loans_screen.dart';
import '../subscriptions/subscriptions_screen.dart';
import '../../utils/amount_input_formatter.dart';

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
          ? const Color(0xFF13211F)
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
                        backgroundColor: AerisColors.seed,
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
              ? AerisColors.seed.withValues(alpha: isDark ? 0.18 : 0.10)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected
                ? AerisColors.seed.withValues(alpha: 0.60)
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
                  ? AerisColors.seed
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
            const Icon(Icons.check_circle, color: AerisColors.seed, size: 20),
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
    return Container(
      height: 44,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF0F1B1C)
            : Colors.black.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          _tab(context, 0, 'Transactions'),
          _tab(context, 1, 'Lent'),
          _tab(context, 2, 'Subs'),
        ],
      ),
    );
  }

  Widget _tab(BuildContext context, int idx, String label) {
    final sel = selected == idx;
    return Expanded(
      child: GestureDetector(
        onTap: () => onTap(idx),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          decoration: BoxDecoration(
            color: sel ? AerisColors.seed : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                color: sel
                    ? Colors.white
                    : Theme.of(context).colorScheme.onSurfaceVariant,
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

// ── Transactions sub-tab ──────────────────────────────────────
class _TransactionsTab extends ConsumerStatefulWidget {
  final String query;
  final TxnDirection? filterDir;
  final String? filterCat;
  final _SortMode sortMode;
  final double? minAmount;
  final double? maxAmount;
  final bool Function(DateTime) inRange;
  final int visible;
  final ScrollController scroll;
  final void Function(int) onCountChange;
  final ValueChanged<String> onQueryChange;
  final ValueChanged<TxnDirection?> onDirChange;
  final ValueChanged<String?> onCatChange;
  final VoidCallback onFilterTap;
  final bool hasActiveFilter;

  const _TransactionsTab({
    required this.query,
    required this.filterDir,
    required this.filterCat,
    required this.sortMode,
    required this.minAmount,
    required this.maxAmount,
    required this.inRange,
    required this.visible,
    required this.scroll,
    required this.onCountChange,
    required this.onQueryChange,
    required this.onDirChange,
    required this.onCatChange,
    required this.onFilterTap,
    required this.hasActiveFilter,
  });

  @override
  ConsumerState<_TransactionsTab> createState() => _TransactionsTabState();
}

class _TransactionsTabState extends ConsumerState<_TransactionsTab> {
  bool _selectMode = false;
  final Set<String> _picked = {};

  void _toggle(String id) => setState(() {
        if (_picked.contains(id)) {
          _picked.remove(id);
          if (_picked.isEmpty) _selectMode = false;
        } else {
          _picked.add(id);
        }
      });

  void _exitSelect() => setState(() {
        _selectMode = false;
        _picked.clear();
      });

  // Long-press a row to enter select mode with that row already picked.
  void _enterSelect(String id) => setState(() {
        _selectMode = true;
        _picked.add(id);
      });

  Future<void> _deletePicked() async {
    final all = ref.read(transactionsStreamProvider).valueOrNull ??
        const <Transaction>[];
    final picked = all.where((t) => _picked.contains(t.id)).toList();
    _exitSelect();
    // Deletes now, with an UNDO that restores every one of them.
    await deleteTransactionsWithUndo(context, ref, picked);
  }

  void _recategorizePicked() {
    final all = ref.read(transactionsStreamProvider).valueOrNull ??
        const <Transaction>[];
    _recategorize(all.where((t) => _picked.contains(t.id)).toList());
  }

  // Swipe-to-delete: deletes now with the usual UNDO snackbar.
  Future<void> _swipeDelete(Transaction t) =>
      deleteTransactionsWithUndo(context, ref, [t]);

  /// Category picker for [picked] (a swipe on one row, or the selection).
  void _recategorize(List<Transaction> picked) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Recategorize ${picked.length}',
              style:
                  const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          const SizedBox(height: 14),
          GridView.count(
            crossAxisCount: 4,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 0.85,
            children: [
              for (final c in Categories.all)
                GestureDetector(
                  onTap: () async {
                    final uid = ref.read(currentUserIdProvider);
                    final fs = ref.read(firestoreServiceProvider);
                    if (uid != null) {
                      for (final t in picked) {
                        await fs.updateTransaction(
                            uid, t.copyWith(categoryId: c.id));
                      }
                    }
                    if (ctx.mounted) Navigator.pop(ctx);
                    final n = picked.length;
                    if (_selectMode) _exitSelect();
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('$n recategorized')));
                    }
                  },
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                          color: c.color,
                          borderRadius: BorderRadius.circular(16)),
                      child: Icon(c.icon, color: Colors.white, size: 24),
                    ),
                    const SizedBox(height: 5),
                    Text(c.label.split(' ').first,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 10, fontWeight: FontWeight.w700)),
                  ]),
                ),
            ],
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final txns = ref.watch(transactionsStreamProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      children: [
        // ── Select-mode header — entered by long-pressing any row ────
        if (_selectMode)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Row(children: [
              Text('${_picked.length} selected',
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w800)),
              const Spacer(),
              TextButton.icon(
                onPressed: _exitSelect,
                icon: const Icon(Icons.close, size: 18),
                label: const Text('Cancel'),
                style: TextButton.styleFrom(
                    foregroundColor:
                        Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ]),
          ),
        // ── Search bar ──────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: TextField(
            onChanged: widget.onQueryChange,
            decoration: InputDecoration(
              hintText: 'Search merchant, note, category, amount',
              hintStyle: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 14),
              prefixIcon: Icon(Icons.search_outlined,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  size: 20),
              filled: true,
              fillColor: isDark
                  ? const Color(0xFF0F1B1C)
                  : Colors.black.withValues(alpha: 0.05),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
              isDense: true,
            ),
          ),
        ),
        // ── Single scrollable filter row: Filter | All | Debit | Credit | ─── | Categories…
        SizedBox(
          height: 38,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
            children: [
              // Filter chip
              GestureDetector(
                onTap: widget.onFilterTap,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: widget.hasActiveFilter
                          ? AerisColors.seed
                          : (isDark
                              ? Colors.white.withValues(alpha: 0.18)
                              : Colors.black.withValues(alpha: 0.18)),
                      width: widget.hasActiveFilter ? 1.5 : 1,
                    ),
                    borderRadius: BorderRadius.circular(10),
                    color: widget.hasActiveFilter
                        ? AerisColors.seed.withValues(alpha: 0.10)
                        : Colors.transparent,
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.tune,
                        size: 16,
                        color: widget.hasActiveFilter
                            ? AerisColors.seed
                            : Theme.of(context).colorScheme.onSurface),
                    const SizedBox(width: 5),
                    Text('Filter',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: widget.hasActiveFilter
                                ? AerisColors.ink(context)
                                : Theme.of(context).colorScheme.onSurface)),
                  ]),
                ),
              ),
              const SizedBox(width: 10),
              // Dir pills
              _dirPill(context, null, 'All', isDark),
              const SizedBox(width: 8),
              _dirPill(context, TxnDirection.debit, 'Debit', isDark,
                  icon: Icons.south_west,
                  iconColor: AerisColors.moneyOut(context)),
              const SizedBox(width: 8),
              _dirPill(context, TxnDirection.credit, 'Credit', isDark,
                  icon: Icons.north_east,
                  iconColor: AerisColors.moneyIn(context)),
              // Thin divider
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                child: VerticalDivider(
                  width: 1,
                  thickness: 1,
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.15)
                      : Colors.black.withValues(alpha: 0.12),
                ),
              ),
              // Category pills
              _catPill(context, null, 'All', null, null, isDark),
              for (final cat in Categories.all) ...[
                const SizedBox(width: 8),
                _catPill(
                    context, cat.id, cat.label, cat.icon, cat.color, isDark),
              ],
            ],
          ),
        ),
        const SizedBox(height: 10),
        // ── Transaction list ─────────────────────────────────
        Expanded(
          child: txns.when(
            loading: () => _skeleton(context, isDark),
            error: (e, _) => Center(child: Text('$e')),
            data: (list) {
              // Case-folded once here — the raw query comes straight from the
              // TextField, so comparing it against lower-cased fields used to
              // miss anything the user typed with a capital ("Swiggy").
              final q = widget.query.trim().toLowerCase();
              var filtered = list.where((t) {
                if (widget.filterDir != null && t.direction != widget.filterDir) {
                  return false;
                }
                if (widget.filterCat != null &&
                    t.categoryId != widget.filterCat) {
                  return false;
                }
                if (!widget.inRange(t.timestamp)) return false;
                if (widget.minAmount != null && t.amount < widget.minAmount!) {
                  return false;
                }
                if (widget.maxAmount != null && t.amount > widget.maxAmount!) {
                  return false;
                }
                if (q.isEmpty) return true;
                return (t.merchant ?? '').toLowerCase().contains(q) ||
                    (t.note ?? '').toLowerCase().contains(q) ||
                    Categories.byId(t.categoryId)
                        .label
                        .toLowerCase()
                        .contains(q) ||
                    t.amount.toString().contains(q);
              }).toList();

              // Sort
              switch (widget.sortMode) {
                case _SortMode.highest:
                  filtered.sort((a, b) => b.amount.compareTo(a.amount));
                  break;
                case _SortMode.lowest:
                  filtered.sort((a, b) => a.amount.compareTo(b.amount));
                  break;
                case _SortMode.recent:
                  filtered.sort((a, b) => b.timestamp.compareTo(a.timestamp));
                  break;
              }

              widget.onCountChange(filtered.length);
              if (filtered.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.receipt_long_outlined,
                          size: 48,
                          color: Theme.of(context)
                              .colorScheme
                              .onSurfaceVariant
                              .withValues(alpha: 0.4)),
                      const SizedBox(height: 12),
                      Text('No transactions match.',
                          style: TextStyle(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant)),
                    ],
                  ),
                );
              }

              final shown = filtered.length > widget.visible
                  ? widget.visible
                  : filtered.length;
              final groups = _groupByDate(filtered.sublist(0, shown));

              // One sliver group per day: its header stays pinned at the top
              // while that day's rows scroll under it, then hands over to the
              // next day's header.
              return CustomScrollView(
                controller: widget.scroll,
                slivers: [
                  for (final group in groups)
                    SliverMainAxisGroup(slivers: [
                      SliverPersistentHeader(
                        pinned: true,
                        delegate: _DayHeaderDelegate(
                          date: group.key,
                          total: group.value
                              .fold<double>(0, (s, t) => s + t.signed),
                        ),
                      ),
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        sliver: SliverToBoxAdapter(
                          child: _DateGroup(
                              txns: group.value,
                              isDark: isDark,
                              selectMode: _selectMode,
                              picked: _picked,
                              onToggle: _toggle,
                              onLongPress: _enterSelect,
                              onSwipeDelete: _swipeDelete,
                              onSwipeCategory: (t) => _recategorize([t])),
                        ),
                      ),
                    ]),
                ],
              );
            },
          ),
        ),
        // ── Bulk action bar ──────────────────────────────────
        if (_selectMode && _picked.isNotEmpty)
          Container(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              border: Border(
                  top: BorderSide(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.08))),
            ),
            child: Row(children: [
              GestureDetector(
                onTap: _deletePicked,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
                  decoration: BoxDecoration(
                    border: Border.all(color: AerisColors.moneyOut(context)),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.delete_outline_rounded,
                        size: 18, color: AerisColors.moneyOut(context)),
                    const SizedBox(width: 6),
                    Text('Delete',
                        style: TextStyle(
                            color: AerisColors.moneyOut(context),
                            fontWeight: FontWeight.w800,
                            fontSize: 13.5)),
                  ]),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: GestureDetector(
                  onTap: _recategorizePicked,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AerisColors.seed,
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.category_outlined,
                              size: 18, color: Colors.white),
                          SizedBox(width: 6),
                          Text('Recategorize',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 13.5)),
                        ]),
                  ),
                ),
              ),
            ]),
          ),
      ],
    );
  }

  Widget _dirPill(
      BuildContext context, TxnDirection? dir, String label, bool isDark,
      {IconData? icon, Color? iconColor}) {
    final sel = widget.filterDir == dir;
    return GestureDetector(
      onTap: () => widget.onDirChange(dir),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: sel ? AerisColors.seed : Colors.transparent,
          borderRadius: BorderRadius.circular(99),
          border: Border.all(
            color: sel
                ? AerisColors.seed
                : (isDark
                    ? Colors.white.withValues(alpha: 0.18)
                    : Colors.black.withValues(alpha: 0.18)),
          ),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[
            Icon(icon,
                size: 14,
                color: sel ? Colors.white : (iconColor ?? AerisColors.seed)),
            const SizedBox(width: 4),
          ],
          Text(label,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: sel
                      ? Colors.white
                      : Theme.of(context).colorScheme.onSurface)),
        ]),
      ),
    );
  }

  Widget _catPill(BuildContext context, String? catId, String label,
      IconData? icon, Color? color, bool isDark) {
    final sel = widget.filterCat == catId;
    final activeColor = color ?? AerisColors.seed;
    return GestureDetector(
      onTap: () => widget.onCatChange(sel ? null : catId),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        decoration: BoxDecoration(
          color: sel ? activeColor.withValues(alpha: 0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(99),
          border: Border.all(
            color: sel
                ? activeColor
                : (isDark
                    ? Colors.white.withValues(alpha: 0.18)
                    : Colors.black.withValues(alpha: 0.18)),
          ),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[
            Icon(icon,
                size: 13,
                color: sel
                    ? activeColor
                    : Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(width: 4),
          ],
          Text(label,
              style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                  color: sel
                      ? activeColor
                      : Theme.of(context).colorScheme.onSurface)),
        ]),
      ),
    );
  }

  Widget _skeleton(BuildContext context, bool isDark) {
    final base = isDark
        ? Colors.white.withValues(alpha: 0.06)
        : Colors.black.withValues(alpha: 0.06);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        for (var i = 0; i < 7; i++)
          Container(
            height: 54,
            margin: const EdgeInsets.symmetric(vertical: 4),
            decoration: BoxDecoration(
                color: base, borderRadius: BorderRadius.circular(14)),
          ).shimmerLoop(context,
              duration: 1200.ms,
              color:
                  Theme.of(context).colorScheme.surface.withValues(alpha: 0.5)),
      ],
    );
  }

  List<MapEntry<String, List<Transaction>>> _groupByDate(
      List<Transaction> txns) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));

    final map = <String, List<Transaction>>{};
    for (final t in txns) {
      final d = DateTime(t.timestamp.year, t.timestamp.month, t.timestamp.day);
      String key;
      if (d == today) {
        key = 'Today';
      } else if (d == yesterday) {
        key = 'Yesterday';
      } else {
        final weekday = const [
          'Mon',
          'Tue',
          'Wed',
          'Thu',
          'Fri',
          'Sat',
          'Sun'
        ][d.weekday - 1];
        final month = const [
          '',
          'Jan',
          'Feb',
          'Mar',
          'Apr',
          'May',
          'Jun',
          'Jul',
          'Aug',
          'Sep',
          'Oct',
          'Nov',
          'Dec'
        ][d.month];
        key = '$weekday, ${d.day} $month';
      }
      map.putIfAbsent(key, () => []).add(t);
    }
    return map.entries.toList();
  }
}

// ── Pinned day header: "Tue, 24 Sep ········· −₹1,240" ────────
class _DayHeaderDelegate extends SliverPersistentHeaderDelegate {
  final String date;
  final double total;
  const _DayHeaderDelegate({required this.date, required this.total});

  static const _h = 34.0;
  @override
  double get minExtent => _h;
  @override
  double get maxExtent => _h;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlaps) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final sign = total > 0 ? '+' : (total < 0 ? '−' : '');
    return Container(
      // Opaque, so rows scrolling underneath don't show through.
      color: Theme.of(context).scaffoldBackgroundColor,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      alignment: Alignment.center,
      child: Row(children: [
        Text(date,
            style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w700, color: muted)),
        const Spacer(),
        Text('$sign${formatRupees(total.abs())}',
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: total >= 0
                    ? AerisColors.moneyIn(context)
                    : AerisColors.moneyOut(context))),
      ]),
    );
  }

  @override
  bool shouldRebuild(_DayHeaderDelegate old) =>
      old.date != date || old.total != total;
}

// ── One day's transactions card, with swipe actions ───────────
class _DateGroup extends StatelessWidget {
  final List<Transaction> txns;
  final bool isDark;
  final bool selectMode;
  final Set<String> picked;
  final ValueChanged<String> onToggle;
  final ValueChanged<String> onLongPress;
  final ValueChanged<Transaction> onSwipeDelete;
  final ValueChanged<Transaction> onSwipeCategory;
  const _DateGroup(
      {required this.txns,
      required this.isDark,
      this.selectMode = false,
      this.picked = const {},
      required this.onToggle,
      required this.onLongPress,
      required this.onSwipeDelete,
      required this.onSwipeCategory});

  @override
  Widget build(BuildContext context) {
    final cardColor = isDark ? const Color(0xFF14221F) : Colors.white;
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.07);

    return Container(
      clipBehavior: Clip.hardEdge,
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.05),
              blurRadius: 8,
              offset: const Offset(0, 3)),
        ],
      ),
      child: Column(children: [
        for (int i = 0; i < txns.length; i++) ...[
          if (selectMode)
            _selectableTile(context, txns[i])
          else
            _swipeable(
              context,
              txns[i],
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onLongPress: () => onLongPress(txns[i].id),
                child: TransactionTile(txn: txns[i]),
              ),
            ),
          if (i < txns.length - 1)
            Divider(
              height: 1,
              indent: 70,
              endIndent: 16,
              color: isDark
                  ? Colors.white.withValues(alpha: 0.06)
                  : Colors.black.withValues(alpha: 0.05),
            ),
        ],
      ]),
    );
  }

  /// Swipe left → delete (with UNDO). Swipe right → change category.
  /// The row always springs back; the list updates from the data stream, so
  /// Dismissible never has to remove a row the stream still contains.
  Widget _swipeable(BuildContext context, Transaction t, Widget child) {
    Widget bg(Color c, IconData icon, String label, Alignment a) => Container(
          color: c,
          alignment: a,
          padding: const EdgeInsets.symmetric(horizontal: 22),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: Colors.white, size: 20),
              const SizedBox(width: 6),
              Text(label,
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 13)),
            ],
          ),
        );
    return Dismissible(
      key: ValueKey('swipe-${t.id}'),
      background: bg(AerisColors.seed, Icons.category_outlined, 'Category',
          Alignment.centerLeft),
      secondaryBackground: bg(AerisColors.moneyOut(context),
          Icons.delete_outline_rounded, 'Delete', Alignment.centerRight),
      dismissThresholds: const {
        DismissDirection.startToEnd: 0.3,
        DismissDirection.endToStart: 0.3,
      },
      confirmDismiss: (dir) async {
        if (dir == DismissDirection.endToStart) {
          onSwipeDelete(t);
        } else {
          onSwipeCategory(t);
        }
        return false;
      },
      child: child,
    );
  }

  Widget _selectableTile(BuildContext context, Transaction t) {
    final on = picked.contains(t.id);
    final scheme = Theme.of(context).colorScheme;
    return Container(
      color: on ? AerisColors.seed.withValues(alpha: 0.08) : null,
      child: Row(children: [
        Padding(
          padding: const EdgeInsets.only(left: 14),
          child: Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: on ? AerisColors.seed : Colors.transparent,
              border: Border.all(
                  color: on
                      ? AerisColors.seed
                      : scheme.onSurfaceVariant.withValues(alpha: 0.5),
                  width: 2),
            ),
            child: on
                ? const Icon(Icons.check, size: 14, color: Colors.white)
                : null,
          ),
        ),
        Expanded(
          child: TransactionTile(txn: t, onTap: () => onToggle(t.id)),
        ),
      ]),
    );
  }
}

// ── Lent sub-tab ──────────────────────────────────────────────
class _LentTab extends ConsumerWidget {
  const _LentTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loansAsync = ref.watch(loansStreamProvider);
    final totals = ref.watch(loanTotalsProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return loansAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('$e')),
      data: (loans) {
        final pending = loans.where((l) => !l.isSettled).toList();
        final settled = loans.where((l) => l.isSettled).toList();

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 80),
          children: [
            // Summary cards
            Row(children: [
              Expanded(
                child: _LentSummaryCard(
                  label: 'Owed to you',
                  amount: totals.owedToYou,
                  icon: Icons.check,
                  color: AerisColors.moneyIn(context),
                  isDark: isDark,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _LentSummaryCard(
                  label: 'You owe',
                  amount: totals.youOwe,
                  icon: Icons.north_east,
                  color: AerisColors.moneyOut(context),
                  isDark: isDark,
                ),
              ),
            ]),
            const SizedBox(height: 20),
            if (loans.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 40),
                child: Column(children: [
                  Icon(Icons.handshake_outlined,
                      size: 52,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurfaceVariant
                          .withValues(alpha: 0.4)),
                  const SizedBox(height: 10),
                  const Text('Nothing tracked yet',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text('Gave money to a friend?\nAdd it here via the + button.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 13,
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant)),
                ]),
              ),
            if (pending.isNotEmpty) ...[
              Row(children: [
                const Icon(Icons.access_time, size: 16, color: AerisColors.warning),
                const SizedBox(width: 6),
                Text(
                  'Pending ${pending.length}',
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3),
                ),
              ]),
              const SizedBox(height: 10),
              for (final l in pending)
                _LentTile(
                    loan: l,
                    isDark: isDark,
                    onTap: () => showLoanDetailSheet(context, ref, l)),
            ],
            if (settled.isNotEmpty) ...[
              const SizedBox(height: 18),
              Row(children: [
                Icon(Icons.check_circle,
                    size: 16, color: AerisColors.moneyIn(context)),
                const SizedBox(width: 6),
                const Text('Settled',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3)),
              ]),
              const SizedBox(height: 10),
              for (final l in settled)
                _LentTile(
                    loan: l,
                    isDark: isDark,
                    onTap: () => showLoanDetailSheet(context, ref, l)),
            ],
          ],
        );
      },
    );
  }
}

class _LentSummaryCard extends StatelessWidget {
  final String label;
  final double amount;
  final IconData icon;
  final Color color;
  final bool isDark;
  const _LentSummaryCard({
    required this.label,
    required this.amount,
    required this.icon,
    required this.color,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.12 : 0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 5),
          Text(label,
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w700, color: color)),
        ]),
        const SizedBox(height: 6),
        Text(formatRupees(amount),
            style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: color,
                letterSpacing: -0.5)),
      ]),
    );
  }
}

class _LentTile extends StatelessWidget {
  final Loan loan;
  final bool isDark;
  final VoidCallback onTap;
  const _LentTile(
      {required this.loan, required this.isDark, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final l = loan;
    final color = l.borrowed
        ? AerisColors.moneyOut(context)
        : AerisColors.moneyIn(context);
    final avatarColor = _colorForName(l.person);
    final initials = l.person.trim().split(' ').take(2).map((w) {
      return w.isEmpty ? '' : w[0].toUpperCase();
    }).join();
    final dateStr = '${l.createdAt.day} ${const [
      '',
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ][l.createdAt.month]}';
    final cardColor = isDark ? const Color(0xFF14221F) : Colors.white;
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.07);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: borderColor),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.05),
                blurRadius: 8,
                offset: const Offset(0, 3)),
          ],
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Avatar circle
          Container(
            width: 42,
            height: 42,
            decoration:
                BoxDecoration(shape: BoxShape.circle, color: avatarColor),
            child: Center(
              child: Text(
                initials.isEmpty ? '?' : initials,
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 14),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Content
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(l.person,
                  style: const TextStyle(
                      fontSize: 14.5, fontWeight: FontWeight.w800)),
              const SizedBox(height: 2),
              Text(
                '${l.borrowed ? 'You borrowed' : 'You lent'} · $dateStr'
                '${l.note.isNotEmpty ? ' · ${l.note}' : ''}',
                style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w500),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              if (l.isPartial) ...[
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(99),
                      child: LinearProgressIndicator(
                        value: (l.paid / l.amount).clamp(0.0, 1.0),
                        minHeight: 5,
                        backgroundColor: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest,
                        color: AerisColors.seed,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text('${(l.paid / l.amount * 100).round()}%',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: AerisColors.ink(context))),
                ]),
              ],
            ]),
          ),
          const SizedBox(width: 12),
          // Amount + badge
          Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  formatRupees(l.amount),
                  style: TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w800,
                      color: l.isSettled
                          ? Theme.of(context).colorScheme.onSurfaceVariant
                          : color),
                ),
                const SizedBox(height: 5),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: l.isSettled
                        ? AerisColors.moneyIn(context).withValues(alpha: 0.15)
                        : const Color(0xFFD97706).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    l.isSettled ? 'Received' : 'Pending',
                    style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        color: l.isSettled
                            ? AerisColors.moneyIn(context)
                            : const Color(0xFFD97706)),
                  ),
                ),
              ]),
        ]),
      ),
    );
  }

  static Color _colorForName(String name) {
    final colors = [
      const Color(0xFF0EA5A4),
      const Color(0xFF8B5CF6),
      const Color(0xFF15A24A),
      const Color(0xFFD97706),
      const Color(0xFFEC4899),
      const Color(0xFF3B82F6),
      const Color(0xFFEF4444),
    ];
    final hash = name.codeUnits.fold(0, (h, c) => (h * 31 + c) & 0x7FFFFFFF);
    return colors[hash % colors.length];
  }
}

// Subs sub-tab - managed subscriptions (Activity > Subs)
class _SubsTab extends StatelessWidget {
  const _SubsTab();

  @override
  Widget build(BuildContext context) => const SubscriptionsBody(embed: true);
}
