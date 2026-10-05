import 'dart:isolate';

import 'package:cloud_firestore/cloud_firestore.dart' hide Transaction;

import '../models/budget.dart';
import '../models/goal.dart';
import '../models/loan.dart';
import '../models/subscription.dart';
import '../models/transaction.dart';
import 'crypto_service.dart';
import 'key_vault.dart';
import 'sync_outbox.dart';

/// Per-user Firestore data layer. Layout:
///   users/{uid}                       — UserProfile
///     transactions/{txnId}            — Transaction
///     budgets/{categoryId}            — Budget (doc id == categoryId)
///     processed_sms/{smsHash}         — dedupe ledger for SMS imports
class FirestoreService {
  FirestoreService._();
  static final FirestoreService instance = FirestoreService._();

  final _db = FirebaseFirestore.instance;

  /// Every user-data write goes through the outbox: tracked + size-bounded
  /// while offline, and never blocks the caller waiting for a server ack.
  SyncOutbox get _out => SyncOutbox.instance;

  // Cache of decrypted transactions keyed by doc id → (encBlob, txn). Firestore
  // re-emits the whole query on any single change; without this we'd re-decrypt
  // every row each time. The enc blob is immutable per doc version, so a match
  // means the cached decryption is still valid.
  final Map<String, ({String enc, Transaction txn})> _txCache = {};

  CollectionReference<Map<String, dynamic>> _txCol(String uid) =>
      _db.collection('users').doc(uid).collection('transactions');
  CollectionReference<Map<String, dynamic>> _budgetCol(String uid) =>
      _db.collection('users').doc(uid).collection('budgets');
  CollectionReference<Map<String, dynamic>> _processedCol(String uid) =>
      _db.collection('users').doc(uid).collection('processed_sms');
  CollectionReference<Map<String, dynamic>> _blockedCol(String uid) =>
      _db.collection('users').doc(uid).collection('blocked_senders');
  DocumentReference<Map<String, dynamic>> _gamDoc(String uid) =>
      _db.collection('users').doc(uid).collection('meta').doc('gamification');

  // ─ Gamification (streak / aura) cloud backup ───────────────
  // Not encrypted on purpose: it's non-sensitive (streak counts, award keys)
  // and must be restorable on a fresh install BEFORE the vault is unlocked.

  Future<Map<String, dynamic>?> fetchGamification(String uid) async =>
      (await _gamDoc(uid).get()).data();

  Future<void> saveGamification(String uid, Map<String, dynamic> data) =>
      _out.set(
        _gamDoc(uid),
        {...data, 'updatedAt': SyncOutbox.serverTimestamp},
        merge: true,
      );

  // ─ Daily usage tracking ────────────────────────────────────
  // One small doc per active day at users/{uid}/usage/{yyyy-MM-dd}. Uses
  // FieldValue.increment so it's atomic + offline-safe, and is cheap to query
  // by date range (active-day streaks, monthly heatmaps, retention).

  CollectionReference<Map<String, dynamic>> _usageCol(String uid) =>
      _db.collection('users').doc(uid).collection('usage');

  /// Records one app-open for [day] (local date, format yyyy-MM-dd).
  Future<void> recordDailyUsage(String uid, String day) =>
      _usageCol(uid).doc(day).set({
        'date': day,
        'opens': FieldValue.increment(1),
        'lastActive': FieldValue.serverTimestamp(),
        'firstOpen': FieldValue.serverTimestamp(), // only sticks on create
      }, SetOptions(merge: true));

  /// Active-day docs in a date range (inclusive), for streaks / heatmaps.
  Future<List<Map<String, dynamic>>> fetchUsage(
      String uid, String fromDay, String toDay) async {
    final snap = await _usageCol(uid)
        .where('date', isGreaterThanOrEqualTo: fromDay)
        .where('date', isLessThanOrEqualTo: toDay)
        .get();
    return snap.docs.map((d) => d.data()).toList();
  }

  // ─ Transactions ────────────────────────────────────────────

  Stream<List<Transaction>> watchTransactions(String uid, {int? limit}) {
    Query<Map<String, dynamic>> q =
        _txCol(uid).orderBy('timestamp', descending: true);
    if (limit != null) q = q.limit(limit);
    return q.snapshots().asyncMap((s) => _decodeAll(s.docs));
  }

