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
import '../../widgets/ds.dart';

/// "Shared bills": who owes you what, your groups (and their auto-split
/// rules), and every bill you've split.
class SharedScreen extends ConsumerWidget {
  /// Shown as a tab inside People (no title bar of its own).
  final bool embedded;
  const SharedScreen({super.key, this.embedded = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(amountHiddenProvider);
    final tk = context.tk;
    final owed = ref.watch(owedToYouProvider);
    final open = ref.watch(openSharesProvider);
    final groups = ref.watch(splitGroupsProvider).valueOrNull ?? const [];
    final bills = ref.watch(sharedBillsProvider);
    final total = owed.values.fold<double>(0, (s, v) => s + v);

    // "Rent · 3 Oct" — the latest bill each person still owes on.
    String why(String person) {
      final mine = [
        for (final s in open)
          if (s.share.name == person) s
      ]..sort((a, b) => b.bill.timestamp.compareTo(a.bill.timestamp));
      if (mine.isEmpty) return 'shared bills';
      final b = mine.first.bill;
      final what = b.merchant ?? Categories.byId(b.categoryId).label;
      return mine.length == 1
          ? '$what · ${shortDate(b.timestamp)}'
          : '$what + ${mine.length - 1} more';
    }

    return Scaffold(
      appBar: embedded ? null : AppBar(title: const Text('Shared bills')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
        children: [
          Container(
            clipBehavior: Clip.antiAlias,
            decoration: AerisColors.cardDecoration(context),
            child: Material(
              type: MaterialType.transparency,
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 8, 12),
                      child: Row(children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Owed to you',
                                  style: Ts.bodyS.copyWith(color: tk.t2)),
                              MoneyText(total,
                                  color: total > 0 ? tk.ok : tk.t1,
                                  smallSymbol: false,
                                  style: Ts.amountL),
                            ],
                          ),
                        ),
                      ]),
                    ),
                    if (owed.isEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        child: Text(
                            bills.isEmpty
                                ? 'Paid a bill for others — rent, electricity, a '
                                    'dinner? Open it and tap "Split this bill".'
                                : 'Everyone has paid you back.',
                            style: Ts.bodyS.copyWith(color: tk.t2)),
                      ),
                    for (final e in owed.entries) ...[
                      Container(height: 1, color: tk.hair),
                      DsRow(
                        padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
                        leading: InitialAvatar(e.key),
                        title: e.key,
                        titleMaxLines: 1,
                        sub: why(e.key),
                        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                          MoneyText(e.value,
                              style: const TextStyle(
                                  fontSize: 15, fontWeight: FontWeight.w700)),
                          const SizedBox(width: 10),
                          _RemindButton(
                            onTap: () => remind(e.key, [
                              for (final s in open)
                                if (s.share.name == e.key) s
                            ]),
                          ),
                        ]),
                      ),
                    ],
                  ]),
            ),
          ),
          const SizedBox(height: 20),
          Row(children: [
            const Expanded(
              child: Padding(
                padding: EdgeInsets.only(left: 4),
                child: Overline('Groups'),
              ),
            ),
            InkWell(
              onTap: () => _newGroup(context, ref),
              borderRadius: BorderRadius.circular(Rad.chip),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Ph.plus, size: 15, color: tk.acc),
                  const SizedBox(width: 4),
                  Text('New group',
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: tk.acc)),
                ]),
              ),
            ),
          ]),
          const SizedBox(height: 4),
          if (groups.isEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 8),
              child: Text(
                  'Groups are made when you split a bill — or add one here.',
                  style: Ts.bodyS.copyWith(color: tk.t2)),
            ),
          for (final g in groups) _GroupCard(group: g),
          if (bills.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Padding(
              padding: EdgeInsets.fromLTRB(4, 0, 4, 8),
              child: Overline('Shared bills'),
            ),
            ListGroup(children: [
              for (final b in bills.take(40)) _BillRow(bill: b),
            ]),
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

/// The tonal "Remind" pill: 34 dp, accent-soft.
class _RemindButton extends StatelessWidget {
  final VoidCallback onTap;
  const _RemindButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final tk = context.tk;
    return Material(
      color: tk.accSoft,
      borderRadius: BorderRadius.circular(Rad.chip),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Rad.chip),
        child: Container(
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.center,
          child: Text('Remind',
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w700, color: tk.acc)),
        ),
      ),
    );
  }
}

