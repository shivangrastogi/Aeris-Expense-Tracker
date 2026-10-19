import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:uuid/uuid.dart';

import '../../core/theme.dart';
import '../../models/category.dart';
import '../../models/split.dart';
import '../../models/transaction.dart';
import '../../providers/auth_provider.dart';
import '../../providers/privacy_provider.dart';
import '../../providers/split_provider.dart';
import '../../providers/transactions_provider.dart';
import '../../utils/formatters.dart';
import '../../widgets/aeris_toast.dart';
import '../../widgets/text_input_dialog.dart';
import '../transactions/transaction_detail_screen.dart';

/// "Shared bills": who owes you what, your groups (and their auto-split
/// rules), and every bill you've split.
class SharedScreen extends ConsumerWidget {
  /// Shown as a tab inside People (no title bar of its own).
  final bool embedded;
  const SharedScreen({super.key, this.embedded = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(amountHiddenProvider);
    final owed = ref.watch(owedToYouProvider);
    final open = ref.watch(openSharesProvider);
    final groups = ref.watch(splitGroupsProvider).valueOrNull ?? const [];
    final bills = ref.watch(sharedBillsProvider);
    final total = owed.values.fold<double>(0, (s, v) => s + v);
    final muted = AerisColors.muted(context);

    return Scaffold(
      appBar: embedded ? null : AppBar(title: const Text('Shared bills')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
        children: [
          AerisCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('OWED TO YOU', style: hudLabel(context)),
              const SizedBox(height: 4),
              Text(formatRupees(total, decimals: true),
                  style: const TextStyle(
                      fontSize: 28, fontWeight: FontWeight.w800)),
              if (owed.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                      bills.isEmpty
                          ? 'Paid a bill for others — rent, electricity, a '
                              'dinner? Open it and tap "Split this bill".'
                          : 'Everyone has paid you back.',
                      style: TextStyle(color: muted, fontSize: 13)),
                ),
              for (final e in owed.entries)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Row(children: [
                    CircleAvatar(
                      radius: 16,
                      backgroundColor: AerisColors.accentSoft(context),
                      child: Text(e.key[0].toUpperCase(),
                          style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: AerisColors.accent(context))),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(e.key,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                    ),
                    Text(formatRupees(e.value, decimals: true),
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    TextButton(
                      onPressed: () => remind(e.key, [
                        for (final s in open)
                          if (s.share.name == e.key) s
                      ]),
                      child: const Text('Remind'),
                    ),
                  ]),
                ),
            ]),
          ),
          const SizedBox(height: 22),
          const SectionLabel('Groups'),
          if (groups.isEmpty)
            Text('Groups are made when you split a bill — or add one here.',
                style: TextStyle(color: muted, fontSize: 13)),
          for (final g in groups) _GroupCard(group: g),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => _newGroup(context, ref),
              icon: const Icon(Icons.group_add_outlined),
              label: const Text('New group'),
            ),
          ),
          if (bills.isNotEmpty) ...[
            const SizedBox(height: 14),
            const SectionLabel('Shared bills'),
            AerisCard(
              padding: EdgeInsets.zero,
              child: Column(children: [
                for (final b in bills.take(40)) _BillRow(bill: b),
              ]),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _newGroup(BuildContext context, WidgetRef ref) async {
    final uid = ref.read(currentUserIdProvider);
    final name = await promptText(context,
        title: 'New group',
        hint: 'e.g. Flat, Goa trip',
        capitalization: TextCapitalization.words,
        confirmLabel: 'Create');
    if (name == null || name.isEmpty || uid == null || !context.mounted) return;
    final g = SplitGroup(
        id: const Uuid().v4(),
        name: name,
        members: const []);
    await ref.read(firestoreServiceProvider).setSplitGroup(uid, g);
    if (context.mounted) await showGroupEditor(context, ref, g);
  }
}

/// Share a polite reminder of what [person] owes ([shares]).
Future<void> remind(String person, List<OpenShare> shares) async {
  final total = shares.fold<double>(0, (s, x) => s + x.share.outstanding);
  final lines = [
    for (final s in shares)
      '• ${s.bill.merchant ?? Categories.byId(s.bill.categoryId).label} '
          '(${shortDate(s.bill.timestamp)}): '
          '${formatRupees(s.share.outstanding, decimals: true, raw: true)}',
  ];
  await Share.share([
    'Hi $person, a quick reminder of your share:',
    ...lines,
    'Total ${formatRupees(total, decimals: true, raw: true)}. Thanks!',
  ].join('\n'));
}

class _BillRow extends StatelessWidget {
  final Transaction bill;
  const _BillRow({required this.bill});

  @override
  Widget build(BuildContext context) {
    final split = bill.split!;
    final paid = split.shares.where((s) => s.settled).length;
    final muted = AerisColors.muted(context);
    return ListTile(
      onTap: () => Navigator.push(context,
          MaterialPageRoute(builder: (_) => TransactionDetailScreen(txn: bill))),
      leading: Icon(Categories.byId(bill.categoryId).icon,
          color: Categories.byId(bill.categoryId).color),
      title: Text(bill.merchant ?? Categories.byId(bill.categoryId).label),
      subtitle: Text(
          '${shortDate(bill.timestamp)} · your share '
          '${formatRupees(bill.spendAmount)} · $paid of ${split.shares.length} paid back',
          style: TextStyle(color: muted)),
      trailing: split.settled
          ? Icon(Icons.check_circle_rounded, color: AerisColors.moneyIn(context))
          : Text(formatRupees(split.outstanding),
              style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: AerisColors.warning)),
    );
  }
}

