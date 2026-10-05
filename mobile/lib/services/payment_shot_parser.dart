import '../models/transaction.dart';
import 'merchant_directory.dart';

/// One line of recognised text with where it sits on the image (pixels).
class OcrLine {
  final String text;
  final double left, top, bottom;
  const OcrLine(this.text,
      {required this.left, required this.top, required this.bottom});
}

/// What a UPI payment screenshot (PhonePe, Google Pay, Paytm, BHIM…) says.
class PaymentShot {
  final double amount;
  final TxnDirection direction;
  final String? name; // who was paid / who paid
  final String? upiVpa;
  final DateTime? when;
  final String? reference; // UTR / UPI ref — the same number bank SMS carry
  final String? account; // last 4 of the bank account it hit

  /// No ₹/Rs was found next to the number, so it may be misread.
  final bool amountUncertain;

  /// Nothing on the screen said paid or received; debit is only a guess.
  final bool directionGuessed;

  const PaymentShot({
    required this.amount,
    required this.direction,
    this.name,
    this.upiVpa,
    this.when,
    this.reference,
    this.account,
    this.amountUncertain = false,
    this.directionGuessed = false,
  });
}

/// Turns the OCR text of a payment-app screenshot into a [PaymentShot].
///
/// Pure string work (the OCR itself happens in receipt_scanner.dart), so it's
/// unit-tested against real screen layouts. Returns null when the text doesn't
/// look like a payment — better nothing than a wrong transaction.
class PaymentShotParser {
  PaymentShotParser._();

  /// Rebuilds reading order from positioned OCR lines: lines that share a
  /// visual row are joined left-to-right with a tab, rows with a newline. The
  /// recogniser returns blocks in no reliable order ("₹4,750" can come out
  /// far from the name it sits beside).
  static String layout(List<OcrLine> lines) {
    final sorted = [...lines]
      ..sort((a, b) => (a.top + a.bottom).compareTo(b.top + b.bottom));
    final rows = <List<OcrLine>>[];
    for (final l in sorted) {
      final c = (l.top + l.bottom) / 2;
      // The row's first line is the band; not widened, so rows can't chain.
      if (rows.isNotEmpty && c >= rows.last.first.top && c <= rows.last.first.bottom) {
        rows.last.add(l);
      } else {
        rows.add([l]);
      }
    }
    return [
      for (final r in rows)
        (r..sort((a, b) => a.left.compareTo(b.left)))
            .map((l) => l.text.trim())
            .join('\t'),
    ].join('\n');
  }

  static const _signals = [
    'paid to', 'received from', 'sent to', 'debited from', 'credited to',
    'transaction successful', 'payment successful', 'paid successfully',
    'money sent', 'money received', 'payment to', 'transfer details',
    'transaction id', 'banking name', 'utr', 'upi',
  ];
  static const _creditKeys = [
    'received from', 'credited to', 'money received', 'payment received',
    'you received',
  ];
  static const _debitKeys = [
    'paid to', 'debited from', 'sent to', 'money sent', 'paid successfully',
    'payment to', 'transferred to', 'you paid',
  ];
  static const _toLabels = [
    'paid successfully to', 'money sent to', 'paid to', 'sent to',
    'payment to', 'transferred to', 'to:',
  ];
  static const _fromLabels = ['money received from', 'received from', 'from:'];

  // Screen furniture that is never the other person's name.
  static const _notName = [
    'transaction', 'successful', 'transfer details', 'debited', 'credited',
    'upi', 'utr', 'payment', 'paid', 'received', 'banking name', 'balance',
    'history', 'receipt', 'contact', 'support', 'powered by', 'completed',
    'phonepe', 'google pay', 'paytm', 'bank', 'a/c', 'message', 'split',
  ];

  static final _moneyRe = RegExp(
      r'(?<![a-z])(?:₹|₨|rs\.?|inr)\s*([0-9][0-9,]*(?:\.[0-9]{1,2})?)',
      caseSensitive: false);
  // "₹" is sometimes read as a stray capital glued to the number: "F4,750".
  static final _misreadMoneyRe =
      RegExp(r'^[FRZ] ?(\d{1,3}(?:,\d{2,3})+|\d{1,6})(\.\d{1,2})?$');
  static final _groupedRe = RegExp(r'^\d{1,3}(?:,\d{2,3})+(?:\.\d{1,2})?$');
  static final _decimalRe = RegExp(r'^\d{1,6}\.\d{1,2}$');
  static final _plainRe = RegExp(r'^\d{1,6}$');

