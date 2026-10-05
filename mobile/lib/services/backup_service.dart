import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/budget.dart';
import '../models/goal.dart';
import '../models/loan.dart';
import '../models/subscription.dart';
import '../models/transaction.dart';
import 'crypto_service.dart';
import 'firestore_service.dart';

/// Encrypted, off-device backup of the user's data: transactions, budgets,
/// goals, lent/borrowed entries and subscriptions (v2; v1 files held only
/// transactions and still restore).
///
/// The backup file is a small JSON wrapper `{app, v, createdAt, count, salt,
/// enc}` where `enc` is the transaction list encrypted (AES-256-GCM) under a
/// KEK derived from a user-chosen passphrase — so the file is useless without
/// it. Restore re-adds each transaction by its original id (the Firestore doc
/// id), so importing the same backup twice never creates duplicates.
class BackupService {
  BackupService._();
  static final BackupService instance = BackupService._();

  /// Build an encrypted backup of all transactions and open the share sheet.
  /// Returns the file path.
  Future<String> exportBackup(String uid, String passphrase) async {
    final cs = CryptoService.instance;
    final txns =
        await FirestoreService.instance.fetchTransactions(uid, since: DateTime(2000));
    final list = txns.map((t) {
      final m = t.toMap();
      m['id'] = t.id;
      m['timestamp'] = t.timestamp.millisecondsSinceEpoch; // JSON-safe
      return m;
    }).toList();

    final fs = FirestoreService.instance;
    final budgets = await fs.watchBudgets(uid).first;
    final goals = await fs.watchGoals(uid).first;
    final loans = await fs.watchLoans(uid).first;
    final subs = await fs.watchSubscriptions(uid).first;

    final salt = cs.randomBytes(16);
    final kek = await cs.deriveKek(passphrase, salt);
    final enc = await cs.encryptJson({
      'transactions': list,
      'budgets': [
        for (final b in budgets)
          {
            'id': b.id,
            'categoryId': b.categoryId,
            'monthlyCap': b.monthlyCap,
            'updatedAt': b.updatedAt.millisecondsSinceEpoch,
          }
      ],
      'goals': [for (final g in goals) {...g.toMap(), 'id': g.id}],
      'loans': [for (final l in loans) {...l.toMap(), 'id': l.id}],
      'subscriptions': [for (final s in subs) {...s.toMap(), 'id': s.id}],
    }, kek);

    final wrapper = jsonEncode({
      'app': 'aeris',
      'v': 2,
      'createdAt': DateTime.now().toIso8601String(),
      'count': list.length,
      'salt': base64Encode(salt),
      'enc': enc,
    });

    final dir = await getTemporaryDirectory();
    final path =
        '${dir.path}/AERIS_backup_${DateTime.now().millisecondsSinceEpoch}.aeris';
    File(path).writeAsStringSync(wrapper, flush: true);
    await Share.shareXFiles([XFile(path)],
        text: 'My AERIS encrypted backup (${list.length} transactions)',
        subject: 'AERIS Backup');
    return path;
  }

  /// Let the user pick a backup file and restore it. Returns the number of
  /// transactions restored, or -1 if the user cancelled the file picker.
  /// Throws on a wrong passphrase or an invalid file.
  Future<int> restoreBackup(String uid, String passphrase) async {
    final res = await FilePicker.platform.pickFiles(withData: true);
    if (res == null || res.files.isEmpty) return -1;
    final f = res.files.first;
    final content = f.bytes != null
        ? utf8.decode(f.bytes!)
        : File(f.path!).readAsStringSync();

    final wrapper = jsonDecode(content) as Map<String, dynamic>;
    if (wrapper['app'] != 'aeris' || wrapper['enc'] is! String) {
      throw const FormatException('Not an AERIS backup file.');
    }
    final cs = CryptoService.instance;
    final salt = base64Decode(wrapper['salt'] as String);
    final kek = await cs.deriveKek(passphrase, salt);
    // Throws (GCM tag mismatch) if the passphrase is wrong.
    final data = await cs.decryptJson(wrapper['enc'] as String, kek);

    final list = (data['transactions'] as List?) ?? const [];
    final fs = FirestoreService.instance;
    var n = 0;
    for (final raw in list) {
      final m = Map<String, dynamic>.from(raw as Map);
      final id = m['id'] as String?;
      if (id == null || id.isEmpty) continue;
      m['timestamp'] =
          Timestamp.fromMillisecondsSinceEpoch((m['timestamp'] as num).toInt());
      // Doc id == transaction id → re-import is idempotent (no duplicates).
      await fs.addTransaction(uid, Transaction.fromMap(id, m));
      n++;
    }

    // v2 extras — each keeps its original id, so restoring twice is safe.
    List<Map<String, dynamic>> rows(String key) => [
          for (final r in (data[key] as List?) ?? const [])
            if (r is Map && r['id'] is String) Map<String, dynamic>.from(r)
        ];
    for (final m in rows('budgets')) {
      await fs.setBudget(
          uid,
          Budget(
            id: m['id'] as String,
            categoryId: m['categoryId'] as String? ?? 'other',
            monthlyCap: (m['monthlyCap'] as num?)?.toDouble() ?? 0,
            updatedAt: DateTime.fromMillisecondsSinceEpoch(
                (m['updatedAt'] as num?)?.toInt() ?? 0),
          ));
    }
    for (final m in rows('goals')) {
      await fs.setGoal(uid, Goal.fromMap(m['id'] as String, m));
    }
    for (final m in rows('loans')) {
      await fs.setLoan(uid, Loan.fromMap(m['id'] as String, m));
    }
    for (final m in rows('subscriptions')) {
      await fs.setSubscription(uid, Subscription.fromMap(m['id'] as String, m));
    }
    return n;
  }
}
