import 'package:aeris_expense/providers/gamification_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Checked in every day Mon 19 Oct → Sat 24 Oct 2026.
  const g = GamificationState(
    checkinStreak: 6,
    lastCheckinDay: '2026-10-24',
    awardedKeys: {
      'checkin_2026-10-19', 'checkin_2026-10-20', 'checkin_2026-10-21',
      'checkin_2026-10-22', 'checkin_2026-10-23', 'checkin_2026-10-24',
    },
  );

  test('on Sunday the dots keep last week instead of wiping to empty', () {
    final sunday = DateTime(2026, 10, 25, 9);
    // Mon–Sat checked; today (Sunday) waits for its check-in.
    expect(g.recentCheckins(sunday), [true, true, true, true, true, true, false]);
    expect(
        GamificationState.recentDays(sunday)
            .map(GamificationState.dayLetter)
            .join(),
        'MTWTFSS'); // Mon 19 … Sun 25, today last
  });

  test('today is always the last day', () {
    final days = GamificationState.recentDays(DateTime(2026, 3, 2, 23, 59));
    expect(days.last, DateTime(2026, 3, 2));
    expect(days.first, DateTime(2026, 2, 24)); // across a month end
    expect(days.length, 7);
  });
}
