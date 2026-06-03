import 'package:flutter/material.dart';

/// A cosmetic skin for the Aeris avatar. `cost` is the Aura needed to unlock
/// (0 = free / default). Colours drive the 2.5D painter (body, glow, accents).
class AvatarSkin {
  final String id;
  final String name;
  final String tagline;
  final int cost;
  final Color core;
  final Color aura;
  final Color accent;

  const AvatarSkin({
    required this.id,
    required this.name,
    required this.tagline,
    required this.cost,
    required this.core,
    required this.aura,
    required this.accent,
  });
}

class Avatars {
  Avatars._();

  static const all = <AvatarSkin>[
    AvatarSkin(id: 'spark', name: 'Spark', tagline: 'The original Aeris', cost: 0,
        core: Color(0xFF5EEAD4), aura: Color(0xFF0EA5A4), accent: Color(0xFFEAFFF8)),
    AvatarSkin(id: 'tide', name: 'Tide', tagline: 'Cool, calm saver', cost: 300,
        core: Color(0xFF38BDF8), aura: Color(0xFF0284C7), accent: Color(0xFFE0F2FE)),
    AvatarSkin(id: 'ember', name: 'Ember', tagline: 'Burns through bad habits', cost: 600,
        core: Color(0xFFFB7185), aura: Color(0xFFE11D48), accent: Color(0xFFFFE4E6)),
    AvatarSkin(id: 'verdant', name: 'Verdant', tagline: 'Grows your wealth', cost: 1000,
        core: Color(0xFF34D399), aura: Color(0xFF059669), accent: Color(0xFFD1FAE5)),
    AvatarSkin(id: 'nova', name: 'Nova', tagline: 'Cosmic discipline', cost: 1500,
        core: Color(0xFFA78BFA), aura: Color(0xFF7C3AED), accent: Color(0xFFEDE9FE)),
    AvatarSkin(id: 'aurum', name: 'Aurum', tagline: 'For the truly frugal', cost: 3000,
        core: Color(0xFFFBBF24), aura: Color(0xFFD97706), accent: Color(0xFFFEF3C7)),
  ];

  static AvatarSkin byId(String id) =>
      all.firstWhere((a) => a.id == id, orElse: () => all.first);
}

// ── Levels & evolution ────────────────────────────────────────
const int auraPerLevel = 500;

int levelForAura(int earned) => (1 + earned ~/ auraPerLevel).clamp(1, 50);

/// Aura still needed to reach the next level.
int auraToNextLevel(int earned) =>
    auraPerLevel - (earned % auraPerLevel);

/// Visual evolution stage 1..5 (drives size, rays, particle density).
int evolutionStage(int level) => (1 + (level - 1) ~/ 3).clamp(1, 5);

const List<String> stageNames = [
  '', 'Hatchling', 'Sprout', 'Guardian', 'Sage', 'Ascended',
];
