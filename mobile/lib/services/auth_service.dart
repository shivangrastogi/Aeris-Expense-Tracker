import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/user_profile.dart';
import 'crypto_service.dart';
import 'firestore_service.dart';
import 'key_vault.dart';

class AuthService {
  AuthService._();
  static final AuthService instance = AuthService._();

  final _auth = FirebaseAuth.instance;
  final _db = FirebaseFirestore.instance;

  User? get currentUser => _auth.currentUser;
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  /// Creates the account AND bootstraps end-to-end encryption keys.
  /// Returns the one-time **recovery key** the UI must show the user once.
  Future<String> signUpWithEmail({
    required String email,
    required String password,
    required String displayName,
  }) async {
    final cred = await _auth.createUserWithEmailAndPassword(
        email: email.trim(), password: password);
    final user = cred.user!;
    await user.updateDisplayName(displayName);

    final recoveryKey = await _bootstrapKeys(user.uid, password);

    final profile = UserProfile(
      uid: user.uid,
      email: email.trim(),
      displayName: displayName,
      createdAt: DateTime.now(),
    );
    await _db.collection('users').doc(user.uid).set(
        await _profileDoc(profile, deleteLegacy: false));
    return recoveryKey;
  }

  /// Builds the Firestore profile map with `monthlyIncome` encrypted into an
  /// `incomeEnc` blob (it's financial data). Other fields stay plaintext —
  /// email/displayName already live in Firebase Auth.
  Future<Map<String, dynamic>> _profileDoc(UserProfile p,
      {required bool deleteLegacy}) async {
    final m = p.toMap();
    final dek = KeyVault.instance.dek;
    if (dek == null) return m; // vault locked — keep plaintext fallback
    m.remove('monthlyIncome');
    m['incomeEnc'] =
        await CryptoService.instance.encryptJson({'income': p.monthlyIncome}, dek);
    if (deleteLegacy) m['monthlyIncome'] = FieldValue.delete();

    // Profile picture — encrypt the image BYTES (never a clear URL or the raw
    // image). Stored as a `photoEnc` blob, just like income. If photoBytes is
    // null and the user didn't explicitly clear it, leave photoEnc untouched so
    // a name-only edit (merge write) keeps the existing picture.
    m.remove('photoUrl');
    if (p.photoBytes != null) {
      m['photoEnc'] = await CryptoService.instance.encryptBytes(p.photoBytes!, dek);
      if (deleteLegacy) m['photoUrl'] = FieldValue.delete();
    } else if (p.photoCleared) {
      m['photoEnc'] = FieldValue.delete();
      m['photoUrl'] = FieldValue.delete();
    }
    return m;
  }

  Future<UserCredential> signInWithEmail({
    required String email,
    required String password,
  }) async {
    final cred = await _auth.signInWithEmailAndPassword(
        email: email.trim(), password: password);
    await unlockWithPassword(cred.user!.uid, password);
    return cred;
  }

  // ── End-to-end encryption key handling ─────────────────────

  /// Generate a fresh DEK, wrap it by both the password and a new recovery
  /// key, persist the wrapped copies, and unlock the in-memory vault.
  Future<String> _bootstrapKeys(String uid, String password) async {
    final cs = CryptoService.instance;
    final salt = cs.randomBytes(16);
    final dek = cs.randomBytes(32);
    final recoveryKey = cs.generateRecoveryKey();
    final pwKek = await cs.deriveKek(password, salt);
    final recKek = await cs.deriveRecoveryKek(recoveryKey, salt);

    await FirestoreService.instance.saveKeys(uid, {
      'v': 1,
      'salt': base64Encode(salt),
      'wrapPw': await cs.encryptBytes(dek, pwKek),
      'wrapRec': await cs.encryptBytes(dek, recKek),
    });
    await KeyVault.instance.setDek(uid, dek);
    return recoveryKey;
  }

  /// Unlock the vault using the login password (called right after sign-in).
  Future<void> unlockWithPassword(String uid, String password) async {
    final keys = await FirestoreService.instance.fetchKeys(uid);
    if (keys == null) return; // pre-encryption / phone-only account
    final cs = CryptoService.instance;
    final salt = base64Decode(keys['salt'] as String);
    final kek = await cs.deriveKek(password, salt);
    final dek = await cs.decryptBytes(keys['wrapPw'] as String, kek);
    await KeyVault.instance.setDek(uid, dek);
  }

