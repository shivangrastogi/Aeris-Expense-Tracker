import 'dart:collection';

import 'package:shared_preferences/shared_preferences.dart';

import '../core/routes.dart';
import '../models/split.dart';
import '../models/transaction.dart';
import '../utils/formatters.dart';
import 'card_dues.dart';
import 'category_rules.dart';
import 'crypto_service.dart';
import 'firestore_service.dart';
import 'key_vault.dart';
import 'ledger_links.dart';
import 'notification_service.dart';
import 'sms_parser.dart';
import 'sms_service.dart';
import 'sms_templates.dart';
import 'split_links.dart';

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
    final ms =
        p.getInt(_hwmKey) ?? p.getInt(_legacyKey); // seed from legacy once
    if (ms != null) _hwm = DateTime.fromMillisecondsSinceEpoch(ms);
    _recent
      ..clear()
      ..addAll(p.getStringList(_recentKey) ?? const []);
    _loaded = true;
  }

  /// Forget the in-memory pointer and hash cache (on sign-out; the prefs
  /// behind them are cleared by AuthService.signOut).
  void reset() {
    _hwm = null;
    _recent.clear();
    _loaded = false;
    _ledger = null;
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

  /// LEGACY signature — kept only so previously-imported messages are still
  /// recognised as duplicates (don't change it).
  String _raw(ParsedSms p) {
    final t = p.txn;
    return '${t.smsSender ?? "?"}|${(t.smsBody ?? "").length}|${t.amount}|'
        '${t.timestamp.year}${t.timestamp.month}${t.timestamp.day}'
        '${t.timestamp.hour}${t.timestamp.minute}';
  }

  /// Current signature. When a reference/UTR is present it's the strongest
  /// unique key — using it stops distinct same-amount templated alerts (e.g.
  /// several ₹20 Amazon Pay wallet debits) from colliding into one dedupe id
  /// and being dropped. Falls back to the legacy signature when there's no ref.
  String _raw2(ParsedSms p) {
    final t = p.txn;
    final ref = (t.reference ?? '').trim();
    if (ref.isNotEmpty) return '${t.smsSender ?? "?"}|${t.amount}|$ref';
    return _raw(p);
  }

  /// Parse-independent signature: the message itself (sender + text + day),
  /// not what the parser made of it. v2/legacy include the parsed amount, so
  /// a parser fix (₹85,610 → ₹200) would make an already-imported SMS look
  /// new; this one stays the same across parser versions.
  String _raw3(Transaction t) {
    final body = (t.smsBody ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
    final d = t.timestamp;
    return 'v3|${t.smsSender ?? "?"}|$body|${d.year}-${d.month}-${d.day}';
  }

  Future<String> _tag(String raw) =>
      CryptoService.instance.dedupeTag(raw, KeyVault.instance.dek ?? const []);

  Future<String> _hashOf(ParsedSms p) => _tag(_raw2(p));
  Future<String> _hash3Of(Transaction t) => _tag(_raw3(t));

  /// Persist one parsed SMS (skips blocked senders + already-imported).
  /// Returns true if a new transaction was written. Used by the live listener.
  Future<bool> persistOne(String uid, ParsedSms p, Set<String> blocked) async {
    await _ensureLoaded();
    _ledger = null; // a live message must see the user's latest edits
    p = await SmsTemplates.instance.apply(p);
    final hash = await _hashOf(p);
    final hash3 = await _hash3Of(p.txn);
    // Already imported — no network.
    if (_recent.contains(hash) || _recent.contains(hash3)) return false;
    final wrote = await _persistChecked(uid, p, hash, hash3, blocked);
    await _save();
    return wrote;
  }

  /// Persist a message whose dedupe hashes are already computed and known to
  /// be absent from the local cache. Falls back to the Firestore ledger so
  /// dupes from another device are still caught.
  Future<bool> _persistChecked(String uid, ParsedSms p, String hash,
      String hash3, Set<String> blocked) async {
    final sender = p.txn.smsSender;
    if (sender != null && blocked.contains(sender)) return false;
    final fs = FirestoreService.instance;
    // Check the current hashes AND the legacy hash, so messages imported
    // before a dedupe change aren't re-imported as duplicates.
    final legacy = await _tag(_raw(p));
    if (await fs.alreadyImported(uid, hash3) ||
        await fs.alreadyImported(uid, hash) ||
        (legacy != hash && await fs.alreadyImported(uid, legacy))) {
      // Cache them so we never query Firestore for this message again.
      _remember(hash);
      _remember(hash3);
      _advanceHwm(p.txn.timestamp);
      return false;
    }
    // Apply any learned merchant → category rule (doesn't affect the dedupe id).
    var txn = p.txn.copyWith(balance: p.balance);
    final ruled = await CategoryRules.instance.categoryFor(txn.merchant);
    if (ruled != null && ruled != txn.categoryId) {
      txn = txn.copyWith(categoryId: ruled);
    }
    Future<void> markSeen() async {
      await fs.markImported(uid, hash);
      await fs.markImported(uid, hash3);
      _remember(hash);
      _remember(hash3);
      _advanceHwm(p.txn.timestamp);
    }

    final ledger = await _ledgerFor(uid, txn.timestamp);
    // The same payment already came in from another sender (bank SMS + UPI
    // app): fold anything new it says into the saved one, don't add a second.
    final dup = LedgerLinks.duplicateOf(txn, ledger);
    if (dup != null) {
      final current = await fs.fetchTransaction(uid, dup.id) ?? dup;
      var merged = LedgerLinks.enrich(current, txn);
      // The second report may name the payer the first didn't ("Received
      // ₹4,000 from Rahul" after an anonymous bank credit): try again to
      // recognise it as a share being paid back.
      if (!merged.isSettlement && !current.isSettlement) {
        final hit = SplitLinks.paybackTarget(merged, ledger, _groups);
        if (hit != null) {
          final name = hit.$1.split!.shares[hit.$2].name;
          final bill = await fs.fetchTransaction(uid, hit.$1.id) ?? hit.$1;
          final i = bill.split?.shares.indexWhere((s) => s.name == name) ?? -1;
          if (i >= 0) {
            final paid = SplitLinks.receive(bill, i, merged.amount);
            await fs.updateTransaction(uid, paid);
            _replaceInLedger(paid);
            merged = SplitLinks.markPayback(merged, bill, i);
          }
        }
      }
      await fs.updateTransaction(uid, merged);
      _replaceInLedger(merged);
      await markSeen();
      return false;
    }
    final partner = LedgerLinks.transferPartner(txn, ledger);
    if (partner != null) {
      final current = await fs.fetchTransaction(uid, partner.id) ?? partner;
      final (mine, theirs) = LedgerLinks.pairTransfer(txn, current);
      txn = mine;
      await fs.updateTransaction(uid, theirs);
      _replaceInLedger(theirs);
    } else if (txn.isRefund) {
      final bought = LedgerLinks.refundedPurchase(txn, ledger);
      if (bought != null) txn = txn.copyWith(linkId: bought.id);
    } else if (txn.isDebit) {
      // A payee the user always splits (rent to the landlord): split it.
      final g = SplitLinks.autoGroupFor(txn, _groups);
      if (g != null) {
        txn = txn.copyWith(split: SplitLinks.shareOut(g, txn.amount));
      }
    } else {
      // A roommate paying back their share: settle it, not income.
      final hit = SplitLinks.paybackTarget(txn, ledger, _groups);
      if (hit != null) {
        final name = hit.$1.split!.shares[hit.$2].name;
        final bill = await fs.fetchTransaction(uid, hit.$1.id) ?? hit.$1;
        final i = bill.split?.shares.indexWhere((s) => s.name == name) ?? -1;
        if (i >= 0) {
          final paid = SplitLinks.receive(bill, i, txn.amount);
          await fs.updateTransaction(uid, paid);
          _replaceInLedger(paid);
          txn = SplitLinks.markPayback(txn, bill, i);
          final group =
              _groups.where((g) => g.id == bill.split!.groupId).firstOrNull;
          if (group != null) {
            final learned = SplitLinks.learnHandle(group, name, txn);
            if (!identical(learned, group)) {
              await fs.setSplitGroup(uid, learned);
              _groups = [
                for (final g in _groups) g.id == learned.id ? learned : g
              ];
            }
          }
        }
      }
    }
    // A confident read (amount bound to a verb, account + payee found, a real
    // category) is saved as confirmed — only doubtful ones wait for review.
    if (!txn.reviewed && await autoConfirmOn() && isConfident(p, txn)) {
      txn = txn.copyWith(reviewed: true);
    }
    await fs.addTransaction(uid, txn);
    _ledger?.add(txn);
    await markSeen();
    await _afterSave(txn);
    return true;
  }

  // ── Recent ledger (for duplicate / transfer / refund linking) ──────────
  List<Transaction>? _ledger;
  DateTime? _ledgerFrom;

  /// The user's split groups, loaded with the ledger.
  List<SplitGroup> _groups = const [];

  /// Saved transactions from 90 days before [around] onwards (and the split
  /// groups). Cached for one backfill run; a live message reloads them so
  /// user edits are seen.
  Future<List<Transaction>> _ledgerFor(String uid, DateTime around) async {
    final from = around.subtract(const Duration(days: 90));
    if (_ledger == null || _ledgerFrom!.isAfter(from)) {
      final fs = FirestoreService.instance;
      _ledger = await fs.fetchTransactions(uid, since: from);
      _ledgerFrom = from;
      try {
        _groups = await fs.fetchSplitGroups(uid);
      } catch (_) {
        _groups = const [];
      }
    }
    return _ledger!;
  }

  void _replaceInLedger(Transaction t) {
    final l = _ledger;
    if (l == null) return;
    final i = l.indexWhere((x) => x.id == t.id);
    if (i >= 0) l[i] = t;
  }

  /// Side effects of a new transaction: a card-bill payment closes that
  /// card's due; a low balance raises an alert.
  Future<void> _afterSave(Transaction t) async {
    final body = t.smsBody;
    if (body != null && SmsParser.isCardPayment(body)) {
      await CardDues.instance.markPaid(
          last4: t.isCredit ? t.account : null,
          amount: t.amount,
          when: t.timestamp);
    }
    await _maybeAlertLowBalance(t);
    await _maybeAskReview(t);
  }

  static const lowBalanceKey = 'low_balance_alert';
  static const autoConfirmKey = 'auto_confirm_imports';

  /// Whether confident imports skip the review queue (Settings; default on).
  static Future<bool> autoConfirmOn() async =>
      (await SharedPreferences.getInstance()).getBool(autoConfirmKey) ?? true;

  /// Sure enough to skip review: a high parser score and a real category.
  static bool isConfident(ParsedSms p, Transaction t) =>
      p.confidence >= 0.85 && t.categoryId != 'other';

  Future<void> _maybeAlertLowBalance(Transaction t) async {
    final bal = t.balance;
    if (bal == null || t.account == null) return;
    // Only for news: a backfill of old SMS must not ring.
    if (DateTime.now().difference(t.timestamp) > const Duration(hours: 24)) {
      return;
    }
    final limit = (await SharedPreferences.getInstance()).getInt(lowBalanceKey);
    if (limit == null || limit <= 0 || bal >= limit) return;
    await NotificationService.instance.showNow(
      3100 + (t.account.hashCode.abs() % 50),
      'Low balance on A/C ••${t.account}',
      'Only ${formatRupees(bal, decimals: true)} left after '
          '${t.isDebit ? 'spending' : 'receiving'} '
          '${formatRupees(t.amount, decimals: true)}.',
      route: AppRoutes.accounts,
      actions: const [('See accounts', AppRoutes.accounts)],
    );
  }

  /// A fresh bank SMS that AERIS wasn't sure about: "Check this payment"
  /// with a Review button (SMS → notification → review → detail).
  Future<void> _maybeAskReview(Transaction t) async {
    if (!t.needsReview) return;
    // Only for news: a backfill of old SMS must not ring.
    if (DateTime.now().difference(t.timestamp) > const Duration(hours: 2)) {
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    if (!(prefs.getBool('reminders_on') ?? false)) return;
    if (!(prefs.getBool('notif_review') ?? true)) return;
    final who = t.merchant ?? (t.isCredit ? 'Money in' : 'A payment');
    // The salary lock covers notifications too.
    final salary = t.isCredit && t.categoryId == 'salary';
    final amount = salary && (prefs.getBool('income_locked') ?? false)
        ? 'amount hidden'
        : formatRupees(t.amount);
    await NotificationService.instance.showNow(
      3200 + (t.id.hashCode.abs() % 100),
      'Check this payment',
      '$who · $amount — AERIS wasn\'t sure of the category.',
      route: AppRoutes.smsReview,
      actions: const [('Review', AppRoutes.smsReview)],
    );
  }

  /// Bump when the parser improves enough that old imports should be re-read.
  static const _reparseVersion = 3;
  static const _reparseKey = 'sms_reparse_version';

  /// One-time repair after a parser upgrade, over every imported transaction:
  ///  * re-read the SMS behind each one the user hasn't confirmed and fix
  ///    amount / type / category / payee where the new parser disagrees;
  ///  * fill in the bank balance the SMS printed (any transaction);
  ///  * merge duplicates (one payment imported twice — unconfirmed copies
  ///    only), pair transfers between your own accounts, link refunds;
  ///  * pick up card statements from the last 45 days of SMS;
  ///  * stamp every SMS transaction with the parse-independent dedupe key, so
  ///    a later full rescan can't re-import a message that now parses
  ///    differently.
  /// Confirmed transactions keep their amount, type and category.
  Future<({int fixed, int merged, int transfers})> repairImported(
      String uid) async {
    const none = (fixed: 0, merged: 0, transfers: 0);
    final prefs = await SharedPreferences.getInstance();
    if ((prefs.getInt(_reparseKey) ?? 0) >= _reparseVersion) return none;
    await _ensureLoaded();
    final fs = FirestoreService.instance;
    final all = await fs.fetchTransactions(uid,
        // Covers the longest backfill range Settings allows (5 years).
        since: DateTime.now().subtract(const Duration(days: 1830)));
    final byId = {for (final t in all) t.id: t};
    final changed = <String>{};
    var fixed = 0;
    for (var i = 0; i < all.length; i++) {
      final old = all[i];
      final body = old.smsBody;
      if (old.source != TxnSource.sms || body == null) continue;
      final hash3 = await _hash3Of(old);
      if (!_recent.contains(hash3)) {
        await fs.markImported(uid, hash3);
        _remember(hash3);
      }
      if (i % 8 == 7) await Future<void>.delayed(Duration.zero);
      final parsed = SmsParser.parse(
          sender: old.smsSender ?? '', body: body, receivedAt: old.timestamp);
      if (parsed == null) continue;
      var t = old;
      if (t.balance == null && parsed.balance != null) {
        t = t.copyWith(balance: parsed.balance);
      }
      if (!old.reviewed) {
        final fresh = (await SmsTemplates.instance.apply(parsed)).txn;
        final merchant = old.merchant ?? fresh.merchant;
        final category = await CategoryRules.instance.categoryFor(merchant) ??
            fresh.categoryId;
        if (fresh.amount != old.amount ||
            fresh.direction != old.direction ||
            category != old.categoryId ||
            merchant != old.merchant) {
          t = t.copyWith(
            amount: fresh.amount,
            direction: fresh.direction,
            categoryId: category,
            merchant: merchant,
          );
          // The corrected parse has its own v2 key; record it too.
          final hash = await _hashOf(parsed.withTxn(t));
          await fs.markImported(uid, hash);
          _remember(hash);
          fixed++;
        }
      }
      if (!identical(t, old)) {
        byId[t.id] = t;
        changed.add(t.id);
      }
    }

    // Link in time order, each transaction against the ones before it.
    final sorted = byId.values.toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    final seen = <Transaction>[];
    final deleted = <String>{};
    var merged = 0, transfers = 0;
    void replace(Transaction t) {
      byId[t.id] = t;
      changed.add(t.id);
      final i = seen.indexWhere((x) => x.id == t.id);
      if (i >= 0) seen[i] = t;
    }

    for (final t0 in sorted) {
      var t = byId[t0.id]!;
      if (t.selfTransfer || t.linkId != null) {
        seen.add(t);
        continue;
      }
      final dup = LedgerLinks.duplicateOf(t, seen);
      if (dup != null && !t.reviewed) {
        replace(LedgerLinks.enrich(byId[dup.id]!, t));
        deleted.add(t.id);
        changed.remove(t.id);
        merged++;
        continue;
      }
      final partner = LedgerLinks.transferPartner(t, seen);
      if (partner != null) {
        final (mine, theirs) = LedgerLinks.pairTransfer(t, byId[partner.id]!);
        t = mine;
        replace(theirs);
        byId[t.id] = t;
        changed.add(t.id);
        transfers++;
      } else if (t.isRefund) {
        final bought = LedgerLinks.refundedPurchase(t, seen);
        if (bought != null) {
          t = t.copyWith(linkId: bought.id);
          byId[t.id] = t;
          changed.add(t.id);
        }
      }
      seen.add(t);
    }

    for (final id in changed) {
      await fs.updateTransaction(uid, byId[id]!);
    }
    for (final id in deleted) {
      await fs.deleteTransaction(uid, id);
    }
    // Statements were never imported (they aren't transactions); read the
    // recent ones so current card dues show up straight away.
    try {
      final scan = await SmsService.instance
          .scanInbox(since: DateTime.now().subtract(const Duration(days: 45)));
      for (final s in scan.statements) {
        await CardDues.instance.record(s);
      }
    } catch (_) {}
    await _save();
    await prefs.setInt(_reparseKey, _reparseVersion);
    return (fixed: fixed, merged: merged, transfers: transfers);
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

    final scan = await SmsService.instance.scanInbox(since: since);
    for (final s in scan.statements) {
      await CardDues.instance.record(s);
    }
    // Oldest first, so a refund is linked to a purchase that's already saved.
    final parsed = scan.txns.reversed.toList();
    _ledger = null; // fresh view of the ledger for this run

    // Fast pass: drop everything we've already imported this install using the
    // local hash cache — no network. Only the leftovers ("fresh") need work.
    // Yield to the UI thread periodically so hashing a large inbox can't freeze
    // the dashboard (HMAC over hundreds of messages otherwise blocks a frame).
    final fresh = <({ParsedSms p, String hash, String hash3})>[];
    for (var i = 0; i < parsed.length; i++) {
      final p = await SmsTemplates.instance.apply(parsed[i]);
      final hash = await _hashOf(p);
      final hash3 = await _hash3Of(p.txn);
      if (!_recent.contains(hash) && !_recent.contains(hash3)) {
        fresh.add((p: p, hash: hash, hash3: hash3));
      }
      if (i % 8 == 7) await Future<void>.delayed(Duration.zero);
    }

    var saved = 0;
    for (var i = 0; i < fresh.length; i++) {
      onProgress?.call(i, fresh.length);
      final f = fresh[i];
      if (await _persistChecked(uid, f.p, f.hash, f.hash3, blocked)) {
        saved++;
      }
      if (i % 8 == 7) {
        await Future<void>.delayed(Duration.zero); // keep UI alive
      }
    }
    if (fresh.isNotEmpty) onProgress?.call(fresh.length, fresh.length);

    // Advance the pointer: every message up to scan time has now been examined.
    _advanceHwm(scanStart);
    await _save();
    return saved;
  }
}
