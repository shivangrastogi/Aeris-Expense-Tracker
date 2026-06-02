import 'dart:async';
import 'package:another_telephony/telephony.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

import 'sms_background.dart';
import 'sms_parser.dart';

/// Wraps `another_telephony` so the rest of the app talks to a small,
/// platform-agnostic API. On non-Android platforms this degrades to a
/// stub (`hasPermission` → false, `inboxStream` → empty).
class SmsService {
  SmsService._();
  static final SmsService instance = SmsService._();

  final _telephony = Telephony.instance;
  final _ctrl = StreamController<ParsedSms>.broadcast();

  Stream<ParsedSms> get parsedStream => _ctrl.stream;

  /// Ask the user for SMS read + receive permission. Returns true if both
  /// are granted. On iOS / desktop this just returns false.
  Future<bool> requestPermission() async {
    if (!_isAndroid) return false;
    final smsRead = await Permission.sms.request();
    if (!smsRead.isGranted) return false;
    final notif = await Permission.notification.request();   // optional but nice
    debugPrint('[sms] notif permission: $notif');
    return true;
  }

  Future<bool> hasPermission() async {
    if (!_isAndroid) return false;
    return Permission.sms.isGranted;
  }

  /// Parse the inbox and RETURN the parsed transactions (no stream emit, no
  /// persistence). Lets callers persist in a controlled, progress-reported
  /// loop instead of flooding the live stream — which kept the UI smooth.
  Future<List<ParsedSms>> scanInbox({DateTime? since}) async {
    if (!await hasPermission()) return const [];
    final since0 = since ?? DateTime.now().subtract(const Duration(days: 90));
    final filter = SmsFilter.where(SmsColumn.DATE)
        .greaterThan(since0.millisecondsSinceEpoch.toString());
    final messages = await _telephony.getInboxSms(
      columns: [
        SmsColumn.ID, SmsColumn.ADDRESS, SmsColumn.BODY, SmsColumn.DATE,
      ],
      filter: filter,
      sortOrder: [OrderBy(SmsColumn.DATE, sort: Sort.DESC)],
    );
    final out = <ParsedSms>[];
    for (var i = 0; i < messages.length; i++) {
      final m = messages[i];
      final parsed = SmsParser.parse(
        sender: m.address ?? '',
        body: m.body ?? '',
        receivedAt: m.date != null
            ? DateTime.fromMillisecondsSinceEpoch(m.date!)
            : DateTime.now(),
      );
      if (parsed != null) out.add(parsed);
      if (i % 25 == 24) await Future<void>.delayed(Duration.zero);
    }
    return out;
  }

  /// Walk the full inbox once and emit every parseable transaction.
  /// Returns the count of parsed entries.
  Future<int> backfillInbox({DateTime? since}) async {
    if (!await hasPermission()) return 0;
    final since0 = since ?? DateTime.now().subtract(const Duration(days: 90));
    final filter = SmsFilter.where(SmsColumn.DATE)
        .greaterThan(since0.millisecondsSinceEpoch.toString());
    final messages = await _telephony.getInboxSms(
      columns: [
        SmsColumn.ID, SmsColumn.ADDRESS, SmsColumn.BODY, SmsColumn.DATE,
      ],
      filter: filter,
      sortOrder: [OrderBy(SmsColumn.DATE, sort: Sort.DESC)],
    );
    int n = 0;
    for (var i = 0; i < messages.length; i++) {
      final m = messages[i];
      final parsed = SmsParser.parse(
        sender: m.address ?? '',
        body: m.body ?? '',
        receivedAt: m.date != null
            ? DateTime.fromMillisecondsSinceEpoch(m.date!)
            : DateTime.now(),
      );
      if (parsed != null) {
        _ctrl.add(parsed);
        n++;
      }
      // Yield to the event loop every 25 messages so a large inbox can't
      // freeze the UI thread while we parse.
      if (i % 25 == 24) await Future<void>.delayed(Duration.zero);
    }
    return n;
  }

  /// Subscribe to incoming SMS in real-time. Each parsed message lands in
  /// [parsedStream] AND is also forwarded to the [onTxn] callback if given.
  Future<void> startLiveListening({
    void Function(ParsedSms)? onTxn,
  }) async {
    if (!await hasPermission()) return;
    _telephony.listenIncomingSms(
      onNewMessage: (SmsMessage msg) {
        final parsed = SmsParser.parse(
          sender: msg.address ?? '',
          body: msg.body ?? '',
          receivedAt: msg.date != null
              ? DateTime.fromMillisecondsSinceEpoch(msg.date!)
              : DateTime.now(),
        );
        if (parsed == null) return;
        _ctrl.add(parsed);
        onTxn?.call(parsed);
      },
      // Capture SMS even when the app is closed via a background isolate.
      onBackgroundMessage: smsBackgroundHandler,
      listenInBackground: true,
    );
  }

  bool get _isAndroid =>
      defaultTargetPlatform == TargetPlatform.android;
}
