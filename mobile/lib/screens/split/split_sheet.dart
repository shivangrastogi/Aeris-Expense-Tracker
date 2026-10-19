import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/theme.dart';
import '../../models/category.dart';
import '../../models/split.dart';
import '../../models/transaction.dart';
import '../../providers/auth_provider.dart';
import '../../providers/split_provider.dart';
import '../../providers/transactions_provider.dart';
import '../../services/split_links.dart';
import '../../services/split_service.dart';
import '../../utils/amount_input_formatter.dart';
import '../../utils/formatters.dart';

/// Split [bill] (or edit its split). Returns the saved transaction, or null
/// if the user backed out.
Future<Transaction?> showSplitSheet(BuildContext context, Transaction bill) =>
    showModalBottomSheet<Transaction>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _SplitSheet(bill: bill),
    );

class _Person {
  final String name;
  final double weight;
  final TextEditingController amount;
  _Person(this.name, this.weight, double inr)
      : amount = TextEditingController(text: inrToDisplayText(inr));
}

class _SplitSheet extends ConsumerStatefulWidget {
  final Transaction bill;
  const _SplitSheet({required this.bill});

  @override
  ConsumerState<_SplitSheet> createState() => _SplitSheetState();
}

class _SplitSheetState extends ConsumerState<_SplitSheet> {
  final _people = <_Person>[];
  final _newPerson = TextEditingController();
  final _groupName = TextEditingController();
  String? _groupId; // selected existing group
  bool _saveGroup = true;
  bool _auto = false;
  bool _busy = false;
  double _myWeight = 1;
  bool _seeded = false;

  Transaction get _bill => widget.bill;
  String? get _payee => SplitLinks.payeeKeys(_bill).firstOrNull;

  @override
  void dispose() {
    for (final p in _people) {
      p.amount.dispose();
    }
    _newPerson.dispose();
    _groupName.dispose();
    super.dispose();
  }

  /// First build: an existing split, else the group this payee auto-splits
  /// into, else the only group, else empty.
  void _seed(List<SplitGroup> groups) {
    if (_seeded) return;
    _seeded = true;
    final split = _bill.split;
    if (split != null) {
      _groupId = split.groupId;
      for (final s in split.shares) {
        _people.add(_Person(s.name, 1, s.amount));
      }
      final g = groups.where((g) => g.id == _groupId).firstOrNull;
      _auto = g != null && g.autoPayees.contains(_payee);
      return;
    }
    final g = SplitLinks.autoGroupFor(
            _bill.copyWith(clearSplit: true), groups) ??
        (groups.length == 1 ? groups.single : null);
    if (g != null) _pickGroup(g);
  }

  void _pickGroup(SplitGroup g) {
    for (final p in _people) {
      p.amount.dispose();
    }
    _people.clear();
    _groupId = g.id;
    _myWeight = g.myWeight;
    _auto = g.autoPayees.contains(_payee);
    for (final m in g.members) {
      _people.add(_Person(m.name, m.weight, 0));
    }
    _divide();
  }

  /// Divide the bill by weight (equal unless the group says otherwise).
  /// No rebuild — safe to call while building; see [_equal].
  void _divide() {
    final total = _people.fold<double>(_myWeight, (s, p) => s + p.weight);
    for (final p in _people) {
      final v = (_bill.amount * p.weight / total * 100).roundToDouble() / 100;
      p.amount.text = inrToDisplayText(v);
    }
  }

  void _equal() => setState(_divide);

  void _addPerson() {
    final name = _newPerson.text.trim();
    if (name.isEmpty) return;
    if (_people.any((p) => p.name.toLowerCase() == name.toLowerCase())) return;
    _people.add(_Person(name, 1, 0));
    _newPerson.clear();
    _equal();
  }

  double _othersTotal() => _people.fold(
      0, (s, p) => s + (displayToInr(p.amount.text) ?? 0));

  Future<void> _save(List<SplitGroup> groups) async {
    final uid = ref.read(currentUserIdProvider);
    if (uid == null) return;
    final shares = [
      for (final p in _people)
        if ((displayToInr(p.amount.text) ?? 0) > 0)
          SplitShare(name: p.name, amount: displayToInr(p.amount.text)!),
    ];
    if (shares.isEmpty) return;
    setState(() => _busy = true);
    final fs = ref.read(firestoreServiceProvider);
    var all = [...groups];
    String? groupId = _groupId;
    final existing = all.where((g) => g.id == groupId).firstOrNull;
    final payee = _payee;
    if (existing != null) {
      // Add anyone new to the group; keep the auto rule in step.
      final known = {for (final m in existing.members) m.name.toLowerCase()};
      var g = existing.copyWith(members: [
        ...existing.members,
        for (final s in shares)
          if (!known.contains(s.name.toLowerCase())) SplitMember(name: s.name),
      ]);
      if (payee != null) {
        final rules = {...g.autoPayees};
        _auto ? rules.add(payee) : rules.remove(payee);
        g = g.copyWith(autoPayees: rules.toList());
      }
      await fs.setSplitGroup(uid, g);
      all = [for (final x in all) x.id == g.id ? g : x];
    } else if (_saveGroup) {
      final name = _groupName.text.trim();
      final g = SplitGroup(
        id: const Uuid().v4(),
        name: name.isEmpty ? 'Shared' : name,
        members: [for (final s in shares) SplitMember(name: s.name)],
        autoPayees: _auto && payee != null ? [payee] : const [],
      );
      await fs.setSplitGroup(uid, g);
      all.add(g);
      groupId = g.id;
    }
    final saved = await SplitService.instance.applySplit(
        uid, _bill, SplitInfo(groupId: groupId, shares: shares),
        groups: all);
    if (mounted) Navigator.pop(context, saved);
  }

