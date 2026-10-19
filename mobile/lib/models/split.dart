/// Shared bills: you pay the whole thing (rent to the landlord, the
/// electricity bill, a group dinner) and the others pay you back their part.
///
/// Only YOUR share counts as your spending; the rest is money owed to you,
/// and each payback (UPI, bank transfer or cash) settles a share instead of
/// counting as income. All JSON-safe, so it rides inside the encrypted
/// transaction / group blobs.
library;

/// One person's part of a shared bill you paid.
class SplitShare {
  final String name;
  final double amount; // what they owe for this bill
  final double received; // paid back so far (matched payment or marked)

  const SplitShare({required this.name, required this.amount, this.received = 0});

  double get outstanding {
    final o = amount - received;
    return o < 0 ? 0 : o;
  }

  bool get settled => outstanding < 0.5;

  SplitShare copyWith({String? name, double? amount, double? received}) =>
      SplitShare(
        name: name ?? this.name,
        amount: amount ?? this.amount,
        received: received ?? this.received,
      );

  Map<String, dynamic> toMap() =>
      {'name': name, 'amount': amount, if (received > 0) 'received': received};

  factory SplitShare.fromMap(Map<String, dynamic> m) => SplitShare(
        name: (m['name'] as String?) ?? 'Friend',
        amount: (m['amount'] as num?)?.toDouble() ?? 0,
        received: (m['received'] as num?)?.toDouble() ?? 0,
      );
}

/// The split on a bill the user paid: [shares] are what the others owe; the
/// rest of the transaction amount is the user's own share.
class SplitInfo {
  final String? groupId;
  final List<SplitShare> shares;

  const SplitInfo({this.groupId, required this.shares});

  double get othersTotal => shares.fold(0, (s, x) => s + x.amount);

  /// The user's own part of a bill of [total].
  double myShare(double total) {
    final m = total - othersTotal;
    return m < 0 ? 0 : m;
  }

  double get outstanding => shares.fold(0, (s, x) => s + x.outstanding);
  bool get settled => shares.every((s) => s.settled);

  SplitInfo withShare(int i, SplitShare s) => SplitInfo(
        groupId: groupId,
        shares: [for (var j = 0; j < shares.length; j++) j == i ? s : shares[j]],
      );

  Map<String, dynamic> toMap() => {
        if (groupId != null) 'group': groupId,
        'shares': [for (final s in shares) s.toMap()],
      };

  factory SplitInfo.fromMap(Map<String, dynamic> m) => SplitInfo(
        groupId: m['group'] as String?,
        shares: [
          for (final s in (m['shares'] as List? ?? const []))
            SplitShare.fromMap(Map<String, dynamic>.from(s as Map)),
        ],
      );
}

/// Someone you share bills with.
class SplitMember {
  final String name;

  /// Relative share for an automatic split (1 = equal; 1.5 = a bigger room).
  final double weight;

  /// UPI IDs / payer names seen paying the user back — learned, so their
  /// next payback is recognised even when the SMS names them differently.
  final List<String> handles;

  const SplitMember({required this.name, this.weight = 1, this.handles = const []});

  SplitMember copyWith({String? name, double? weight, List<String>? handles}) =>
      SplitMember(
        name: name ?? this.name,
        weight: weight ?? this.weight,
        handles: handles ?? this.handles,
      );

  Map<String, dynamic> toMap() => {
        'name': name,
        if (weight != 1) 'weight': weight,
        if (handles.isNotEmpty) 'handles': handles,
      };

  factory SplitMember.fromMap(Map<String, dynamic> m) => SplitMember(
        name: (m['name'] as String?) ?? 'Friend',
        weight: (m['weight'] as num?)?.toDouble() ?? 1,
        handles: [for (final h in (m['handles'] as List? ?? const [])) '$h'],
      );
}

/// People the user regularly splits with ("Flat", "Goa trip"), and the
/// payees whose payments split among them automatically (the landlord's UPI
/// ID, the electricity board…).
class SplitGroup {
  final String id;
  final String name;
  final List<SplitMember> members; // everyone except the user
  final double myWeight;

  /// Lower-cased payee names / UPI IDs that auto-split into this group.
  final List<String> autoPayees;

  const SplitGroup({
    required this.id,
    required this.name,
    required this.members,
    this.myWeight = 1,
    this.autoPayees = const [],
  });

  SplitGroup copyWith({
    String? name,
    List<SplitMember>? members,
    double? myWeight,
    List<String>? autoPayees,
  }) =>
      SplitGroup(
        id: id,
        name: name ?? this.name,
        members: members ?? this.members,
        myWeight: myWeight ?? this.myWeight,
        autoPayees: autoPayees ?? this.autoPayees,
      );

  Map<String, dynamic> toMap() => {
        'name': name,
        'members': [for (final m in members) m.toMap()],
        if (myWeight != 1) 'myWeight': myWeight,
        if (autoPayees.isNotEmpty) 'autoPayees': autoPayees,
      };

  factory SplitGroup.fromMap(String id, Map<String, dynamic> m) => SplitGroup(
        id: id,
        name: (m['name'] as String?) ?? 'Group',
        members: [
          for (final x in (m['members'] as List? ?? const []))
            SplitMember.fromMap(Map<String, dynamic>.from(x as Map)),
        ],
        myWeight: (m['myWeight'] as num?)?.toDouble() ?? 1,
        autoPayees: [for (final p in (m['autoPayees'] as List? ?? const [])) '$p'],
      );
}
