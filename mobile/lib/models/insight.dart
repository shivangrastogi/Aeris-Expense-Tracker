/// Output of the on-device AI engine (`services/prediction_service.dart`
/// and `services/recommendation_service.dart`). Kept dumb on purpose —
/// the engine is just a value producer; UI cards consume these.

enum InsightSeverity { info, positive, warning, alert }

/// A forward-looking estimate for a category (or "total").
class Prediction {
  final String label;          // e.g. "Estimated June spend"
  final String? categoryId;    // null = aggregate
  final double estimate;       // currency
  final double low;            // lower CI
  final double high;           // upper CI
  final String basis;          // 1-line explanation

  const Prediction({
    required this.label,
    required this.estimate,
    required this.low,
    required this.high,
    required this.basis,
    this.categoryId,
  });
}

/// A behavioural nudge.
class Recommendation {
  final String title;
  final String body;
  final InsightSeverity severity;
  final double? potentialSaving;    // monthly INR if user follows it
  final String? categoryId;
  final String actionLabel;
  final Map<String, dynamic>? data;

  const Recommendation({
    required this.title,
    required this.body,
    required this.severity,
    required this.actionLabel,
    this.potentialSaving,
    this.categoryId,
    this.data,
  });
}

/// A statistical outlier flagged for review.
class Anomaly {
  final String reason;
  final DateTime when;
  final double amount;
  final String? merchant;
  final String? categoryId;

  const Anomaly({
    required this.reason,
    required this.when,
    required this.amount,
    this.merchant,
    this.categoryId,
  });
}

/// A month-end projection for a category that has a budget cap.
class BudgetProjection {
  final String categoryId;
  final double cap;
  final double spentSoFar;
  final double projectedMonthEnd; // at current burn rate
  final bool alreadyOver;
  final int? daysUntilExceed; // null = won't exceed this month; 0 = already over

  const BudgetProjection({
    required this.categoryId,
    required this.cap,
    required this.spentSoFar,
    required this.projectedMonthEnd,
    required this.alreadyOver,
    required this.daysUntilExceed,
  });

  bool get willExceed => alreadyOver || projectedMonthEnd > cap;
}

/// Current-month cash position + a forward projection ("will I run short?").
class Cashflow {
  final double incomeSoFar;
  final double expenseSoFar;
  final double projectedExpense;   // month-end at the current burn rate
  final double projectedNet;       // available income − projected expense
  final int? runwayDays;           // days the remaining money lasts at burn rate
  final InsightSeverity severity;
  final String message;

  const Cashflow({
    required this.incomeSoFar,
    required this.expenseSoFar,
    required this.projectedExpense,
    required this.projectedNet,
    required this.runwayDays,
    required this.severity,
    required this.message,
  });
}

/// A recurring payment the system has detected (rent, Netflix, EMI etc.).
class RecurringPayment {
  final String merchant;
  final String categoryId;
  final double approxAmount;
  final int dayOfMonth;        // 1..31 best estimate
  final int occurrences;       // how many months observed

  const RecurringPayment({
    required this.merchant,
    required this.categoryId,
    required this.approxAmount,
    required this.dayOfMonth,
    required this.occurrences,
  });
}