  /// Decode a whole snapshot, reusing the per-doc cache and offloading any
  /// uncached AES-GCM work to a background isolate so the UI never blocks while
  /// the dashboard first loads.
  Future<List<Transaction>> _decodeAll(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) async {
    final dek = KeyVault.instance.dek;
    final results = List<Transaction?>.filled(docs.length, null);
    final pendingIdx = <int>[];
    final pendingBlobs = <String>[];

    for (var i = 0; i < docs.length; i++) {
      final data = docs[i].data();
      final enc = data['enc'];
      if (enc is String && dek != null) {
        final cached = _txCache[docs[i].id];
        if (cached != null && cached.enc == enc) {
          results[i] = cached.txn; // reuse — no re-decrypt
        } else {
          pendingIdx.add(i);
          pendingBlobs.add(enc);
        }
      } else {
        results[i] = Transaction.fromMap(docs[i].id, data); // legacy plaintext
      }
    }

    if (pendingBlobs.isNotEmpty && dek != null) {
      // Big first load → decrypt in an isolate; a couple of new docs → inline
      // (avoids isolate spawn overhead on live updates).
      final maps = pendingBlobs.length >= 12
          ? await Isolate.run(() => _decryptBlobs(pendingBlobs, dek))
          : await _decryptBlobs(pendingBlobs, dek);
      for (var j = 0; j < pendingIdx.length; j++) {
        final i = pendingIdx[j];
        final m = maps[j];
        if (m == null) {
          results[i] = Transaction.fromMap(docs[i].id, docs[i].data());
          continue;
        }
        m['timestamp'] = Timestamp.fromMillisecondsSinceEpoch(
            (m['timestamp'] as num).toInt());
        final txn = Transaction.fromMap(docs[i].id, m);
        _txCache[docs[i].id] = (enc: pendingBlobs[j], txn: txn);
        results[i] = txn;
      }
    }
    return [
      for (final t in results)
        if (t != null) t
    ];
  }

  Future<List<Transaction>> fetchTransactions(String uid,
      {DateTime? since, int? limit}) async {
    Query<Map<String, dynamic>> q =
        _txCol(uid).orderBy('timestamp', descending: true);
    if (since != null) {
      q = q.where('timestamp',
          isGreaterThanOrEqualTo: Timestamp.fromDate(since));
    }
    if (limit != null) q = q.limit(limit);
    final snap = await q.get();
    final out = <Transaction>[];
    for (final d in snap.docs) {
      out.add(await _decodeTxn(d.id, d.data()));
    }
    return out;
  }

  Future<void> addTransaction(String uid, Transaction t) async {
    await _out.set(_txCol(uid).doc(t.id), await _encodeTxn(t));
  }

  Future<void> updateTransaction(String uid, Transaction t) async {
    // Full rewrite — an encrypted blob can't be partially merged.
    await _out.set(_txCol(uid).doc(t.id), await _encodeTxn(t));
  }

  Future<void> deleteTransaction(String uid, String id) async {
    await _out.delete(_txCol(uid).doc(id));
  }

  // ─ Receipt photos (encrypted, one doc per transaction) ─────
  // Stored in Firestore rather than Storage so they ride the same offline
  // outbox + E2E encryption. Images are downscaled before this (≈100–250 KB),
  // well under Firestore's 1 MiB doc limit.

  DocumentReference<Map<String, dynamic>> _receiptDoc(
          String uid, String txnId) =>
      _db.collection('users').doc(uid).collection('receipts').doc(txnId);

  Future<void> setReceipt(String uid, String txnId, List<int> jpeg) async {
    final dek = KeyVault.instance.dek;
    if (dek == null) throw StateError('Vault is locked');
    await _out.set(_receiptDoc(uid, txnId), {
      'enc': await CryptoService.instance.encryptBytes(jpeg, dek),
      'v': 1,
    });
  }

