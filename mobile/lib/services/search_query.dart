import '../models/category.dart';
import '../models/transaction.dart';

/// Plain-language search for the Activity list.
///
/// "above 1000 last month", "swiggy september", "food under 500 this week",
/// "received between 2k and 10k" — amounts, dates, direction and category are
/// pulled out; whatever words are left must appear in the merchant, note or
/// category. A plain word ("swiggy") or number ("450") behaves like the old
/// contains-search.
class SearchQuery {
  final double? minAmount;
  final double? maxAmount;
  final DateTime? from; // inclusive, start of day
  final DateTime? to; // inclusive, end of day
  final TxnDirection? direction;
  final String? categoryId;
  final List<String> words;

  /// Human-readable pieces of what was understood, for filter chips.
  final List<String> understood;

  const SearchQuery({
    this.minAmount,
    this.maxAmount,
    this.from,
    this.to,
    this.direction,
    this.categoryId,
    this.words = const [],
    this.understood = const [],
  });

  bool get isEmpty =>
      minAmount == null &&
      maxAmount == null &&
      from == null &&
      to == null &&
      direction == null &&
      categoryId == null &&
      words.isEmpty;

  bool matches(Transaction t) {
    if (minAmount != null && t.amount < minAmount!) return false;
    if (maxAmount != null && t.amount > maxAmount!) return false;
    if (from != null && t.timestamp.isBefore(from!)) return false;
    if (to != null && t.timestamp.isAfter(to!)) return false;
    if (direction != null && t.direction != direction) return false;
    if (categoryId != null && t.categoryId != categoryId) return false;
    if (words.isEmpty) return true;
    final hay = [
      t.merchant ?? '',
      t.note ?? '',
      Categories.byId(t.categoryId).label,
    ].join(' ').toLowerCase();
    final amt = t.amount.toString();
    for (final w in words) {
      final numeric = RegExp(r'^\d+(\.\d+)?$').hasMatch(w);
      if (!(hay.contains(w) || (numeric && amt.contains(w)))) return false;
    }
    return true;
  }

  // ── Parsing ────────────────────────────────────────────────

  static const _months = {
    'jan': 1, 'january': 1, 'feb': 2, 'february': 2, 'mar': 3, 'march': 3,
    'apr': 4, 'april': 4, 'may': 5, 'jun': 6, 'june': 6, 'jul': 7,
    'july': 7, 'aug': 8, 'august': 8, 'sep': 9, 'sept': 9, 'september': 9,
    'oct': 10, 'october': 10, 'nov': 11, 'november': 11, 'dec': 12,
    'december': 12,
  };
  static const _monthNames = [
    '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct',
    'Nov', 'Dec'
  ];

  static const _minWords = [
    'more than', 'greater than', 'at least', 'atleast', 'above', 'over',
    'min', '>=', '>',
  ];
  static const _maxWords = [
    'less than', 'up to', 'upto', 'below', 'under', 'max', '<=', '<',
  ];

  static const _debitWords = {
    'spent', 'spend', 'spending', 'debit', 'debits', 'debited', 'paid',
    'expense', 'expenses',
  };
  static const _creditWords = {
    'received', 'income', 'credit', 'credits', 'credited', 'got', 'earned',
  };

  static const _stop = {
    'in', 'on', 'at', 'for', 'from', 'the', 'of', 'and', 'with', 'to',
    'txn', 'txns', 'transaction', 'transactions', 'rs', 'rs.', 'inr', '₹',
    'all', 'my', 'show', 'me',
  };

  /// Amount literal: 1000, 1,000, ₹1,000.50, 1k, 1.5k, 2 lakh, 2l.
  static const _amt =
      r'(?:₹|rs\.?\s*|inr\s*)?(\d[\d,]*(?:\.\d+)?)\s*(k|thousand|l|lac|lakh|lakhs)?\b';

  static double? _toAmount(String n, String? unit) {
    final v = double.tryParse(n.replaceAll(',', ''));
    if (v == null) return null;
    switch (unit) {
      case 'k':
      case 'thousand':
        return v * 1000;
      case 'l':
      case 'lac':
      case 'lakh':
      case 'lakhs':
        return v * 100000;
    }
    return v;
  }

  static String _fmt(double v) {
    final s = v % 1 == 0 ? v.toStringAsFixed(0) : v.toStringAsFixed(2);
    // Indian grouping: 1,00,000
    final parts = s.split('.');
    var i = parts[0];
    if (i.length > 3) {
      final last3 = i.substring(i.length - 3);
      var rest = i.substring(0, i.length - 3);
      final groups = <String>[];
      while (rest.length > 2) {
        groups.insert(0, rest.substring(rest.length - 2));
        rest = rest.substring(0, rest.length - 2);
      }
      if (rest.isNotEmpty) groups.insert(0, rest);
      i = '${groups.join(',')},$last3';
    }
    return '₹$i${parts.length > 1 ? '.${parts[1]}' : ''}';
  }

