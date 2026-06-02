import 'package:intl/intl.dart';

final _rupee = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
final _rupeeDec = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2);

String formatRupees(num n, {bool compact = false, bool decimals = false}) {
  if (compact) return _compactRupees(n.toDouble());
  return (decimals ? _rupeeDec : _rupee).format(n);
}

/// Indian-style short money: ₹999, ₹7.5K, ₹7.5L, ₹2.3Cr.
/// (ICU's compactCurrency emits "T"/"M" which read wrong in India.)
String _compactRupees(double v) {
  final neg = v < 0;
  final a = v.abs();
  String s;
  if (a < 1000) {
    s = '₹${a.toStringAsFixed(0)}';
  } else if (a < 100000) {
    s = '₹${_trim(a / 1000)}K';
  } else if (a < 10000000) {
    s = '₹${_trim(a / 100000)}L';
  } else {
    s = '₹${_trim(a / 10000000)}Cr';
  }
  return neg ? '-$s' : s;
}

/// One decimal, but drop a trailing ".0" so we show 7K not 7.0K.
String _trim(double x) {
  final r = x.toStringAsFixed(1);
  return r.endsWith('.0') ? r.substring(0, r.length - 2) : r;
}

String relativeDate(DateTime d) {
  final now = DateTime.now();
  final diff = now.difference(d);
  if (diff.inDays == 0) {
    return DateFormat('h:mm a').format(d);
  } else if (diff.inDays == 1) {
    return 'Yesterday';
  } else if (diff.inDays < 7) {
    return DateFormat('EEEE').format(d);
  } else if (now.year == d.year) {
    return DateFormat('d MMM').format(d);
  }
  return DateFormat('d MMM yyyy').format(d);
}

String monthLabel(DateTime d) => DateFormat('MMMM yyyy').format(d);
String shortMonth(DateTime d) => DateFormat('MMM yy').format(d);
String shortDay(DateTime d) => DateFormat('d MMM').format(d);
