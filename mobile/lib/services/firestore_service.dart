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
    return q.snapshots().asyncMap((s) async {
      final out = <Transaction>[];
      for (final d in s.docs) {
        out.add(await _decodeTxn(d.id, d.data()));
      }
      return out;
    });
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
