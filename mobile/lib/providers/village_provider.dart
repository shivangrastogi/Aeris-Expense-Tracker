import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/budget.dart';
import '../models/town_catalog.dart';
import '../services/firestore_service.dart';
import 'auth_provider.dart';
import 'budgets_provider.dart';
import 'gamification_provider.dart';
import 'transactions_provider.dart';

/// A placed building on the isometric town grid.
class VillageBuilding {
  final String type;
  final int col;
  final int row;
  final int lvl; // 0-based; shown as lvl+1
  final int endMs; // when construction/upgrade finishes; 0 = idle

  const VillageBuilding({
    required this.type,
    required this.col,
    required this.row,
    this.lvl = 0,
    this.endMs = 0,
  });

  bool busy(int now) => endMs > now;
  TownBuilding get def => TownCatalog.byId(type);

  VillageBuilding copyWith({int? lvl, int? endMs}) =>
      VillageBuilding(type: type, col: col, row: row, lvl: lvl ?? this.lvl, endMs: endMs ?? this.endMs);

  Map<String, dynamic> toJson() => {'t': type, 'c': col, 'r': row, 'l': lvl, 'e': endMs};

  factory VillageBuilding.fromJson(Map<String, dynamic> m) => VillageBuilding(
        type: m['t'] as String,
        col: (m['c'] as num).toInt(),
        row: (m['r'] as num).toInt(),
        lvl: (m['l'] as num?)?.toInt() ?? 0,
        endMs: (m['e'] as num?)?.toInt() ?? 0,
      );
}

/// How today's habits change what the town produces.
enum TownWeather { clear, bright, storm }

class VillageState {
  final Map<String, VillageBuilding> buildings;
  final Map<String, int> collected; // building id → last collect (or ready) ms
  final int updatedAt; // for cloud merge
  final bool loaded;

  const VillageState({
    this.buildings = const {},
    this.collected = const {},
    this.updatedAt = 0,
    this.loaded = false,
  });

  VillageState copyWith({Map<String, VillageBuilding>? buildings, Map<String, int>? collected, int? updatedAt, bool? loaded}) =>
      VillageState(
        buildings: buildings ?? this.buildings,
        collected: collected ?? this.collected,
        updatedAt: updatedAt ?? this.updatedAt,
        loaded: loaded ?? this.loaded,
      );

  int get townLevel => (buildings['th']?.lvl ?? 0) + 1;
  int get builders => 2 + (townLevel >= 4 ? 1 : 0) + (buildings.values.any((b) => b.type == 'tower' && b.endMs == 0) ? 1 : 0);
  int busyCount(int now) => buildings.values.where((b) => b.busy(now)).length;
  int freeBuilders(int now) => builders - busyCount(now);
  int count(String type) => buildings.values.where((b) => b.type == type).length;

  /// +5% per finished decoration level-1, capped at +50%.
  double get beauty {
    final n = buildings.values.where((b) => b.def.role == TownRole.decoration && b.endMs == 0).length;
    return math.min(0.5, n * 0.05);
  }

  /// Aura sitting in building [id] right now (before multipliers). Holds at
  /// most one day of production.
  int stored(String id, int now) {
    final b = buildings[id];
    if (b == null || !b.def.produces || b.busy(now)) return 0;
    final since = collected[id] ?? now;
    final hours = (now - since) / 3600000;
    final perDay = b.def.dailyYield(b.lvl);
    return math.min(perDay, (perDay * hours / 24).floor());
  }

  int totalStored(int now) => buildings.keys.fold(0, (s, id) => s + stored(id, now));
  int dailyIncome() => buildings.values
      .where((b) => b.def.produces && b.endMs == 0)
      .fold(0, (s, b) => s + b.def.dailyYield(b.lvl));

  Map<String, dynamic> toJson() => {
        'buildings': buildings.map((k, v) => MapEntry(k, v.toJson())),
        'collected': collected,
        'updatedAt': updatedAt,
      };

  static VillageState fromJson(Map<String, dynamic> m) {
    final b = ((m['buildings'] as Map?) ?? const {})
        .map((k, v) => MapEntry('$k', VillageBuilding.fromJson((v as Map).cast<String, dynamic>())));
    final c = ((m['collected'] as Map?) ?? const {}).map((k, v) => MapEntry('$k', (v as num).toInt()));
    return VillageState(
      buildings: b.isEmpty ? _seed : b,
      collected: c,
      updatedAt: (m['updatedAt'] as num?)?.toInt() ?? 0,
      loaded: true,
    );
  }

