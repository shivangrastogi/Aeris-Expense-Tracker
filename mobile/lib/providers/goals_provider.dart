import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/goal.dart';
import 'auth_provider.dart';
import 'transactions_provider.dart';

final goalsStreamProvider = StreamProvider<List<Goal>>((ref) {
  final uid = ref.watch(currentUserIdProvider);
  if (uid == null) return const Stream.empty();
  return ref.read(firestoreServiceProvider).watchGoals(uid);
});

class StreakInfo {
  final int current;
  final int best;
  const StreakInfo(this.current, this.best);
}

/// Day-streak for opening the app, persisted on-device. Reading it also
/// advances the streak for today (idempotent within a day).
final streakProvider = FutureProvider<StreakInfo>((ref) async {
  final prefs = await SharedPreferences.getInstance();
  final now = DateTime.now();
  String key(DateTime d) => '${d.year}-${d.month}-${d.day}';

  final todayKey = key(now);
  final lastKey = prefs.getString('streak_last');
  var current = prefs.getInt('streak_current') ?? 0;
  var best = prefs.getInt('streak_best') ?? 0;

  if (lastKey != todayKey) {
    final yesterdayKey = key(now.subtract(const Duration(days: 1)));
    current = (lastKey == yesterdayKey) ? current + 1 : 1;
    if (current > best) best = current;
    await prefs.setString('streak_last', todayKey);
    await prefs.setInt('streak_current', current);
    await prefs.setInt('streak_best', best);
  } else if (current == 0) {
    current = 1;
    best = best < 1 ? 1 : best;
    await prefs.setInt('streak_current', current);
    await prefs.setInt('streak_best', best);
  }
  return StreakInfo(current, best);
});
