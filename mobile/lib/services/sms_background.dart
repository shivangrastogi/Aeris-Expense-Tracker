import 'dart:ui';

import 'package:another_telephony/telephony.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../firebase_options.dart';
import 'key_vault.dart';
import 'sms_import_service.dart';
import 'sms_parser.dart';

/// Runs in a SEPARATE background isolate when an SMS arrives while the app is
/// closed/backgrounded (registered with another_telephony). It re-initialises
/// Firebase, restores the encryption key from secure storage, parses the SMS,
/// and persists it — all without the UI being open.
///
/// Must be a top-level function annotated for AOT entry.
@pragma('vm:entry-point')
Future<void> smsBackgroundHandler(SmsMessage message) async {
  try {
    DartPluginRegistrant.ensureInitialized();
    await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform);

    final prefs = await SharedPreferences.getInstance();
    final uid =
        prefs.getString('current_uid') ?? FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    // Restore the data key from the device keystore (set at login). Without it
    // we can't encrypt-write, so bail and let the next app-open backfill catch
    // this message.
    if (!KeyVault.instance.isUnlocked && !await KeyVault.instance.loadCached(uid)) {
      return;
    }

    final parsed = SmsParser.parse(
      sender: message.address ?? '',
      body: message.body ?? '',
      receivedAt: message.date != null
          ? DateTime.fromMillisecondsSinceEpoch(message.date!)
          : DateTime.now(),
    );
    if (parsed == null) return;

    await SmsImportService.instance.persistOne(uid, parsed, const {});
  } catch (_) {/* background best-effort; foreground backfill is the fallback */}
}
