import 'package:shared_preferences/shared_preferences.dart';

import 'category_rules.dart';
import 'crypto_service.dart';
import 'firestore_service.dart';
import 'key_vault.dart';
import 'sms_parser.dart';
import 'sms_service.dart';

/// Centralises SMS → transaction persistence so both the live listener and the
/// backfill use the SAME dedupe logic, and so backfill can run as a controlled,
/// progress-reported batch (instead of flooding the live stream and janking
/// the UI).
class SmsImportService {
  SmsImportService._();
  static final SmsImportService instance = SmsImportService._();

  /// Deterministic signature for a parsed SMS — fed to an HMAC for the
  /// opaque dedupe id. Must stay identical across live + backfill paths.
  String _raw(ParsedSms p) {
    final t = p.txn;
    return '${t.smsSender ?? "?"}|${(t.smsBody ?? "").length}|${t.amount}|'
        '${t.timestamp.year}${t.timestamp.month}${t.timestamp.day}'
        '${t.timestamp.hour}${t.timestamp.minute}';
  }

  /// Persist one parsed SMS (skips blocked senders + already-imported).
  /// Returns true if a new transaction was written.
  Future<bool> persistOne(String uid, ParsedSms p, Set<String> blocked) async {
    final sender = p.txn.smsSender;
    if (sender != null && blocked.contains(sender)) return false;
    final fs = FirestoreService.instance;
    final hash = await CryptoService.instance
        .dedupeTag(_raw(p), KeyVault.instance.dek ?? const []);
    if (await fs.alreadyImported(uid, hash)) return false;
    // Apply any learned merchant → category rule (doesn't affect the dedupe id).
    var txn = p.txn;
    final ruled = await CategoryRules.instance.categoryFor(txn.merchant);
    if (ruled != null && ruled != txn.categoryId) {
      txn = txn.copyWith(categoryId: ruled);
    }
    await fs.addTransaction(uid, txn);
    await fs.markImported(uid, hash);
    return true;
  }

  static const _lastSyncKey = 'last_sms_sync';

  /// Scan the inbox and persist matches in a yielding loop, reporting progress.
  ///
  /// When [incremental] is true (the default startup sync), it only scans
  /// messages received SINCE the last successful sync — so re-opening the app
  /// doesn't redundantly re-scan and re-check weeks of old SMS. A manual
  /// backfill passes incremental:false to force a full [days]-day rescan.
  Future<int> backfill(
    String uid, {
    required Set<String> blocked,
    int days = 90,
    bool incremental = false,
    void Function(int done, int total)? onProgress,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final fallback = DateTime.now().subtract(Duration(days: days));
    DateTime since = fallback;
    if (incremental) {
      final last = prefs.getInt(_lastSyncKey);
      if (last != null) {
        // small overlap so a message mid-write isn't missed; dedupe handles it
        since = DateTime.fromMillisecondsSinceEpoch(last)
            .subtract(const Duration(hours: 6));
      }
    }

    final parsed = await SmsService.instance.scanInbox(since: since);
    var saved = 0;
    for (var i = 0; i < parsed.length; i++) {
      onProgress?.call(i, parsed.length);
      if (await persistOne(uid, parsed[i], blocked)) saved++;
      if (i % 8 == 7) await Future<void>.delayed(Duration.zero); // keep UI alive
    }
    onProgress?.call(parsed.length, parsed.length);
    await prefs.setInt(_lastSyncKey, DateTime.now().millisecondsSinceEpoch);
    return saved;
  }
}
