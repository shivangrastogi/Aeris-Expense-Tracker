part of 'transactions_screen.dart';

// ── Transactions sub-tab ──────────────────────────────────────
class _TransactionsTab extends ConsumerStatefulWidget {
  final String query;
  final TxnDirection? filterDir;
  final String? filterCat;
  final String? filterAcct;
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
  final ValueChanged<String?> onAcctChange;
  final VoidCallback onFilterTap;
  final VoidCallback onClearAll;
  final List<(String, VoidCallback)> activeChips;
  final int filterCount;

  const _TransactionsTab({
    required this.query,
    required this.filterDir,
    required this.filterCat,
    required this.filterAcct,
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
    required this.onAcctChange,
    required this.onFilterTap,
    required this.onClearAll,
    required this.activeChips,
    required this.filterCount,
  });

  @override
  ConsumerState<_TransactionsTab> createState() => _TransactionsTabState();
}

class _TransactionsTabState extends ConsumerState<_TransactionsTab> {
  bool _selectMode = false;
  final Set<String> _picked = {};
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

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

  Future<void> _markReviewed(Transaction t) async {
    final uid = ref.read(currentUserIdProvider);
    if (uid == null || t.reviewed) return;
    await ref
        .read(firestoreServiceProvider)
        .updateTransaction(uid, t.copyWith(reviewed: true));
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showToast(const SnackBar(content: Text('Marked as reviewed')));
    }
  }

  // Swipe-to-delete: deletes now with the usual UNDO snackbar.
  Future<void> _swipeDelete(Transaction t) =>
      deleteTransactionsWithUndo(context, ref, [t]);

  /// Category picker for [picked] (a swipe on one row, or the selection).
  void _recategorize(List<Transaction> picked) {
    final money = picked.fold<double>(0, (s, t) => s + t.amount);
    showDsSheet<void>(
      context,
      title: picked.length == 1
          ? 'Categorise ${formatRupees(money)}'
          : 'Categorise ${picked.length} transactions',
      subtitle: picked.length == 1
          ? [
              picked.single.merchant ?? 'Transaction',
              relativeDate(picked.single.timestamp),
            ].join(' · ')
          : null,
      scrollControlled: true,
      builder: (ctx) => GridView.count(
        crossAxisCount: 4,
        shrinkWrap: true,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 0.95,
        children: [
          for (final c in Categories.all)
            _CatPick(
              category: c,
              selected: picked.length == 1 && picked.single.categoryId == c.id,
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
                  ScaffoldMessenger.of(context).showToast(SnackBar(
                      content: Text(n == 1
                          ? 'Moved to ${c.label}'
                          : '$n moved to ${c.label}')));
                }
              },
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tk = context.tk;
    final txns = ref.watch(transactionsStreamProvider);
    // The two busiest named accounts get a quick chip.
    final accounts = ref
        .watch(accountsProvider)
        .where((a) => a.key != unassignedAccount)
        .take(2)
        .toList();

    return Column(
      children: [
        // ── Select mode: × · N selected · Select all ─────────────
        if (_selectMode)
          SizedBox(
            height: 52,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 12, 0),
              child: Row(children: [
                IconButton(
                  onPressed: _exitSelect,
                  tooltip: 'Exit selection',
                  icon: Icon(Ph.x, size: 22, color: tk.t1),
                ),
                Expanded(
                  child: Text('${_picked.length} selected',
                      style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                          color: tk.t1,
                          fontFeatures: const [FontFeature.tabularFigures()])),
                ),
                TextLink('Select all', onTap: () {
                  final ids = _visibleIds;
                  setState(() => _picked.addAll(ids));
                }),
              ]),
            ),
          ),
        // ── Search ───────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: _SearchField(
            controller: _searchCtrl,
            onChanged: (q) {
              setState(() {}); // shows / hides the clear button
              widget.onQueryChange(q);
            },
            onClear: () {
              _searchCtrl.clear();
              setState(() {});
              widget.onQueryChange('');
            },
          ),
        ),
        // What the search understood — shown once it's more than plain text.
        Builder(builder: (context) {
          final sq = SearchQuery.parse(widget.query);
          final smart = sq.understood.length > (sq.words.isEmpty ? 0 : 1);
          if (!smart) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 20, 0),
            child: Row(children: [
              Icon(Ph.sparkle, size: 14, color: tk.acc),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  sq.understood.join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w700, color: tk.acc),
                ),
              ),
            ]),
          );
        }),
        // ── Filter · All · Spent · Received · accounts ───────────
        SizedBox(
          height: 46,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
            children: [
              // Active filters show as the badge; × clears them (the sheet
              // lists each one and has Reset).
              _FilterButton(
                  count: widget.filterCount,
                  onTap: widget.onFilterTap,
                  onClear: widget.onClearAll),
              const SizedBox(width: 8),
              DsChip('All',
                  selected: widget.filterDir == null &&
                      widget.filterAcct == null, onTap: () {
                widget.onDirChange(null);
                widget.onAcctChange(null);
              }),
              const SizedBox(width: 8),
              DsChip('Spent',
                  selected: widget.filterDir == TxnDirection.debit,
                  onTap: () => widget.onDirChange(
                      widget.filterDir == TxnDirection.debit
                          ? null
                          : TxnDirection.debit)),
              const SizedBox(width: 8),
              DsChip('Received',
                  selected: widget.filterDir == TxnDirection.credit,
                  onTap: () => widget.onDirChange(
                      widget.filterDir == TxnDirection.credit
                          ? null
                          : TxnDirection.credit)),
              for (final a in accounts) ...[
                const SizedBox(width: 8),
                DsChip(a.nickname ?? '••${a.key}',
                    selected: widget.filterAcct == a.key,
                    onTap: () => widget.onAcctChange(
                        widget.filterAcct == a.key ? null : a.key)),
              ],
              // An account opened from Accounts that isn't one of the two.
              if (widget.filterAcct != null &&
                  !accounts.any((a) => a.key == widget.filterAcct)) ...[
                const SizedBox(width: 8),
                DsChip(accountLabel(widget.filterAcct!),
                    selected: true, onTap: () => widget.onAcctChange(null)),
              ],
            ],
          ),
        ),
        const SizedBox(height: 6),
        // ── The list ─────────────────────────────────────────────
        Expanded(
          child: txns.when(
            loading: () => _skeleton(),
            error: (e, _) => ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Banner2(
                  tone: Tone.bad,
                  icon: PhFill.cloudX,
                  title: "Couldn't load transactions",
                  body: '$e',
                ),
              ],
            ),
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
                if (widget.filterAcct != null) {
                  final k = (t.account == null || t.account!.trim().isEmpty)
                      ? unassignedAccount
                      : t.account!.trim();
                  if (k != widget.filterAcct) return false;
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
              final shown = filtered.length > widget.visible
                  ? widget.visible
                  : filtered.length;
              _visibleIds = [for (final t in filtered.take(shown)) t.id];

              if (filtered.isEmpty) {
                return ListView(children: [
                  if (list.isEmpty)
                    EmptyState(
                      icon: Ph.receipt,
                      title: 'No transactions yet',
                      body: 'Turn on SMS reading and your bank alerts become '
                          'transactions automatically. Or add one yourself.',
                      cta: 'Add an expense',
                      onCta: () => Navigator.pushNamed(
                          context, AppRoutes.addTxn,
                          arguments: TxnDirection.debit),
                    )
                  else
                    _NoMatches(
                      query: widget.query,
                      onClear: () {
                        _searchCtrl.clear();
                        widget.onQueryChange('');
                        widget.onClearAll();
                      },
                    ),
                ]);
              }

              final groups = _groupByDate(filtered.sublist(0, shown));

              // One sliver group per day: its header stays pinned at the top
              // while that day's rows scroll under it.
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
                              .where((t) => !t.isInternal)
                              .fold<double>(0, (s, t) => s + t.signed),
                        ),
                      ),
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
                        sliver: SliverToBoxAdapter(
                          child: _DateGroup(
                              txns: group.value,
                              selectMode: _selectMode,
                              picked: _picked,
                              onToggle: _toggle,
                              onLongPress: _enterSelect,
                              onSwipeDelete: _swipeDelete,
                              onSwipeReviewed: _markReviewed,
                              onSwipeCategory: (t) => _recategorize([t])),
                        ),
                      ),
                    ]),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Ph.handSwipeLeft, size: 15, color: tk.t3),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                                'Swipe for actions · press and hold to select',
                                style: TextStyle(fontSize: 12, color: tk.t3)),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        // ── Bulk action bar ──────────────────────────────────────
        if (_selectMode && _picked.isNotEmpty)
          Container(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
            decoration: BoxDecoration(
              color: tk.bg,
              border: Border(top: BorderSide(color: tk.hair)),
            ),
            child: Row(children: [
              OutlinedButton.icon(
                onPressed: _deletePicked,
                icon: Icon(Ph.trash, size: 18, color: tk.bad),
                label: Text('Delete', style: TextStyle(color: tk.bad)),
                style: OutlinedButton.styleFrom(
                    side: BorderSide(color: tk.badLine, width: 1.5)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _recategorizePicked,
                  icon: const Icon(Ph.tag, size: 18),
                  label: const Text('Category'),
                ),
              ),
            ]),
          ),
      ],
    );
  }

  /// Ids currently on screen (for "Select all").
  List<String> _visibleIds = const [];

  Widget _skeleton() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
      children: [
        for (var g = 0; g < 2; g++) ...[
          const SkeletonBox(
              width: 80, height: 12, margin: EdgeInsets.fromLTRB(4, 8, 0, 10)),
          Container(
            decoration: AerisColors.cardDecoration(context),
            child: Column(children: [
              for (var i = 0; i < 3; i++)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(children: [
                    SkeletonBox(width: 40, height: 40, radius: Rad.tile),
                    SizedBox(width: 12),
                    Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SkeletonBox(width: 120, height: 12),
                            SizedBox(height: 7),
                            SkeletonBox(width: 170, height: 10),
                          ]),
                    ),
                    SkeletonBox(width: 52, height: 12),
                  ]),
                ),
            ]),
          ),
        ],
      ],
    );
  }

  List<MapEntry<String, List<Transaction>>> _groupByDate(
      List<Transaction> txns) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = [
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
    ];

    final map = <String, List<Transaction>>{};
    for (final t in txns) {
      final d = DateTime(t.timestamp.year, t.timestamp.month, t.timestamp.day);
      final key = d == today
          ? 'Today'
          : d == yesterday
              ? 'Yesterday'
              : '${weekdays[d.weekday - 1]}, ${d.day} ${months[d.month]}';
      map.putIfAbsent(key, () => []).add(t);
    }
    return map.entries.toList();
  }
}

