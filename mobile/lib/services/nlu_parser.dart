import '../models/category.dart';
import '../models/transaction.dart';

/// What the NLU extracted from a free-text / spoken sentence.
class NluResult {
  final double? amount;
  final TxnDirection direction;
  final String? merchant;
  final String categoryId;
  final DateTime when;
  final String rawText;

  const NluResult({
    required this.amount,
    required this.direction,
    required this.merchant,
    required this.categoryId,
    required this.when,
    required this.rawText,
  });
}

/// A tiny, fully on-device natural-language understanding pass for transaction
/// entry. It is intentionally NOT a neural model — for sentences like
/// "spent 200 on chai yesterday" or "got 5000 salary" a focused rule-based
/// extractor is instant, offline, ~0 KB, and accurate enough, where a real LLM
/// would add hundreds of MB and seconds of latency. Returns the best guess;
/// the UI always lets the user confirm/correct before saving.
class NluParser {
  NluParser._();

  static const _incomeWords = [
    'received', 'credited', 'got', 'salary', 'refund', 'refunded', 'earned',
    'income', 'deposited', 'cashback', 'returned', 'reimburse', 'stipend',
  ];
  static const _expenseWords = [
    'spent', 'paid', 'bought', 'buy', 'purchase', 'purchased', 'debited',
    'expense', 'cost', 'gave', 'recharge',
  ];

  /// Split one spoken/typed phrase into MULTIPLE transactions and parse each —
  /// "spent 200 on chai and 500 on petrol and got 5000 salary" → 3 entries.
  /// Only segments that yield an amount are kept; falls back to a single parse.
  static List<NluResult> parseMulti(String text, {DateTime? now}) {
    final parts =
        text.split(RegExp(r'\b(?:and|also|then|plus)\b|[,&;]', caseSensitive: false));
    final out = <NluResult>[];
    for (final p in parts) {
      if (p.trim().isEmpty) continue;
      final r = parse(p, now: now);
      if (r.amount != null) out.add(r);
    }
    if (out.isEmpty) {
      final r = parse(text, now: now);
      if (r.amount != null) out.add(r);
    }
    return out;
  }

  static NluResult parse(String text, {DateTime? now}) {
    final ts = now ?? DateTime.now();
    final t = text.trim();
    final low = t.toLowerCase();

    final direction = _direction(low);
    final amount = _extractAmount(low);
    final merchant = _extractMerchant(t, low, direction);
    final when = _extractDate(low, ts);
    final categoryId = _categoryFor(direction, '${merchant ?? ''} $low');

    return NluResult(
      amount: amount,
      direction: direction,
      merchant: merchant,
      categoryId: categoryId,
      when: when,
      rawText: t,
    );
  }

  // ── Direction ──────────────────────────────────────────────
  static TxnDirection _direction(String low) {
    final inc = _firstIndexOfAny(low, _incomeWords);
    final exp = _firstIndexOfAny(low, _expenseWords);
    if (inc != -1 && (exp == -1 || inc < exp)) return TxnDirection.credit;
    return TxnDirection.debit; // default: expense
  }

  static int _firstIndexOfAny(String hay, List<String> needles) {
    var best = -1;
    for (final n in needles) {
      final i = hay.indexOf(n);
      if (i != -1 && (best == -1 || i < best)) best = i;
    }
    return best;
  }

