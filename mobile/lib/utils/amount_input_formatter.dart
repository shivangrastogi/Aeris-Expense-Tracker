import 'package:flutter/services.dart';

import 'formatters.dart';

/// Restricts a text field to a money amount: digits with at most one decimal
/// point, [maxDecimals] fractional digits and [maxWhole] whole digits.
/// Commas pasted in (e.g. "1,200") are stripped rather than rejected.
///
/// With [allowMath], simple arithmetic is accepted too ("120+45×2"): typed
/// `*` `/` `-` are shown as `×` `÷` `−`; evaluate it with [evalAmount].
class AmountInputFormatter extends TextInputFormatter {
  final int maxWhole;
  final int maxDecimals;
  final bool allowMath;
  const AmountInputFormatter(
      {this.maxWhole = 9, this.maxDecimals = 2, this.allowMath = false});

  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    var text = newValue.text.replaceAll(',', '').replaceAll(' ', '');
    if (allowMath) {
      text = text
          .replaceAll('*', '×')
          .replaceAll('x', '×')
          .replaceAll('/', '÷')
          .replaceAll('-', '−');
      // Typing a second operator replaces the first ("12+×" → "12×").
      text = text.replaceAllMapped(
          RegExp('[+−×÷]{2,}'), (m) => m[0]!.substring(m[0]!.length - 1));
    }
    if (text.isEmpty) return newValue.copyWith(text: '');
    // Leading "." → "0." so the value always parses.
    if (text.startsWith('.')) text = '0$text';
    final num = '\\d{0,$maxWhole}(\\.\\d{0,$maxDecimals})?';
    final ok = allowMath
        ? RegExp('^$num([+−×÷]$num)*\$')
        : RegExp('^\\d{1,$maxWhole}(\\.\\d{0,$maxDecimals})?\$');
    if (!ok.hasMatch(text)) return oldValue;
    // Untouched input keeps the user's cursor position (mid-string edits).
    if (text == newValue.text) return newValue;
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}

/// True if [text] contains an arithmetic operator (i.e. needs evaluating).
bool isAmountExpression(String text) => RegExp('[+−×÷*/-]').hasMatch(
    text.length > 1 ? text.substring(1) : ''); // ignore a leading sign

/// Evaluates an amount, optionally an expression like "120+45×2" (× and ÷
/// bind tighter than + and −). Returns null if it's empty, malformed, divides
/// by zero, or isn't a positive number. Result is rounded to 2 decimals.
double? evalAmount(String text) {
  final s = text
      .replaceAll(',', '')
      .replaceAll(' ', '')
      .replaceAll('*', '×')
      .replaceAll('/', '÷')
      .replaceAll('-', '−')
      // A trailing operator ("120+") is ignored rather than failing.
      .replaceFirst(RegExp(r'[+−×÷]+$'), '');
  if (s.isEmpty) return null;
  final tokens = RegExp(r'\d+(\.\d*)?|\.\d+|[+−×÷]').allMatches(s).toList();
  if (tokens.map((m) => m[0]).join() != s) return null;

  double total = 0;
  double? term;
  var addOp = '+';
  var mulOp = '';
  var expectNumber = true;
  for (final m in tokens) {
    final tok = m[0]!;
    if (expectNumber) {
      final v = double.tryParse(tok);
      if (v == null) return null;
      if (mulOp.isEmpty) {
        term = v;
      } else if (mulOp == '×') {
        term = term! * v;
      } else {
        if (v == 0) return null;
        term = term! / v;
      }
      expectNumber = false;
    } else {
      if (tok == '×' || tok == '÷') {
        mulOp = tok;
      } else {
        total = addOp == '+' ? total + term! : total - term!;
        addOp = tok;
        mulOp = '';
      }
      expectNumber = true;
    }
  }
  if (expectNumber || term == null) return null; // e.g. leading operator
  total = addOp == '+' ? total + term : total - term;
  if (total.isNaN || total.isInfinite || total <= 0) return null;
  return (total * 100).roundToDouble() / 100;
}

/// An amount typed in the user's display currency, converted to INR (what's
/// stored). Accepts "1,200" and simple math like "120+45". Null when empty,
/// invalid or not positive.
double? displayToInr(String text) {
  final v = evalAmount(text);
  return v == null ? null : (v * kCurrency.rate * 100).roundToDouble() / 100;
}

/// A stored INR amount as plain text in the display currency, for pre-filling
/// an input. Empty for null.
String inrToDisplayText(double? inr) {
  if (inr == null) return '';
  final v = inr / kCurrency.rate;
  return v % 1 == 0 ? v.toStringAsFixed(0) : v.toStringAsFixed(2);
}
