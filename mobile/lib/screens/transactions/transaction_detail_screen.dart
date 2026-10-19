import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../models/category.dart';
import '../../models/split.dart';
import '../../models/transaction.dart';
import '../../providers/auth_provider.dart';
import '../../providers/gamification_provider.dart';
import '../../providers/prefs_data_provider.dart';
import '../../providers/split_provider.dart';
import '../../providers/transactions_provider.dart';
import '../../services/category_rules.dart';
import '../../services/merchant_directory.dart';
import '../../services/notification_intake.dart';
import '../../services/sms_parser.dart';
import '../../services/sms_templates.dart';
import '../../services/split_links.dart';
import '../../services/split_service.dart';
import '../../utils/formatters.dart';
import '../../core/routes.dart';
import '../../widgets/field_editor.dart';
import '../../widgets/receipt_field.dart';
import '../../widgets/txn_undo.dart';
import '../../widgets/aeris_toast.dart';
import '../split/shared_screen.dart';
import '../split/split_sheet.dart';

class TransactionDetailScreen extends ConsumerStatefulWidget {
  final Transaction txn;
  const TransactionDetailScreen({super.key, required this.txn});

  @override
  ConsumerState<TransactionDetailScreen> createState() => _TxDetailState();
}

class _TxDetailState extends ConsumerState<TransactionDetailScreen> {
  late Transaction _t = widget.txn;

  Future<void> _changeCategory() async {
    final picked = await editCategoryField(context, selected: _t.categoryId);
    if (picked == null || picked == _t.categoryId) return;
    await _apply(_t.copyWith(categoryId: picked, reviewed: true));
    // Learn: future SMS from this merchant auto-tag to this category.
    await CategoryRules.instance.remember(_t.merchant, picked);
    // Reward categorising this transaction (once per transaction).
    final awarded =
        ref.read(gamificationProvider.notifier).rewardCategorization(_t.id);
    if (awarded > 0 && mounted) {
      ScaffoldMessenger.of(context).showToast(SnackBar(
          content: Text('+$awarded Aura for categorising 🎉'),
          duration: const Duration(seconds: 2)));
    }
  }

  // Each row edits just its own field in a small sheet — tapping "Note"
  // never opens the whole add form.

  Future<void> _editAmount() async {
    final v = await editAmountField(context,
        title: _t.isCredit ? 'Income amount' : 'Expense amount',
        initialInr: _t.amount);
    if (v == null || v == _t.amount) return;
    await _apply(_t.copyWith(amount: v));
  }

  Future<void> _editMerchant() async {
    final v = await editTextField(context,
        title: _t.isCredit ? 'Payer / source' : 'Merchant / payee',
        initial: _t.merchant ?? '',
        icon: Icons.storefront_rounded,
        maxLength: 80,
        capitalization: TextCapitalization.words);
    if (v == null || v == (_t.merchant ?? '')) return;
    await _apply(v.isEmpty
        ? _t.copyWith(clearMerchant: true)
        : _t.copyWith(merchant: v));
  }

  Future<void> _editNote() async {
    final v = await editTextField(context,
        title: 'Note',
        initial: _t.note ?? '',
        hint: 'e.g. dinner with friends',
        icon: Icons.notes_rounded,
        multiline: true);
    if (v == null || v == (_t.note ?? '')) return;
    await _apply(
        v.isEmpty ? _t.copyWith(clearNote: true) : _t.copyWith(note: v));
  }

  Future<void> _editWhen() async {
    final v = await editDateTimeField(context, initial: _t.timestamp);
    if (v == null || v == _t.timestamp) return;
    await _apply(_t.copyWith(timestamp: v));
  }

