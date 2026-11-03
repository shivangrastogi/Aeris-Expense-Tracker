import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../models/category.dart';
import '../../models/split.dart';
import '../../models/transaction.dart';
import '../../providers/auth_provider.dart';
import '../../providers/gamification_provider.dart';
import '../../providers/loans_provider.dart';
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
import '../../widgets/ds.dart';
import '../../widgets/field_editor.dart';
import '../../widgets/receipt_field.dart';
import '../../widgets/txn_undo.dart';
import '../../widgets/aeris_toast.dart';
import '../../widgets/income_text.dart';
import '../../providers/income_lock_provider.dart';
import '../split/shared_screen.dart';
import '../split/split_sheet.dart';

class TransactionDetailScreen extends ConsumerStatefulWidget {
  final Transaction txn;

  /// Set when shown as the right pane on a tablet (list–detail): "back" and
  /// delete close the pane instead of popping a route.
  final VoidCallback? onClose;
  const TransactionDetailScreen({super.key, required this.txn, this.onClose});

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
        icon: Ph.storefront,
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
        icon: Ph.notePencil,
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
    final picked = await showDsSheet<TxnDirection>(
      context,
      title: 'Type',
      builder: (s) {
        final tk = s.tk;
        return ListGroup(inset: 64, children: [
          for (final (d, label, icon, color) in [
            (TxnDirection.debit, 'Expense (money out)', Ph.arrowUpRight, tk.t1),
            (TxnDirection.credit, 'Income (money in)', Ph.arrowDownLeft, tk.ok),
          ])
            SettingsRow(
              icon: icon,
              iconColor: color,
              title: label,
              trailing: d == _t.direction
                  ? Icon(PhBold.check, size: 18, color: tk.acc)
                  : const SizedBox.shrink(),
              onTap: () => Navigator.pop(s, d),
            ),
        ]);
      },
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
    if (!mounted) return;
    widget.onClose != null ? widget.onClose!() : Navigator.pop(context);
  }

  /// What kind of money movement this is, for the pill under the amount.
  String get _kind =>
      _t.linkKind ??
      (_t.isRefund
          ? 'Refund'
          : _t.isCredit
              ? 'Income'
              : 'Expense');

