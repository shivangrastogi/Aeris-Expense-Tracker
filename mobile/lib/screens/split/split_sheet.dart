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
import '../../widgets/ds.dart';

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
    final tk = context.tk;
    final others = _othersTotal();
    final mine = _bill.amount - others;
    final over = mine < -0.5;
    final title = _bill.merchant ?? Categories.byId(_bill.categoryId).label;
    final isNewGroup = _groupId == null;

    Widget toggle(String t, String sub, bool v, ValueChanged<bool> on) =>
        DsRow(
          padding: const EdgeInsets.symmetric(vertical: 8),
          minHeight: 56,
          title: t,
          sub: sub,
          trailing: Switch(value: v, onChanged: on),
          onTap: () => on(!v),
        );

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Split ${formatRupees(_bill.amount, decimals: true)} · $title',
                  style: Ts.title.copyWith(color: tk.t1)),
              const SizedBox(height: 4),
              Text(
                  'Only your share counts as your spending. Their payments '
                  'back are matched automatically.',
                  style: Ts.bodyS.copyWith(color: tk.t2)),
              const SizedBox(height: 14),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final g in groups)
                  DsChip(g.name,
                      selected: _groupId == g.id,
                      showCheck: true,
                      icon: Ph.usersThree,
                      onTap: () => setState(() => _pickGroup(g))),
                DsChip('New people',
                    selected: isNewGroup,
                    showCheck: true,
                    icon: Ph.plus,
                    onTap: () => setState(() {
                          for (final p in _people) {
                            p.amount.dispose();
                          }
                          _people.clear();
                          _groupId = null;
                          _myWeight = 1;
                          _auto = false;
                        })),
              ]),
              const SizedBox(height: 14),
              for (var i = 0; i < _people.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(children: [
                    InitialAvatar(_people[i].name, size: 36),
                    const SizedBox(width: 10),
                    Expanded(
                        child: Text(_people[i].name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Ts.rowTitle.copyWith(color: tk.t1))),
                    SizedBox(
                      width: 128,
                      child: TextField(
                        controller: _people[i].amount,
                        keyboardType:
                            const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: const [AmountInputFormatter()],
                        textAlign: TextAlign.right,
                        onChanged: (_) => setState(() {}),
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: over ? tk.bad : tk.t1,
                            fontFeatures: const [FontFeature.tabularFigures()]),
                        decoration: InputDecoration(
                          isDense: true,
                          prefixText: '${kCurrency.symbol.trim()} ',
                          enabledBorder: over
                              ? OutlineInputBorder(
                                  borderRadius:
                                      BorderRadius.circular(Rad.input),
                                  borderSide: BorderSide(color: tk.bad))
                              : null,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Remove ${_people[i].name}',
                      icon: Icon(Ph.x, size: 18, color: tk.t2),
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
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: 'Add a person (e.g. Rahul)',
                      prefixIcon: Icon(Ph.userPlus, size: 18, color: tk.t2),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                    tooltip: 'Add',
                    onPressed: _addPerson,
                    style: IconButton.styleFrom(
                        backgroundColor: tk.accSoft, foregroundColor: tk.acc),
                    icon: const Icon(PhBold.plus, size: 18)),
              ]),
              const SizedBox(height: 8),
              Row(children: [
                TextButton.icon(
                  onPressed: _people.isEmpty ? null : _equal,
                  icon: const Icon(Ph.scales, size: 18),
                  label: const Text('Split equally'),
                ),
                const Spacer(),
                if (!over)
                  Text(
                      'Your share ${formatRupees(mine < 0 ? 0 : mine, decimals: true)}',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: tk.t1,
                          fontFeatures: const [FontFeature.tabularFigures()])),
              ]),
              // Over the bill: red, with an icon and the numbers — never
              // colour alone.
              if (over)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(children: [
                    Icon(PhFill.warningCircle, size: 15, color: tk.bad),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                          'More than the bill by ${formatRupees(-mine, decimals: true)}',
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: tk.bad)),
                    ),
                  ]),
                ),
              if (isNewGroup && _people.isNotEmpty) ...[
                toggle('Save these people as a group',
                    'Reuse them for the next bill', _saveGroup,
                    (v) => setState(() => _saveGroup = v)),
                if (_saveGroup)
                  TextField(
                    controller: _groupName,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                        isDense: true, hintText: 'Group name (e.g. Flat)'),
                  ),
              ],
              if (_payee != null &&
                  (!isNewGroup || _saveGroup) &&
                  _people.isNotEmpty)
                toggle('Always split payments to $title',
                    'Next month\'s bill splits by itself', _auto,
                    (v) => setState(() => _auto = v)),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _busy || over || _people.isEmpty || others <= 0
                      ? null
                      : () => _save(groups),
                  child: _busy
                      ? RisingLoader(color: tk.onAcc)
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
