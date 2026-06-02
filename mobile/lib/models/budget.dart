import 'package:cloud_firestore/cloud_firestore.dart';

class Budget {
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
