import 'package:flutter/material.dart';

/// A single placed plot in the Aeris Town garden: which [TownElement] sits on
/// the tile and how far up its evolution [chain] it has been upgraded.
class TownTile {
  final String type;
  final int lvl;

  const TownTile({required this.type, this.lvl = 0});

  TownTile copyWith({int? lvl}) => TownTile(type: type, lvl: lvl ?? this.lvl);

  Map<String, dynamic> toJson() => {'type': type, 'lvl': lvl};

  factory TownTile.fromJson(Map<String, dynamic> j) => TownTile(
        type: j['type'] as String,
        lvl: (j['lvl'] as num?)?.toInt() ?? 0,
      );
}

/// A buildable garden element: its emoji evolution [chain], Aura [base] cost
/// to place, and an optional total-savings [lock] threshold before it can be
/// placed at all.
class TownElement {
  final String id;
  final String name;
  final int base;
  final String category;
  final List<String> chain;
  final int? lock;

  const TownElement({
    required this.id,
    required this.name,
    required this.base,
    required this.category,
    required this.chain,
    this.lock,
  });

  String emojiAt(int lvl) {
    if (lvl <= 0) return chain.first;
    if (lvl >= chain.length) return chain.last;
    return chain[lvl];
  }
}

class TownElements {
  TownElements._();

  static const categories = <String>['Nature', 'Buildings', 'Decor'];

  static const all = <TownElement>[
    TownElement(
        id: 'tree',
        name: 'Tree',
        base: 40,
        category: 'Nature',
        chain: ['🌱', '🌿', '🌳', '🌲', '🎄']),
    TownElement(
        id: 'flower',
        name: 'Flowers',
        base: 25,
        category: 'Nature',
        chain: ['🌱', '🌷', '🌻', '🌺', '🌹']),
    TownElement(
        id: 'hedge',
        name: 'Hedge',
        base: 20,
        category: 'Nature',
        chain: ['🌿', '🍀', '🌳']),
    TownElement(
        id: 'crop',
        name: 'Farm',
        base: 60,
        category: 'Nature',
        chain: ['🌾', '🌽', '🍅', '🚜']),
    TownElement(
        id: 'house',
        name: 'Home',
        base: 120,
        category: 'Buildings',
        chain: ['⛺', '🛖', '🏠', '🏡', '🏘️']),
    TownElement(
        id: 'tower',
        name: 'Tower',
        base: 300,
        category: 'Buildings',
        chain: ['🏗️', '🏢', '🏬', '🏙️'],
        lock: 40000),
    TownElement(
        id: 'shop',
        name: 'Shop',
        base: 180,
        category: 'Buildings',
        chain: ['🛒', '🏪', '🏬', '🏤'],
        lock: 25000),
    TownElement(
        id: 'landmark',
        name: 'Landmark',
        base: 600,
        category: 'Buildings',
        chain: ['🗿', '🗼', '🏰', '🏛️'],
        lock: 90000),
    TownElement(
        id: 'water',
        name: 'Water',
        base: 90,
        category: 'Decor',
        chain: ['💧', '🪷', '⛲', '🌊']),
    TownElement(
        id: 'park',
        name: 'Park',
        base: 140,
        category: 'Decor',
        chain: ['🪨', '🛝', '🎠', '🎡', '🎢'],
        lock: 30000),
    TownElement(
        id: 'path',
        name: 'Path',
        base: 10,
        category: 'Decor',
        chain: ['🟫', '🧱', '🪵']),
    TownElement(
        id: 'light',
        name: 'Lamp',
        base: 35,
        category: 'Decor',
        chain: ['🕯️', '💡', '🏮']),
  ];

  static TownElement byId(String id) =>
      all.firstWhere((e) => e.id == id, orElse: () => all.first);

  static List<TownElement> inCategory(String category) =>
      all.where((e) => e.category == category).toList();

  /// Aura cost to upgrade an element currently at [lvl] to `lvl + 1`.
  static int upgradeCost(TownElement el, int lvl) =>
      (el.base * (lvl + 1) * 1.6).round();
}

/// A ground/sky palette for the Aeris Town garden.
class GardenTheme {
  final String id;
  final String label;
  final List<Color> sky;
  final Color g1;
  final Color g2;

  const GardenTheme({
    required this.id,
    required this.label,
    required this.sky,
    required this.g1,
    required this.g2,
  });

  LinearGradient get skyGradient => LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: sky,
      );
}

class GardenThemes {
  GardenThemes._();

  static const all = <GardenTheme>[
    GardenTheme(
      id: 'meadow',
      label: 'Meadow',
      sky: [Color(0xFF9BDCF6), Color(0xFFBFEAD8)],
      g1: Color(0xFFA8E063),
      g2: Color(0xFF93D356),
    ),
    GardenTheme(
      id: 'zen',
      label: 'Zen',
      sky: [Color(0xFFD5EAE6), Color(0xFFE6E2C3)],
      g1: Color(0xFFC7D9A8),
      g2: Color(0xFFB6CC95),
    ),
    GardenTheme(
      id: 'desert',
      label: 'Desert',
      sky: [Color(0xFFFCE5B0), Color(0xFFE8C07A)],
      g1: Color(0xFFE6C079),
      g2: Color(0xFFD9B069),
    ),
    GardenTheme(
      id: 'tropic',
      label: 'Tropic',
      sky: [Color(0xFF86E0E8), Color(0xFF9CE88C)],
      g1: Color(0xFF7BD88C),
      g2: Color(0xFF67C778),
    ),
  ];

  static GardenTheme byId(String id) =>
      all.firstWhere((t) => t.id == id, orElse: () => all.first);
}
