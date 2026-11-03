import 'package:cloud_firestore/cloud_firestore.dart';

import 'split.dart';

enum TxnDirection { debit, credit }

enum TxnSource { sms, manual, recurring, imported }

class Transaction {
  final String id;
  final double amount; // always positive; direction held separately
  final TxnDirection direction;
  final DateTime timestamp;
  final String? merchant;
  final String? account; // last-4 or masked acct
  final String categoryId;
  final String? note;
  final TxnSource source;
  final String? smsBody; // original SMS for audit/review
  final String? smsSender;
  final bool reviewed; // user has confirmed an auto-parsed txn
  final String? reference; // UPI Ref / UTR / RRN from the SMS
  final String? upiVpa; // payee/payer UPI ID e.g. name@okhdfcbank
  final bool hasReceipt; // an encrypted photo lives at receipts/{id}
  final double? balance; // account balance the bank SMS printed after this txn

  /// The paired transaction: the other leg of a transfer between your own
  /// accounts, or (on a refund) the purchase it refunds.
  final String? linkId;

  /// Money moved between two of YOUR accounts: neither spend nor income.
  final bool selfTransfer;

  /// A shared bill the user paid: who owes what (see [spendAmount]).
  final SplitInfo? split;

  /// On a payback: the shared bill ([id]) whose share this settles — or a
  /// loan, as [loanStart] + its id on the money that started it and
  /// [loanRepay] + its id on each repayment…
  final String? settles;

  /// …and whose share it is (the [SplitShare.name]), or who the loan is with.
  final String? settlesMember;

  static const loanStart = 'lend:', loanRepay = 'loan:';

  const Transaction({
    required this.id,
    required this.amount,
    required this.direction,
    required this.timestamp,
    required this.categoryId,
    this.merchant,
    this.account,
    this.note,
    this.source = TxnSource.manual,
    this.smsBody,
    this.smsSender,
    this.reviewed = true,
    this.reference,
    this.upiVpa,
    this.hasReceipt = false,
    this.balance,
    this.linkId,
    this.selfTransfer = false,
    this.split,
    this.settles,
    this.settlesMember,
  });

  bool get isDebit => direction == TxnDirection.debit;
  bool get isCredit => direction == TxnDirection.credit;

  /// Money back for a purchase. Not income: it's taken off total spend.
  bool get isRefund => isCredit && categoryId == 'refund';
  double get signed => isDebit ? -amount : amount;

  /// Counts as spending in totals (a transfer between your own accounts
  /// doesn't). Use these — not [isDebit]/[isCredit] — for any aggregate, and
  /// sum [spendAmount], not [amount].
  bool get isSpend => isDebit && !isInternal;

  /// Counts as income or refund in totals (see [isRefund] to tell them apart).
  /// A friend paying back their share of a bill is neither.
  bool get isIncoming => isCredit && !selfTransfer && !isSettlement;

  /// Linked to a share of a shared bill or to a loan — see [settles].
  bool get isSettlement => settles != null;

  /// Money lent out or borrowed in, tracked as a loan.
  bool get startsLoan => settles?.startsWith(loanStart) ?? false;

  /// Money that pays back a loan, either way.
  bool get repaysLoan => settles?.startsWith(loanRepay) ?? false;

  bool get isLoan => startsLoan || repaysLoan;
  String? get loanId => isLoan ? settles!.substring(loanStart.length) : null;

  /// What a linked entry is, named in place of its category; null if none.
  String? get linkKind => selfTransfer
      ? 'Transfer'
      : startsLoan
          ? (isDebit ? 'Lent' : 'Borrowed')
          : repaysLoan && isDebit
              ? 'Repaid'
              : isSettlement
                  ? 'Payback'
                  : null;

  /// Moves money that is neither spend nor income (own-account transfer,
  /// share payback, loan) — skip it in every total.
  bool get isInternal => selfTransfer || isSettlement;

  /// What this adds to the user's spending: their own share of a split bill,
  /// else the whole amount. (Bank balances still use [amount].)
  double get spendAmount => split?.myShare(amount) ?? amount;

  /// Auto-captured (bank SMS, payment screenshot) and not yet confirmed by
  /// the user — it waits in the review deck.
  bool get needsReview => !reviewed;

  /// Came from a payment screenshot: the image is its receipt and there is
  /// no SMS behind it.
  bool get fromScreenshot => hasReceipt && smsBody == null;