// ── 48 dp search field ────────────────────────────────────────
class _SearchField extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;
  const _SearchField(
      {required this.controller,
      required this.onChanged,
      required this.onClear});

  @override
  Widget build(BuildContext context) {
    final tk = context.tk;
    return Container(
      height: 48,
      padding: const EdgeInsets.only(left: 14, right: 4),
      decoration: BoxDecoration(
        color: tk.field,
        borderRadius: BorderRadius.circular(Rad.input),
        border: Border.all(color: tk.hair),
      ),
      child: Row(children: [
        Icon(Ph.magnifyingGlass, size: 18, color: tk.t2),
        const SizedBox(width: 10),
        Expanded(
          child: TextField(
            controller: controller,
            onChanged: onChanged,
            textInputAction: TextInputAction.search,
            style: TextStyle(fontSize: 14, color: tk.t1),
            decoration: InputDecoration(
              hintText: "Try 'swiggy september' or 'above 1000'",
              hintStyle: TextStyle(fontSize: 14, color: tk.t2),
              filled: false,
              isCollapsed: true,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              contentPadding: EdgeInsets.zero,
            ),
          ),
        ),
        if (controller.text.isNotEmpty)
          IconButton(
            onPressed: onClear,
            tooltip: 'Clear search',
            icon: Icon(PhFill.xCircle, size: 18, color: tk.t2),
          ),
      ]),
    );
  }
}

