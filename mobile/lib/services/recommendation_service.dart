import '../models/budget.dart';
import '../models/category.dart';
import '../models/insight.dart';
import '../models/transaction.dart';
import '../models/user_profile.dart';
import 'prediction_service.dart';

/// Pure-function "what should the user do?" engine. Consumes the same
/// transactions + budgets the analytics screen has, and emits actionable
/// nudges. Conservative — we'd rather miss a tip than nag.
class RecommendationService {
  RecommendationService._();
  static final RecommendationService instance = RecommendationService._();

  List<Recommendation> recommend({
    required List<Transaction> txns,
    required List<Budget> budgets,
    required UserProfile? profile,
  }) {
    final out = <Recommendation>[];
    final now = DateTime.now();
    final mKey = '${now.year}-${now.month.toString().padLeft(2, '0')}';

    // ── 1. Budget burn-rate alerts ──────────────────────────
    final spentByCat = <String, double>{};
    for (final t in txns.where((t) =>
        t.isDebit && _monthKeyOf(t.timestamp) == mKey)) {
      spentByCat[t.categoryId] = (spentByCat[t.categoryId] ?? 0) + t.amount;
    }
    final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
    final dayIdx = now.day.clamp(1, daysInMonth);

    for (final b in budgets) {
      final spent = spentByCat[b.categoryId] ?? 0;
      if (b.monthlyCap <= 0) continue;
      final ratio = spent / b.monthlyCap;
      final pace = spent / dayIdx * daysInMonth;
      final cat = Categories.byId(b.categoryId);
      if (ratio >= 1.0) {
        out.add(Recommendation(
          title: '${cat.label}: budget breached',
          body: 'You spent ₹${spent.toStringAsFixed(0)} this month — '
              '${((ratio - 1) * 100).toStringAsFixed(0)}% over your '
              '₹${b.monthlyCap.toStringAsFixed(0)} cap.',
          severity: InsightSeverity.alert,
          actionLabel: 'Review category',
          potentialSaving: spent - b.monthlyCap,
          categoryId: b.categoryId,
        ));
      } else if (pace > b.monthlyCap * 1.1) {
        out.add(Recommendation(
          title: '${cat.label}: on track to exceed',
          body: 'At your current pace you\'ll hit '
              '₹${pace.toStringAsFixed(0)} by month-end — '
              '${((pace / b.monthlyCap - 1) * 100).toStringAsFixed(0)}% '
              'above the cap.',
          severity: InsightSeverity.warning,
          actionLabel: 'Slow down',
          potentialSaving: pace - b.monthlyCap,
          categoryId: b.categoryId,
        ));
      }
    }

    // ── 2. Recurring payments review ────────────────────────
    final recurring = PredictionService.instance.detectRecurring(txns);
    final totalRecurring = recurring.fold<double>(0, (s, r) => s + r.approxAmount);
    if (recurring.length >= 3) {
      out.add(Recommendation(
        title: '${recurring.length} recurring payments detected',
        body: 'You spend ~₹${totalRecurring.toStringAsFixed(0)} every month on '
            'recurring charges (top: '
            '${recurring.take(3).map((r) => r.merchant).join(", ")}). '
            'Audit them — cancel anything you stopped using.',
        severity: InsightSeverity.info,
        actionLabel: 'See list',
        potentialSaving: totalRecurring * 0.10,
      ));
    }

    // ── 3. Anomalies turned into actionable tips ────────────
    final anomalies = PredictionService.instance.detectAnomalies(txns);
    if (anomalies.isNotEmpty) {
      final big = anomalies.first;
      out.add(Recommendation(
        title: 'Unusual ${Categories.byId(big.categoryId ?? 'other').label.toLowerCase()} spend',
        body: '₹${big.amount.toStringAsFixed(0)} '
            '${big.merchant != null ? "at ${big.merchant}" : ""} on '
            '${big.when.day}/${big.when.month}/${big.when.year}. '
            '${big.reason}',
        severity: InsightSeverity.warning,
        actionLabel: 'Review',
        categoryId: big.categoryId,
      ));
    }

    // ── 4. Savings-rate tip vs income ───────────────────────
    if (profile != null && profile.monthlyIncome > 0) {
      final monthExpense = spentByCat.values.fold<double>(0, (a, b) => a + b);
      final savingRate =
          (profile.monthlyIncome - monthExpense) / profile.monthlyIncome;
      if (savingRate < 0.10) {
        out.add(Recommendation(
          title: 'Saving rate below 10%',
          body: 'This month you\'ve kept '
              '${(savingRate * 100).toStringAsFixed(1)}% of your income. '
              'Target 20% — start by capping the top-spending category below.',
          severity: InsightSeverity.warning,
          actionLabel: 'Set a budget',
          potentialSaving: profile.monthlyIncome * 0.10,
        ));
      } else if (savingRate > 0.30) {
        out.add(Recommendation(
          title: 'You\'re saving ${(savingRate * 100).toStringAsFixed(0)}% — nice',
          body: 'Consider routing the surplus into an investment '
              '(₹${(profile.monthlyIncome * savingRate).toStringAsFixed(0)} '
              'this month).',
          severity: InsightSeverity.positive,
          actionLabel: 'Plan investment',
        ));
      }
    }

    // ── 5. Top-category cut-down tip ────────────────────────
    if (spentByCat.isNotEmpty) {
      final top = spentByCat.entries.reduce((a, b) => a.value > b.value ? a : b);
      final cat = Categories.byId(top.key);
      // Only suggest cutting discretionary categories.
      const discretionary = {'food','shopping','entertainment','travel'};
      if (discretionary.contains(top.key)) {
        out.add(Recommendation(
          title: 'Cut ${cat.label} by 15%',
          body: '${cat.label} is your largest variable spend this month at '
              '₹${top.value.toStringAsFixed(0)}. Trimming 15% would save '
              '₹${(top.value * 0.15).toStringAsFixed(0)}.',
          severity: InsightSeverity.info,
          actionLabel: 'Set cap',
          potentialSaving: top.value * 0.15,
          categoryId: top.key,
        ));
      }
    }

    return out;
  }

  static String _monthKeyOf(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}';
}
