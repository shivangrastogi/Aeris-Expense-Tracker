import 'package:flutter/material.dart';

/// Rarity tier — drives the badge colour/glow shown on avatar cards.
enum AvatarRarity { common, rare, epic, legendary, mythic }

extension AvatarRarityX on AvatarRarity {
  String get label => switch (this) {
        AvatarRarity.common => 'Common',
        AvatarRarity.rare => 'Rare',
        AvatarRarity.epic => 'Epic',
        AvatarRarity.legendary => 'Legendary',
        AvatarRarity.mythic => 'Mythic',
      };

  Color get color => switch (this) {
        AvatarRarity.common => const Color(0xFF94A3B8),
        AvatarRarity.rare => const Color(0xFF38BDF8),
        AvatarRarity.epic => const Color(0xFFA78BFA),
        AvatarRarity.legendary => const Color(0xFFFBBF24),
        AvatarRarity.mythic => const Color(0xFFFB7185),
      };
}

/// A cosmetic skin for the Aeris avatar. `cost` is the Aura needed to unlock
/// (0 = free / default). Colours drive the character painter (body gradient,
/// glow, highlight).
class AvatarSkin {
  final String id;
  final String name;
  final String tagline;
  final int cost;
  final AvatarRarity rarity;
  final Color core;
  final Color aura;
  final Color accent;

  const AvatarSkin({
    required this.id,
    required this.name,
    required this.tagline,
    required this.cost,
    required this.rarity,
    required this.core,
    required this.aura,
    required this.accent,
  });
}

class Avatars {
  Avatars._();

  static const all = <AvatarSkin>[
    AvatarSkin(
        id: 'sprout',
        name: 'Saver Sprout',
        tagline: 'Where every saver begins',
        cost: 0,
        rarity: AvatarRarity.common,
        core: Color(0xFF19C2B6),
        aura: Color(0xFF0F766E),
        accent: Color(0xFFEAFFF8)),
    AvatarSkin(
        id: 'warrior',
        name: 'Coin Crusher',
        tagline: 'Swings a blade for your budget',
        cost: 300,
        rarity: AvatarRarity.rare,
        core: Color(0xFFEF4444),
        aura: Color(0xFF991B1B),
        accent: Color(0xFFFFF1F2)),
    AvatarSkin(
        id: 'ninja',
        name: 'Stealth Saver',
        tagline: 'Cuts impulse buys in the dark',
        cost: 600,
        rarity: AvatarRarity.rare,
        core: Color(0xFF334155),
        aura: Color(0xFF0F172A),
        accent: Color(0xFF94A3B8)),
    AvatarSkin(
        id: 'knight',
        name: 'Frugal Knight',
        tagline: 'Shields your savings from raids',
        cost: 1000,
        rarity: AvatarRarity.epic,
        core: Color(0xFF64748B),
        aura: Color(0xFF334155),
        accent: Color(0xFFE2E8F0)),
    AvatarSkin(
        id: 'wizard',
        name: 'Wealth Wizard',
        tagline: 'Conjures compound interest',
        cost: 1500,
        rarity: AvatarRarity.epic,
        core: Color(0xFF8B5CF6),
        aura: Color(0xFF5B21B6),
        accent: Color(0xFFEDE9FE)),
    AvatarSkin(
        id: 'astro',
        name: 'Astro Saver',
        tagline: 'Saving to the moon, literally',
        cost: 2200,
        rarity: AvatarRarity.epic,
        core: Color(0xFF38BDF8),
        aura: Color(0xFF0369A1),
        accent: Color(0xFFE0F2FE)),
    AvatarSkin(
        id: 'dragon',
        name: 'Money Dragon',
        tagline: 'Hoards gold, breathes discipline',
        cost: 3500,
        rarity: AvatarRarity.legendary,
        core: Color(0xFFF59E0B),
        aura: Color(0xFFB45309),
        accent: Color(0xFFFEF3C7)),
    AvatarSkin(
        id: 'phoenix',
        name: 'Penny Phoenix',
        tagline: 'Rises from every overspend',
        cost: 5000,
        rarity: AvatarRarity.legendary,
        core: Color(0xFFFB7185),
        aura: Color(0xFFBE123C),
        accent: Color(0xFFFFE4E6)),
    AvatarSkin(
        id: 'king',
        name: 'Frugal King',
        tagline: 'Rules a kingdom of compounding',
        cost: 8000,
        rarity: AvatarRarity.mythic,
        core: Color(0xFFFBBF24),
        aura: Color(0xFF92400E),
        accent: Color(0xFFFEF3C7)),
  ];

  static AvatarSkin byId(String id) =>
      all.firstWhere((a) => a.id == id, orElse: () => all.first);
}

// ── Levels & evolution ────────────────────────────────────────
const int auraPerLevel = 500;

int levelForAura(int earned) => (1 + earned ~/ auraPerLevel).clamp(1, 50);

/// Aura still needed to reach the next level.
int auraToNextLevel(int earned) => auraPerLevel - (earned % auraPerLevel);

/// Visual evolution stage 1..5 (drives size, rays, particle density).
int evolutionStage(int level) => (1 + (level - 1) ~/ 3).clamp(1, 5);

const List<String> stageNames = [
  '',
  'Hatchling',
  'Sprout',
  'Guardian',
  'Sage',
  'Ascended',
];
