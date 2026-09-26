import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/insight.dart';
import '../services/prediction_service.dart';
import '../services/recommendation_service.dart';
import 'auth_provider.dart';
import 'budgets_provider.dart';
import 'transactions_provider.dart';

class InsightsBundle {
  final Prediction monthEstimate;
  final List<Prediction> categoryForecasts;
  final List<BudgetProjection> budgetProjections;
  final List<Anomaly> anomalies;
  final List<RecurringPayment> recurring;
  final List<Recommendation> recommendations;
  final Cashflow cashflow;

  const InsightsBundle({
    required this.monthEstimate,
    required this.categoryForecasts,
    required this.budgetProjections,
    required this.anomalies,
    required this.recurring,
    required this.recommendations,
    required this.cashflow,
  });
}

// A FutureProvider (not a sync Provider) on purpose: the prediction pass
// scans the full transaction list several times. Running it synchronously
// inside the Firestore stream notification used to land in the same frame as
// whatever animation was playing (sheet close, IME hide) and caused visible
// jank. The small delay lets the triggering frame finish first, and also
// coalesces rapid bursts of stream emissions into one recompute.
final insightsProvider = FutureProvider<InsightsBundle>((ref) async {
  final txns = await ref.watch(transactionsStreamProvider.future);
  final budgetList = ref.watch(budgetsStreamProvider).valueOrNull ?? const [];
  final profile = ref.watch(userProfileProvider).valueOrNull;

  await Future<void>.delayed(const Duration(milliseconds: 250));

  final pred = PredictionService.instance;
  final rec = RecommendationService.instance.recommend(
    txns: txns,
    budgets: budgetList,
    profile: profile,
  );
  return InsightsBundle(
    monthEstimate: pred.predictCurrentMonth(txns),
    categoryForecasts: pred.predictPerCategoryNextMonth(txns),
    budgetProjections: pred.projectBudgets(txns, budgetList),
    anomalies: pred.detectAnomalies(txns),
    recurring: pred.detectRecurring(txns),
    recommendations: rec,
    cashflow: pred.cashflowThisMonth(txns,
        monthlyIncome: profile?.monthlyIncome ?? 0),
  );
});