  Future<void> _editType() async {
    final picked = await showModalBottomSheet<TxnDirection>(
      context: context,
      showDragHandle: true,
      builder: (s) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (d, label, icon, color) in [
              (
                TxnDirection.debit,
                'Expense (money out)',
                Icons.south_west_rounded,
                AerisColors.moneyOut(context)
              ),
              (
                TxnDirection.credit,
                'Income (money in)',
                Icons.north_east_rounded,
                AerisColors.moneyIn(context)
              ),
            ])
              ListTile(
                leading: Icon(icon, color: color),
                title: Text(label),
                trailing: d == _t.direction
                    ? Icon(Icons.check_rounded,
                        color: Theme.of(context).colorScheme.primary)
                    : null,
                onTap: () => Navigator.pop(s, d),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (picked == null || picked == _t.direction) return;
    await _apply(_t.copyWith(direction: picked));
  }

  /// Opens the full form — only from the app bar's "Edit all details",
  /// for things without their own row (account, receipt…).
  Future<void> _openEditor() async {
    final updated =
        await Navigator.pushNamed(context, AppRoutes.addTxn, arguments: _t);
    if (updated is Transaction && mounted) {
      setState(() {
        _t = updated;
        _receiptFuture = null;
      });
    }
  }

  Future<List<int>?>? _receiptFuture;

  Future<void> _apply(Transaction updated) async {
    final uid = ref.read(currentUserIdProvider);
    if (uid == null) return;
    final previous = _t;
    setState(() => _t = updated);
    try {
      await ref.read(firestoreServiceProvider).updateTransaction(uid, updated);
    } catch (err) {
      if (!mounted) return;
      setState(() => _t = previous);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not save: $err')));
      return;
    }
    // Learn: a fixed amount / type / category on an SMS import is replayed
    // on this bank template's future alerts.
    await SmsTemplates.instance.learn(previous, updated);
    if (mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(
            content: Text('Saved'), duration: Duration(seconds: 1)));
    }
  }

  /// Deletes straight away but offers UNDO on the next screen.
  Future<void> _delete() async {
    await deleteTransactionsWithUndo(context, ref, [_t]);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final cat = Categories.byId(_t.categoryId);
    final color = _t.isCredit
        ? AerisColors.moneyIn(context)
        : AerisColors.moneyOut(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Transaction'),
        actions: [
          IconButton(
              tooltip: 'Edit all details',
              icon: const Icon(Icons.edit_outlined),
              onPressed: _openEditor),
          IconButton(
              tooltip: 'Delete',
              icon: const Icon(Icons.delete_outline),
              onPressed: _delete),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Row(children: [
            CircleAvatar(
              radius: 28,
              backgroundColor: cat.color.withValues(alpha: 0.18),
              child: Icon(cat.icon, color: cat.color),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_t.merchant ?? cat.label,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          )),
                  const SizedBox(height: 4),
                  InkWell(
                    onTap: _editAmount,
                    child: Row(
                      children: [
                        Text(
                          '${_t.isCredit ? "+ " : "− "}${formatRupees(_t.amount, decimals: true)}',
                          style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                              color: color),
                        ),
                        const SizedBox(width: 8),
                        Icon(Icons.edit,
                            size: 16,
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ]),
          const SizedBox(height: 28),
          _row('Category', cat.label,
              onTap: _changeCategory, trailingIcon: Icons.edit),
          _row('Type', _t.isCredit ? 'Income' : 'Expense',
              onTap: _editType, trailingIcon: Icons.edit),
          _row(_t.isCredit ? 'Payer' : 'Merchant',
              _t.merchant ?? (_t.isCredit ? 'Add payer' : 'Add merchant'),
              onTap: _editMerchant, trailingIcon: Icons.edit),
          _row(
              'When',
              '${relativeDate(_t.timestamp)} · '
                  '${TimeOfDay.fromDateTime(_t.timestamp).format(context)}',
              onTap: _editWhen,
              trailingIcon: Icons.edit),
          if (_t.account != null)
            _row('Account', () {
              final nick = (ref.watch(accountNamesProvider).valueOrNull ??
                  const {})[_t.account];
              return nick == null ? '••${_t.account}' : '$nick · ••${_t.account}';
            }()),
          if (MerchantDirectory.appFor(_t.upiVpa) != null)
            _row('Paid via', MerchantDirectory.appFor(_t.upiVpa)!),
          if (_t.upiVpa != null) _row('UPI ID', _t.upiVpa!),
          if (_t.reference != null) _row('Reference', _t.reference!),
          _row('Source', _t.source.name),
          _row('Note', _t.note ?? 'Add a note',
              onTap: _editNote, trailingIcon: Icons.edit),
          if (_t.balance != null)
            _row('Balance after', formatRupees(_t.balance!, decimals: true)),
          ..._links(context),
          ..._splitSection(context),
          if (_t.hasReceipt) _receiptSection(),
          if (_t.smsBody != null) _originalMessage(context),
        ],
      ),
    );
  }

  // ── Linked transactions: own-account transfer pair, refund ↔ purchase ──

  List<Widget> _links(BuildContext context) {
    final all = ref.watch(transactionsStreamProvider).valueOrNull ?? const [];
    Transaction? byId(String? id) =>
        id == null ? null : all.where((t) => t.id == id).firstOrNull;
    final out = <Widget>[];
    String brief(Transaction t) =>
        '${formatRupees(t.amount, decimals: true)} · '
        '${t.merchant ?? Categories.byId(t.categoryId).label} · '
        '${relativeDate(t.timestamp)}';

    if (_t.selfTransfer) {
      final other = byId(_t.linkId);
      out.add(_linkCard(
        context,
        icon: Icons.swap_horiz_rounded,
        title: 'Transfer between your accounts',
        body: 'Not counted as spending or income.'
            '${other == null ? '' : '\n${other.isCredit ? 'Arrived in' : 'Left from'} '
                '${other.account == null ? 'another account' : 'A/C ••${other.account}'} · '
                '${relativeDate(other.timestamp)}'}',
        onOpen: other == null ? null : () => _open(other),
        action: TextButton(
            onPressed: () => _unlinkTransfer(other),
            child: const Text('Not a transfer')),
      ));
    }
    if (_t.isRefund && _t.linkId != null) {
      final bought = byId(_t.linkId);
      if (bought != null) {
        out.add(_linkCard(context,
            icon: Icons.replay_rounded,
            title: 'Refund for',
            body: brief(bought),
            onOpen: () => _open(bought)));
      }
    }
    if (_t.isDebit && !_t.selfTransfer) {
      final refunds =
          all.where((t) => t.isRefund && t.linkId == _t.id).toList();
      if (refunds.isNotEmpty) {
        final back = refunds.fold<double>(0, (s, t) => s + t.amount);
        out.add(_linkCard(context,
            icon: Icons.replay_rounded,
            title: back + 0.01 >= _t.amount
                ? 'Fully refunded'
                : 'Refunded ${formatRupees(back, decimals: true)}',
            body: refunds.map(brief).join('\n'),
            onOpen: refunds.length == 1 ? () => _open(refunds.single) : null));
      }
    }
    return out;
  }

