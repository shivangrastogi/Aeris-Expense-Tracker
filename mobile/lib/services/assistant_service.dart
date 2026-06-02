import '../models/budget.dart';
import '../models/category.dart';
import '../models/transaction.dart';
import '../utils/formatters.dart';

/// A fully on-device "assistant" that answers natural questions about the
/// user's money by querying their (already-decrypted) transactions. No network,
/// no LLM — just intent + keyword matching over real data. The same interface
/// could later be backed by an LLM without changing callers.
class AssistantService {
  AssistantService._();

  static String answer(
    String question, {
    required List<Transaction> txns,
    required List<Budget> budgets,
    double? monthlyIncome,
  }) {
    final q = question.toLowerCase().trim();
    if (q.isEmpty) return "Ask me anything about your spending!";

    // Small talk / help
    if (q == 'hi' || q == 'hii' || q == 'hello' || q == 'hey' ||
        _has(q, ['namaste', 'good morning', 'good evening'])) {
      return "Hey! 👋 I read your transactions on-device and answer money "
          "questions privately. Try “how much on food this month?” or tap a "
          "suggestion below.";
    }
    if (_has(q, ['thank', 'thx'])) {
      return "Anytime! 💚 Ask me whenever you want a quick money check-in.";
    }
    if (_has(q, ['help', 'what can you', 'what do you', 'how to use', 'how do you'])) {
      return "I can tell you:\n"
          "• Spend by category or total\n"
          "• Income & savings\n"
          "• Biggest category or merchant\n"
          "• Budget status\n"
          "• Largest expense, daily average & counts\n"
          "Just ask in plain words — everything stays on your device.";
    }

    final period = _period(q);
    final inRange = txns
        .where((t) =>
            !t.timestamp.isBefore(period.start) &&
            !t.timestamp.isAfter(period.end))
        .toList();
    final debits = inRange.where((t) => t.isDebit).toList();
    final credits = inRange.where((t) => t.isCredit).toList();
    double sum(Iterable<Transaction> ts) =>
        ts.fold(0.0, (a, b) => a + b.amount);

    final cat = _category(q);

    // ── Category spend ───────────────────────────────────────
    if (cat != null &&
        _has(q, ['spend', 'spent', 'spend on', 'expense', 'how much', 'cost'])) {
      final total = sum(debits.where((t) => t.categoryId == cat.id));
      return total == 0
          ? "No ${cat.label} spending ${period.label}."
          : "You spent ${formatRupees(total)} on ${cat.label} ${period.label}.";
    }

    // ── Income ───────────────────────────────────────────────
    if (_has(q, ['income', 'earn', 'earned', 'credited', 'salary'])) {
      final total = sum(credits);
      return "You received ${formatRupees(total)} ${period.label}.";
    }

    // ── Net / savings ────────────────────────────────────────
    if (_has(q, ['save', 'saved', 'saving', 'net', 'left', 'balance'])) {
      final net = sum(credits) - sum(debits);
      if (monthlyIncome != null && monthlyIncome > 0 && period.isMonth) {
        final rate = ((monthlyIncome - sum(debits)) / monthlyIncome * 100);
        return "Net ${period.label}: ${formatRupees(net)}. "
            "You've kept ${rate.toStringAsFixed(0)}% of your ₹${monthlyIncome.toStringAsFixed(0)} income.";
      }
      return "Net ${period.label}: ${formatRupees(net)} "
          "(${formatRupees(sum(credits))} in − ${formatRupees(sum(debits))} out).";
    }

    // ── Top category ─────────────────────────────────────────
    if (_has(q, ['biggest', 'top category', 'most', 'highest', 'where'])) {
      if (debits.isEmpty) return "No spending ${period.label} yet.";
      final byCat = <String, double>{};
      for (final t in debits) {
        byCat[t.categoryId] = (byCat[t.categoryId] ?? 0) + t.amount;
      }
      // Top merchant question?
      if (_has(q, ['merchant', 'shop', 'store', 'where'])) {
        final byMerch = <String, double>{};
        for (final t in debits.where((t) => (t.merchant ?? '').isNotEmpty)) {
          byMerch[t.merchant!] = (byMerch[t.merchant!] ?? 0) + t.amount;
        }
        if (byMerch.isNotEmpty) {
          final top = byMerch.entries.reduce((a, b) => a.value > b.value ? a : b);
          return "Most went to ${top.key}: ${formatRupees(top.value)} ${period.label}.";
        }
      }
      final top = byCat.entries.reduce((a, b) => a.value > b.value ? a : b);
      return "Your biggest category ${period.label} is "
          "${Categories.byId(top.key).label} at ${formatRupees(top.value)}.";
    }

    // ── Budget status ────────────────────────────────────────
    if (_has(q, ['budget', 'over budget', 'on track', 'cap'])) {
      if (budgets.isEmpty) {
        return "You haven't set any budgets yet. Set one from Home → Set, "
            "and I'll track your pace.";
      }
      final byCat = <String, double>{};
      for (final t in debits) {
        byCat[t.categoryId] = (byCat[t.categoryId] ?? 0) + t.amount;
      }
      final over = budgets
          .where((b) => b.monthlyCap > 0 && (byCat[b.categoryId] ?? 0) > b.monthlyCap)
          .toList();
      if (over.isEmpty) return "You're within all your budgets ${period.label}. 👍";
      return "Over budget on: ${over.map((b) => Categories.byId(b.categoryId).label).join(', ')}.";
    }

    // ── Biggest single transaction ───────────────────────────
    if (_has(q, ['largest', 'biggest transaction', 'biggest payment', 'most expensive'])) {
      if (debits.isEmpty) return "No expenses ${period.label}.";
      final big = debits.reduce((a, b) => a.amount > b.amount ? a : b);
      return "Your largest expense ${period.label} was "
          "${formatRupees(big.amount)}${big.merchant != null ? " at ${big.merchant}" : ""}.";
    }

    // ── Count ────────────────────────────────────────────────
    if (_has(q, ['how many', 'number of', 'count', 'transactions'])) {
      return "You have ${inRange.length} transactions ${period.label} "
          "(${debits.length} expenses, ${credits.length} income).";
    }

    // ── Daily average ────────────────────────────────────────
    if (_has(q, ['average', 'avg', 'per day', 'daily'])) {
      final now = DateTime.now();
      final effEnd = period.end.isBefore(now) ? period.end : now;
      final days = (effEnd.difference(period.start).inDays + 1).clamp(1, 100000);
      return "You're spending about ${formatRupees(sum(debits) / days)} per day "
          "${period.label}.";
    }

    // ── Recent / what did I buy ──────────────────────────────
    if (_has(q, ['recent', 'last transaction', 'last expense', 'what did i buy'])) {
      if (debits.isEmpty) return "No recent expenses ${period.label}.";
      final recent = [...debits]
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
      final top3 = recent
          .take(3)
          .map((t) =>
              '• ${formatRupees(t.amount)}${t.merchant != null ? " at ${t.merchant}" : ""}')
          .join('\n');
      return "Your most recent expenses:\n$top3";
    }

    // ── Total spend (catch-all spend question) ───────────────
    if (_has(q, ['spend', 'spent', 'expense', 'how much', 'total'])) {
      final total = sum(debits);
      return "You spent ${formatRupees(total)} ${period.label} across "
          "${debits.length} transactions.";
    }

    // ── Fallback ─────────────────────────────────────────────
    return "I can answer things like:\n"
        "• \"How much did I spend on food this month?\"\n"
        "• \"What's my biggest category?\"\n"
        "• \"Am I over budget?\"\n"
        "• \"How much did I earn this month?\"\n"
        "• \"What was my largest expense?\"";
  }

