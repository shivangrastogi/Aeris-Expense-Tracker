import 'package:cloud_firestore/cloud_firestore.dart';

enum TxnDirection { debit, credit }

enum TxnSource { sms, manual, recurring, imported }

class Transaction {
  final String id;
  final double amount;            // always positive; direction held separately
  final TxnDirection direction;
  final DateTime timestamp;
  final String? merchant;
  final String? account;          // last-4 or masked acct
  final String categoryId;
  final String? note;
  final TxnSource source;
  final String? smsBody;          // original SMS for audit/review
  final String? smsSender;
  final bool reviewed;            // user has confirmed an auto-parsed txn

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
  });

  bool get isDebit => direction == TxnDirection.debit;
  bool get isCredit => direction == TxnDirection.credit;
  double get signed => isDebit ? -amount : amount;

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
      };

  factory Transaction.fromMap(String id, Map<String, dynamic> map) => Transaction(
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
      );

  Transaction copyWith({
    double? amount,
    TxnDirection? direction,
    DateTime? timestamp,
    String? merchant,
    String? categoryId,
    String? note,
    bool? reviewed,
  }) => Transaction(
        id: id,
        amount: amount ?? this.amount,
        direction: direction ?? this.direction,
        timestamp: timestamp ?? this.timestamp,
        merchant: merchant ?? this.merchant,
        account: account,
        categoryId: categoryId ?? this.categoryId,
        note: note ?? this.note,
        source: source,
        smsBody: smsBody,
        smsSender: smsSender,
        reviewed: reviewed ?? this.reviewed,
      );

  static TxnDirection _dirFrom(String? s) {
    return s == 'credit' ? TxnDirection.credit : TxnDirection.debit;
  }

  static TxnSource _srcFrom(String? s) {
    switch (s) {
      case 'sms': return TxnSource.sms;
      case 'recurring': return TxnSource.recurring;
      case 'imported': return TxnSource.imported;
      default: return TxnSource.manual;
    }
  }
}