  Widget _linkCard(BuildContext context,
      {required IconData icon,
      required String title,
      required String body,
      VoidCallback? onOpen,
      Widget? action}) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onOpen,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
            child: Row(children: [
              Icon(icon, color: scheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(body,
                        style: TextStyle(
                            fontSize: 12.5, color: scheme.onSurfaceVariant)),
                  ],
                ),
              ),
              if (action != null) action,
              if (onOpen != null && action == null)
                const Icon(Icons.chevron_right_rounded),
            ]),
          ),
        ),
      ),
    );
  }

  // ── Shared bills: split a bill you paid; paybacks from friends ─────────

  List<Widget> _splitSection(BuildContext context) {
    final all = ref.watch(transactionsStreamProvider).valueOrNull ?? const [];
    // Keep the on-screen copy in step with the ledger (paybacks change it).
    final live = all.where((t) => t.id == _t.id).firstOrNull;
    final t = live ?? _t;
    final scheme = Theme.of(context).colorScheme;

    if (t.isDebit && !t.selfTransfer) {
      final split = t.split;
      if (split == null) {
        return [
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: OutlinedButton.icon(
              onPressed: () => _split(t),
              icon: const Icon(Icons.call_split_rounded),
              label: const Text('Split this bill'),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 4),
            child: Text(
                'Paid for roommates or friends? Count only your share — their '
                'payments back are matched automatically.',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
          ),
        ];
      }
      return [
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Icon(Icons.call_split_rounded, color: scheme.primary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                          'Shared bill · your share ${formatRupees(t.spendAmount, decimals: true)}',
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                    ),
                    IconButton(
                        tooltip: 'Edit split',
                        icon: const Icon(Icons.edit_outlined, size: 20),
                        onPressed: () => _split(t)),
                  ]),
                  for (var i = 0; i < split.shares.length; i++)
                    _shareRow(t, i, split.shares[i]),
                  TextButton(
                    onPressed: () => _removeSplit(t),
                    child: Text('Remove split',
                        style: TextStyle(color: AerisColors.danger(context))),
                  ),
                ],
              ),
            ),
          ),
        ),
      ];
    }

    if (t.isSettlement) {
      final bill = all.where((x) => x.id == t.settles).firstOrNull;
      return [
        _linkCard(
          context,
          icon: Icons.call_split_rounded,
          title: '${t.settlesMember ?? 'A share'} paid back',
          body: bill == null
              ? 'Their share of a shared bill — not counted as income.'
              : 'Their share of ${bill.merchant ?? Categories.byId(bill.categoryId).label} '
                  '(${formatRupees(bill.amount, decimals: true)} · '
                  '${relativeDate(bill.timestamp)}) — not counted as income.',
          onOpen: bill == null ? null : () => _open(bill),
          action: TextButton(
              onPressed: () => _unlinkPayback(t),
              child: const Text('Not a payback')),
        ),
      ];
    }

    if (t.isCredit && !t.isRefund && !t.selfTransfer) {
      final open = ref.watch(openSharesProvider);
      if (open.isEmpty) return const [];
      return [
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: OutlinedButton.icon(
            onPressed: () => _pickShare(t, open),
            icon: const Icon(Icons.call_split_rounded),
            label: const Text('Is this someone paying you back?'),
          ),
        ),
      ];
    }
    return const [];
  }

  Widget _shareRow(Transaction bill, int i, SplitShare s) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final status = s.settled
        ? 'Paid back'
        : s.received > 0
            ? '${formatRupees(s.received)} of ${formatRupees(s.amount)} paid'
            : '${formatRupees(s.outstanding)} pending';
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(children: [
        Icon(
            s.settled
                ? Icons.check_circle_rounded
                : Icons.radio_button_unchecked_rounded,
            size: 20,
            color: s.settled ? AerisColors.moneyIn(context) : muted),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${s.name} · ${formatRupees(s.amount, decimals: true)}',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              Text(status,
                  style: TextStyle(
                      fontSize: 12,
                      color: s.settled
                          ? AerisColors.moneyIn(context)
                          : AerisColors.warning)),
            ],
          ),
        ),
        PopupMenuButton<String>(
          tooltip: 'Options for ${s.name}',
          onSelected: (v) async {
            final uid = ref.read(currentUserIdProvider);
            if (uid == null) return;
            if (v == 'remind') {
              await remind(s.name, [(bill: bill, index: i, share: s)]);
            } else {
              await SplitService.instance
                  .markReceived(uid, bill, i, received: v == 'paid');
              if (mounted) {
                ScaffoldMessenger.of(context).showToast(SnackBar(
                    content: Text(v == 'paid'
                        ? '${s.name}\'s share marked as received'
                        : '${s.name}\'s share marked as pending')));
              }
            }
          },
          itemBuilder: (_) => [
            if (!s.settled)
              const PopupMenuItem(
                  value: 'paid', child: Text('Mark received (cash / other)')),
            if (s.received > 0)
              const PopupMenuItem(value: 'unpaid', child: Text('Mark as not paid')),
            if (!s.settled)
              const PopupMenuItem(value: 'remind', child: Text('Remind')),
          ],
        ),
      ]),
    );
  }

  Future<void> _split(Transaction bill) async {
    final saved = await showSplitSheet(context, bill);
    if (saved != null && mounted) {
      setState(() => _t = saved);
      ScaffoldMessenger.of(context).showToast(SnackBar(
          content: Text(
              'Split saved — your share is ${formatRupees(saved.spendAmount, decimals: true)}')));
    }
  }

  Future<void> _removeSplit(Transaction bill) async {
    final uid = ref.read(currentUserIdProvider);
    if (uid == null) return;
    await SplitService.instance.removeSplit(uid, bill);
    if (!mounted) return;
    setState(() => _t = _t.copyWith(clearSplit: true));
    ScaffoldMessenger.of(context).showToast(const SnackBar(
        content: Text('Split removed — the full amount counts again')));
  }

  Future<void> _unlinkPayback(Transaction credit) async {
    final uid = ref.read(currentUserIdProvider);
    if (uid == null) return;
    await SplitService.instance.unlinkPayback(uid, credit);
    if (!mounted) return;
    setState(() =>
        _t = _t.copyWith(clearSettles: true, categoryId: 'transfer'));
  }

  Future<void> _pickShare(Transaction credit, List<OpenShare> open) async {
    final picked = await showModalBottomSheet<OpenShare>(
      context: context,
      showDragHandle: true,
      builder: (s) => SafeArea(
        child: ListView(shrinkWrap: true, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(
                'Which share does ${formatRupees(credit.amount, decimals: true)} pay back?',
                style: Theme.of(s)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
          ),
          for (final o in open.take(20))
            ListTile(
              leading: const Icon(Icons.person_outline),
              title: Text(o.share.name),
              subtitle: Text(
                  '${o.bill.merchant ?? Categories.byId(o.bill.categoryId).label} · '
                  '${relativeDate(o.bill.timestamp)}'),
              trailing: Text(formatRupees(o.share.outstanding),
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              onTap: () => Navigator.pop(s, o),
            ),
        ]),
      ),
    );
    final uid = ref.read(currentUserIdProvider);
    if (picked == null || uid == null) return;
    final groups = ref.read(splitGroupsProvider).valueOrNull ?? const [];
    final group =
        groups.where((g) => g.id == picked.bill.split?.groupId).firstOrNull;
    await SplitService.instance
        .linkPayback(uid, credit, picked.bill, picked.index, group: group);
    if (!mounted) return;
    setState(() => _t = SplitLinks.markPayback(_t, picked.bill, picked.index));
    ScaffoldMessenger.of(context).showToast(SnackBar(
        content: Text('Linked as ${picked.share.name}\'s share — '
            'not counted as income')));
  }

  void _open(Transaction t) => Navigator.push(context,
      MaterialPageRoute(builder: (_) => TransactionDetailScreen(txn: t)));

  /// The pair wasn't a transfer between the user's own accounts: count both
  /// legs again.
  Future<void> _unlinkTransfer(Transaction? other) async {
    final uid = ref.read(currentUserIdProvider);
    await _apply(_t.copyWith(clearLink: true, reviewed: true));
    if (uid != null && other != null) {
      await ref
          .read(firestoreServiceProvider)
          .updateTransaction(uid, other.copyWith(clearLink: true));
    }
  }

  // ── Original SMS / notification, numbers tappable ──────────────────────

  Widget _originalMessage(BuildContext context) {
    final app = NotificationIntake.appNameOf(_t.smsSender);
    final scheme = Theme.of(context).colorScheme;
    final read = SmsParser.amountSpans(_t.smsBody!);
    final spans = <InlineSpan>[];
    var at = 0;
    for (final s in read.spans) {
      if (s.start < at) continue;
      spans.add(TextSpan(text: read.text.substring(at, s.start)));
      final current = (s.value - _t.amount).abs() < 0.005;
      spans.add(WidgetSpan(
        alignment: PlaceholderAlignment.baseline,
        baseline: TextBaseline.alphabetic,
        child: GestureDetector(
          onTap: current ? null : () => _useAmount(s.value),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            decoration: BoxDecoration(
              color: current
                  ? scheme.primary.withValues(alpha: 0.16)
                  : scheme.onSurface.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(5),
              border: Border.all(
                  color: current
                      ? scheme.primary
                      : scheme.onSurface.withValues(alpha: 0.18)),
            ),
            child: Text(read.text.substring(s.start, s.end),
                style: TextStyle(
                    fontSize: 12,
                    height: 1.3,
                    fontWeight: FontWeight.w700,
                    color: current ? scheme.primary : null)),
          ),
        ),
      ));
      at = s.end;
    }
    spans.add(TextSpan(text: read.text.substring(at)));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        Text(app == null ? 'Original SMS' : 'Original notification',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                )),
        const SizedBox(height: 6),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Text.rich(TextSpan(children: spans),
                style: const TextStyle(fontSize: 12, height: 1.5)),
          ),
        ),
        if (read.spans.length > 1)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
                'Wrong amount? Tap the right number — AERIS remembers it for '
                'this bank\'s messages.',
                style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
          ),
        Text(
            app == null
                ? 'From: ${_t.smsSender ?? "unknown sender"}'
                : 'From: $app app',
            style: const TextStyle(fontSize: 11)),
      ],
    );
  }

  Future<void> _useAmount(double value) async {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (s) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Use ${formatRupees(value, decimals: true)} as the amount?',
                  style: Theme.of(s)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text(
                  'Instead of ${formatRupees(_t.amount, decimals: true)}. '
                  'Future messages in this format will use the same number.',
                  style: TextStyle(
                      color: Theme.of(s).colorScheme.onSurfaceVariant)),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(
                  child: OutlinedButton(
                      onPressed: () => Navigator.pop(s, false),
                      child: const Text('Cancel')),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                      onPressed: () => Navigator.pop(s, true),
                      child: const Text('Use this')),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
    if (ok == true) await _apply(_t.copyWith(amount: value, reviewed: true));
  }

  Widget _receiptSection() {
    final uid = ref.read(currentUserIdProvider);
    _receiptFuture ??= uid == null
        ? Future.value(null)
        : ref.read(firestoreServiceProvider).fetchReceipt(uid, _t.id);
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Receipt',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          FutureBuilder<List<int>?>(
            future: _receiptFuture,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const SizedBox(
                    height: 120,
                    child: Center(child: CircularProgressIndicator()));
              }
              final data = snap.data;
              if (data == null) {
                return const Text(
                    "Receipt isn't available offline on this device yet.");
              }
              final bytes = Uint8List.fromList(data);
              return GestureDetector(
                onTap: () => showReceiptViewer(context, bytes),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Image.memory(bytes,
                      height: 180, width: double.infinity, fit: BoxFit.cover),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _row(String label, String value,
      {VoidCallback? onTap, IconData? trailingIcon}) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      trailing: trailingIcon != null
          ? Icon(trailingIcon, size: 18)
          : const SizedBox.shrink(),
      subtitle: Text(value,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
      onTap: onTap,
    );
  }
}
