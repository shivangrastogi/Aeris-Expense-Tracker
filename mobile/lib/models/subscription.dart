/// A recurring subscription/bill the user manages (Netflix, rent, etc.).
/// JSON-safe so it can be encrypted into a single blob before syncing.
class Subscription {
  final String id;
  final String name;
  final double amount;
  final String categoryId;
  final int day; // renewal day of month, 1..28

  const Subscription({
    required this.id,
    required this.name,
    required this.amount,
    required this.categoryId,
    this.day = 1,
  });

  Map<String, dynamic> toMap() => {
        'name': name,
        'amount': amount,
        'categoryId': categoryId,
        'day': day,
      };

  factory Subscription.fromMap(String id, Map<String, dynamic> m) =>
      Subscription(
        id: id,
        name: (m['name'] as String?) ?? 'Subscription',
        amount: (m['amount'] as num?)?.toDouble() ?? 0,
        categoryId: (m['categoryId'] as String?) ?? 'bills',
        day: (m['day'] as num?)?.toInt() ?? 1,
      );

  Subscription copyWith({
    String? name,
    double? amount,
    String? categoryId,
    int? day,
  }) =>
      Subscription(
        id: id,
        name: name ?? this.name,
        amount: amount ?? this.amount,
        categoryId: categoryId ?? this.categoryId,
        day: day ?? this.day,
      );
}