  static SearchQuery parse(String input, {DateTime? now}) {
    now ??= DateTime.now();
    var s = ' ${input.toLowerCase().trim()} ';
    double? minA, maxA;
    DateTime? from, to;
    TxnDirection? dir;
    String? cat;
    final understood = <String>[];

    DateTime sod(DateTime d) => DateTime(d.year, d.month, d.day);
    DateTime eod(DateTime d) => DateTime(d.year, d.month, d.day, 23, 59, 59);
    void cut(Match m) => s = s.replaceRange(m.start, m.end, ' ');

    // "between 200 and 800" / "200 to 800" / "200-800"
    final between = RegExp('(?:between\\s+)?$_amt\\s*(?:and|to|-)\\s*$_amt')
        .firstMatch(s);
    if (between != null) {
      final a = _toAmount(between.group(1)!, between.group(2));
      final b = _toAmount(between.group(3)!, between.group(4));
      if (a != null && b != null && (s.contains('between') || a < b)) {
        minA = a < b ? a : b;
        maxA = a < b ? b : a;
        cut(between);
        understood.add('${_fmt(minA)}–${_fmt(maxA)}');
      }
    }
    if (minA == null) {
      for (final w in _minWords) {
        final m = RegExp('${RegExp.escape(w)}\\s*$_amt').firstMatch(s);
        if (m != null) {
          minA = _toAmount(m.group(1)!, m.group(2));
          cut(m);
          if (minA != null) understood.add('over ${_fmt(minA)}');
          break;
        }
      }
    }
    if (maxA == null) {
      for (final w in _maxWords) {
        final m = RegExp('${RegExp.escape(w)}\\s*$_amt').firstMatch(s);
        if (m != null) {
          maxA = _toAmount(m.group(1)!, m.group(2));
          cut(m);
          if (maxA != null) understood.add('under ${_fmt(maxA)}');
          break;
        }
      }
    }

    // Relative dates.
    final today = sod(now);
    final rel = <String, (DateTime, DateTime, String)>{
      'today': (today, eod(now), 'Today'),
      'yesterday': (
        today.subtract(const Duration(days: 1)),
        eod(today.subtract(const Duration(days: 1))),
        'Yesterday'
      ),
      'this week': (
        today.subtract(Duration(days: now.weekday - 1)),
        eod(now),
        'This week'
      ),
      'last week': (
        today.subtract(Duration(days: now.weekday + 6)),
        eod(today.subtract(Duration(days: now.weekday))),
        'Last week'
      ),
      'this month': (DateTime(now.year, now.month, 1), eod(now), 'This month'),
      'last month': (
        DateTime(now.year, now.month - 1, 1),
        eod(DateTime(now.year, now.month, 0)),
        'Last month'
      ),
      'this year': (DateTime(now.year, 1, 1), eod(now), 'This year'),
      'last year': (
        DateTime(now.year - 1, 1, 1),
        eod(DateTime(now.year - 1, 12, 31)),
        'Last year'
      ),
    };
    for (final e in rel.entries) {
      final m = RegExp('\\b${e.key}\\b').firstMatch(s);
      if (m != null) {
        (from, to, _) = e.value;
        understood.add(e.value.$3);
        cut(m);
        break;
      }
    }
    if (from == null) {
      final m = RegExp(r'\b(?:last|past)\s+(\d{1,3})\s+days?\b').firstMatch(s);
      if (m != null) {
        final n = int.parse(m.group(1)!);
        from = today.subtract(Duration(days: n - 1));
        to = eod(now);
        understood.add('Last $n days');
        cut(m);
      }
    }
    if (from == null) {
      final names = _months.keys.toList()
        ..sort((a, b) => b.length.compareTo(a.length));
      final m = RegExp('\\b(${names.join('|')})\\b(?:\\s+(\\d{4}))?')
          .firstMatch(s);
      if (m != null) {
        final mm = _months[m.group(1)]!;
        var yy = m.group(2) != null ? int.parse(m.group(2)!) : now.year;
        if (m.group(2) == null && mm > now.month) yy -= 1; // most recent
        from = DateTime(yy, mm, 1);
        to = eod(DateTime(yy, mm + 1, 0));
        understood.add('${_monthNames[mm]} $yy');
        cut(m);
      }
    }

    // Direction + category from single words; everything else is text.
    final words = <String>[];
    for (final w in s.split(RegExp(r'\s+')).where((w) => w.isNotEmpty)) {
      if (dir == null && _debitWords.contains(w)) {
        dir = TxnDirection.debit;
        understood.add('Spent');
      } else if (dir == null && _creditWords.contains(w)) {
        dir = TxnDirection.credit;
        understood.add('Received');
      } else if (cat == null && _categoryWord(w) != null) {
        cat = _categoryWord(w);
        understood.add(Categories.byId(cat!).label.split(RegExp(r' [&/] ')).first);
      } else if (!_stop.contains(w)) {
        words.add(w);
      }
    }
    if (words.isNotEmpty) understood.add('“${words.join(' ')}”');

    return SearchQuery(
      minAmount: minA,
      maxAmount: maxA,
      from: from,
      to: to,
      direction: dir,
      categoryId: cat,
      words: words,
      understood: understood,
    );
  }

  static String? _categoryWord(String w) {
    for (final c in Categories.all) {
      if (c.id == 'other' || c.id == 'transfer') continue;
      final first = c.label.split(RegExp(r'[ &/]')).first.toLowerCase();
      if (w == c.id || w == first) return c.id;
    }
    return null;
  }
}
