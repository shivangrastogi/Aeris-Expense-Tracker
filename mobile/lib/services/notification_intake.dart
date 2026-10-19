import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/category.dart';
import 'merchant_directory.dart';
import 'sms_parser.dart';

/// Payments seen in UPI app notifications (Google Pay, PhonePe, Paytm…) —
/// many of those apps send no SMS. The native `UpiNotificationListener`
/// queues the notifications; this drains the queue and runs each one through
/// [SmsParser] as if it were an SMS from that app (sender `NOTIF-<APP>`).
/// The duplicate check in the importer folds it into the bank's own SMS for
/// the same payment when both arrive.
class NotificationIntake {
  NotificationIntake._();
  static final NotificationIntake instance = NotificationIntake._();

  static const _ch = MethodChannel('aeris/notif');
  static const senderPrefix = 'NOTIF-';

  static const _appNames = {
    'GPAY': 'Google Pay', 'PHONEPE': 'PhonePe', 'PAYTM': 'Paytm',
    'BHIM': 'BHIM', 'APAY': 'Amazon Pay', 'CRED': 'CRED',
    'MOBIKWIK': 'MobiKwik', 'NAVI': 'Navi', 'SUPERMONEY': 'super.money',
    'SLICE': 'slice', 'JUPITER': 'Jupiter', 'EPIFI': 'Fi',
  };

  /// "Google Pay" for a `NOTIF-GPAY` sender; null for an SMS sender.
  static String? appNameOf(String? sender) {
    if (sender == null || !sender.startsWith(senderPrefix)) return null;
    final code = sender.substring(senderPrefix.length);
    return _appNames[code] ?? code;
  }

  bool get _android => defaultTargetPlatform == TargetPlatform.android;

  Future<bool> isEnabled() async {
    if (!_android) return false;
    try {
      return await _ch.invokeMethod<bool>('isEnabled') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Opens Android's notification-access screen (the user flips AERIS on).
  Future<void> openSettings() async {
    if (_android) await _ch.invokeMethod('openSettings');
  }

  /// Listen for new notifications and hand each parsed payment to
  /// [onPayment]; also drains whatever queued while the app was closed.
  Future<void> attach(Future<void> Function(ParsedSms) onPayment) async {
    if (!_android) return;
    _ch.setMethodCallHandler((call) async {
      if (call.method == 'queued') await _drainTo(onPayment);
    });
    await _drainTo(onPayment);
  }

  bool _draining = false;

  Future<void> _drainTo(Future<void> Function(ParsedSms) onPayment) async {
    if (_draining) return;
    _draining = true;
    try {
      final raw = await _ch.invokeListMethod<Map>('drain') ?? const [];
      for (final m in raw) {
        final p = parse(
          app: m['app'] as String,
          title: (m['title'] as String?) ?? '',
          text: (m['text'] as String?) ?? '',
          postedAt: DateTime.fromMillisecondsSinceEpoch(m['ts'] as int),
        );
        if (p != null) await onPayment(p);
      }
    } catch (e) {
      debugPrint('[notif] drain failed: $e');
    } finally {
      _draining = false;
    }
  }

  static final _genericTitle = RegExp(
    r'^(google pay|gpay|phonepe|paytm|bhim|amazon pay|cred|mobikwik|navi|'
    r'slice|jupiter|fi|super\.money|payment (?:successful|received|sent|done)|'
    r'money (?:received|sent)|transaction successful|paid|received|sent|'
    r'upi payment|bank account)$',
    caseSensitive: false,
  );

  /// One notification → a payment, or null if it isn't one. Pure (testable).
  static ParsedSms? parse({
    required String app,
    required String title,
    required String text,
    required DateTime postedAt,
  }) {
    final t = title.trim(), x = text.trim();
    final body = t.isEmpty
        ? x
        : x.isEmpty
            ? t
            : '$t. $x';
    final p = SmsParser.parse(
        sender: '$senderPrefix$app', body: body, receivedAt: postedAt);
    if (p == null) return null;
    var txn = p.txn;
    // Google Pay style: the title IS the person/shop ("Rohan Sharma" /
    // "Paid ₹10"). Use it when the text named nobody.
    final weakPayee = txn.merchant == null || txn.merchant!.startsWith('A/c ••');
    if (weakPayee &&
        t.isNotEmpty &&
        t.length <= 40 &&
        !_genericTitle.hasMatch(t) &&
        !RegExp(r'[\d₹]').hasMatch(t)) {
      final hit = MerchantDirectory.lookup(t);
      final name = hit?.name ?? t;
      var cat = txn.categoryId;
      if (txn.isDebit && (cat == 'other' || cat == 'transfer')) {
        cat = hit?.categoryId ??
            Categories.classify(t, exclude: const {'salary', 'refund'});
        if (cat == 'other') cat = txn.categoryId;
      }
      txn = txn.copyWith(merchant: name, categoryId: cat);
    }
    return p.withTxn(txn);
  }
}