// ── "Filter" chip: count badge + an inline × to clear ─────────
// Active filters live in the badge, not in a separate row of chips, so the
// list never gets pushed down. Tap the chip to see or change each filter.
class _FilterButton extends StatelessWidget {
  final int count;
  final VoidCallback onTap;
  final VoidCallback onClear;
  const _FilterButton(
      {required this.count, required this.onTap, required this.onClear});

  @override
  Widget build(BuildContext context) {
    final tk = context.tk;
    final on = count > 0;
    final fg = on ? tk.acc : tk.t1;
    return Container(
      height: 36,
      decoration: BoxDecoration(
        color: on ? tk.accSoft : Colors.transparent,
        borderRadius: BorderRadius.circular(Rad.chip),
        border: Border.all(color: on ? Colors.transparent : tk.hair2),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Semantics(
            button: true,
            label: on ? 'Filters, $count on' : 'Filters',
            excludeSemantics: true,
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.horizontal(
                left: const Radius.circular(Rad.chip),
                right: Radius.circular(on ? 0 : Rad.chip),
              ),
              child: Padding(
                padding: EdgeInsets.only(left: 12, right: on ? 8 : 12),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Ph.slidersHorizontal, size: 16, color: fg),
                  const SizedBox(width: 6),
                  Text('Filter',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: fg)),
                  if (on) ...[
                    const SizedBox(width: 6),
                    Container(
                      constraints: const BoxConstraints(minWidth: 18),
                      height: 18,
                      padding: const EdgeInsets.symmetric(horizontal: 5),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                          color: tk.acc,
                          borderRadius: BorderRadius.circular(9)),
                      child: Text('$count',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: tk.onAcc)),
                    ),
                  ],
                ]),
              ),
            ),
          ),
          if (on) ...[
            Container(
                width: 1, height: 18, color: tk.acc.withValues(alpha: 0.3)),
            Semantics(
              button: true,
              label: 'Clear filters',
              excludeSemantics: true,
              child: InkWell(
                onTap: onClear,
                borderRadius: const BorderRadius.horizontal(
                    right: Radius.circular(Rad.chip)),
                child: SizedBox(
                  width: 34,
                  height: 36,
                  child: Icon(PhBold.x, size: 13, color: tk.acc),
                ),
              ),
            ),
          ],
        ]),
      ),
    );
  }
}

