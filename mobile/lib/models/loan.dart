/// Money lent to (or borrowed from) a friend, tracked until it's settled.
/// All fields are JSON-safe (dates as epoch millis) so the whole object can be
/// encrypted into a single blob before it touches Firestore — friend names
/// and amounts are personal data.
class Loan {
  final String id;
  final String person; // who the money went to / came from
  final double amount;
  final String note;

  /// How much has been repaid so far (partial repayments). 0..amount.
  final double paid;

  /// false = I gave money (they owe me) · true = I took money (I owe them)
  final bool borrowed;
  final DateTime createdAt;

  /// When the money came back (or was paid back). null = still pending.
  final DateTime? settledAt;

  const Loan({
    required this.id,
    required this.person,
    required this.amount,
    required this.createdAt,
    this.note = '',
    this.paid = 0,
    this.borrowed = false,
    this.settledAt,
  });

  bool get isSettled => settledAt != null;

  /// Outstanding amount still owed (never negative).
  double get outstanding => (amount - paid).clamp(0, amount);
  bool get isPartial => paid > 0 && paid < amount && !isSettled;

  Map<String, dynamic> toMap() => {
        'person': person,
        'amount': amount,
        'note': note,
        'paid': paid,
        'borrowed': borrowed,
        'createdAt': createdAt.millisecondsSinceEpoch,
        'settledAt': settledAt?.millisecondsSinceEpoch,
      };

  factory Loan.fromMap(String id, Map<String, dynamic> m) => Loan(
        id: id,
        person: (m['person'] as String?) ?? 'Friend',
        amount: (m['amount'] as num?)?.toDouble() ?? 0,
        note: (m['note'] as String?) ?? '',
        paid: (m['paid'] as num?)?.toDouble() ?? 0,
        borrowed: (m['borrowed'] as bool?) ?? false,
        createdAt: DateTime.fromMillisecondsSinceEpoch(
            (m['createdAt'] as num?)?.toInt() ?? 0),
        settledAt: m['settledAt'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(
                (m['settledAt'] as num).toInt()),
      );

  Loan copyWith({
    String? person,
    double? amount,
    String? note,
    double? paid,
    bool? borrowed,
    Object? settledAt = _noChange,
  }) =>
      Loan(
        id: id,
        person: person ?? this.person,
        amount: amount ?? this.amount,
        note: note ?? this.note,
        paid: paid ?? this.paid,
        borrowed: borrowed ?? this.borrowed,
        createdAt: createdAt,
        settledAt:
            settledAt == _noChange ? this.settledAt : settledAt as DateTime?,
      );
}

const _noChange = Object();