  static const _seed = {'th': VillageBuilding(type: 'townhall', col: 3, row: 3)};
}

/// The multiplier applied when collecting, from real money habits.
final townWeatherProvider = Provider<TownWeather>((ref) {
  final g = ref.watch(gamificationProvider);
  final txns = ref.watch(transactionsStreamProvider).valueOrNull ?? const [];
  final budgets = ref.watch(budgetsStreamProvider).valueOrNull ?? const [];
  final now = DateTime.now();
  final explicit = budgets.where((b) => b.categoryId == Budget.totalId).fold<double>(0, (s, b) => s + b.monthlyCap);
  final cap = explicit > 0
      ? explicit
      : budgets.where((b) => b.categoryId != Budget.totalId).fold<double>(0, (s, b) => s + b.monthlyCap);
  if (cap > 0) {
    var spent = 0.0;
    for (final t in txns) {
      if (t.timestamp.year != now.year || t.timestamp.month != now.month) continue;
      if (t.isRefund) {
        spent -= t.spendAmount;
      } else if (t.isSpend) {
        spent += t.spendAmount;
      }
    }
    if (spent > cap) return TownWeather.storm;
  }
  return g.checkedInOn(now) ? TownWeather.bright : TownWeather.clear;
});

double weatherMultiplier(TownWeather w) => switch (w) {
      TownWeather.bright => 1.5,
      TownWeather.storm => 0.5,
      TownWeather.clear => 1.0,
    };

class VillageNotifier extends StateNotifier<VillageState> {
  final Ref ref;
  static const _key = 'village_v2';

  VillageNotifier(this.ref) : super(const VillageState()) {
    _load();
    ref.listen<String?>(currentUserIdProvider, (_, uid) {
      if (uid != null) _restoreFromCloud(uid);
    }, fireImmediately: true);
  }

