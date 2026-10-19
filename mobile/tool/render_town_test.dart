// Renders a sample Aeris Town with every building type (plus one under
// construction) to a PNG, for checking the town art without a phone:
//   flutter test tool/render_town_test.dart --update-goldens
// Output: $AERIS_SHOTS_DIR/town_sample.png (or tool/shots/).
import 'dart:io';

import 'package:aeris_expense/providers/village_provider.dart';
import 'package:aeris_expense/widgets/town_painter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final out = Platform.environment['AERIS_SHOTS_DIR'] ?? '${Directory.current.path}/tool/shots';

  testWidgets('town sample', (tester) async {
    tester.view.physicalSize = const Size(1520, 1120);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final now = DateTime(2026, 10, 18, 21).millisecondsSinceEpoch;
    const b = VillageBuilding.new;
    final v = VillageState(loaded: true, buildings: {
      'th': b(type: 'townhall', col: 3, row: 3, lvl: 2),
      'h1': b(type: 'house', col: 1, row: 2),
      'h2': b(type: 'house', col: 2, row: 1, lvl: 2),
      'f1': b(type: 'farm', col: 5, row: 2, lvl: 1),
      'm1': b(type: 'market', col: 4, row: 5, lvl: 1),
      'v1': b(type: 'vault', col: 1, row: 5),
      't1': b(type: 'tree', col: 0, row: 0),
      't2': b(type: 'tree', col: 6, row: 6, lvl: 2),
      'fo': b(type: 'fountain', col: 3, row: 5),
      'st': b(type: 'statue', col: 5, row: 4),
      'to': b(type: 'tower', col: 0, row: 4),
      'cx': VillageBuilding(type: 'house', col: 5, row: 0, endMs: now + 5 * 60000),
    });
    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: RepaintBoundary(
        child: CustomPaint(
          size: const Size(760, 560),
          painter: TownPainter(village: v, iso: const Iso(Offset(380, 140), 92), now: now),
        ),
      ),
    ));
    await expectLater(find.byType(RepaintBoundary).first, matchesGoldenFile(Uri.file('$out/town_sample.png')));
  });
}