  static final _vpaRe = RegExp(
      r'([a-z0-9][a-z0-9._\-]{1,48})\s?@\s?([a-z][a-z0-9]{1,20})(?![a-z0-9]*\.[a-z])');
  static final _refRe = RegExp(
      r'(?:utr|rrn|upi\s*(?:ref(?:erence)?|transaction|txn)\s*(?:no\.?|number|id)?|'
      r'(?:bank\s*)?ref(?:erence)?\s*(?:no\.?|number|id))\s*[:#\-]?\s*(\d{9,18})');
  static final _acctRe = RegExp(r'[x*•]{2,}\s?(\d{4})(?!\d)');

  static const _months = {
    'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6, 'jul': 7,
    'aug': 8, 'sep': 9, 'oct': 10, '0ct': 10, 'nov': 11, 'n0v': 11, 'dec': 12,
  };
  // A month must end at a non-letter, so "20 Mayank" is not the 20th of May.
  static const _mon =
      r'(jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|june?|july?|'
      r'aug(?:ust)?|sep(?:t(?:ember)?)?|[o0]ct(?:ober)?|n[o0]v(?:ember)?|'
      r'dec(?:ember)?)(?![a-z])';
  static final _dayMonRe = RegExp(
      r'(?<![\d:.,])([0-3]?\d)(?:st|nd|rd|th)?[\s\-,.]*' +
          _mon +
          r"(?:[\s\-,.']*(20\d{2}))?");
  static final _monDayRe = RegExp(
      r'(?<![a-z])' + _mon + r'\s+([0-3]?\d)(?![:\d])(?:st|nd|rd|th)?(?:,?\s*(20\d{2}))?');
  static final _numDateRe =
      RegExp(r'(?<!\d)([0-3]?\d)[/\-.]([01]?\d)[/\-.](20\d{2}|\d{2})(?!\d)');
  static final _time12Re = RegExp(
      r'(?<!\d)(1[0-2]|0?\d)[:.]([0-5]\d)(?::[0-5]\d)?\s*([ap])\.?\s?m(?![a-z])');
  static final _time24Re =
      RegExp(r'(?<![\d:])([01]?\d|2[0-3]):([0-5]\d)(?![\d:])');

  static PaymentShot? parse(String text, {DateTime? now}) {
    now ??= DateTime.now();
    final lines = text
        .replaceAll('\u00a0', ' ')
        .split(RegExp(r'[\r\n]+'))
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    if (lines.isEmpty) return null;
    final rows = [
      for (final l in lines)
        l.split('\t').map((c) => c.trim()).where((c) => c.isNotEmpty).toList(),
    ];
    final low = [for (final l in lines) l.toLowerCase().replaceAll('\t', ' ')];
    final flat = low.join('\n');

    final firstSignal = low.indexWhere((l) => _signals.any(l.contains));
    if (firstSignal < 0) return null;

    final amount = _amount(rows, firstSignal);
    if (amount == null) return null;

    // ── Paid or received: the earliest explicit phrase wins.
    final c = _firstIndex(flat, _creditKeys);
    final d = _firstIndex(flat, _debitKeys);
    TxnDirection? dir;
    if (c >= 0 || d >= 0) {
      dir = (d < 0 || (c >= 0 && c < d))
          ? TxnDirection.credit
          : TxnDirection.debit;
    } else {
      // Google Pay heads the screen with a bare "To NAME" / "From NAME".
      for (final l in low) {
        final m = RegExp(r'^(to|from)\b').firstMatch(l);
        if (m == null) continue;
        dir = m.group(1) == 'to' ? TxnDirection.debit : TxnDirection.credit;
        break;
      }
    }
    final guessed = dir == null;
    dir ??= TxnDirection.debit;

    final nameHit = _name(lines, rows, low, dir);
    final vpa = _vpa(low, from: nameHit?.line ?? 0);
    var name = nameHit?.name ?? _nameNearVpa(rows, low, vpa);
    name = MerchantDirectory.lookup(name)?.name ??
        name ??
        MerchantDirectory.prettyName(vpa, null);

    final oneLine = flat.replaceAll('\n', ' ');
    var reference = _refRe.firstMatch(oneLine)?.group(1);
    if (reference == null) {
      // A UPI reference (RRN) is exactly 12 digits, alone in its cell.
      for (final cell in rows.expand((r) => r)) {
        if (RegExp(r'^\d{12}$').hasMatch(cell)) {
          reference = cell;
          break;
        }
      }
    }

    // The bank account, not a masked phone number: look after the label.
    final acctAt = _firstIndex(oneLine, const ['debited from', 'credited to']);
    final account = _acctRe
        .firstMatch(acctAt < 0 ? oneLine : oneLine.substring(acctAt))
        ?.group(1);

    return PaymentShot(
      amount: amount.value,
      direction: dir,
      name: name,
      upiVpa: vpa,
      when: _when(low, now),
      reference: reference,
      account: account,
      amountUncertain: !amount.marked,
      directionGuessed: guessed,
    );
  }

