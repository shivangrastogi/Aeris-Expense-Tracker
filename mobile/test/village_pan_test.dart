import 'package:aeris_expense/providers/village_provider.dart';
import 'package:aeris_expense/screens/gamification/village_screen.dart';
import 'package:aeris_expense/widgets/town_painter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Regression: dragging the town at the fitted zoom used to make
/// InteractiveViewer jump the whole town away (the content was smaller than
/// the screen, so it couldn't satisfy its own boundary rule and "corrected"
/// the position on the first drag).
void main() {
  testWidgets('dragging the fitted town never throws it off screen',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1080, 2400); // a typical phone
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    final screen = tester.view.physicalSize / tester.view.devicePixelRatio;

    await tester.pumpWidget(ProviderScope(
      overrides: [townWeatherProvider.overrideWithValue(TownWeather.clear)],
      child: const MaterialApp(home: VillageScreen()),
    ));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));

    final town = find.byWidgetPredicate(
        (w) => w is CustomPaint && w.painter is TownPainter);
    final before = tester.getRect(town);
    expect(before.center.dx, closeTo(screen.width / 2, 2)); // centred

    for (final drag in const [
      Offset(0, -220),
      Offset(160, 0),
      Offset(-300, 0),
      Offset(-90, 300),
      Offset(0, 600),
    ]) {
      await tester.dragFrom(screen.center(Offset.zero), drag);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
      final r = tester.getRect(town);
      // Vertically the fitted town is locked in place.
      expect(r.top, closeTo(before.top, 1), reason: 'drag $drag');
      // Sideways it may slide only within its own margins: an edge never
      // comes inside the screen.
      expect(r.left, lessThanOrEqualTo(1), reason: 'drag $drag');
      expect(r.right, greaterThanOrEqualTo(screen.width - 1),
          reason: 'drag $drag');
    }
  });
}