  @override
  Widget build(BuildContext context) {
    final groups = ref.watch(splitGroupsProvider).valueOrNull ?? const [];
    _seed(groups);
    final scheme = Theme.of(context).colorScheme;
    final muted = AerisColors.muted(context);
    final others = _othersTotal();
    final mine = _bill.amount - others;
    final over = mine < -0.5;
    final title = _bill.merchant ?? Categories.byId(_bill.categoryId).label;
    final isNewGroup = _groupId == null;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Split ${formatRupees(_bill.amount, decimals: true)} · $title',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(
                  'Only your share counts as your spending. Their payments '
                  'back are matched automatically.',
                  style: TextStyle(fontSize: 12.5, color: muted)),
              const SizedBox(height: 14),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final g in groups)
                  ChoiceChip(
                    label: Text(g.name),
                    selected: _groupId == g.id,
                    onSelected: (_) => setState(() => _pickGroup(g)),
                  ),
                ChoiceChip(
                  avatar: const Icon(Icons.add, size: 16),
                  label: const Text('New people'),
                  selected: isNewGroup,
                  onSelected: (_) => setState(() {
                    for (final p in _people) {
                      p.amount.dispose();
                    }
                    _people.clear();
                    _groupId = null;
                    _myWeight = 1;
                    _auto = false;
                  }),
                ),
              ]),
              const SizedBox(height: 12),
              for (var i = 0; i < _people.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(children: [
                    CircleAvatar(
                      radius: 16,
                      backgroundColor: AerisColors.accentSoft(context),
                      child: Text(_people[i].name[0].toUpperCase(),
                          style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: AerisColors.accent(context))),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                        child: Text(_people[i].name,
                            style: const TextStyle(fontWeight: FontWeight.w600))),
                    SizedBox(
                      width: 120,
                      child: TextField(
                        controller: _people[i].amount,
                        keyboardType:
                            const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: const [AmountInputFormatter()],
                        textAlign: TextAlign.right,
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          isDense: true,
                          prefixText: '${kCurrency.symbol.trim()} ',
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Remove ${_people[i].name}',
                      icon: const Icon(Icons.close_rounded, size: 20),
                      onPressed: () => setState(() {
                        _people.removeAt(i).amount.dispose();
                      }),
                    ),
                  ]),
                ),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: _newPerson,
                    textCapitalization: TextCapitalization.words,
                    onSubmitted: (_) => _addPerson(),
                    decoration: const InputDecoration(
                      isDense: true,
                      hintText: 'Add a person (e.g. Rahul)',
                      prefixIcon: Icon(Icons.person_add_alt_1_outlined),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                    tooltip: 'Add',
                    onPressed: _addPerson,
                    icon: const Icon(Icons.add)),
              ]),
              const SizedBox(height: 10),
              Row(children: [
                TextButton.icon(
                  onPressed: _people.isEmpty ? null : _equal,
                  icon: const Icon(Icons.balance_rounded, size: 18),
                  label: const Text('Split equally'),
                ),
                const Spacer(),
                Text(
                  over
                      ? 'More than the bill'
                      : 'Your share ${formatRupees(mine < 0 ? 0 : mine, decimals: true)}',
                  style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: over ? AerisColors.danger(context) : null),
                ),
              ]),
              if (isNewGroup && _people.isNotEmpty) ...[
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _saveGroup,
                  onChanged: (v) => setState(() => _saveGroup = v),
                  title: const Text('Save these people as a group'),
                  subtitle: const Text('Reuse them for the next bill'),
                ),
                if (_saveGroup)
                  TextField(
                    controller: _groupName,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                        isDense: true, hintText: 'Group name (e.g. Flat)'),
                  ),
              ],
              if (_payee != null && (!isNewGroup || _saveGroup) && _people.isNotEmpty)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _auto,
                  onChanged: (v) => setState(() => _auto = v),
                  title: Text('Always split payments to $title'),
                  subtitle: const Text('Next month\'s bill splits by itself'),
                ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _busy || over || _people.isEmpty || others <= 0
                      ? null
                      : () => _save(groups),
                  child: _busy
                      ? SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: scheme.onPrimary))
                      : const Text('Save split'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
