import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/transaction.dart';
import 'sms_parser.dart';

/// Learns from the user's corrections to SMS-imported transactions, per bank
/// TEMPLATE, so one fix repairs every future alert of that shape.
///
/// Banks generate alerts from fixed templates. If the user changes an SMS
/// transaction's amount from ₹85,610 to ₹200, we find which number in the SMS
/// (its "slot", see [SmsParser.amountSlots]) holds ₹200 and remember
/// `template → slot`. A direction or category fix is remembered the same way.
/// Next time an alert from that template arrives, the learned choice wins over
/// the parser's guess. Stored on-device only (works in the background isolate).
class SmsTemplates {
  SmsTemplates._();
  static final SmsTemplates instance = SmsTemplates._();

  static const _key = 'sms_templates';
  static const _cap = 400;
  Map<String, Map<String, dynamic>>? _cache;

  Future<Map<String, Map<String, dynamic>>> _load() async {
    if (_cache != null) return _cache!;
    final raw = (await SharedPreferences.getInstance()).getString(_key);
    _cache = raw == null
        ? <String, Map<String, dynamic>>{}
        : (jsonDecode(raw) as Map).map((k, v) =>
            MapEntry(k as String, Map<String, dynamic>.from(v as Map)));
    return _cache!;
  }

  Future<void> _save() async {
    final rules = _cache!;
    while (rules.length > _cap) {
      rules.remove(rules.keys.first); // oldest first (insertion order)
    }
    await (await SharedPreferences.getInstance())
        .setString(_key, jsonEncode(rules));
  }

  /// Forget everything learned (on sign-out — rules belong to one account).
  Future<void> clear() async {
    _cache = null;
    await (await SharedPreferences.getInstance()).remove(_key);
  }

  /// [p] with any learned correction for its template applied.
  Future<ParsedSms> apply(ParsedSms p) async {
    final t = p.txn;
    final body = t.smsBody, sender = t.smsSender;
    if (body == null || sender == null) return p;
    final rule = (await _load())[SmsParser.templateKey(sender, body)];
    if (rule == null) return p;
    var amount = t.amount;
    final slot = rule['slot'] as int?;
    if (slot != null) {
      final slots = SmsParser.amountSlots(body);
      if (slot < slots.length) amount = slots[slot];
    }
    final dir = switch (rule['dir']) {
      'debit' => TxnDirection.debit,
      'credit' => TxnDirection.credit,
      _ => t.direction,
    };
    final cat = rule['cat'] as String?;
    return p.withTxn(t.copyWith(
      amount: amount,
      direction: dir,
      categoryId: t.merchant == null && cat != null ? cat : null,
    ));
  }

  /// Remember what the user fixed between [before] and [after] (the same
  /// SMS-imported transaction). No-op for non-SMS transactions.
  Future<void> learn(Transaction before, Transaction after) async {
    final body = after.smsBody, sender = after.smsSender;
    if (after.source != TxnSource.sms || body == null || sender == null) {
      return;
    }
    final key = SmsParser.templateKey(sender, body);
    final rules = await _load();
    final rule = rules.remove(key) ?? <String, dynamic>{};
    if (after.amount != before.amount) {
      final slots = SmsParser.amountSlots(body);
      final i = slots.indexWhere((v) => (v - after.amount).abs() < 0.005);
      if (i >= 0) {
        rule['slot'] = i;
      } else {
        rule.remove('slot'); // a typed amount that isn't in the SMS
      }
    }
    if (after.direction != before.direction) {
      rule['dir'] = after.direction.name;
    }
    // Merchant-less alerts can't use the merchant → category rules.
    if (after.categoryId != before.categoryId && after.merchant == null) {
      rule['cat'] = after.categoryId;
    }
    if (rule.isNotEmpty) rules[key] = rule; // re-insert = most recent
    await _save();
  }
}
