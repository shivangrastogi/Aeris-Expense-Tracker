import 'dart:collection';

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

  // ── Fast local dedupe state (the "record pointer") ──────────
  // High-water mark: the newest SMS instant we've already processed. The
  // incremental scan starts just below this, so re-opening the app never
  // re-walks weeks of old SMS.
  static const _hwmKey = 'sms_hwm_ms';
  // Old key (pre-pointer). Used once to seed the high-water mark on upgrade.
  static const _legacyKey = 'last_sms_sync';
  // A bounded, on-device cache of dedupe hashes we've already imported. Lets us
  // skip an already-imported message WITHOUT a Firestore round-trip — Firestore
  // is only consulted on a cache miss (the cross-device source of truth).
  static const _recentKey = 'sms_recent_hashes';
  static const _recentCap = 1000;

  DateTime? _hwm;
  final LinkedHashSet<String> _recent = LinkedHashSet<String>();
  bool _loaded = false;

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    final p = await SharedPreferences.getInstance();
    final ms = p.getInt(_hwmKey) ?? p.getInt(_legacyKey); // seed from legacy once
    if (ms != null) _hwm = DateTime.fromMillisecondsSinceEpoch(ms);
    _recent
      ..clear()
      ..addAll(p.getStringList(_recentKey) ?? const []);
    _loaded = true;
  }

  void _remember(String hash) {
    _recent.add(hash);
    while (_recent.length > _recentCap) {
      _recent.remove(_recent.first); // drop oldest
    }
  }

  void _advanceHwm(DateTime when) {
    if (_hwm == null || when.isAfter(_hwm!)) _hwm = when;
  }

  Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    if (_hwm != null) await p.setInt(_hwmKey, _hwm!.millisecondsSinceEpoch);
    await p.setStringList(_recentKey, _recent.toList());
  }

  /// Deterministic signature for a parsed SMS — fed to an HMAC for the
  /// opaque dedupe id. Must stay identical across live + backfill paths.
  String _raw(ParsedSms p) {
    final t = p.txn;
    return '${t.smsSender ?? "?"}|${(t.smsBody ?? "").length}|${t.amount}|'
        '${t.timestamp.year}${t.timestamp.month}${t.timestamp.day}'
        '${t.timestamp.hour}${t.timestamp.minute}';
  }

  Future<String> _hashOf(ParsedSms p) =>
      CryptoService.instance.dedupeTag(_raw(p), KeyVault.instance.dek ?? const []);

  /// Persist one parsed SMS (skips blocked senders + already-imported).
  /// Returns true if a new transaction was written. Used by the live listener.
  Future<bool> persistOne(String uid, ParsedSms p, Set<String> blocked) async {
    await _ensureLoaded();
    final hash = await _hashOf(p);
    if (_recent.contains(hash)) return false; // already imported — no network
    final wrote = await _persistChecked(uid, p, hash, blocked);
    await _save();
    return wrote;
  }

  /// Persist a message whose dedupe [hash] is already computed and known to be
  /// absent from the local cache. Falls back to the Firestore ledger so dupes
  /// from another device are still caught.
  Future<bool> _persistChecked(
      String uid, ParsedSms p, String hash, Set<String> blocked) async {
    final sender = p.txn.smsSender;
    if (sender != null && blocked.contains(sender)) return false;
    final fs = FirestoreService.instance;
    if (await fs.alreadyImported(uid, hash)) {
      _remember(hash); // cache it so we never query Firestore for it again
      _advanceHwm(p.txn.timestamp);
      return false;
    }
    // Apply any learned merchant → category rule (doesn't affect the dedupe id).
    var txn = p.txn;
    final ruled = await CategoryRules.instance.categoryFor(txn.merchant);
    if (ruled != null && ruled != txn.categoryId) {
      txn = txn.copyWith(categoryId: ruled);
    }
    await fs.addTransaction(uid, txn);
    await fs.markImported(uid, hash);
    _remember(hash);
    _advanceHwm(p.txn.timestamp);
    return true;
  }

  /// Scan the inbox and persist matches in a yielding loop, reporting progress.
  ///
  /// When [incremental] is true (the default startup sync), it only scans
  /// messages received since the high-water mark — so re-opening the app
  /// doesn't redundantly re-scan weeks of old SMS — and any message already in
  /// the local dedupe cache is skipped with no Firestore read. Progress is
  /// reported over the genuinely-new messages only, so the import chip never
  /// appears when there's nothing new to bring in. A manual backfill passes
  /// incremental:false to force a full [days]-day rescan.
  Future<int> backfill(
    String uid, {
    required Set<String> blocked,
    int days = 90,
    bool incremental = false,
    void Function(int done, int total)? onProgress,
  }) async {
    await _ensureLoaded();
    final scanStart = DateTime.now();
    DateTime since = scanStart.subtract(Duration(days: days));
    if (incremental && _hwm != null) {
      // Start just below the pointer (small overlap absorbs clock skew / SMS
      // delivered with a slightly-past timestamp); the local cache makes
      // re-checking that overlap free.
      since = _hwm!.subtract(const Duration(hours: 2));
    }

    final parsed = await SmsService.instance.scanInbox(since: since);

    // Fast pass: drop everything we've already imported this install using the
    // local hash cache — no network. Only the leftovers ("fresh") need work.
    // Yield to the UI thread periodically so hashing a large inbox can't freeze
    // the dashboard (HMAC over hundreds of messages otherwise blocks a frame).
    final fresh = <({ParsedSms p, String hash})>[];
    for (var i = 0; i < parsed.length; i++) {
      final hash = await _hashOf(parsed[i]);
      if (!_recent.contains(hash)) fresh.add((p: parsed[i], hash: hash));
      if (i % 8 == 7) await Future<void>.delayed(Duration.zero);
    }

    var saved = 0;
    for (var i = 0; i < fresh.length; i++) {
      onProgress?.call(i, fresh.length);
      if (await _persistChecked(uid, fresh[i].p, fresh[i].hash, blocked)) saved++;
      if (i % 8 == 7) await Future<void>.delayed(Duration.zero); // keep UI alive
    }
    if (fresh.isNotEmpty) onProgress?.call(fresh.length, fresh.length);

    // Advance the pointer: every message up to scan time has now been examined.
    _advanceHwm(scanStart);
    await _save();
    return saved;
  }
}