  /// On app restart with a persisted session, restore the DEK from secure
  /// storage. Returns true if the vault is ready.
  Future<bool> ensureUnlocked(String uid) async {
    if (KeyVault.instance.isUnlocked) return true;
    if (await KeyVault.instance.loadCached(uid)) return true;
    // No keys doc at all → nothing to unlock (legacy account).
    // Bound the network read: when offline (or on a flaky connection) a
    // Firestore .get() can hang indefinitely, which would freeze the splash
    // forever. On timeout we fall through to the password unlock screen
    // instead of leaving the user staring at a stuck loader.
    try {
      final keys = await FirestoreService.instance
          .fetchKeys(uid)
          .timeout(const Duration(seconds: 8));
      return keys == null;
    } catch (_) {
      return false;
    }
  }

  /// Recover access with the one-time recovery key, then re-wrap the DEK
  /// under a new password so future logins work normally.
  Future<void> restoreWithRecovery({
    required String uid,
    required String recoveryKey,
    required String newPassword,
  }) async {
    final keys = await FirestoreService.instance.fetchKeys(uid);
    if (keys == null) throw Exception('No encryption keys for this account.');
    final cs = CryptoService.instance;
    final salt = base64Decode(keys['salt'] as String);
    final recKek = await cs.deriveRecoveryKek(recoveryKey, salt);
    final dek = await cs.decryptBytes(keys['wrapRec'] as String, recKek);
    final pwKek = await cs.deriveKek(newPassword, salt);
    await FirestoreService.instance.saveKeys(uid, {
      ...keys,
      'wrapPw': await cs.encryptBytes(dek, pwKek),
    });
    await KeyVault.instance.setDek(uid, dek);
  }

  /// For accounts created before E2E existed: generate keys (if missing) and
  /// re-encrypt all existing plaintext data. Returns a fresh recovery key when
  /// keys had to be created (so the UI can show it once), else null.
  Future<String?> setupEncryptionNow(String uid, String password) async {
    String? recoveryKey;
    final keys = await FirestoreService.instance.fetchKeys(uid);
    if (keys == null) {
      recoveryKey = await _bootstrapKeys(uid, password); // creates + unlocks
    } else if (!KeyVault.instance.isUnlocked) {
      await unlockWithPassword(uid, password);
    }
    await FirestoreService.instance.migrateToEncrypted(uid);
    final p = await loadProfile(uid);
    if (p != null) await saveProfile(p); // encrypts income
    return recoveryKey;
  }

  // ── Phone auth (unchanged) ─────────────────────────────────

  Future<String> startPhoneVerification(String e164Phone) async {
    final completer = Completer<String>();
    await _auth.verifyPhoneNumber(
      phoneNumber: e164Phone,
      timeout: const Duration(seconds: 60),
      verificationCompleted: (_) {},
      verificationFailed: (e) => completer.completeError(e),
      codeSent: (verificationId, _) {
        if (!completer.isCompleted) completer.complete(verificationId);
      },
      codeAutoRetrievalTimeout: (_) {},
    );
    return completer.future;
  }

  Future<UserCredential> confirmOtp({
    required String verificationId,
    required String smsCode,
  }) {
    final cred = PhoneAuthProvider.credential(
        verificationId: verificationId, smsCode: smsCode);
    return _auth.signInWithCredential(cred);
  }

  Future<void> signOut() async {
    final uid = _auth.currentUser?.uid;
    if (uid != null) await KeyVault.instance.clear(uid);
    await _auth.signOut();
  }

  Future<UserProfile?> loadProfile(String uid) async {
    final doc = await _db.collection('users').doc(uid).get();
    if (!doc.exists) return null;
    final data = Map<String, dynamic>.from(doc.data()!);
    final dek = KeyVault.instance.dek;
    if (data['incomeEnc'] is String && dek != null) {
      try {
        final dec = await CryptoService.instance
            .decryptJson(data['incomeEnc'] as String, dek);
        data['monthlyIncome'] = (dec['income'] as num?)?.toDouble() ?? 0;
      } catch (_) {/* leave as-is if it can't be decrypted */}
    }
    var profile = UserProfile.fromMap(uid, data);
    if (data['photoEnc'] is String && dek != null) {
      try {
        final bytes = await CryptoService.instance
            .decryptBytes(data['photoEnc'] as String, dek);
        profile = profile.copyWith(photoBytes: Uint8List.fromList(bytes));
      } catch (_) {/* picture stays empty if it can't be decrypted */}
    }
    return profile;
  }

  Future<void> saveProfile(UserProfile p) async {
    await _db
        .collection('users')
        .doc(p.uid)
        .set(await _profileDoc(p, deleteLegacy: true), SetOptions(merge: true));
  }
}