// ── No search results ─────────────────────────────────────────
class _NoMatches extends StatelessWidget {
  final String query;
  final VoidCallback onClear;
  const _NoMatches({required this.query, required this.onClear});

  @override
  Widget build(BuildContext context) {
    final tk = context.tk;
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 64, 32, 24),
      child: Column(children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
              color: tk.press, borderRadius: BorderRadius.circular(18)),
          child: Icon(Ph.magnifyingGlass, size: 30, color: tk.t2),
        ),
        const SizedBox(height: 12),
        Text(
            query.trim().isEmpty
                ? 'Nothing matches these filters'
                : "No matches for '${query.trim()}'",
            textAlign: TextAlign.center,
            style: Ts.title.copyWith(color: tk.t1)),
        const SizedBox(height: 8),
        Text(
            "Try a merchant, a category, a month or an amount, like 'above 1000'.",
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, height: 20 / 14, color: tk.t2)),
        const SizedBox(height: 16),
        OutlinedButton(
          onPressed: onClear,
          child: const Text('Clear search and filters'),
        ),
      ]),
    );
  }
}

// ── Pinned day header: "Tue, 24 Sep ········· −₹1,240" ────────
class _DayHeaderDelegate extends SliverPersistentHeaderDelegate {
  final String date;
  final double total;
  _DayHeaderDelegate({required this.date, required this.total});

