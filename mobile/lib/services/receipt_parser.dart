import '../models/transaction.dart';

/// Turns the raw OCR text of a bill/receipt into the three things the add
/// screen needs: the total, who it's from, and when.
///
/// Pure string work (the OCR itself happens in receipt_scanner.dart), so it's
/// unit-tested against real-world receipt layouts.
class ReceiptInfo {
  final double? total;
  final String? merchant;
  final DateTime? date;

  /// Set only when the image was a payment screenshot that says which way
  /// the money went; a shop bill has no direction.
  final TxnDirection? direction;
  const ReceiptInfo({this.total, this.merchant, this.date, this.direction});

  bool get isEmpty => total == null && merchant == null && date == null;
}

class ReceiptParser {
  ReceiptParser._();

  // Strongest first: "grand total" beats "total"; "sub total" never counts.
  static const _totalKeys = [
    'grand total', 'net amount', 'net payable', 'amount payable',
    'total payable', 'amount due', 'balance due', 'bill amount', 'to pay',
    'net total', 'total amount', 'total',
  ];
  static const _notTotal = [
    'sub total', 'subtotal', 'sub-total', 'total items', 'total qty',
    'total quantity', 'total tax', 'total gst', 'total discount', 'savings',
  ];
  static const _notMerchant = [
    'tax invoice', 'invoice', 'receipt', 'bill', 'gst', 'gstin', 'date',
    'phone', 'tel', 'mobile', 'cash memo', 'order', 'table', 'welcome',
    'thank', 'customer', 'copy', 'fssai', 'cin',
  ];

  static final _num =
      RegExp(r'(?:₹|rs\.?|inr)?\s*(\d{1,3}(?:,\d{2,3})+|\d+)(?:\.(\d{1,2}))?',
          caseSensitive: false);

  static double? _amountIn(String line) {
    double? best;
    for (final m in _num.allMatches(line)) {
      final whole = m.group(1)!.replaceAll(',', '');
      final v = double.tryParse('$whole.${m.group(2) ?? '0'}');
      if (v == null || v <= 0 || v >= 1000000) continue;
      // Skip things that look like years, phone numbers or long ids.
      if (m.group(2) == null && whole.length >= 7) continue;
      best = best == null || v > best ? v : best;
    }
    return best;
  }

  static ReceiptInfo parse(String text) {
    final lines = text
        .split(RegExp(r'[\r\n]+'))
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    final low = lines.map((l) => l.toLowerCase()).toList();

    // ── Total: the strongest keyword line with an amount on it (or the next
    // line — OCR often splits "TOTAL" and "₹540.00").
    double? total;
    outer:
    for (final key in _totalKeys) {
      for (var i = low.length - 1; i >= 0; i--) {
        final l = low[i];
        if (!l.contains(key) || _notTotal.any(l.contains)) continue;
        final v = _amountIn(lines[i]) ??
            (i + 1 < lines.length ? _amountIn(lines[i + 1]) : null);
        if (v != null) {
          total = v;
          break outer;
        }
      }
    }
    // Fallback: the largest decimal amount on the receipt.
    if (total == null) {
      for (final l in lines) {
        for (final m in _num.allMatches(l)) {
          if (m.group(2) == null) continue;
          final v = double.tryParse(
              '${m.group(1)!.replaceAll(',', '')}.${m.group(2)}');
          if (v != null && v < 1000000 && (total == null || v > total)) {
            total = v;
          }
        }
      }
    }

    // ── Merchant: the first "name-like" line near the top.
    String? merchant;
    for (var i = 0; i < lines.length && i < 6; i++) {
      final l = lines[i];
      final letters = RegExp(r'[A-Za-z]').allMatches(l).length;
      final digits = RegExp(r'\d').allMatches(l).length;
      if (letters < 3 || digits > letters) continue;
      if (_notMerchant.any(low[i].contains)) continue;
      merchant = _titleCase(l.replaceAll(RegExp(r'[^A-Za-z0-9&\x27. -]'), ' '));
      break;
    }

    return ReceiptInfo(total: total, merchant: merchant, date: _date(text));
  }

  static String _titleCase(String s) => s
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .map((w) => w.length <= 2 && w == w.toUpperCase()
          ? w // keep short caps like "&", "KFC"-style initials
          : w[0].toUpperCase() + w.substring(1).toLowerCase())
      .join(' ');

  static const _mon = {
    'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
    'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
  };

  static DateTime? _date(String text) {
    final low = text.toLowerCase();
    // 12/09/2026, 12-09-26, 12.09.2026 (Indian day-first)
    final m = RegExp(r'\b(\d{1,2})[/\-.](\d{1,2})[/\-.](\d{2,4})\b')
        .firstMatch(low);
    if (m != null) {
      final d = int.parse(m.group(1)!);
      final mo = int.parse(m.group(2)!);
      var y = int.parse(m.group(3)!);
      if (y < 100) y += 2000;
      if (d >= 1 && d <= 31 && mo >= 1 && mo <= 12) return DateTime(y, mo, d);
    }
    // 12 Sep 2026 / 12-Sep-26
    final t = RegExp(
            r'\b(\d{1,2})[\s\-]*(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*[\s\-,]*(\d{2,4})\b')
        .firstMatch(low);
    if (t != null) {
      var y = int.parse(t.group(3)!);
      if (y < 100) y += 2000;
      return DateTime(y, _mon[t.group(2)]!, int.parse(t.group(1)!));
    }
    return null;
  }
}
