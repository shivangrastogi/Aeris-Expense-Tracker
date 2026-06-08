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

final insightsProvider = Provider<AsyncValue<InsightsBundle>>((ref) {
  final tx = ref.watch(transactionsStreamProvider);
  final budgets = ref.watch(budgetsStreamProvider);
  final profile = ref.watch(userProfileProvider);

  return tx.whenData((txns) {
    final pred = PredictionService.instance;
    final budgetList = budgets.asData?.value ?? const [];
    final rec = RecommendationService.instance.recommend(
      txns: txns,
      budgets: budgetList,
      profile: profile.asData?.value,
    );
    return InsightsBundle(
      monthEstimate: pred.predictCurrentMonth(txns),
      categoryForecasts: pred.predictPerCategoryNextMonth(txns),
      budgetProjections: pred.projectBudgets(txns, budgetList),
      anomalies: pred.detectAnomalies(txns),
      recurring: pred.detectRecurring(txns),
      recommendations: rec,
      cashflow: pred.cashflowThisMonth(txns,
          monthlyIncome: profile.asData?.value?.monthlyIncome ?? 0),
    );
  });
});