class _GroupCard extends ConsumerWidget {
  final SplitGroup group;
  const _GroupCard({required this.group});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final muted = AerisColors.muted(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AerisCard(
        onTap: () => showGroupEditor(context, ref, group),
        child: Row(children: [
          const Icon(Icons.groups_2_outlined),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(group.name,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              Text(
                  group.members.isEmpty
                      ? 'No one added yet'
                      : 'You, ${group.members.map((m) => m.name).join(', ')}',
                  style: TextStyle(color: muted, fontSize: 12.5)),
              if (group.autoPayees.isNotEmpty)
                Text('Auto-splits: ${group.autoPayees.join(', ')}',
                    style: TextStyle(color: muted, fontSize: 12)),
            ]),
          ),
          const Icon(Icons.chevron_right_rounded),
        ]),
      ),
    );
  }
}

/// Edit a group: rename, add / remove people, unequal shares (weights),
/// remove auto-split payees, delete.
Future<void> showGroupEditor(
        BuildContext context, WidgetRef ref, SplitGroup group) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _GroupEditor(group: group),
    );

class _GroupEditor extends ConsumerStatefulWidget {
  final SplitGroup group;
  const _GroupEditor({required this.group});

  @override
  ConsumerState<_GroupEditor> createState() => _GroupEditorState();
}

class _GroupEditorState extends ConsumerState<_GroupEditor> {
  late SplitGroup _g = widget.group;
  final _add = TextEditingController();

  static const _weights = [0.5, 1.0, 1.5, 2.0];

  @override
  void dispose() {
    _add.dispose();
    super.dispose();
  }

  Future<void> _save(SplitGroup g, {String? toast}) async {
    final uid = ref.read(currentUserIdProvider);
    if (uid == null) return;
    setState(() => _g = g);
    await ref.read(firestoreServiceProvider).setSplitGroup(uid, g);
    if (mounted && toast != null) {
      ScaffoldMessenger.of(context).showToast(SnackBar(content: Text(toast)));
    }
  }

  void _addPerson() {
    final name = _add.text.trim();
    if (name.isEmpty ||
        _g.members.any((m) => m.name.toLowerCase() == name.toLowerCase())) {
      return;
    }
    _add.clear();
    _save(_g.copyWith(members: [..._g.members, SplitMember(name: name)]),
        toast: '$name added to ${_g.name}');
  }

