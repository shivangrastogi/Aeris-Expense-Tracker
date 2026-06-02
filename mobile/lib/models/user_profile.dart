import 'package:cloud_firestore/cloud_firestore.dart';

class UserProfile {
  final String uid;
  final String email;
  final String? displayName;
  final String? phone;
  final String? photoUrl;
  final String currency;        // 'INR' default
  final double monthlyIncome;   // for budget recommendations
  final DateTime createdAt;

  const UserProfile({
    required this.uid,
    required this.email,
    required this.createdAt,
    this.displayName,
    this.phone,
    this.photoUrl,
    this.currency = 'INR',
    this.monthlyIncome = 0,
  });

  Map<String, dynamic> toMap() => {
        'email': email,
        'displayName': displayName,
        'phone': phone,
        'photoUrl': photoUrl,
        'currency': currency,
        'monthlyIncome': monthlyIncome,
        'createdAt': Timestamp.fromDate(createdAt),
      };

  factory UserProfile.fromMap(String uid, Map<String, dynamic> map) => UserProfile(
        uid: uid,
        email: map['email'] as String? ?? '',
        displayName: map['displayName'] as String?,
        phone: map['phone'] as String?,
        photoUrl: map['photoUrl'] as String?,
        currency: map['currency'] as String? ?? 'INR',
        monthlyIncome: (map['monthlyIncome'] as num?)?.toDouble() ?? 0,
        createdAt: (map['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      );

  UserProfile copyWith({
    String? displayName,
    String? phone,
    String? photoUrl,
    String? currency,
    double? monthlyIncome,
  }) => UserProfile(
        uid: uid,
        email: email,
        createdAt: createdAt,
        displayName: displayName ?? this.displayName,
        phone: phone ?? this.phone,
        photoUrl: photoUrl ?? this.photoUrl,
        currency: currency ?? this.currency,
        monthlyIncome: monthlyIncome ?? this.monthlyIncome,
      );
}