  @override
  Widget build(BuildContext context) {
    final tk = context.tk;
    final cat = Categories.byId(_t.categoryId);
    // Salary: amount, balance and the SMS stay hidden behind the fingerprint.
    final salaryLocked = _t.isCredit &&
        _t.categoryId == 'salary' &&
        ref.watch(incomeLockProvider).masked;
    final (tileColor, tileIcon) = _t.isSettlement
        ? (tk.ok, Ph.handCoins)
        : _t.selfTransfer
            ? (tk.t2, Ph.arrowsLeftRight)
            : (cat.color, cat.icon);
    final app = MerchantDirectory.appFor(_t.upiVpa);

    final fields = <Widget>[
      // A loan isn't spending or income, so it has no category.
      if (!_t.isLoan) _row('Category', cat.label, onTap: _changeCategory),
      _row(
          'Type',
          _t.isInternal
              ? (_t.isCredit ? 'Money in' : 'Money out')
              : (_t.isCredit ? 'Income' : 'Expense'),
          onTap: _editType),
      _row(_t.isCredit ? 'Payer' : 'Merchant',
          _t.merchant ?? (_t.isCredit ? 'Add payer' : 'Add merchant'),
          onTap: _editMerchant, placeholder: _t.merchant == null),
      _row(
          'When',
          // relativeDate is just the time today, and has no time a year on.
          switch (relativeDate(_t.timestamp)) {
            final r when !r.contains(':') =>
              '$r, ${TimeOfDay.fromDateTime(_t.timestamp).format(context)}',
            final r when !r.contains(',') => 'Today, $r',
            final r => r,
          },
          onTap: _editWhen),
      if (_t.account != null)
        _row('Account', () {
          final nick = (ref.watch(accountNamesProvider).valueOrNull ??
              const {})[_t.account];
          return nick == null ? '••${_t.account}' : '$nick ••${_t.account}';
        }()),
      if (app != null) _row('Paid via', app),
      if (_t.upiVpa != null) _row('UPI ID', _t.upiVpa!),
      if (_t.reference != null) _row('Reference', _t.reference!),
      _row(
          'Source',
          NotificationIntake.appNameOf(_t.smsSender) != null
              ? 'UPI app notification'
              : _t.scanGenerated
                  ? 'Scanned photo'
                  : _sourceLabel(_t.source.name)),
      _row('Note', _t.note ?? 'Add a note',
          onTap: _editNote, placeholder: _t.note == null),
      if (_t.balance != null)
        _row(
            'Balance after',
            salaryLocked
                ? '${kCurrency.symbol}••••'
                : formatRupees(_t.balance!, decimals: true)),
    ];

    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          // ── ← · Edit all details · Delete ─────────────────────
          SizedBox(
            height: 56,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 8, 0),
              child: Row(children: [
                IconButton(
                  tooltip: 'Back',
                  onPressed:
                      widget.onClose ?? () => Navigator.maybePop(context),
                  icon: Icon(widget.onClose != null ? Ph.x : Ph.arrowLeft,
                      size: 22, color: tk.t1),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: _openEditor,
                  icon: const Icon(Ph.pencilSimple, size: 18),
                  label: const Text('Edit all details'),
                  style: TextButton.styleFrom(
                      foregroundColor: tk.acc,
                      textStyle: const TextStyle(
                          fontFamily: kFontFamily,
                          fontSize: 14,
                          fontWeight: FontWeight.w600)),
                ),
                IconButton(
                  tooltip: 'Delete transaction',
                  onPressed: _delete,
                  icon: Icon(Ph.trash, size: 22, color: tk.bad),
                ),
              ]),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 36),
              children: [
                // ── Header: tile · merchant · amount · kind ────────
                Column(children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: tileColor.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Icon(tileIcon, size: 32, color: tileColor),
                  ),
                  const SizedBox(height: 8),
                  Text(_t.merchant ?? cat.label,
                      textAlign: TextAlign.center,
                      style: Ts.title.copyWith(color: tk.t1)),
                  const SizedBox(height: 4),
                  Semantics(
                    button: true,
                    label: 'Edit amount',
                    child: InkWell(
                      onTap: _editAmount,
                      borderRadius: BorderRadius.circular(14),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Flexible(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: salaryLocked
                                  ? IncomeText(_t.amount,
                                      credit: true,
                                      color: tk.ok,
                                      style: const TextStyle(
                                          fontSize: 40,
                                          height: 44 / 40,
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: -1))
                                  : MoneyText(
                                      _t.amount,
                                      credit: _t.isCredit,
                                      decimals: _t.amount % 1 != 0,
                                      color: _t.isCredit ? tk.ok : tk.t1,
                                      style: const TextStyle(
                                          fontSize: 40,
                                          height: 44 / 40,
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: -1),
                                    ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Icon(Ph.pencilSimple, size: 16, color: tk.t3),
                        ]),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    height: 24,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                        color: tk.press,
                        borderRadius: BorderRadius.circular(12)),
                    child: Text(_kind,
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: tk.t1)),
                  ),
                ]),
                const SizedBox(height: 14),
                if (_t.needsReview) ...[
                  _reviewBanner(context),
                  const SizedBox(height: 14),
                ],
                for (final w in [..._splitSection(context), ..._links(context)])
                  Padding(padding: const EdgeInsets.only(bottom: 14), child: w),
                ListGroup(inset: 0, children: fields),
                if (_t.hasReceipt) _receiptSection(),
                if (_t.smsBody != null) ...[
                  const SizedBox(height: 14),
                  salaryLocked
                      ? _lockedMessage(context)
                      : _originalMessage(context),
                ],
              ],
            ),
          ),
        ]),
      ),
    );
  }

  static String _sourceLabel(String name) => switch (name) {
        'sms' => 'Bank SMS',
        'manual' => 'Added by you',
        'recurring' => 'Recurring',
        'imported' => 'Imported',
        _ => name.isEmpty ? name : name[0].toUpperCase() + name.substring(1),
      };

  /// "AERIS wasn't sure about this one" + Looks right.
  Widget _reviewBanner(BuildContext context) {
    final tk = context.tk;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      decoration: BoxDecoration(
          color: tk.accSoft, borderRadius: BorderRadius.circular(16)),
      child: Row(children: [
        Icon(Ph.question, size: 20, color: tk.acc),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
              "AERIS wasn't sure about this one. Check the category and amount.",
              style: TextStyle(fontSize: 13, height: 18 / 13, color: tk.t1)),
        ),
        const SizedBox(width: 10),
        FilledButton(
          onPressed: () => _apply(_t.copyWith(reviewed: true)),
          style: FilledButton.styleFrom(
            minimumSize: const Size(0, 36),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(Rad.chip)),
            textStyle:
                const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          ),
          child: const Text('Looks right'),
        ),
      ]),
    );
  }

  // ── Linked transactions: own-account transfer pair, refund ↔ purchase ──

  List<Widget> _links(BuildContext context) {
    final tk = context.tk;
    final all = ref.watch(transactionsStreamProvider).valueOrNull ?? const [];
    Transaction? byId(String? id) =>
        id == null ? null : all.where((t) => t.id == id).firstOrNull;
    final out = <Widget>[];
    String brief(Transaction t) =>
        '${formatRupees(t.amount, decimals: true)} · '
        '${relativeDate(t.timestamp)}'
        '${t.account == null ? '' : ' · ••${t.account}'}';

    if (_t.selfTransfer) {
      final other = byId(_t.linkId);
      final from = _t.isDebit ? _t.account : other?.account;
      final to = _t.isDebit ? other?.account : _t.account;
      out.add(_card(context, children: [
        _cardHead(context,
            tile: const BadgeTile(icon: Ph.arrowsLeftRight),
            title: 'Transfer between your accounts',
            body: other == null
                ? 'Not counted as spending or income.'
                : 'Not counted as spending or income · '
                    '${other.isCredit ? 'Arrived in' : 'Left from'} '
                    '${other.account == null ? 'another account' : '••${other.account}'}'),
        if (from != null || to != null)
          InkWell(
            onTap: other == null ? null : () => _open(other),
            borderRadius: BorderRadius.circular(14),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                  color: tk.sunken, borderRadius: BorderRadius.circular(14)),
              child: Row(children: [
                Text(from == null ? 'Account' : '••$from', style: _semi(tk)),
                const SizedBox(width: 8),
                Icon(Ph.arrowRight, size: 18, color: tk.t2),
                const SizedBox(width: 8),
                Text(to == null ? 'Account' : '••$to', style: _semi(tk)),
              ]),
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: _smallOutline('Not a transfer', () => _unlinkTransfer(other)),
        ),
      ]));
    }
    if (_t.isRefund && _t.linkId != null) {
      final bought = byId(_t.linkId);
      if (bought != null) {
        final bcat = Categories.byId(bought.categoryId);
        out.add(_card(context,
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
            children: [
              const Overline('Refund for'),
              _linkRow(context,
                  tile: CatTile.of(bcat),
                  title: bought.merchant ?? bcat.label,
                  sub: brief(bought),
                  onTap: () => _open(bought)),
            ]));
      }
    }
    if (_t.isDebit && !_t.selfTransfer) {
      final refunds =
          all.where((t) => t.isRefund && t.linkId == _t.id).toList();
      if (refunds.isNotEmpty) {
        final back = refunds.fold<double>(0, (s, t) => s + t.amount);
        final full = back + 0.01 >= _t.amount;
        out.add(_card(context,
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
            children: [
              Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Expanded(
                      child: Text(
                          full
                              ? 'Fully refunded'
                              : 'Refunded ${formatRupees(back, decimals: true)}',
                          style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: tk.ok)),
                    ),
                    if (!full)
                      Text(
                          'You paid ${formatRupees(_t.amount - back, decimals: true)} in the end',
                          style: TextStyle(fontSize: 13, color: tk.t2)),
                  ]),
              for (final r in refunds)
                _linkRow(context,
                    tile: CatTile(color: tk.ok, icon: Ph.arrowUUpLeft),
                    title: r.merchant ?? 'Refund',
                    sub:
                        '+${formatRupees(r.amount, decimals: true)} · ${relativeDate(r.timestamp)}',
                    onTap: () => _open(r)),
            ]));
      }
    }
    return out;
  }

  TextStyle _semi(AerisTokens tk) =>
      TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: tk.t1);

  Widget _card(BuildContext context,
          {required List<Widget> children,
          EdgeInsetsGeometry padding = const EdgeInsets.all(16)}) =>
      Container(
        padding: padding,
        decoration: AerisColors.cardDecoration(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) const SizedBox(height: 12),
              children[i],
            ],
          ],
        ),
      );

  Widget _cardHead(BuildContext context,
      {required Widget tile, required String title, required String body}) {
    final tk = context.tk;
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      tile,
      const SizedBox(width: 12),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: Ts.rowTitle.copyWith(color: tk.t1)),
          const SizedBox(height: 2),
          Text(body, style: Ts.bodyS.copyWith(color: tk.t2)),
        ]),
      ),
    ]);
  }

  Widget _linkRow(BuildContext context,
      {required Widget tile,
      required String title,
      required String sub,
      required VoidCallback onTap}) {
    final tk = context.tk;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Rad.tile),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(children: [
          tile,
          const SizedBox(width: 12),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: Ts.rowTitle.copyWith(color: tk.t1)),
              Text(sub, style: Ts.bodyS.copyWith(color: tk.t2)),
            ]),
          ),
          Icon(Ph.caretRight, size: 16, color: tk.t3),
        ]),
      ),
    );
  }

  Widget _smallOutline(String label, VoidCallback onTap) => OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 38),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(Rad.chip)),
          textStyle: const TextStyle(
              fontFamily: kFontFamily,
              fontSize: 13,
              fontWeight: FontWeight.w600),
        ),
        child: Text(label),
      );

  Widget _smallTonal(String label, VoidCallback onTap, {IconData? trailing}) {
    final tk = context.tk;
    return FilledButton(
      onPressed: onTap,
      style: FilledButton.styleFrom(
        backgroundColor: tk.accSoft,
        foregroundColor: tk.acc,
        minimumSize: const Size(0, 38),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Rad.chip)),
        textStyle: const TextStyle(
            fontFamily: kFontFamily, fontSize: 13, fontWeight: FontWeight.w700),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(label),
        if (trailing != null) ...[
          const SizedBox(width: 4),
          Icon(trailing, size: 12),
        ],
      ]),
    );
  }

  // ── Shared bills: split a bill you paid; paybacks from friends ─────────

  List<Widget> _splitSection(BuildContext context) {
    final tk = context.tk;
    final all = ref.watch(transactionsStreamProvider).valueOrNull ?? const [];
    // Keep the on-screen copy in step with the ledger (paybacks change it).
    final live = all.where((t) => t.id == _t.id).firstOrNull;
    final t = live ?? _t;

    if (t.isLoan) return [_loanCard(context, t)];

    if (t.isDebit && !t.selfTransfer) {
      final split = t.split;
      if (split == null) {
        return [
          Column(children: [
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _split(t),
                icon: const Icon(Ph.usersThree, size: 18),
                label: const Text('Split this bill'),
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 52)),
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                  'Only your share will count as spending. When friends pay '
                  'you back, AERIS matches it here.',
                  textAlign: TextAlign.center,
                  style:
                      TextStyle(fontSize: 13, height: 18 / 13, color: tk.t2)),
            ),
          ]),
        ];
      }
      return [
        Container(
          clipBehavior: Clip.antiAlias,
          decoration: AerisColors.cardDecoration(context),
          child: Material(
            type: MaterialType.transparency,
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
                child: Row(children: [
                  BadgeTile(icon: Ph.usersThree, tint: tk.acc),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Overline('Shared bill'),
                          Text(
                              'Your share ${formatRupees(t.spendAmount, decimals: true)}',
                              style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: tk.t1,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures()
                                  ])),
                        ]),
                  ),
                  FilledButton.icon(
                    onPressed: () => _split(t),
                    icon: const Icon(Ph.pencilSimple, size: 14),
                    label: const Text('Edit'),
                    style: FilledButton.styleFrom(
                      backgroundColor: tk.accSoft,
                      foregroundColor: tk.acc,
                      minimumSize: const Size(0, 36),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(Rad.chip)),
                      textStyle: const TextStyle(
                          fontFamily: kFontFamily,
                          fontSize: 13,
                          fontWeight: FontWeight.w700),
                    ),
                  ),
                ]),
              ),
              for (var i = 0; i < split.shares.length; i++) ...[
                Container(height: 1, color: tk.hair),
                _shareRow(t, i, split.shares[i]),
              ],
              Container(height: 1, color: tk.hair),
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: TextButton(
                    onPressed: () => _removeSplit(t),
                    style: TextButton.styleFrom(foregroundColor: tk.bad),
                    child: const Text('Remove split'),
                  ),
                ),
              ),
            ]),
          ),
        ),
      ];
    }

    if (t.isSettlement) {
      final bill = all.where((x) => x.id == t.settles).firstOrNull;
      final billName = bill == null
          ? null
          : bill.merchant ?? Categories.byId(bill.categoryId).label;
      return [
        _card(context, children: [
          _cardHead(context,
              tile: BadgeTile(icon: Ph.handCoins, tint: tk.ok),
              title: '${t.settlesMember ?? 'A share'} paid back',
              body: bill == null
                  ? 'Their share of a shared bill. Not counted as income.'
                  : 'Their share of $billName '
                      '(${formatRupees(bill.amount, decimals: true)} · '
                      '${relativeDate(bill.timestamp)}). Not counted as income.'),
          Wrap(spacing: 8, runSpacing: 8, children: [
            if (bill != null)
              _smallTonal('Open $billName', () => _open(bill),
                  trailing: PhBold.caretRight),
            _smallOutline('Not a payback', () => _unlinkPayback(t)),
          ]),
        ]),
      ];
    }

    if (t.isCredit && !t.isRefund && !t.selfTransfer) {
      // Only while a friend still owes a share; loans are set in the full
      // edit form ("What is it?").
      final open = ref.watch(openSharesProvider);
      if (open.isEmpty) return const [];
      return [
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => _pickShare(t, open),
            icon: const Icon(Ph.handCoins, size: 18),
            label: const Text('Their share of a split bill?'),
            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 52)),
          ),
        ),
      ];
    }
    return const [];
  }

  Widget _shareRow(Transaction bill, int i, SplitShare s) {
    final tk = context.tk;
    final (status, statusColor, statusIcon) = s.settled
        ? ('Paid back', tk.ok, PhFill.checkCircle)
        : s.received > 0
            ? (
                '${formatRupees(s.received)} of ${formatRupees(s.amount)} paid',
                tk.warn,
                PhFill.clock
              )
            : ('${formatRupees(s.outstanding)} pending', tk.warn, PhFill.clock);
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 62),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 4, 10),
        child: Row(children: [
          InitialAvatar(s.name),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.name, style: Ts.rowTitle.copyWith(color: tk.t1)),
                const SizedBox(height: 2),
                Row(children: [
                  Icon(statusIcon, size: 13, color: statusColor),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(status,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: statusColor)),
                  ),
                ]),
              ],
            ),
          ),
          MoneyText(s.amount),
          PopupMenuButton<String>(
            tooltip: 'Options for ${s.name}',
            icon: Icon(PhBold.dotsThreeVertical, size: 18, color: tk.t2),
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
                const PopupMenuItem(
                    value: 'unpaid', child: Text('Mark as not paid')),
              if (!s.settled)
                const PopupMenuItem(value: 'remind', child: Text('Remind')),
            ],
          ),
        ]),
      ),
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
    setState(
        () => _t = _t.copyWith(clearSettles: true, categoryId: 'transfer'));
  }

  Future<void> _pickShare(Transaction credit, List<OpenShare> open) async {
    final picked = await showDsSheet<OpenShare>(
      context,
      title:
          'Which share does ${formatRupees(credit.amount, decimals: true)} pay back?',
      scrollControlled: true,
      builder: (s) => SingleChildScrollView(
        child: ListGroup(children: [
          for (final o in open.take(20))
            DsRow(
              leading: InitialAvatar(o.share.name),
              title: o.share.name,
              sub:
                  '${o.bill.merchant ?? Categories.byId(o.bill.categoryId).label} · '
                  '${relativeDate(o.bill.timestamp)}',
              trailing: MoneyText(o.share.outstanding),
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

  // ── Loans: set in the full edit form; shown and undone here ───────────

  Widget _loanCard(BuildContext context, Transaction t) {
    final tk = context.tk;
    final loans = ref.watch(loansStreamProvider);
    final loan =
        loans.valueOrNull?.where((l) => l.id == t.loanId).firstOrNull;
    final who = t.settlesMember ?? loan?.person ?? 'Someone';
    final title = t.startsLoan
        ? (t.isDebit ? 'Lent to $who' : 'Borrowed from $who')
        : (t.isCredit ? '$who paid you back' : 'Paid $who back');
    final back = (loan?.borrowed ?? t.isDebit) ? 'repaid' : 'back';
    final status = !loans.hasValue
        ? ''
        : loan == null
            ? 'The loan was deleted. '
            : loan.isSettled
                ? 'All ${formatRupees(loan.amount)} $back · settled. '
                : '${formatRupees(loan.paid)} of ${formatRupees(loan.amount)} '
                    '$back · ${formatRupees(loan.outstanding)} left. ';
    return _card(context, children: [
      _cardHead(context,
          tile: BadgeTile(icon: Ph.handCoins, tint: tk.ok),
          title: title,
          body: '$status'
              'Not counted as ${t.isCredit ? 'income' : 'spending'}.'),
      Wrap(spacing: 8, runSpacing: 8, children: [
        _smallTonal('Open loans',
            () => Navigator.pushNamed(context, AppRoutes.loans),
            trailing: PhBold.caretRight),
        _smallOutline('Change', _openEditor),
      ]),
    ]);
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

  // ── The SMS of a salary credit names the amount: hidden while locked ────
  Widget _lockedMessage(BuildContext context) {
    final tk = context.tk;
    return Material(
      color: tk.surface,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Rad.card),
          side: BorderSide(color: tk.isDark ? tk.hair : Colors.transparent)),
      child: InkWell(
        borderRadius: BorderRadius.circular(Rad.card),
        onTap: () => unlockIncome(context, ref),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            BadgeTile(icon: Ph.lockSimple, tint: tk.acc),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Original SMS hidden',
                      style: Ts.rowTitle.copyWith(color: tk.t1)),
                  Text(
                      'It shows your salary. Tap to unlock with your '
                      'fingerprint.',
                      style: Ts.bodyS.copyWith(color: tk.t2)),
                ],
              ),
            ),
            Icon(Ph.fingerprint, size: 22, color: tk.acc),
          ]),
        ),
      ),
    );
  }

  // ── Original SMS / notification, numbers tappable ──────────────────────

  Widget _originalMessage(BuildContext context) {
    final tk = context.tk;
    final app = NotificationIntake.appNameOf(_t.smsSender);
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
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: current ? tk.accSoft2 : tk.press,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: current ? tk.acc : tk.hair2),
            ),
            child: Text(read.text.substring(s.start, s.end),
                style: TextStyle(
                    fontSize: 14,
                    height: 1.4,
                    fontWeight: FontWeight.w700,
                    color: current ? tk.acc : tk.t1)),
          ),
        ),
      ));
      at = s.end;
    }
    spans.add(TextSpan(text: read.text.substring(at)));
    final mono = TextStyle(fontSize: 11, color: tk.t2, fontFamily: 'monospace');

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: AerisColors.cardDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
                child: Overline(_t.scanGenerated
                    ? 'Generated from scan'
                    : app == null
                        ? 'Original SMS'
                        : 'Original notification')),
            Flexible(
              child: Text(
                  _t.scanGenerated
                      ? 'Not a bank SMS'
                      : app == null
                          ? 'From: ${_t.smsSender ?? 'unknown sender'}'
                          : 'From: $app app',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: mono),
            ),
          ]),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: tk.sunken,
              borderRadius: app == null
                  ? const BorderRadius.only(
                      topLeft: Radius.circular(16),
                      topRight: Radius.circular(16),
                      bottomRight: Radius.circular(16),
                      bottomLeft: Radius.circular(4))
                  : BorderRadius.circular(18),
            ),
            child: Text.rich(TextSpan(children: spans),
                style: TextStyle(fontSize: 14, height: 2, color: tk.t1)),
          ),
          if (read.spans.length > 1) ...[
            const SizedBox(height: 10),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Ph.handTap, size: 16, color: tk.acc),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                    'Wrong amount? Tap the right number — AERIS remembers it '
                    'for this bank.',
                    style:
                        TextStyle(fontSize: 12, height: 17 / 12, color: tk.t2)),
              ),
            ]),
          ],
        ],
      ),
    );
  }

  Future<void> _useAmount(double value) async {
    final ok = await showDsSheet<bool>(
      context,
      title: 'Use ${formatRupees(value, decimals: true)} as the amount?',
      subtitle: 'Instead of ${formatRupees(_t.amount, decimals: true)}. '
          'Future messages in this format will use the same number.',
      builder: (s) => Row(children: [
        Expanded(
          child: OutlinedButton(
              onPressed: () => Navigator.pop(s, false),
              child: const Text('Cancel')),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: FilledButton(
              onPressed: () => Navigator.pop(s, true),
              child: const Text('Use this')),
        ),
      ]),
    );
    if (ok == true) await _apply(_t.copyWith(amount: value, reviewed: true));
  }

  Widget _receiptSection() {
    final tk = context.tk;
    final uid = ref.read(currentUserIdProvider);
    _receiptFuture ??= uid == null
        ? Future.value(null)
        : ref.read(firestoreServiceProvider).fetchReceipt(uid, _t.id);
    return Container(
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.all(16),
      decoration: AerisColors.cardDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Overline('Receipt'),
          const SizedBox(height: 10),
          FutureBuilder<List<int>?>(
            future: _receiptFuture,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const SizedBox(
                    height: 120, child: Center(child: RisingLoader(width: 28)));
              }
              final data = snap.data;
              if (data == null) {
                return Text(
                    "Receipt isn't available offline on this device yet.",
                    style: Ts.bodyS.copyWith(color: tk.t2));
              }
              final bytes = Uint8List.fromList(data);
              return GestureDetector(
                onTap: () => showReceiptViewer(context, bytes),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(Rad.input),
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

  /// A detail field: label left (13, secondary), value right (14/600), and a
  /// caret when it can be edited.
  Widget _row(String label, String value,
      {VoidCallback? onTap, bool placeholder = false}) {
    final tk = context.tk;
    return InkWell(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 50),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(children: [
          SizedBox(
            width: 108,
            child: Text(label, style: TextStyle(fontSize: 13, color: tk.t2)),
          ),
          Expanded(
            child: Text(value,
                textAlign: TextAlign.right,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: placeholder ? FontWeight.w500 : FontWeight.w600,
                    color: placeholder ? tk.t3 : tk.t1,
                    fontFeatures: const [FontFeature.tabularFigures()])),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 14,
            child: onTap == null
                ? null
                : Icon(Ph.caretRight, size: 14, color: tk.t3),
          ),
        ]),
      ),
    );
  }
}

