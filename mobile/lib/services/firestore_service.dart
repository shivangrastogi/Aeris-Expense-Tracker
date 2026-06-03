import 'dart:isolate';

import 'package:cloud_firestore/cloud_firestore.dart' hide Transaction;

import '../models/budget.dart';
import '../models/goal.dart';
import '../models/transaction.dart';
import 'crypto_service.dart';
import 'key_vault.dart';

/// Per-user Firestore data layer. Layout:
///   users/{uid}                       — UserProfile
///     transactions/{txnId}            — Transaction
///     budgets/{categoryId}            — Budget (doc id == categoryId)
///     processed_sms/{smsHash}         — dedupe ledger for SMS imports
class FirestoreService {
  FirestoreService._();
  static final FirestoreService instance = FirestoreService._();

  final _db = FirebaseFirestore.instance;

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
        m['timestamp'] =
            Timestamp.fromMillisecondsSinceEpoch((m['timestamp'] as num).toInt());
        final txn = Transaction.fromMap(docs[i].id, m);
        _txCache[docs[i].id] = (enc: pendingBlobs[j], txn: txn);
        results[i] = txn;
      }
    }
    return [for (final t in results) if (t != null) t];
  }

  Future<List<Transaction>> fetchTransactions(String uid,
      {DateTime? since, int? limit}) async {
    Query<Map<String, dynamic>> q = _txCol(uid).orderBy('timestamp', descending: true);
    if (since != null) {
      q = q.where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(since));
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
    await _txCol(uid).doc(t.id).set(await _encodeTxn(t));
  }

  Future<void> updateTransaction(String uid, Transaction t) async {
    // Full rewrite — an encrypted blob can't be partially merged.
    await _txCol(uid).doc(t.id).set(await _encodeTxn(t));
  }

  Future<void> deleteTransaction(String uid, String id) async {
    await _txCol(uid).doc(id).delete();
  }

  // ─ Transaction encryption (envelope, AES-256-GCM) ──────────
  // Stored doc shape: { timestamp (plaintext, for ordering), enc (blob), v }.
  // The blob holds every sensitive field — amount, merchant, SMS text, etc.

  Future<Map<String, dynamic>> _encodeTxn(Transaction t) async {
    final dek = KeyVault.instance.dek;
    if (dek == null) return t.toMap(); // vault locked — should not happen
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
    await _budgetCol(uid).doc(b.categoryId).set(await _encodeBudget(b));
  }

  Future<void> deleteBudget(String uid, String categoryId) =>
      _budgetCol(uid).doc(categoryId).delete();

  // The monthly cap is encrypted; the doc id (categoryId) is just a label.
  Future<Map<String, dynamic>> _encodeBudget(Budget b) async {
    final dek = KeyVault.instance.dek;
    if (dek == null) return b.toMap();
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
            : DateTime.fromMillisecondsSinceEpoch((m['updatedAt'] as num).toInt()),
      );
    }
    return Budget.fromMap(id, doc);
  }

  // ─ SMS dedupe ──────────────────────────────────────────────

  Future<bool> alreadyImported(String uid, String smsHash) async {
    final doc = await _processedCol(uid).doc(smsHash).get();
    return doc.exists;
  }

  Future<void> markImported(String uid, String smsHash) =>
      _processedCol(uid).doc(smsHash).set({'at': FieldValue.serverTimestamp()});

  // ─ Blocked senders ─────────────────────────────────────────
  // Senders the user has flagged as junk. Future SMS from them are never
  // imported. Doc id is a sanitised key; the raw value lives in 'sender'.

  static String _senderKey(String sender) =>
      sender.trim().toUpperCase().replaceAll(RegExp(r'[\/\.\#\$\[\]]'), '_');

  Stream<Set<String>> watchBlockedSenders(String uid) =>
      _blockedCol(uid).snapshots().map((s) =>
          s.docs.map((d) => (d.data()['sender'] as String?) ?? d.id).toSet());

  Future<void> blockSender(String uid, String sender) =>
      _blockedCol(uid).doc(_senderKey(sender)).set({
        'sender': sender,
        'at': FieldValue.serverTimestamp(),
      });

  Future<void> unblockSender(String uid, String sender) =>
      _blockedCol(uid).doc(_senderKey(sender)).delete();

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
    final dek = KeyVault.instance.dek;
    if (dek == null) return;
    final snap = await _balancesDoc(uid).get();
    final current = <String, double>{};
    final enc = snap.data()?['enc'];
    if (enc is String) {
      try {
        current.addAll(
            _decodeBalances(await CryptoService.instance.decryptJson(enc, dek)));
      } catch (_) {/* start fresh */}
    }
    current[accountKey] = amount;
    await _balancesDoc(uid).set({
      'enc': await CryptoService.instance.encryptJson({'balances': current}, dek),
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
      await _txCol(uid).doc(d.id).set(
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
    final dek = KeyVault.instance.dek;
    final doc = dek == null
        ? g.toMap()
        : {
            'createdAt': Timestamp.fromDate(g.createdAt),
            'enc': await CryptoService.instance.encryptJson(g.toMap(), dek),
            'v': 1,
          };
    await _goalsCol(uid).doc(g.id).set(doc);
  }

  Future<void> deleteGoal(String uid, String id) =>
      _goalsCol(uid).doc(id).delete();
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
