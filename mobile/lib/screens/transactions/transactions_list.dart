part of 'transactions_screen.dart';

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
                      ScaffoldMessenger.of(context).showToast(
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
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Try “swiggy september” or “above 1000 last month”',
              prefixIcon: Icon(Icons.search_rounded,
                  color: AerisColors.muted(context), size: 20),
              fillColor: AerisColors.card(context),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
              isDense: true,
            ),
          ),
        ),
        // What the search understood — shown once it's more than plain text.
        Builder(builder: (context) {
          final sq = SearchQuery.parse(widget.query);
          final smart = sq.understood.length > (sq.words.isEmpty ? 0 : 1);
          if (!smart) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 16, 10),
            child: Row(children: [
              Icon(Icons.auto_awesome_rounded,
                  size: 14, color: AerisColors.accent(context)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  sq.understood.join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: AerisColors.accent(context)),
                ),
              ),
            ]),
          );
        }),
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
                          ? AerisColors.accent(context)
                          : AerisColors.line(context),
                      width: widget.hasActiveFilter ? 1.5 : 1,
                    ),
                    borderRadius: BorderRadius.circular(99),
                    color: widget.hasActiveFilter
                        ? AerisColors.accentSoft(context)
                        : AerisColors.card(context),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.tune,
                        size: 16,
                        color: widget.hasActiveFilter
                            ? AerisColors.accent(context)
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
              _dirPill(context, TxnDirection.debit, 'Spent', isDark,
                  icon: Icons.south_west_rounded,
                  iconColor: AerisColors.moneyOut(context)),
              const SizedBox(width: 8),
              _dirPill(context, TxnDirection.credit, 'Received', isDark,
                  icon: Icons.north_east_rounded,
                  iconColor: AerisColors.moneyIn(context)),
              // Thin divider
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                child: VerticalDivider(
                  width: 1,
                  thickness: 1,
                  color: AerisColors.line(context),
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
              // The search box speaks plain language ("above 1000 last
              // month", "swiggy september") — see SearchQuery.
              final sq = SearchQuery.parse(widget.query);
              var filtered = list.where((t) {
                if (widget.filterDir != null &&
                    t.direction != widget.filterDir) {
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
                return sq.matches(t);
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
                    border: Border.all(color: AerisColors.danger(context)),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.delete_outline_rounded,
                        size: 18, color: AerisColors.danger(context)),
                    SizedBox(width: 6),
                    Text('Delete',
                        style: TextStyle(
                            color: AerisColors.danger(context),
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
                      color: AerisColors.accent(context),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.category_outlined,
                              size: 18, color: AerisColors.onAccent(context)),
                          SizedBox(width: 6),
                          Text('Recategorize',
                              style: TextStyle(
                                  color: AerisColors.onAccent(context),
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
          color: sel ? AerisColors.accent(context) : AerisColors.card(context),
          borderRadius: BorderRadius.circular(99),
          border: Border.all(
            color:
                sel ? AerisColors.accent(context) : AerisColors.line(context),
          ),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[
            Icon(icon,
                size: 14,
                color: sel
                    ? AerisColors.onAccent(context)
                    : (iconColor ?? AerisColors.accent(context))),
            const SizedBox(width: 4),
          ],
          Text(label,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: sel
                      ? AerisColors.onAccent(context)
                      : Theme.of(context).colorScheme.onSurface)),
        ]),
      ),
    );
  }

  Widget _catPill(BuildContext context, String? catId, String label,
      IconData? icon, Color? color, bool isDark) {
    final sel = widget.filterCat == catId;
    final activeColor = color ?? AerisColors.accent(context);
    return GestureDetector(
      onTap: () => widget.onCatChange(sel ? null : catId),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        decoration: BoxDecoration(
          color: sel
              ? activeColor.withValues(alpha: 0.15)
              : AerisColors.card(context),
          borderRadius: BorderRadius.circular(99),
          border: Border.all(
            color: sel ? activeColor : AerisColors.line(context),
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
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: AerisColors.cardDecoration(context, radius: 20),
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
                child: TransactionTile(txn: txns[i], showDate: false),
              ),
            ),
          if (i < txns.length - 1)
            const Divider(height: 1, indent: 70, endIndent: 16),
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
      background: bg(AerisColors.accent(context), Icons.category_outlined,
          'Category', Alignment.centerLeft),
      secondaryBackground: bg(AerisColors.danger(context),
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
      color: on ? AerisColors.accent(context).withValues(alpha: 0.08) : null,
      child: Row(children: [
        Padding(
          padding: const EdgeInsets.only(left: 14),
          child: Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: on ? AerisColors.accent(context) : Colors.transparent,
              border: Border.all(
                  color: on
                      ? AerisColors.accent(context)
                      : scheme.onSurfaceVariant.withValues(alpha: 0.5),
                  width: 2),
            ),
            child: on
                ? Icon(Icons.check,
                    size: 14, color: AerisColors.onAccent(context))
                : null,
          ),
        ),
        Expanded(
          child: TransactionTile(
              txn: t, showDate: false, onTap: () => onToggle(t.id)),
        ),
      ]),
    );
  }
}