class _BillRow extends StatelessWidget {
  final Transaction bill;
  const _BillRow({required this.bill});

  @override
  Widget build(BuildContext context) {
    final tk = context.tk;
    final split = bill.split!;
    final paid = split.shares.where((s) => s.settled).length;
    final cat = Categories.byId(bill.categoryId);
    return DsRow(
      onTap: () => Navigator.push(context,
          MaterialPageRoute(builder: (_) => TransactionDetailScreen(txn: bill))),
      leading: CatTile.of(cat),
      title: bill.merchant ?? cat.label,
      sub: '${shortDate(bill.timestamp)} · ${formatRupees(bill.amount)}',
      trailing: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('your share ${formatRupees(bill.spendAmount)}',
              style: Ts.rowTitle.copyWith(color: tk.t1)),
          const SizedBox(height: 3),
          split.settled
              ? const StatusPill('Settled',
                  icon: PhFill.checkCircle, tone: Tone.ok, small: true)
              : StatusPill('$paid of ${split.shares.length} paid back',
                  icon: PhFill.clock, tone: Tone.warn, small: true),
        ],
      ),
    );
  }
}

class _GroupCard extends ConsumerWidget {
  final SplitGroup group;
  const _GroupCard({required this.group});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tk = context.tk;
    final names = ['You', ...group.members.map((m) => m.name)];
    final shown = names.take(3).toList();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AerisCard(
        padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
        onTap: () => showGroupEditor(context, ref, group),
        child: Row(children: [
          // Overlapping initials.
          SizedBox(
            width: 28.0 + 20 * (shown.length - 1),
            height: 32,
            child: Stack(children: [
              for (var i = 0; i < shown.length; i++)
                Positioned(
                  left: i * 20.0,
                  child: Container(
                    decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: tk.surface, width: 2)),
                    child: InitialAvatar(shown[i], size: 28),
                  ),
                ),
            ]),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(group.name, style: Ts.rowTitle.copyWith(color: tk.t1)),
              Text(
                  group.members.isEmpty
                      ? 'No one added yet'
                      : 'You, ${group.members.map((m) => m.name).join(', ')}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Ts.label
                      .copyWith(fontWeight: FontWeight.w400, color: tk.t2)),
              const SizedBox(height: 2),
              Row(children: [
                Icon(Ph.lightning,
                    size: 12,
                    color: group.autoPayees.isNotEmpty ? tk.acc : tk.t3),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                      group.autoPayees.isNotEmpty
                          ? 'Auto-splits: payments to ${group.autoPayees.join(', ')}'
                          : 'No auto-splits',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: group.autoPayees.isNotEmpty ? tk.acc : tk.t3)),
                ),
              ]),
            ]),
          ),
          Icon(Ph.caretRight, size: 16, color: tk.t3),
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
                  foregroundColor: context.tk.isDark ? const Color(0xFF1A0F0E) : Colors.white),
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
                    style: Ts.title.copyWith(color: context.tk.t1)),
              ),
              IconButton(
                tooltip: 'Rename',
                icon: const Icon(Ph.pencilSimple),
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
                      prefixIcon: Icon(Ph.userPlus)),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                  tooltip: 'Add', onPressed: _addPerson, icon: const Icon(Ph.plus)),
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
              icon: Icon(Ph.trash, color: AerisColors.danger(context)),
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
        InitialAvatar(name, size: 32),
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
              icon: const Icon(Ph.x, size: 20),
              onPressed: onRemove)
        else
          const SizedBox(width: 48),
      ]),
    );
  }
}
