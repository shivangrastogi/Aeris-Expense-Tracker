// Aeris Town rules: producers hold at most one day of Aura, decorations add
// +5% each (capped), builders grow with the hall/workshop, and Aura made in
// the town is spendable but never raises the level.
import 'package:aeris_expense/models/town_catalog.dart';
import 'package:aeris_expense/providers/gamification_provider.dart';
import 'package:aeris_expense/providers/village_provider.dart';
import 'package:flutter_test/flutter_test.dart';

const _h = 3600000;

void main() {
  final t0 = DateTime(2026, 10, 18, 9).millisecondsSinceEpoch;

  VillageState town(Map<String, VillageBuilding> b, {Map<String, int>? collected}) =>
      VillageState(buildings: {'th': const VillageBuilding(type: 'townhall', col: 3, row: 3), ...b},
          collected: collected ?? {for (final k in b.keys) k: t0}, loaded: true);

  test('production accrues per real hour and caps at one day', () {
    final v = town({'h': const VillageBuilding(type: 'house', col: 0, row: 0)});
    final perDay = TownCatalog.byId('house').perDay;
    expect(v.stored('h', t0), 0);
    expect(v.stored('h', t0 + 12 * _h), perDay ~/ 2);
    expect(v.stored('h', t0 + 24 * _h), perDay);
    expect(v.stored('h', t0 + 72 * _h), perDay, reason: 'no backlog beyond a day');
  });

  test('a level-3 producer makes three times level 1', () {
    final v = town({'h': const VillageBuilding(type: 'house', col: 0, row: 0, lvl: 2)});
    expect(v.stored('h', t0 + 24 * _h), TownCatalog.byId('house').perDay * 3);
  });

  test('nothing is produced while under construction', () {
    final v = town({'h': VillageBuilding(type: 'house', col: 0, row: 0, endMs: t0 + 48 * _h)});
    expect(v.stored('h', t0 + 24 * _h), 0);
  });

  test('decorations add 5% each, capped at 50%', () {
    final few = town({for (var i = 0; i < 3; i++) 't$i': VillageBuilding(type: 'tree', col: i, row: 0)});
    expect(few.beauty, closeTo(0.15, 1e-9));
    final many = town({for (var i = 0; i < 14; i++) 't$i': VillageBuilding(type: 'tree', col: i % 7, row: i ~/ 7)});
    expect(many.beauty, 0.5);
  });

  test('builders: 2, +1 at hall 4, +1 for a finished workshop', () {
    expect(town({}).builders, 2);
    const hall4 = VillageState(buildings: {'th': VillageBuilding(type: 'townhall', col: 3, row: 3, lvl: 3)});
    expect(hall4.builders, 3);
    final shop = town({'w': const VillageBuilding(type: 'tower', col: 0, row: 0)});
    expect(shop.builders, 3);
  });

  test('weather multipliers', () {
    expect(weatherMultiplier(TownWeather.bright), 1.5);
    expect(weatherMultiplier(TownWeather.storm), 0.5);
    expect(weatherMultiplier(TownWeather.clear), 1.0);
  });

  test('town Aura is spendable but does not raise the level', () {
    const g = GamificationState(earned: 400, bonus: 5000, spent: 100);
    expect(g.available, 5300);
    expect(g.level, const GamificationState(earned: 400).level);
  });

  test('upgrade cost grows quadratically', () {
    final house = TownCatalog.byId('house');
    expect(house.upgradeCost(0) < house.upgradeCost(1), isTrue);
    expect(house.upgradeCost(3), house.baseCost * 25 ~/ 2);
  });
}