  static bool _has(String q, List<String> words) => words.any(q.contains);

  static ExpenseCategory? _category(String q) {
    for (final c in Categories.all) {
      if (q.contains(c.label.toLowerCase()) || q.contains(c.id)) return c;
    }
    return null;
  }

  static _Period _period(String q) {
    final now = DateTime.now();
    DateTime sod(DateTime d) => DateTime(d.year, d.month, d.day);
    DateTime eod(DateTime d) => DateTime(d.year, d.month, d.day, 23, 59, 59);
    if (q.contains('today')) {
      return _Period(sod(now), eod(now), 'today', false);
    }
    if (q.contains('yesterday')) {
      final y = now.subtract(const Duration(days: 1));
      return _Period(sod(y), eod(y), 'yesterday', false);
    }
    if (q.contains('this week') || q.contains('last 7')) {
      return _Period(sod(now.subtract(const Duration(days: 6))), eod(now),
          'this week', false);
    }
    if (q.contains('last month')) {
      final lm = DateTime(now.year, now.month - 1, 1);
      return _Period(lm, eod(DateTime(now.year, now.month, 0)), 'last month', true);
    }
    if (q.contains('last 30')) {
      return _Period(sod(now.subtract(const Duration(days: 29))), eod(now),
          'in the last 30 days', false);
    }
    if (q.contains('this year')) {
      return _Period(DateTime(now.year, 1, 1), eod(now), 'this year', false);
    }
    if (q.contains('all time') || q.contains('ever') || q.contains('total ')) {
      return _Period(DateTime(2000), eod(now), 'all-time', false);
    }
    return _Period(DateTime(now.year, now.month, 1), eod(now), 'this month', true);
  }
}

class _Period {
  final DateTime start;
  final DateTime end;
  final String label;
  final bool isMonth;
  const _Period(this.start, this.end, this.label, this.isMonth);
}