  /// Decrypted JPEG bytes, or null if there's no receipt (or it can't be read
  /// yet — e.g. offline and never cached on this device).
  Future<List<int>?> fetchReceipt(String uid, String txnId) async {
    final dek = KeyVault.instance.dek;
    if (dek == null) return null;
    DocumentSnapshot<Map<String, dynamic>> snap;
    try {
      snap = await _receiptDoc(uid, txnId).get();
    } catch (_) {
      try {
        snap = await _receiptDoc(uid, txnId)
            .get(const GetOptions(source: Source.cache));
      } catch (_) {
        return null;
      }
    }
    final enc = snap.data()?['enc'];
    if (enc is! String) return null;
    return CryptoService.instance.decryptBytes(enc, dek);
  }

  Future<void> deleteReceipt(String uid, String txnId) =>
      _out.delete(_receiptDoc(uid, txnId));

  // ─ Transaction encryption (envelope, AES-256-GCM) ──────────
  // Stored doc shape: { timestamp (plaintext, for ordering), enc (blob), v }.
  // The blob holds every sensitive field — amount, merchant, SMS text, etc.

  /// The data key, or throws: personal data is never written in the clear.
  /// (Callers already surface save errors; the Key Gate keeps the vault
  /// unlocked during normal use, so this only trips on a real fault.)
  List<int> _requireDek() {
    final dek = KeyVault.instance.dek;
    if (dek == null) {
      throw StateError('Your data is locked. Unlock the app and try again.');
    }
    return dek;
  }

  Future<Map<String, dynamic>> _encodeTxn(Transaction t) async {
    final dek = _requireDek();
    final json = t.toMap();
    json['timestamp'] = t.timestamp.millisecondsSinceEpoch; // JSON-safe
    return {
      'timestamp': Timestamp.fromDate(t.timestamp),
      'enc': await CryptoService.instance.encryptJson(json, dek),
      'v': 1,
    };
  }

  Future<Transaction> _decodeTxn(String id, Map<String, dynamic> doc) async {
    final dek = KeyVault.instance.dek;
    final enc = doc['enc'];
    if (enc is String && dek != null) {
      final cached = _txCache[id];
      if (cached != null && cached.enc == enc) return cached.txn; // reuse
      final m = await CryptoService.instance.decryptJson(enc, dek);
      m['timestamp'] =
          Timestamp.fromMillisecondsSinceEpoch(m['timestamp'] as int);
      final txn = Transaction.fromMap(id, m);
      _txCache[id] = (enc: enc, txn: txn);
      return txn;
    }
    // Legacy plaintext doc (created before encryption) — read as-is.
    return Transaction.fromMap(id, doc);
  }

  // ─ Budgets ─────────────────────────────────────────────────

  Stream<List<Budget>> watchBudgets(String uid) =>
      _budgetCol(uid).snapshots().asyncMap((s) async {
        final out = <Budget>[];
        for (final d in s.docs) {
          out.add(await _decodeBudget(d.id, d.data()));
        }
        return out;
      });

  Future<void> setBudget(String uid, Budget b) async {
    // Doc id == categoryId so each category has exactly one budget.
    await _out.set(_budgetCol(uid).doc(b.categoryId), await _encodeBudget(b));
  }

  Future<void> deleteBudget(String uid, String categoryId) =>
      _out.delete(_budgetCol(uid).doc(categoryId));

  // The monthly cap is encrypted; the doc id (categoryId) is just a label.
  Future<Map<String, dynamic>> _encodeBudget(Budget b) async {
    final dek = _requireDek();
    return {
      'categoryId': b.categoryId,
      'enc': await CryptoService.instance.encryptJson({
        'monthlyCap': b.monthlyCap,
        'updatedAt': b.updatedAt.millisecondsSinceEpoch,
      }, dek),
      'v': 1,
    };
  }

  Future<Budget> _decodeBudget(String id, Map<String, dynamic> doc) async {
    final dek = KeyVault.instance.dek;
    final enc = doc['enc'];
    if (enc is String && dek != null) {
      final m = await CryptoService.instance.decryptJson(enc, dek);
      return Budget(
        id: id,
        categoryId: (doc['categoryId'] as String?) ?? id,
        monthlyCap: (m['monthlyCap'] as num?)?.toDouble() ?? 0,
        updatedAt: m['updatedAt'] == null
            ? DateTime.now()
            : DateTime.fromMillisecondsSinceEpoch(
                (m['updatedAt'] as num).toInt()),
      );
    }
    return Budget.fromMap(id, doc);
  }

  // ─ SMS dedupe ──────────────────────────────────────────────