  /// Index of the earliest of [needles] in [hay], or -1.
  static int _firstIndex(String hay, List<String> needles) {
    var best = -1;
    for (final n in needles) {
      final i = hay.indexOf(n);
      if (i >= 0 && (best < 0 || i < best)) best = i;
    }
    return best;
  }

  static double? _num(String whole, [String? frac]) {
    final v = double.tryParse('${whole.replaceAll(',', '')}${frac ?? ''}');
    return v == null || v <= 0 || v >= 10000000 ? null : v;
  }

  static ({double value, bool marked})? _amount(
      List<List<String>> rows, int firstSignal) {
    // Amounts with a currency mark. Payment screens repeat the amount, so the
    // most repeated one wins; the first one breaks a tie.
    final seen = <double, int>{};
    for (final cell in rows.expand((r) => r)) {
      for (final m in _moneyRe.allMatches(cell)) {
        final v = _num(m.group(1)!);
        if (v != null) seen[v] = (seen[v] ?? 0) + 1;
      }
      final mis = _misreadMoneyRe.firstMatch(cell);
      if (mis != null) {
        final v = _num(mis.group(1)!, mis.group(2));
        if (v != null) seen[v] = (seen[v] ?? 0) + 1;
      }
    }
    if (seen.isNotEmpty) {
      var best = seen.keys.first;
      for (final e in seen.entries) {
        if (e.value > seen[best]!) best = e.key;
      }
      return (value: best, marked: true);
    }
    // No currency mark survived OCR: take a bare number, skipping the status
    // bar (clock, battery %) above the first payment phrase.
    final cells = rows.skip(firstSignal).expand((r) => r).toList();
    for (final re in [_groupedRe, _decimalRe, _plainRe]) {
      for (final cell in cells) {
        if (!re.hasMatch(cell)) continue;
        final v = _num(cell);
        if (v != null) return (value: v, marked: false);
      }
    }
    return null;
  }

  static String? _vpa(List<String> low, {required int from}) {
    String? first;
    for (var i = 0; i < low.length; i++) {
      final m = _vpaRe.firstMatch(low[i]);
      if (m == null) continue;
      final v = '${m.group(1)}@${m.group(2)}';
      if (i >= from) return v; // the one beside the other party's name
      first ??= v;
    }
    return first;
  }

  static ({String name, int line})? _name(List<String> lines,
      List<List<String>> rows, List<String> low, TxnDirection dir) {
    final labels = dir == TxnDirection.credit
        ? [..._fromLabels, ..._toLabels]
        : [..._toLabels, ..._fromLabels];
    ({String name, int line})? after(int i, int end) {
      final rest = end >= lines[i].length ? '' : lines[i].substring(end);
      final cells = [
        ...rest.split('\t'),
        for (var j = i + 1; j < rows.length && j <= i + 3; j++) ...rows[j],
      ];
      for (final cell in cells) {
        final n = _cleanName(cell);
        if (n != null) return (name: n, line: i);
      }
      return null;
    }

    for (final label in labels) {
      for (var i = 0; i < low.length; i++) {
        final at = low[i].indexOf(label);
        if (at < 0) continue;
        final hit = after(i, at + label.length);
        if (hit != null) return hit;
      }
    }
    // Bare "To NAME" / "From NAME" at the start of a line (Google Pay).
    final word = dir == TxnDirection.credit ? 'from' : 'to';
    for (var i = 0; i < low.length; i++) {
      final m = RegExp('^$word\\b[:\\s]*').firstMatch(low[i]);
      if (m == null) continue;
      final hit = after(i, m.end);
      if (hit != null) return hit;
    }
    for (var i = 0; i < low.length; i++) {
      final at = low[i].indexOf('banking name');
      if (at < 0) continue;
      final hit = after(i, at + 'banking name'.length);
      if (hit != null) return hit;
    }
    return null;
  }