  // Captured when built, so the eye toggle redraws headers already pinned.
  final bool _hidden = kAmountsHidden;

  static const _h = 36.0;
  @override
  double get minExtent => _h;
  @override
  double get maxExtent => _h;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlaps) {
    // Opaque, so rows scrolling underneath don't show through.
    return ColoredBox(
      color: context.tk.bg,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
        child: Align(
          alignment: Alignment.bottomCenter,
          child: DayHeader(date,
              total: total == 0 ? null : signedMoney(total, credit: total > 0)),
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(_DayHeaderDelegate old) =>
      old.date != date || old.total != total || old._hidden != _hidden;
}

// ── One day's transactions card, with swipe actions ───────────
class _DateGroup extends StatelessWidget {
  final List<Transaction> txns;
  final bool selectMode;
  final Set<String> picked;
  final ValueChanged<String> onToggle;
  final ValueChanged<String> onLongPress;
  final ValueChanged<Transaction> onSwipeDelete;
  final ValueChanged<Transaction> onSwipeReviewed;
  final ValueChanged<Transaction> onSwipeCategory;
  const _DateGroup(
      {required this.txns,
      this.selectMode = false,
      this.picked = const {},
      required this.onToggle,
      required this.onLongPress,
      required this.onSwipeDelete,
      required this.onSwipeReviewed,
      required this.onSwipeCategory});

  @override
  Widget build(BuildContext context) {
    return ListGroup(children: [
      for (final t in txns)
        if (selectMode)
          _selectableTile(context, t)
        else
          _swipeable(
            context,
            t,
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onLongPress: () => onLongPress(t.id),
              child: TransactionTile(txn: t, showDate: false),
            ),
          ),
    ]);
  }

  /// Swipe right → Reviewed (if it needs review) or Category. Swipe left →
  /// Delete (with UNDO). The row always springs back; the list updates from
  /// the data stream, so Dismissible never removes a row the stream still has.
  Widget _swipeable(BuildContext context, Transaction t, Widget child) {
    final tk = context.tk;
    final review = t.needsReview;
    Widget bg(Color c, Color fg, IconData icon, String label, Alignment a) =>
        Container(
          color: c,
          alignment: a,
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: fg, size: 20),
              const SizedBox(height: 4),
              Text(label,
                  style: TextStyle(
                      color: fg, fontWeight: FontWeight.w700, fontSize: 11)),
            ],
          ),
        );
    return Dismissible(
      key: ValueKey('swipe-${t.id}'),
      background: review
          ? bg(tk.ok, tk.isDark ? tk.onAcc : Colors.white, PhBold.check,
              'Reviewed', Alignment.centerLeft)
          : bg(tk.acc, tk.onAcc, Ph.tag, 'Category', Alignment.centerLeft),
      secondaryBackground: bg(tk.bad, tk.isDark ? tk.onAcc : Colors.white,
          Ph.trash, 'Delete', Alignment.centerRight),
      dismissThresholds: const {
        DismissDirection.startToEnd: 0.3,
        DismissDirection.endToStart: 0.3,
      },
      confirmDismiss: (dir) async {
        if (dir == DismissDirection.endToStart) {
          onSwipeDelete(t);
        } else if (review) {
          onSwipeReviewed(t);
        } else {
          onSwipeCategory(t);
        }
        return false;
      },
      child: child,
    );
  }

  Widget _selectableTile(BuildContext context, Transaction t) {
    final tk = context.tk;
    final on = picked.contains(t.id);
    return Container(
      color: on ? tk.accSoft : null,
      child: Row(children: [
        Padding(
          padding: const EdgeInsets.only(left: 16),
          child: AnimatedContainer(
            duration: Mo.standard,
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: on ? tk.acc : Colors.transparent,
              border: Border.all(color: on ? tk.acc : tk.hair2, width: 2),
            ),
            child: on ? Icon(PhBold.check, size: 13, color: tk.onAcc) : null,
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
