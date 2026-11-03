import 'dart:async';
import 'dart:ui';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../firebase_options.dart';
import 'firestore_service.dart';
import 'key_vault.dart';
import 'notification_intake.dart';
import 'sms_import_service.dart';
import 'widget_service.dart';

/// Keeps the home-screen widgets current while AERIS is closed.
///
/// Android runs this in a headless Flutter engine (BackgroundDart.kt, via
/// `widgetBackgroundMain` in main.dart):
/// every ~30 min (WidgetRefreshWorker), and the moment a UPI app posts a
/// payment notification. It saves any queued UPI-app payments — previously
/// those waited until the app was next opened — then recomputes the widget
/// totals and streak from the real data, so the widgets match the app
/// without it being open.
Future<void> runWidgetBackground() async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  const ch = MethodChannel('aeris/bg');
  try {
    await _run(ch).timeout(const Duration(seconds: 75));
  } catch (e, st) {
    try {
      await FirebaseCrashlytics.instance
          .recordError(e, st, reason: 'widget background refresh');
    } catch (_) {}
  } finally {
    try {
      await ch.invokeMethod('done');
    } catch (_) {}
  }
}

Future<void> _run(MethodChannel ch) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  final prefs = await SharedPreferences.getInstance();
  await prefs.reload(); // the app may have written since this engine started

  final uid =
      prefs.getString('current_uid') ?? FirebaseAuth.instance.currentUser?.uid;
  // Signed out, or the data key isn't on this device: the streak can still
  // move (it lives in prefs), the money totals can't be read.
  final unlocked = uid != null &&
      (KeyVault.instance.isUnlocked || await KeyVault.instance.loadCached(uid));

  if (unlocked) {
    // UPI-app payments queued by UpiNotificationListener while closed.
    final queued = await ch.invokeListMethod<Map>('drain') ?? const [];
    if (queued.isNotEmpty) {
      final blocked = (prefs.getStringList('blocked_senders') ?? const []).toSet();
      for (final m in queued) {
        final p = NotificationIntake.parse(
          app: m['app'] as String,
          title: (m['title'] as String?) ?? '',
          text: (m['text'] as String?) ?? '',
          postedAt: DateTime.fromMillisecondsSinceEpoch(m['ts'] as int),
        );
        if (p != null) {
          await SmsImportService.instance.persistOne(uid, p, blocked);
        }
      }
    }
  }

  final now = DateTime.now();
  WidgetSnapshot? snap;
  if (unlocked) {
    // This month, from Firestore (its local cache when offline) — includes
    // entries added on another device or in the web app.
    final txns = await FirestoreService.instance
        .fetchTransactions(uid, since: DateTime(now.year, now.month))
        .timeout(const Duration(seconds: 40));
    snap = WidgetSnapshot.compute(txns, now);
  }
  await WidgetService.pushFromBackground(
    snap: snap,
    streak: prefs.getInt('gam_checkin_streak') ?? 0,
    lastCheckinDay: prefs.getString('gam_checkin_day'),
    checkinDays: [
      for (final k in prefs.getStringList('gam_awarded') ?? const <String>[])
        if (k.startsWith('checkin_')) k.substring(8),
    ],
  );
}