  // ── Amount ─────────────────────────────────────────────────
  static double? _extractAmount(String t) {
    // 1) Currency-anchored: "rs 500", "₹500", "500 rupees".
    final cur = RegExp(r'(?:rs\.?|₹|inr)\s*([\d,]+(?:\.\d+)?)', caseSensitive: false)
            .firstMatch(t) ??
        RegExp(r'([\d,]+(?:\.\d+)?)\s*(?:rs\b|rupees?|₹)', caseSensitive: false)
            .firstMatch(t);
    if (cur != null) {
      final v = double.tryParse(cur.group(1)!.replaceAll(',', ''));
      if (v != null && v > 0) return v;
    }
    // 2) Shorthand multipliers: "2k", "1.5k", "3 thousand", "1 lakh".
    final mult = RegExp(r'(\d+(?:\.\d+)?)\s*(k|thousand|lakh|lac)\b',
            caseSensitive: false)
        .firstMatch(t);
    if (mult != null) {
      final base = double.tryParse(mult.group(1)!) ?? 0;
      final m = mult.group(2)!.toLowerCase();
      final factor = (m == 'k' || m == 'thousand') ? 1000 : 100000;
      if (base > 0) return base * factor;
    }
    // 3) First bare number that isn't part of a date/time expression.
    for (final m in RegExp(r'\b(\d[\d,]*(?:\.\d+)?)\b').allMatches(t)) {
      final after = t.substring(m.end).trimLeft();
      if (RegExp(r'^(st|nd|rd|th|day|days|month|months|year|years|pm|am|hr|hrs|hour|hours|min|:)',
              caseSensitive: false)
          .hasMatch(after)) {
        continue;
      }
      final v = double.tryParse(m.group(1)!.replaceAll(',', ''));
      if (v != null && v > 0) return v;
    }
    return null;
  }

  // ── Merchant ───────────────────────────────────────────────
  static String? _extractMerchant(String original, String low, TxnDirection dir) {
    final preps = dir == TxnDirection.credit
        ? ['from']
        : ['on', 'at', 'to', 'for'];
    for (final p in preps) {
      final m = RegExp('\\b$p\\s+([A-Za-z0-9&._\\- ]{2,40})', caseSensitive: false)
          .firstMatch(original);
      if (m != null) {
        final cleaned = _clean(m.group(1)!);
        if (cleaned.isNotEmpty) return cleaned;
      }
    }
    return null;
  }

  static const _stopWords = {
    'for', 'on', 'at', 'to', 'from', 'rs', 'rupees', 'rupee', 'inr', 'today',
    'yesterday', 'tomorrow', 'last', 'ago', 'via', 'using', 'paid', 'spent',
    'got', 'received', 'bought', 'and', 'the', 'a', 'an',
  };

  static String _clean(String raw) {
    final kept = <String>[];
    for (final w in raw.trim().split(RegExp(r'\s+'))) {
      final lw = w.toLowerCase().replaceAll(RegExp(r'[^a-z0-9&._\-]'), '');
      if (lw.isEmpty) continue;
      if (_stopWords.contains(lw)) break;
      if (RegExp(r'^\d').hasMatch(lw)) break; // ran into an amount/date number
      kept.add(w);
      if (kept.length >= 3) break;
    }
    return kept.join(' ').trim();
  }

  // ── Category ───────────────────────────────────────────────
  static String _categoryFor(TxnDirection dir, String hint) {
    if (dir == TxnDirection.credit) {
      final low = hint.toLowerCase();
      if (low.contains('salary') || low.contains('payroll')) return 'salary';
      if (low.contains('refund') || low.contains('reversed')) return 'shopping';
      return 'transfer';
    }
    return Categories.classify(hint);
  }

  // ── Date ───────────────────────────────────────────────────
  static DateTime _extractDate(String low, DateTime now) {
    DateTime at(DateTime d) => DateTime(d.year, d.month, d.day, now.hour, now.minute);
    if (low.contains('day before yesterday')) {
      return at(now.subtract(const Duration(days: 2)));
    }
    if (low.contains('yesterday')) return at(now.subtract(const Duration(days: 1)));
    if (low.contains('today') || low.contains('just now') || low.contains('now')) {
      return now;
    }
    final ago = RegExp(r'(\d+)\s*days?\s*ago').firstMatch(low);
    if (ago != null) {
      final d = int.tryParse(ago.group(1)!) ?? 0;
      return at(now.subtract(Duration(days: d)));
    }
    final dm = RegExp(r'\b([0-3]?\d)[\/\-]([01]?\d)(?:[\/\-](\d{2,4}))?\b')
        .firstMatch(low);
    if (dm != null) {
      final dd = int.tryParse(dm.group(1)!) ?? now.day;
      final mm = int.tryParse(dm.group(2)!) ?? now.month;
      var yy = dm.group(3) != null
          ? (int.tryParse(dm.group(3)!) ?? now.year)
          : now.year;
      if (yy < 100) yy += 2000;
      try {
        return DateTime(yy, mm, dd, now.hour, now.minute);
      } catch (_) {/* fall through */}
    }
    return now;
  }
}
