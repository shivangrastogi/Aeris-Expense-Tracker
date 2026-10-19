import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'sms_parser.dart';

/// What's owed on a credit card, read from its statement SMS.
class CardDue {
  final String key; // bank|last4
  final String bank;
  final String? last4;
  final double total;
  final double? minimum;
  final DateTime dueDate;
  final DateTime statementAt;
  final DateTime? paidAt;

  const CardDue({
    required this.key,
    required this.bank,
    required this.last4,
    required this.total,
    required this.minimum,
    required this.dueDate,
    required this.statementAt,
    this.paidAt,
  });

  bool get isPaid => paidAt != null;

  /// "HDFC card ••1234".
  String get label =>
      '${_bankName(bank)} card${last4 == null ? '' : ' ••$last4'}';

  static String _bankName(String core) {
    const names = {
      'HDFC': 'HDFC', 'ICICI': 'ICICI', 'SBI': 'SBI', 'AXIS': 'Axis',
      'KOTAK': 'Kotak', 'IDFC': 'IDFC FIRST', 'INDUS': 'IndusInd',
      'YES': 'Yes Bank', 'AMEX': 'Amex', 'ONECRD': 'OneCard', 'RBL': 'RBL',
      'AU': 'AU', 'HSBC': 'HSBC', 'SCB': 'Standard Chartered', 'BOB': 'BOB',
      'CITI': 'Citi', 'FED': 'Federal',
    };
    for (final e in names.entries) {
      if (core.contains(e.key)) return e.value;
    }
    return core;
  }

  CardDue copyWith({DateTime? paidAt}) => CardDue(
        key: key,
        bank: bank,
        last4: last4,
        total: total,
        minimum: minimum,
        dueDate: dueDate,
        statementAt: statementAt,
        paidAt: paidAt ?? this.paidAt,
      );

  Map<String, dynamic> toJson() => {
        'bank': bank,
        'last4': last4,
        'total': total,
        'min': minimum,
        'due': dueDate.millisecondsSinceEpoch,
        'at': statementAt.millisecondsSinceEpoch,
        if (paidAt != null) 'paid': paidAt!.millisecondsSinceEpoch,
      };

  factory CardDue.fromJson(String key, Map<String, dynamic> m) => CardDue(
        key: key,
        bank: m['bank'] as String? ?? '',
        last4: m['last4'] as String?,
        total: (m['total'] as num?)?.toDouble() ?? 0,
        minimum: (m['min'] as num?)?.toDouble(),
        dueDate: DateTime.fromMillisecondsSinceEpoch(m['due'] as int),
        statementAt: DateTime.fromMillisecondsSinceEpoch(m['at'] as int),
        paidAt: m['paid'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(m['paid'] as int),
      );
}

/// Credit-card dues from statement SMS, one per card (the latest statement
/// wins). A card-bill payment SMS marks it paid. On-device; also written by
/// the background SMS isolate, so readers reload prefs before reading.
class CardDues {
  CardDues._();
  static final CardDues instance = CardDues._();

  static const _key = 'card_dues';
  final _changes = StreamController<void>.broadcast();

  /// Fires after this isolate changes the dues.
  Stream<void> get changes => _changes.stream;

  Future<Map<String, CardDue>> _load() async {
    final p = await SharedPreferences.getInstance();
    await p.reload(); // the background isolate may have written
    final raw = p.getString(_key);
    if (raw == null) return {};
    return (jsonDecode(raw) as Map).map((k, v) => MapEntry(
        k as String, CardDue.fromJson(k, Map<String, dynamic>.from(v as Map))));
  }

  Future<void> _save(Map<String, CardDue> dues) async {
    await (await SharedPreferences.getInstance()).setString(
        _key, jsonEncode(dues.map((k, v) => MapEntry(k, v.toJson()))));
    _changes.add(null);
  }

  /// All known dues, soonest first.
  Future<List<CardDue>> all() async =>
      (await _load()).values.toList()
        ..sort((a, b) => a.dueDate.compareTo(b.dueDate));

  /// Unpaid dues that aren't long past (shown as bills / reminded about).
  Future<List<CardDue>> open(DateTime now) async => [
        for (final d in await all())
          if (!d.isPaid &&
              !d.dueDate.isBefore(now.subtract(const Duration(days: 7))))
            d
      ];

  /// Record a statement. An older statement never replaces a newer one.
  Future<void> record(CardStatement s) async {
    final dues = await _load();
    final prev = dues[s.key];
    if (prev != null && !s.receivedAt.isAfter(prev.statementAt)) return;
    dues[s.key] = CardDue(
      key: s.key,
      bank: s.bank,
      last4: s.last4,
      total: s.total,
      minimum: s.minimum,
      dueDate: s.dueDate,
      statementAt: s.receivedAt,
    );
    await _save(dues);
  }

  /// Record [body] if it's a card statement (raw SMS fields, as the SMS
  /// plugins hand them over).
  Future<void> recordFrom(String sender, String body, int? dateMs) async {
    final s = SmsParser.parseStatement(
      sender: sender,
      body: body,
      receivedAt: dateMs != null
          ? DateTime.fromMillisecondsSinceEpoch(dateMs)
          : DateTime.now(),
    );
    if (s != null) await record(s);
  }

  /// A card-bill payment of [amount] at [when]: marks the matching unpaid
  /// due paid — the card whose digits are [last4], else the one whose total
  /// is the amount, else the only unpaid one if the payment covers at least
  /// its minimum. Returns the due marked paid, if any.
  Future<CardDue?> markPaid(
      {String? last4, required double amount, required DateTime when}) async {
    final dues = await _load();
    final unpaid = dues.values
        .where((d) => !d.isPaid && !when.isBefore(d.statementAt))
        .toList();
    CardDue? hit;
    if (last4 != null) {
      hit = unpaid.where((d) => d.last4 != null && _same(d.last4!, last4)).firstOrNull;
    }
    hit ??= unpaid.where((d) => (d.total - amount).abs() < 1).firstOrNull;
    if (hit == null && unpaid.length == 1) {
      final d = unpaid.single;
      if (amount + 0.01 >= (d.minimum ?? d.total)) hit = d;
    }
    if (hit == null) return null;
    dues[hit.key] = hit.copyWith(paidAt: when);
    await _save(dues);
    return dues[hit.key];
  }

  static bool _same(String a, String b) =>
      a.length <= b.length ? b.endsWith(a) : a.endsWith(b);

  Future<void> clear() async {
    await (await SharedPreferences.getInstance()).remove(_key);
    _changes.add(null);
  }
}