  String _wLabel(double w) => w == 1 ? 'Equal' : '${w}x';

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text('Delete ${_g.name}?'),
        content: const Text(
            'Bills already split keep their shares. Future payments stop '
            'auto-splitting into this group.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
          FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: AerisColors.danger(context),
                  foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(d, true),
              child: const Text('Delete')),
        ],
      ),
    );
    final uid = ref.read(currentUserIdProvider);
    if (ok != true || uid == null) return;
    await ref.read(firestoreServiceProvider).deleteSplitGroup(uid, _g.id);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final muted = AerisColors.muted(context);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                child: Text(_g.name,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700)),
              ),
              IconButton(
                tooltip: 'Rename',
                icon: const Icon(Icons.edit_outlined),
                onPressed: () async {
                  final n = await promptText(context,
                      title: 'Rename group',
                      initial: _g.name,
                      capitalization: TextCapitalization.words);
                  if (n != null && n.isNotEmpty) {
                    await _save(_g.copyWith(name: n), toast: 'Renamed');
                  }
                },
              ),
            ]),
            Text('Shares for automatic splits. "Equal" for everyone splits '
                'evenly; give a bigger room 1.5x.',
                style: TextStyle(color: muted, fontSize: 12.5)),
            const SizedBox(height: 8),
            _personRow('You', _g.myWeight,
                (w) => _save(_g.copyWith(myWeight: w), toast: 'Saved')),
            for (var i = 0; i < _g.members.length; i++)
              _personRow(_g.members[i].name, _g.members[i].weight, (w) {
                final ms = [..._g.members];
                ms[i] = ms[i].copyWith(weight: w);
                _save(_g.copyWith(members: ms), toast: 'Saved');
              }, onRemove: () {
                final ms = [..._g.members]..removeAt(i);
                _save(_g.copyWith(members: ms), toast: 'Removed');
              }),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _add,
                  textCapitalization: TextCapitalization.words,
                  onSubmitted: (_) => _addPerson(),
                  decoration: const InputDecoration(
                      isDense: true,
                      hintText: 'Add a person',
                      prefixIcon: Icon(Icons.person_add_alt_1_outlined)),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                  tooltip: 'Add', onPressed: _addPerson, icon: const Icon(Icons.add)),
            ]),
            if (_g.autoPayees.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Text('Splits automatically when you pay',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final p in _g.autoPayees)
                  InputChip(
                    label: Text(p),
                    onDeleted: () => _save(
                        _g.copyWith(
                            autoPayees: [..._g.autoPayees]..remove(p)),
                        toast: 'Stopped auto-splitting $p'),
                  ),
              ]),
            ],
            const SizedBox(height: 16),
            TextButton.icon(
              onPressed: _delete,
              icon: Icon(Icons.delete_outline, color: AerisColors.danger(context)),
              label: Text('Delete group',
                  style: TextStyle(color: AerisColors.danger(context))),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _personRow(String name, double weight, ValueChanged<double> onWeight,
      {VoidCallback? onRemove}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(children: [
        CircleAvatar(
          radius: 15,
          backgroundColor: AerisColors.accentSoft(context),
          child: Text(name[0].toUpperCase(),
              style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: AerisColors.accent(context))),
        ),
        const SizedBox(width: 10),
        Expanded(child: Text(name, style: const TextStyle(fontWeight: FontWeight.w600))),
        DropdownButtonHideUnderline(
          child: DropdownButton<double>(
            value: _weights.contains(weight) ? weight : 1.0,
            style: TextStyle(
                fontFamily: kFontFamily,
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color: Theme.of(context).colorScheme.onSurface),
            onChanged: (w) => w == null ? null : onWeight(w),
            items: [
              for (final w in _weights)
                DropdownMenuItem(value: w, child: Text(_wLabel(w))),
            ],
          ),
        ),
        if (onRemove != null)
          IconButton(
              tooltip: 'Remove $name',
              icon: const Icon(Icons.close_rounded, size: 20),
              onPressed: onRemove)
        else
          const SizedBox(width: 48),
      ]),
    );
  }
}