  Future<bool> alreadyImported(String uid, String smsHash) async {
    final doc = await _processedCol(uid).doc(smsHash).get();
    return doc.exists;
  }

  Future<void> markImported(String uid, String smsHash) => _out
      .set(_processedCol(uid).doc(smsHash), {'at': SyncOutbox.serverTimestamp});

  // ─ Blocked senders ─────────────────────────────────────────
  // Senders the user has flagged as junk. Future SMS from them are never
  // imported. Doc id is a sanitised key; the raw value lives in 'sender'.

  static String _senderKey(String sender) =>
      sender.trim().toUpperCase().replaceAll(RegExp(r'[\/\.\#\$\[\]]'), '_');

  Stream<Set<String>> watchBlockedSenders(String uid) =>
      _blockedCol(uid).snapshots().map((s) =>
          s.docs.map((d) => (d.data()['sender'] as String?) ?? d.id).toSet());

  Future<void> blockSender(String uid, String sender) =>
      _out.set(_blockedCol(uid).doc(_senderKey(sender)), {
        'sender': sender,
        'at': SyncOutbox.serverTimestamp,
      });

  Future<void> unblockSender(String uid, String sender) =>
      _out.delete(_blockedCol(uid).doc(_senderKey(sender)));

  // ─ E2E key material ────────────────────────────────────────
  // Stores ONLY wrapped (encrypted) keys + salt — never the raw data key.

  DocumentReference<Map<String, dynamic>> _keysDoc(String uid) =>
      _db.collection('users').doc(uid).collection('security').doc('keys');

  Future<Map<String, dynamic>?> fetchKeys(String uid) async =>
      (await _keysDoc(uid).get()).data();

  Future<void> saveKeys(String uid, Map<String, dynamic> data) =>
      _keysDoc(uid).set(data);

  // ─ Opening balances (encrypted) ────────────────────────────
  // Per-account opening balance so we can show a TRUE running balance
  // (opening + cumulative net). Stored as one encrypted {key: amount} map.
  DocumentReference<Map<String, dynamic>> _balancesDoc(String uid) =>
      _db.collection('users').doc(uid).collection('meta').doc('balances');

  Map<String, double> _decodeBalances(Map<String, dynamic>? m) {
    final raw = (m?['balances'] as Map?) ?? const {};
    return raw.map((k, v) => MapEntry(k.toString(), (v as num).toDouble()));
  }

  Stream<Map<String, double>> watchOpeningBalances(String uid) =>
      _balancesDoc(uid).snapshots().asyncMap((d) async {
        final dek = KeyVault.instance.dek;
        final enc = d.data()?['enc'];
        if (enc is String && dek != null) {
          try {
            return _decodeBalances(
                await CryptoService.instance.decryptJson(enc, dek));
          } catch (_) {/* fall through */}
        }
        return <String, double>{};
      });

  Future<void> setOpeningBalance(
      String uid, String accountKey, double amount) async {
    final dek = _requireDek();
    final snap = await _balancesDoc(uid).get();
    final current = <String, double>{};
    final enc = snap.data()?['enc'];
    if (enc is String) {
      try {
        current.addAll(_decodeBalances(
            await CryptoService.instance.decryptJson(enc, dek)));
      } catch (_) {/* start fresh */}
    }
    current[accountKey] = amount;
    await _out.set(_balancesDoc(uid), {
      'enc':
          await CryptoService.instance.encryptJson({'balances': current}, dek),
      'v': 1,
    });
  }

  /// Re-encrypt any plaintext transactions/budgets left from before E2E was
  /// enabled. Idempotent — docs already carrying an `enc` blob are skipped.
  /// Requires the vault to be unlocked.
  Future<void> migrateToEncrypted(String uid) async {
    final tx = await _txCol(uid).get();
    for (final d in tx.docs) {
      if (d.data()['enc'] is String) continue;
      await _out.set(_txCol(uid).doc(d.id),
          await _encodeTxn(Transaction.fromMap(d.id, d.data())));
    }
    final bg = await _budgetCol(uid).get();
    for (final d in bg.docs) {
      if (d.data()['enc'] is String) continue;
      await setBudget(uid, Budget.fromMap(d.id, d.data()));
    }
  }

