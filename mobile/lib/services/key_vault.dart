import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Holds the decrypted Data Key (DEK) for the current session.
///
/// The DEK lives in memory while the app runs, and is cached in the platform
/// secure store (Android Keystore-backed) so a persisted login can still
/// decrypt after an app restart without re-entering the password. It is never
/// written to Firestore or anywhere off-device in the clear.
class KeyVault {
  KeyVault._();
  static final KeyVault instance = KeyVault._();

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  List<int>? _dek;

  bool get isUnlocked => _dek != null;
  List<int>? get dek => _dek;

  Future<void> setDek(String uid, List<int> dek) async {
    _dek = dek;
    await _storage.write(key: _k(uid), value: base64Encode(dek));
  }

  /// Restore the DEK from secure storage (used on app restart with a still
  /// signed-in user). Returns true if a cached key was found.
  Future<bool> loadCached(String uid) async {
    final v = await _storage.read(key: _k(uid));
    if (v == null) return false;
    _dek = base64Decode(v);
    return true;
  }

  Future<void> clear(String uid) async {
    _dek = null;
    await _storage.delete(key: _k(uid));
  }

  static String _k(String uid) => 'aeris_dek_$uid';
}
