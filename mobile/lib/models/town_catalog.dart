import 'package:flutter/material.dart';

/// Aeris Town building catalogue — the rules of the town game in one place.
///
/// Design: the town is a mirror of your money habits, not a clicker.
/// * Producers make Aura per REAL DAY and hold at most one day's worth, so the
///   rhythm is "visit once a day", like the check-in.
/// * Today's check-in boosts what you collect (×1.5); being over this month's
///   budget halves it — the town literally weathers your spending.
/// * Decorations make the town nicer AND add +5% production each (max +50%).
/// * Construction takes real minutes/hours; gems (earned only from
///   milestones) can rush it.
enum TownRole { hall, producer, decoration, utility }

class TownBuilding {
  final String id;
  final String name;
  final String desc;
  final TownRole role;
  final int baseCost; // Aura to place (upgrade = base × (lvl+1)²)
  final int buildMinutes; // first build; upgrade = × (lvl+1)
  final int perDay; // Aura/day at level 1 (producers); × level
  final int maxLevel; // levels are 0-based internally; shown 1..maxLevel
  final int unlockHall; // town hall level required
  final Color color; // roof / accent colour in the painter
  final IconData icon;

  const TownBuilding({
    required this.id,
    required this.name,
    required this.desc,
    required this.role,
    required this.baseCost,
    required this.buildMinutes,
    this.perDay = 0,
    this.maxLevel = 5,
    this.unlockHall = 1,
    required this.color,
    required this.icon,
  });

  bool get produces => perDay > 0;

  int upgradeCost(int lvl) => (baseCost == 0 ? 150 : baseCost) * (lvl + 2) * (lvl + 2) ~/ 2;
  int buildMs(int lvl) => buildMinutes * 60 * 1000 * (lvl + 1);
  int dailyYield(int lvl) => perDay * (lvl + 1);
}

class TownCatalog {
  TownCatalog._();

  static const hall = TownBuilding(
    id: 'townhall',
    name: 'Town Hall',
    desc: 'The heart of Aeris Town. Each level unlocks new buildings and a builder.',
    role: TownRole.hall,
    baseCost: 0,
    buildMinutes: 45,
    color: Color(0xFF7AA6DA),
    icon: Icons.account_balance,
  );

  static const all = <TownBuilding>[
    hall,
    TownBuilding(
      id: 'house',
      name: 'House',
      desc: 'Makes a little Aura every day.',
      role: TownRole.producer,
      baseCost: 60,
      buildMinutes: 15,
      perDay: 20,
      color: Color(0xFF7C9CFF),
      icon: Icons.home_rounded,
    ),
    TownBuilding(
      id: 'farm',
      name: 'Aura Farm',
      desc: 'Cheap and steady. Loves daily check-ins.',
      role: TownRole.producer,
      baseCost: 40,
      buildMinutes: 10,
      perDay: 14,
      color: Color(0xFF63B98F),
      icon: Icons.grass,
    ),
    TownBuilding(
      id: 'market',
      name: 'Market',
      desc: 'Busy trade, good daily Aura.',
      role: TownRole.producer,
      baseCost: 120,
      buildMinutes: 30,
      perDay: 32,
      unlockHall: 2,
      color: Color(0xFFD2A35A),
      icon: Icons.storefront,
    ),
    TownBuilding(
      id: 'vault',
      name: 'Savings Vault',
      desc: 'The best producer. Built on discipline.',
      role: TownRole.producer,
      baseCost: 220,
      buildMinutes: 60,
      perDay: 55,
      unlockHall: 3,
      color: Color(0xFFE8C66A),
      icon: Icons.savings,
    ),
    TownBuilding(
      id: 'tree',
      name: 'Tree',
      desc: 'Decoration · +5% town production.',
      role: TownRole.decoration,
      baseCost: 25,
      buildMinutes: 5,
      maxLevel: 3,
      color: Color(0xFF3DDC97),
      icon: Icons.park,
    ),
    TownBuilding(
      id: 'fountain',
      name: 'Fountain',
      desc: 'Decoration · +5% town production.',
      role: TownRole.decoration,
      baseCost: 90,
      buildMinutes: 20,
      maxLevel: 3,
      unlockHall: 2,
      color: Color(0xFF7AA6DA),
      icon: Icons.water_drop,
    ),
    TownBuilding(
      id: 'statue',
      name: 'Statue',
      desc: 'Decoration · a monument to your discipline.',
      role: TownRole.decoration,
      baseCost: 300,
      buildMinutes: 90,
      maxLevel: 3,
      unlockHall: 4,
      color: Color(0xFFB9C4D4),
      icon: Icons.emoji_events,
    ),
    TownBuilding(
      id: 'tower',
      name: 'Workshop',
      desc: 'Adds one more builder.',
      role: TownRole.utility,
      baseCost: 400,
      buildMinutes: 120,
      maxLevel: 1,
      unlockHall: 3,
      color: Color(0xFF9B8CFF),
      icon: Icons.construction,
    ),
  ];

  static final _byId = {for (final b in all) b.id: b};
  static TownBuilding byId(String id) => _byId[id] ?? hall;

  static List<TownBuilding> get shop => all.where((b) => b.role != TownRole.hall).toList();

  /// Max placed copies per type at a given town hall level.
  static int limit(String id, int hallLevel) => switch (id) {
        'tower' => 1,
        'vault' => hallLevel >= 5 ? 2 : 1,
        _ => 2 + hallLevel,
      };

  static const gridSize = 7;
}
