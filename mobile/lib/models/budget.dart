import 'package:cloud_firestore/cloud_firestore.dart';

class Budget {
  /// Reserved category id for the single overall "total monthly budget"
  /// (stored as one budget doc, kept out of the per-category lists/sums).
  static const totalId = '__total__';

  final String id;
  final String categoryId;
  final double monthlyCap;
  final DateTime updatedAt;

  const Budget({
    required this.id,
    required this.categoryId,
    required this.monthlyCap,
    required this.updatedAt,
  });

  Map<String, dynamic> toMap() => {
        'categoryId': categoryId,
        'monthlyCap': monthlyCap,
        'updatedAt': Timestamp.fromDate(updatedAt),
      };

  factory Budget.fromMap(String id, Map<String, dynamic> map) => Budget(
        id: id,
        categoryId: map['categoryId'] as String? ?? 'other',
        monthlyCap: (map['monthlyCap'] as num?)?.toDouble() ?? 0,
        updatedAt: (map['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      );
}
