import 'package:intl/intl.dart';

import '../models/currency.dart';

/// The user's chosen display currency. All amounts passed to [formatRupees]
/// are assumed to be stored in INR; this converts + formats for display only.
/// Set on app start from prefs (see `currencyProvider`) so there's no flash
/// of the wrong currency.
Currency kCurrency = Currencies.byCode('INR');

/// When true, every amount renders masked (privacy mode). Driven by the
/// eye toggle + `amountHiddenProvider`; set on app start from prefs so there's
/// no flash of real values. Pass `raw: true` to bypass (rarely needed).
bool kAmountsHidden = false;

String formatRupees(num n,
    {bool compact = false, bool decimals = false, bool raw = false}) {
  final c = kCurrency;
  if (kAmountsHidden && !raw) return '${c.symbol}••••';
  final v = n / c.rate;
  if (compact) return _compactMoney(v, c);
  final locale = c.indian ? 'en_IN' : 'en_US';
  return NumberFormat.currency(
          locale: locale, symbol: c.symbol, decimalDigits: decimals ? 2 : 0)
      .format(v);
}

/// Short money in the active currency: ₹7.5K/₹7.5L/₹2.3Cr for Indian
/// grouping, $7.5K/$2.3M/$1.1B otherwise. (ICU's compactCurrency emits
/// "T"/"M" for ₹, which reads wrong in India.)
String _compactMoney(double v, Currency c) {
  final neg = v < 0;
  final a = v.abs();
  String body;
  if (c.indian) {
    if (a < 1000) {
      body = a.toStringAsFixed(0);
    } else if (a < 100000) {
      body = '${_trim(a / 1000)}K';
    } else if (a < 10000000) {
      body = '${_trim(a / 100000)}L';
    } else {
      body = '${_trim(a / 10000000)}Cr';
    }
  } else {
    if (a < 1000) {
      body = a.toStringAsFixed(0);
    } else if (a < 1000000) {
      body = '${_trim(a / 1000)}K';
    } else if (a < 1000000000) {
      body = '${_trim(a / 1000000)}M';
    } else {
      body = '${_trim(a / 1000000000)}B';
    }
  }
  final s = '${c.symbol}$body';
  return neg ? '-$s' : s;
}

/// One decimal, but drop a trailing ".0" so we show 7K not 7.0K.
String _trim(double x) {
  final r = x.toStringAsFixed(1);
  return r.endsWith('.0') ? r.substring(0, r.length - 2) : r;
}

String relativeDate(DateTime d) {
  final now = DateTime.now();
  // Calendar-day difference (not elapsed hours) so a late-night txn still reads
  // "Yesterday", and include the time so you can see WHEN it happened.
  final today = DateTime(now.year, now.month, now.day);
  final that = DateTime(d.year, d.month, d.day);
  final days = today.difference(that).inDays;
  final time = DateFormat('h:mm a').format(d);
  if (days == 0) return time; // today → just the time
  if (days == 1) return 'Yesterday, $time';
  if (days < 7) return '${DateFormat('EEEE').format(d)}, $time';
  if (now.year == d.year) return DateFormat('d MMM, h:mm a').format(d);
  return DateFormat('d MMM yyyy').format(d);
}

String monthLabel(DateTime d) => DateFormat('MMMM yyyy').format(d);
String shortMonth(DateTime d) => DateFormat('MMM yy').format(d);
String shortDay(DateTime d) => DateFormat('d MMM').format(d);