  /// The name usually sits on, or just above, the line with the UPI ID.
  static String? _nameNearVpa(
      List<List<String>> rows, List<String> low, String? vpa) {
    if (vpa == null) return null;
    final i = low.indexWhere((l) => _vpaRe.hasMatch(l));
    if (i < 0) return null;
    for (final cell in [...rows[i], if (i > 0) ...rows[i - 1]]) {
      final n = _cleanName(cell);
      if (n != null) return n;
    }
    return null;
  }

  /// [cell] as a display name, or null if it isn't one.
  static String? _cleanName(String cell) {
    if (cell.contains('@')) return null;
    var s = cell
        .replaceAll(_moneyRe, ' ')
        .replaceAll(RegExp(r'^[\s:\-–·|]+|[\s:\-–·|]+$'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    // Drop the avatar's initials when OCR glued them on: "AP AYUSH PATEL".
    final words = s.split(' ');
    if (words.length >= 3 &&
        words.first.length <= 2 &&
        words.first.toUpperCase() ==
            words.skip(1).take(words.first.length).map((w) => w[0]).join().toUpperCase()) {
      s = words.skip(1).join(' ');
    }
    final letters = RegExp(r'[A-Za-z]').allMatches(s).length;
    final digits = RegExp(r'\d').allMatches(s).length;
    if (letters < 3 || digits >= letters || s.length > 60) return null;
    final l = s.toLowerCase();
    if (_notName.any(l.contains)) return null;
    if (s != s.toUpperCase()) return s;
    return s
        .split(' ')
        .map((w) => w[0] + w.substring(1).toLowerCase())
        .join(' ');
  }

  static DateTime? _when(List<String> low, DateTime now) {
    ({int line, int d, int mo, int? y})? best;
    for (var i = 0; i < low.length; i++) {
      final l = low[i];
      ({int line, int d, int mo, int? y})? hit;
      final a = _dayMonRe.firstMatch(l);
      final b = a == null ? _monDayRe.firstMatch(l) : null;
      final n = a == null && b == null ? _numDateRe.firstMatch(l) : null;
      if (a != null) {
        hit = (
          line: i,
          d: int.parse(a.group(1)!),
          mo: _months[a.group(2)!.substring(0, 3)]!,
          y: int.tryParse(a.group(3) ?? ''),
        );
      } else if (b != null) {
        hit = (
          line: i,
          d: int.parse(b.group(2)!),
          mo: _months[b.group(1)!.substring(0, 3)]!,
          y: int.tryParse(b.group(3) ?? ''),
        );
      } else if (n != null) {
        final y = int.parse(n.group(3)!);
        hit = (
          line: i,
          d: int.parse(n.group(1)!),
          mo: int.parse(n.group(2)!),
          y: y < 100 ? y + 2000 : y,
        );
      }
      if (hit == null || hit.d < 1 || hit.mo < 1 || hit.mo > 12) continue;
      if (hit.y != null) {
        best = hit;
        break; // a date with its year beats one without
      }
      best ??= hit;
    }
    if (best == null) return null;

    // The time printed with the date — never the status-bar clock.
    var h = 0, mi = 0;
    final here = low[best.line];
    RegExpMatch? t12 = _time12Re.firstMatch(here);
    final t24 = t12 == null ? _time24Re.firstMatch(here) : null;
    if (t12 == null && t24 == null) {
      for (final j in [best.line + 1, best.line - 1]) {
        if (j < 0 || j >= low.length) continue;
        t12 = _time12Re.firstMatch(low[j]);
        if (t12 != null) break;
      }
    }
    if (t12 != null) {
      h = int.parse(t12.group(1)!) % 12 + (t12.group(3) == 'p' ? 12 : 0);
      mi = int.parse(t12.group(2)!);
    } else if (t24 != null) {
      h = int.parse(t24.group(1)!);
      mi = int.parse(t24.group(2)!);
    }

    var when = DateTime(best.y ?? now.year, best.mo, best.d, h, mi);
    if (when.month != best.mo) return null; // 31 Feb and friends
    final limit = now.add(const Duration(days: 1));
    if (best.y == null && when.isAfter(limit)) {
      when = DateTime(now.year - 1, best.mo, best.d, h, mi);
    }
    return when.isAfter(limit) ? null : when;
  }
}
