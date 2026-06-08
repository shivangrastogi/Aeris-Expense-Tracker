import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/category.dart';
import '../../models/transaction.dart';
import '../../providers/transactions_provider.dart';
import '../../utils/formatters.dart';
import '../../widgets/transaction_tile.dart';

class TransactionsScreen extends ConsumerStatefulWidget {
  /// Optional starting filters (used when opened from Home's debit/credit tap).
  final TxnDirection? initialDir;
  final String? initialCategory;
  final String? initialAccount; // filter to one account (key from accounts_provider)
  const TransactionsScreen(
      {super.key, this.initialDir, this.initialCategory, this.initialAccount});

  @override
  ConsumerState<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends ConsumerState<TransactionsScreen> {
  String _query = '';
  String? _filterCategory;
  String? _filterAccount;
  TxnDirection? _filterDir;
  DateTimeRange? _dateRange;
  final ScrollController _scroll = ScrollController();
  int _visible = 50; // page size for the list
  int _lastFilteredCount = 0;

  @override
  void initState() {
    super.initState();
    _filterDir = widget.initialDir;
    _filterCategory = widget.initialCategory;
    _filterAccount = widget.initialAccount;
    _scroll.addListener(() {
      if (_scroll.hasClients &&
          _scroll.position.pixels >= _scroll.position.maxScrollExtent - 300 &&
          _visible < _lastFilteredCount) {
        setState(() => _visible += 50);
      }
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 5),
      lastDate: now,
      initialDateRange: _dateRange,
    );
    if (picked != null) setState(() => _dateRange = picked);
  }

  bool _inRange(DateTime t) {
    if (_dateRange == null) return true;
    final start = DateTime(_dateRange!.start.year, _dateRange!.start.month,
        _dateRange!.start.day);
    final end = DateTime(_dateRange!.end.year, _dateRange!.end.month,
        _dateRange!.end.day, 23, 59, 59);
    return !t.isBefore(start) && !t.isAfter(end);
  }

  @override
  Widget build(BuildContext context) {
    final txns = ref.watch(transactionsStreamProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Transactions'),
        actions: [
          IconButton(
            tooltip: 'Import statement',
            icon: const Icon(Icons.upload_file),
            onPressed: () =>
                Navigator.pushNamed(context, '/transactions/import'),
          ),
          IconButton(
            tooltip: 'Filter by date',
            icon: Icon(_dateRange == null
                ? Icons.calendar_month_outlined
                : Icons.event_available),
            onPressed: _pickDate,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Search merchant, note, amount…',
                prefixIcon: Icon(Icons.search),
                isDense: true,
                border: OutlineInputBorder(),
              ),
              onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
            ),
          ),
          // Active date-range pill
          if (_dateRange != null)
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(left: 14, bottom: 4),
                child: InputChip(
                  avatar: const Icon(Icons.event, size: 16),
                  label: Text(
                      '${shortDay(_dateRange!.start)} – ${shortDay(_dateRange!.end)}'),
                  onDeleted: () => setState(() => _dateRange = null),
                ),
              ),
            ),
          SizedBox(
            height: 38,
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              scrollDirection: Axis.horizontal,
              children: [
                _chip('All', _filterDir == null && _filterCategory == null,
                    () => setState(() {
                          _filterDir = null;
                          _filterCategory = null;
                        })),
                _chip('Debits', _filterDir == TxnDirection.debit,
                    () => setState(() => _filterDir = TxnDirection.debit)),
                _chip('Credits', _filterDir == TxnDirection.credit,
                    () => setState(() => _filterDir = TxnDirection.credit)),
                const SizedBox(width: 8),
                for (final c in Categories.all)
                  _chip(c.label, _filterCategory == c.id,
                      () => setState(() => _filterCategory =
                          _filterCategory == c.id ? null : c.id)),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: txns.when(
              loading: () => const _TxnSkeleton(),
              error: (e, _) => Center(child: Text('$e')),
              data: (list) {
                final filtered = list.where((t) {
                  if (_filterDir != null && t.direction != _filterDir) {
                    return false;
                  }
                  if (_filterCategory != null &&
                      t.categoryId != _filterCategory) return false;
                  if (_filterAccount != null) {
                    final acc = (t.account == null || t.account!.trim().isEmpty)
                        ? 'unassigned'
                        : t.account!.trim();
                    if (acc != _filterAccount) return false;
                  }
                  if (!_inRange(t.timestamp)) return false;
                  if (_query.isEmpty) return true;
                  return (t.merchant ?? '').toLowerCase().contains(_query) ||
                      (t.note ?? '').toLowerCase().contains(_query) ||
                      t.amount.toString().contains(_query);
                }).toList();
                if (filtered.isEmpty) {
                  return const Center(child: Text('No transactions match.'));
                }
                final total = filtered.fold<double>(0, (s, t) => s + t.signed);
                _lastFilteredCount = filtered.length;
                final shown =
                    filtered.length > _visible ? _visible : filtered.length;
                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 6),
                      child: Row(
                        children: [
                          Text('${filtered.length} transactions',
                              style: const TextStyle(
                                  fontSize: 12, fontWeight: FontWeight.w600)),
                          const Spacer(),
                          Text('Net: ${formatRupees(total)}',
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: total >= 0
                                      ? Colors.green
                                      : Colors.red)),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ListView.separated(
                        controller: _scroll,
                        itemCount: shown,
                        itemBuilder: (_, i) => TransactionTile(txn: filtered[i]),
                        separatorBuilder: (_, __) =>
                            const Divider(height: 1, indent: 70),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(String label, bool selected, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.only(right: 6),
        child: ChoiceChip(
          label: Text(label),
          selected: selected,
          onSelected: (_) => onTap(),
        ),
      );
}

class _TxnSkeleton extends StatelessWidget {
  const _TxnSkeleton();
  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4);
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        for (var i = 0; i < 8; i++)
          Container(
            height: 56,
            margin: const EdgeInsets.symmetric(vertical: 5),
            decoration: BoxDecoration(
                color: base, borderRadius: BorderRadius.circular(12)),
          )
              .animate(onPlay: (c) => c.repeat())
              .shimmer(
                  duration: 1200.ms,
                  color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.5)),
      ],
    );
  }
}
