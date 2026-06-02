import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/insight.dart';
import '../widgets/mascot/aeris_mascot.dart';
import 'analytics_provider.dart';
import 'auth_provider.dart';
import 'budgets_provider.dart';
import 'insights_provider.dart';

class MascotState {
  final MascotMood mood;
  final String line;
  const MascotState(this.mood, this.line);
}

/// Maps the user's real money situation to Aeris's mood + a one-liner.
/// Prefers the top recommendation for the speech bubble when there is one.
final mascotProvider = Provider<MascotState>((ref) {
  final analytics = ref.watch(analyticsProvider).asData?.value;
  final budgets = ref.watch(budgetsStreamProvider).asData?.value ?? const [];
  final profile = ref.watch(userProfileProvider).asData?.value;
  final insights = ref.watch(insightsProvider).asData?.value;

  if (analytics == null) {
    return const MascotState(
        MascotMood.neutral, "Hi, I'm Aeris! Add or import a few transactions and I'll start helping.");
  }

  final now = DateTime.now();
  final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
  final dayIdx = now.day.clamp(1, daysInMonth);

  var breached = false;
  var pacingOver = false;
  for (final b in budgets) {
    if (b.monthlyCap <= 0) continue;
    final spent = analytics.byCategory[b.categoryId] ?? 0;
    if (spent > b.monthlyCap) {
      breached = true;
    } else if (spent / dayIdx * daysInMonth > b.monthlyCap * 1.1) {
      pacingOver = true;
    }
  }

  double? savingRate;
  if (profile != null && profile.monthlyIncome > 0) {
    savingRate = (profile.monthlyIncome - analytics.monthExpense) /
        profile.monthlyIncome;
  }

  final hasPositive = insights?.recommendations
          .any((r) => r.severity == InsightSeverity.positive) ??
      false;

  MascotMood mood;
  if (breached || (savingRate != null && savingRate < 0)) {
    mood = MascotMood.worried;
  } else if (savingRate != null && savingRate > 0.45) {
    mood = MascotMood.celebrate;
  } else if ((savingRate != null && savingRate > 0.30) || hasPositive) {
    mood = MascotMood.happy;
  } else if (pacingOver) {
    mood = MascotMood.worried;
  } else {
    mood = MascotMood.neutral;
  }

  final rec = (insights?.recommendations.isNotEmpty ?? false)
      ? insights!.recommendations.first
      : null;
  final line = rec?.title ??
      switch (mood) {
        MascotMood.happy => "Nice work — you're keeping more than you spend!",
        MascotMood.celebrate => "Incredible month! You're crushing your savings. 🎉",
        MascotMood.worried => "Heads up — spending's running hot this month.",
        MascotMood.neutral => "All steady. I'll flag anything that needs your eye.",
      };

  return MascotState(mood, line);
});