  int get _now => DateTime.now().millisecondsSinceEpoch;

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_key) ?? p.getString('village_v1'); // v1 had the same building shape
    VillageState s;
    try {
      s = raw == null
          ? const VillageState(buildings: VillageState._seed, loaded: true)
          : VillageState.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      s = const VillageState(buildings: VillageState._seed, loaded: true);
    }
    // v1 counted collection timers in seconds-long cycles; start everything
    // fresh so nothing pays out a backlog the first time.
    if (p.getString(_key) == null) {
      s = s.copyWith(collected: {for (final id in s.buildings.keys) id: _now});
    }
    state = s.copyWith(loaded: true);
    _finishElapsed();
    await _save(sync: false);
  }

  Future<void> _restoreFromCloud(String uid) async {
    try {
      final cloud = await FirestoreService.instance.fetchGamification(uid);
      final v = cloud?['village'];
      if (v is! String) return;
      final c = VillageState.fromJson(jsonDecode(v) as Map<String, dynamic>);
      // Newer copy wins; a fresh install (only the seed hall) always adopts.
      final freshLocal = state.buildings.length <= 1 && (state.buildings['th']?.lvl ?? 0) == 0;
      if (c.updatedAt > state.updatedAt || (freshLocal && c.buildings.length > 1)) {
        state = c.copyWith(loaded: true);
        await _save(sync: false);
      }
    } catch (_) {/* offline — local stands */}
  }

  Future<void> _save({bool sync = true}) async {
    final p = await SharedPreferences.getInstance();
    final json = jsonEncode(state.toJson());
    await p.setString(_key, json);
    if (!sync) return;
    final uid = ref.read(currentUserIdProvider);
    if (uid != null) {
      FirestoreService.instance
          .saveGamification(uid, {'village': json})
          .catchError((_) {/* offline — next save retries */});
    }
  }

  void _commit(VillageState s) {
    state = s.copyWith(updatedAt: _now);
    _save();
  }

  /// Finish any constructions whose timers ran out (also while the app was
  /// closed). A finished producer starts its day from the finish time.
  void _finishElapsed() {
    final now = _now;
    var changed = false;
    final b = {...state.buildings};
    final c = {...state.collected};
    b.forEach((id, v) {
      if (v.endMs != 0 && v.endMs <= now) {
        b[id] = v.copyWith(endMs: 0);
        c[id] = v.endMs;
        changed = true;
      }
    });
    if (changed) _commit(state.copyWith(buildings: b, collected: c));
  }

  void tick() => _finishElapsed();

  String? canPlace(String type, int col, int row) {
    final def = TownCatalog.byId(type);
    final now = _now;
    if (state.townLevel < def.unlockHall) return 'Needs Town Hall ${def.unlockHall}';
    if (state.count(type) >= TownCatalog.limit(type, state.townLevel)) {
      return 'Limit reached — upgrade the Town Hall for more';
    }
    if (state.buildings.values.any((b) => b.col == col && b.row == row)) return 'Tile taken';
    if (state.freeBuilders(now) <= 0) return 'All builders are busy';
    if (ref.read(gamificationProvider).available < def.baseCost) return 'Not enough Aura';
    return null;
  }

  String? place(String type, int col, int row) {
    final err = canPlace(type, col, row);
    if (err != null) return err;
    final def = TownCatalog.byId(type);
    if (!ref.read(gamificationProvider.notifier).spendAura(def.baseCost)) return 'Not enough Aura';
    final id = 'b$_now';
    _commit(state.copyWith(buildings: {
      ...state.buildings,
      id: VillageBuilding(type: type, col: col, row: row, endMs: _now + def.buildMs(0)),
    }));
    return null;
  }

  String? upgrade(String id) {
    final b = state.buildings[id];
    if (b == null) return 'Gone';
    final def = b.def;
    if (b.busy(_now)) return 'Already building';
    if (b.lvl + 1 >= def.maxLevel) return 'Max level';
    if (def.role != TownRole.hall && b.lvl + 1 >= state.townLevel + 1) {
      return 'Upgrade the Town Hall first';
    }
    if (state.freeBuilders(_now) <= 0) return 'All builders are busy';
    final cost = def.upgradeCost(b.lvl);
    if (!ref.read(gamificationProvider.notifier).spendAura(cost)) return 'Need $cost Aura';
    // Bank what it made so far before the upgrade pauses production.
    _collectInto(id);
    _commit(state.copyWith(buildings: {
      ...state.buildings,
      id: b.copyWith(lvl: b.lvl + 1, endMs: _now + def.buildMs(b.lvl + 1)),
    }));
    return null;
  }

  static int rushCost(int msLeft) => math.max(1, (msLeft / 60000 / 15).ceil());

  String? rush(String id) {
    final b = state.buildings[id];
    if (b == null || !b.busy(_now)) return 'Nothing to rush';
    final gems = rushCost(b.endMs - _now);
    if (!ref.read(gamificationProvider.notifier).spendGems(gems)) return 'Need $gems gems';
    _commit(state.copyWith(
      buildings: {...state.buildings, id: b.copyWith(endMs: 0)},
      collected: {...state.collected, id: _now},
    ));
    return null;
  }

  /// Removes a building, refunding half its base cost.
  void demolish(String id) {
    final b = state.buildings[id];
    if (b == null || id == 'th') return;
    ref.read(gamificationProvider.notifier).addTownAura(b.def.baseCost ~/ 2);
    _commit(state.copyWith(
      buildings: {...state.buildings}..remove(id),
      collected: {...state.collected}..remove(id),
    ));
  }

  int _collectInto(String id) {
    final raw = state.stored(id, _now);
    if (raw <= 0) return 0;
    final mult = weatherMultiplier(ref.read(townWeatherProvider)) * (1 + state.beauty);
    final amount = (raw * mult).round();
    ref.read(gamificationProvider.notifier).addTownAura(amount);
    state = state.copyWith(collected: {...state.collected, id: _now});
    return amount;
  }

  /// Collect everything ready. Returns the Aura gained.
  int collectAll() {
    var total = 0;
    for (final id in state.buildings.keys.toList()) {
      total += _collectInto(id);
    }
    if (total > 0) _commit(state);
    return total;
  }

  int collect(String id) {
    final n = _collectInto(id);
    if (n > 0) _commit(state);
    return n;
  }
}

final villageProvider = StateNotifierProvider<VillageNotifier, VillageState>((ref) => VillageNotifier(ref));
