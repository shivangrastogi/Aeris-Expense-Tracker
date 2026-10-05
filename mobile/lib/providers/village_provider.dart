import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'gamification_provider.dart';

/// A single placed building on the isometric village grid.
class VillageBuilding {
  final String type;
  final int col;
  final int row;
  final int lvl; // 0-based; displayed as lvl+1
  final int endMs; // wall-clock ms when construction/upgrade finishes; 0 = idle

  const VillageBuilding({
    required this.type,
    required this.col,
    required this.row,
    this.lvl = 0,
    this.endMs = 0,
  });

  bool busy(int now) => endMs > now;

  VillageBuilding copyWith({int? lvl, int? endMs}) => VillageBuilding(
        type: type,
        col: col,
        row: row,
        lvl: lvl ?? this.lvl,
        endMs: endMs ?? this.endMs,
      );

  Map<String, dynamic> toJson() =>
      {'t': type, 'c': col, 'r': row, 'l': lvl, 'e': endMs};

  factory VillageBuilding.fromJson(Map<String, dynamic> m) => VillageBuilding(
        type: m['t'] as String,
        col: m['c'] as int,
        row: m['r'] as int,
        lvl: (m['l'] ?? 0) as int,
        endMs: (m['e'] ?? 0) as int,
      );
}

class VillageState {
  final Map<String, VillageBuilding> buildings;
  final int gems;
  final int builders;
  final Map<String, int> collected; // building id → last collect ms
  final bool loaded;

  const VillageState({
    this.buildings = const {},
    this.gems = 50,
    this.builders = 2,
    this.collected = const {},
    this.loaded = false,
  });

  VillageState copyWith({
    Map<String, VillageBuilding>? buildings,
    int? gems,
    int? builders,
    Map<String, int>? collected,
    bool? loaded,
  }) =>
      VillageState(
        buildings: buildings ?? this.buildings,
        gems: gems ?? this.gems,
        builders: builders ?? this.builders,
        collected: collected ?? this.collected,
        loaded: loaded ?? this.loaded,
      );

  int busyCount(int now) => buildings.values.where((b) => b.busy(now)).length;
  int freeBuilders(int now) => builders - busyCount(now);
  int get townLevel => (buildings['th']?.lvl ?? 0) + 1;
}

class VillageNotifier extends StateNotifier<VillageState> {
  final Ref ref;
  static const _key = 'village_v1';

  VillageNotifier(this.ref) : super(const VillageState()) {
    _load();
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_key);
    if (raw == null) {
      // Seed a fresh village with the Town Hall in the middle.
      state = const VillageState(
        buildings: {
          'th': VillageBuilding(type: 'townhall', col: 3, row: 3),
        },
        loaded: true,
      );
      _save();
      return;
    }
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      final b = (m['buildings'] as Map<String, dynamic>).map(
        (k, v) =>
            MapEntry(k, VillageBuilding.fromJson(v as Map<String, dynamic>)),
      );
      final col = (m['collected'] as Map<String, dynamic>? ?? {})
          .map((k, v) => MapEntry(k, v as int));
      state = VillageState(
        buildings: b.isEmpty
            ? const {'th': VillageBuilding(type: 'townhall', col: 3, row: 3)}
            : b,
        gems: (m['gems'] ?? 50) as int,
        builders: (m['builders'] ?? 2) as int,
        collected: col,
        loaded: true,
      );
    } catch (_) {
      state = const VillageState(
        buildings: {'th': VillageBuilding(type: 'townhall', col: 3, row: 3)},
        loaded: true,
      );
    }
  }

  Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString(
      _key,
      jsonEncode({
        'buildings': state.buildings.map((k, v) => MapEntry(k, v.toJson())),
        'gems': state.gems,
        'builders': state.builders,
        'collected': state.collected,
      }),
    );
  }

  /// Place a new building (under construction). Spends [cost] Aura.
  bool place(String id, String type, int col, int row, int cost, int durMs) {
    if (!ref.read(gamificationProvider.notifier).spendAura(cost)) return false;
    final end = DateTime.now().millisecondsSinceEpoch + durMs;
    state = state.copyWith(buildings: {
      ...state.buildings,
      id: VillageBuilding(type: type, col: col, row: row, lvl: 0, endMs: end),
    });
    _save();
    return true;
  }

  /// Start upgrading a building: bumps its level immediately and marks it busy
  /// until the timer ends. Spends [cost] Aura.
  bool startUpgrade(String id, int cost, int durMs) {
    final b = state.buildings[id];
    if (b == null) return false;
    if (!ref.read(gamificationProvider.notifier).spendAura(cost)) return false;
    final end = DateTime.now().millisecondsSinceEpoch + durMs;
    state = state.copyWith(buildings: {
      ...state.buildings,
      id: b.copyWith(lvl: b.lvl + 1, endMs: end),
    });
    _save();
    return true;
  }

  /// Construction/upgrade timer elapsed → building becomes idle/operational.
  void finishUpgrade(String id) {
    final b = state.buildings[id];
    if (b == null || b.endMs == 0) return;
    state = state.copyWith(buildings: {
      ...state.buildings,
      id: b.copyWith(endMs: 0),
    });
    _save();
  }

  /// Instantly finish using [gemCost] gems.
  bool rush(String id, int gemCost) {
    final b = state.buildings[id];
    if (b == null || b.endMs == 0) return false;
    if (state.gems < gemCost) return false;
    state = state.copyWith(
      gems: state.gems - gemCost,
      buildings: {...state.buildings, id: b.copyWith(endMs: 0)},
    );
    _save();
    return true;
  }

  void remove(String id) {
    if (id == 'th' || !state.buildings.containsKey(id)) return;
    final b = {...state.buildings}..remove(id);
    final c = {...state.collected}..remove(id);
    state = state.copyWith(buildings: b, collected: c);
    _save();
  }

  /// Collect a building's Aura yield into the shared Aura balance.
  void collect(String id, int amount) {
    ref.read(gamificationProvider.notifier).addAura(amount);
    state = state.copyWith(collected: {
      ...state.collected,
      id: DateTime.now().millisecondsSinceEpoch,
    });
    _save();
  }
}

final villageProvider =
    StateNotifierProvider<VillageNotifier, VillageState>((ref) {
  return VillageNotifier(ref);
});