  // ─ Goals (encrypted like transactions) ─────────────────────

  CollectionReference<Map<String, dynamic>> _goalsCol(String uid) =>
      _db.collection('users').doc(uid).collection('goals');

  Stream<List<Goal>> watchGoals(String uid) {
    return _goalsCol(uid)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .asyncMap((s) async {
      final out = <Goal>[];
      for (final d in s.docs) {
        final dek = KeyVault.instance.dek;
        final enc = d.data()['enc'];
        if (enc is String && dek != null) {
          out.add(Goal.fromMap(
              d.id, await CryptoService.instance.decryptJson(enc, dek)));
        } else {
          out.add(Goal.fromMap(d.id, d.data()));
        }
      }
      return out;
    });
  }

  Future<void> setGoal(String uid, Goal g) async {
    final dek = _requireDek();
    final doc = {
      'createdAt': Timestamp.fromDate(g.createdAt),
      'enc': await CryptoService.instance.encryptJson(g.toMap(), dek),
      'v': 1,
    };
    await _out.set(_goalsCol(uid).doc(g.id), doc);
  }

  Future<void> deleteGoal(String uid, String id) =>
      _out.delete(_goalsCol(uid).doc(id));

  // ─ Loans / money lent to friends (encrypted like goals) ─────

  CollectionReference<Map<String, dynamic>> _loansCol(String uid) =>
      _db.collection('users').doc(uid).collection('loans');

  Stream<List<Loan>> watchLoans(String uid) {
    return _loansCol(uid)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .asyncMap((s) async {
      final out = <Loan>[];
      for (final d in s.docs) {
        final dek = KeyVault.instance.dek;
        final enc = d.data()['enc'];
        if (enc is String && dek != null) {
          out.add(Loan.fromMap(
              d.id, await CryptoService.instance.decryptJson(enc, dek)));
        } else {
          out.add(Loan.fromMap(d.id, d.data()));
        }
      }
      return out;
    });
  }

  Future<void> setLoan(String uid, Loan l) async {
    final dek = _requireDek();
    final doc = {
      'createdAt': Timestamp.fromDate(l.createdAt),
      'enc': await CryptoService.instance.encryptJson(l.toMap(), dek),
      'v': 1,
    };
    await _out.set(_loansCol(uid).doc(l.id), doc);
  }

  Future<void> deleteLoan(String uid, String id) =>
      _out.delete(_loansCol(uid).doc(id));

  // ─ Subscriptions / recurring bills (encrypted like loans) ───

  CollectionReference<Map<String, dynamic>> _subsCol(String uid) =>
      _db.collection('users').doc(uid).collection('subscriptions');

  Stream<List<Subscription>> watchSubscriptions(String uid) {
    return _subsCol(uid).snapshots().asyncMap((s) async {
      final out = <Subscription>[];
      for (final d in s.docs) {
        final dek = KeyVault.instance.dek;
        final enc = d.data()['enc'];
        if (enc is String && dek != null) {
          out.add(Subscription.fromMap(
              d.id, await CryptoService.instance.decryptJson(enc, dek)));
        } else {
          out.add(Subscription.fromMap(d.id, d.data()));
        }
      }
      out.sort((a, b) => a.day.compareTo(b.day));
      return out;
    });
  }

  Future<void> setSubscription(String uid, Subscription s) async {
    final dek = _requireDek();
    final doc = {
      'enc': await CryptoService.instance.encryptJson(s.toMap(), dek),
      'v': 1,
    };
    await _out.set(_subsCol(uid).doc(s.id), doc);
  }

  Future<void> deleteSubscription(String uid, String id) =>
      _out.delete(_subsCol(uid).doc(id));
}

/// Top-level so it can run inside `Isolate.run`. Decrypts a batch of `enc`
/// blobs with the data key; a null entry means that blob failed to decrypt.
/// Pure-Dart AES-GCM, so it runs fine off the main isolate.
Future<List<Map<String, dynamic>?>> _decryptBlobs(
    List<String> blobs, List<int> key) async {
  final cs = CryptoService.instance;
  final out = <Map<String, dynamic>?>[];
  for (final b in blobs) {
    try {
      out.add(await cs.decryptJson(b, key));
    } catch (_) {
      out.add(null);
    }
  }
  return out;
}