  /// [smsSender] of an entry read from a photo (payment screen, bill or a
  /// handwritten note). Its [smsBody] is text AERIS wrote in the style of a
  /// bank SMS, kept instead of the image — never a message from a bank.
  static const scanSender = 'AERIS-SCAN';

  /// [smsBody] was generated from a scanned photo, not received from a bank.
  bool get scanGenerated =>
      source != TxnSource.sms && smsSender == scanSender;

  Map<String, dynamic> toMap() => {
        'amount': amount,
        'direction': direction.name,
        'timestamp': Timestamp.fromDate(timestamp),
        'merchant': merchant,
        'account': account,
        'categoryId': categoryId,
        'note': note,
        'source': source.name,
        'smsBody': smsBody,
        'smsSender': smsSender,
        'reviewed': reviewed,
        'reference': reference,
        'upiVpa': upiVpa,
        if (hasReceipt) 'receipt': true,
        if (balance != null) 'balance': balance,
        if (linkId != null) 'linkId': linkId,
        if (selfTransfer) 'selfTransfer': true,
        if (split != null) 'split': split!.toMap(),
        if (settles != null) 'settles': settles,
        if (settlesMember != null) 'settlesMember': settlesMember,
      };

  factory Transaction.fromMap(String id, Map<String, dynamic> map) =>
      Transaction(
        id: id,
        amount: (map['amount'] as num?)?.toDouble() ?? 0,
        direction: _dirFrom(map['direction'] as String?),
        timestamp: (map['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
        merchant: map['merchant'] as String?,
        account: map['account'] as String?,
        categoryId: map['categoryId'] as String? ?? 'other',
        note: map['note'] as String?,
        source: _srcFrom(map['source'] as String?),
        smsBody: map['smsBody'] as String?,
        smsSender: map['smsSender'] as String?,
        reviewed: map['reviewed'] as bool? ?? true,
        reference: map['reference'] as String?,
        upiVpa: map['upiVpa'] as String?,
        hasReceipt: map['receipt'] as bool? ?? false,
        balance: (map['balance'] as num?)?.toDouble(),
        linkId: map['linkId'] as String?,
        selfTransfer: map['selfTransfer'] as bool? ?? false,
        split: map['split'] is Map
            ? SplitInfo.fromMap(Map<String, dynamic>.from(map['split'] as Map))
            : null,
        settles: map['settles'] as String?,
        settlesMember: map['settlesMember'] as String?,
      );

  Transaction copyWith({
    double? amount,
    TxnDirection? direction,
    DateTime? timestamp,
    String? merchant,
    String? categoryId,
    String? note,
    bool? reviewed,
    bool? hasReceipt,
    double? balance,
    String? linkId,
    bool? selfTransfer,
    SplitInfo? split,
    String? settles,
    String? settlesMember,
    bool clearMerchant = false,
    bool clearNote = false,
    bool clearLink = false,
    bool clearSplit = false,
    bool clearSettles = false,
  }) =>
      Transaction(
        id: id,
        amount: amount ?? this.amount,
        direction: direction ?? this.direction,
        timestamp: timestamp ?? this.timestamp,
        merchant: clearMerchant ? null : (merchant ?? this.merchant),
        account: account,
        categoryId: categoryId ?? this.categoryId,
        note: clearNote ? null : (note ?? this.note),
        source: source,
        smsBody: smsBody,
        smsSender: smsSender,
        reviewed: reviewed ?? this.reviewed,
        reference: reference,
        upiVpa: upiVpa,
        hasReceipt: hasReceipt ?? this.hasReceipt,
        balance: balance ?? this.balance,
        linkId: clearLink ? null : (linkId ?? this.linkId),
        selfTransfer: clearLink ? false : (selfTransfer ?? this.selfTransfer),
        split: clearSplit ? null : (split ?? this.split),
        settles: clearSettles ? null : (settles ?? this.settles),
        settlesMember:
            clearSettles ? null : (settlesMember ?? this.settlesMember),
      );

  static TxnDirection _dirFrom(String? s) {
    return s == 'credit' ? TxnDirection.credit : TxnDirection.debit;
  }

  static TxnSource _srcFrom(String? s) {
    switch (s) {
      case 'sms':
        return TxnSource.sms;
      case 'recurring':
        return TxnSource.recurring;
      case 'imported':
        return TxnSource.imported;
      default:
        return TxnSource.manual;
    }
  }
}
