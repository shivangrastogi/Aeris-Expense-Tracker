import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

/// End-to-end encryption primitives for AERIS.
///
/// Model (envelope encryption):
///   • A random 256-bit **Data Key (DEK)** encrypts the user's transactions
///     with AES-256-GCM. The DEK never leaves the device in the clear.
///   • The DEK is "wrapped" (encrypted) twice and stored in Firestore:
///       – by a Key-Encryption-Key derived from the login password (Argon2id)
///       – by a KEK derived from a one-time recovery key
///     Firestore therefore only ever holds ciphertext + wrapped keys, so the
///     server (and the app owner) can never read a user's financial data.
///
/// Blob format for all ciphertext: "base64(nonce).base64(cipher).base64(mac)".
class CryptoService {
  CryptoService._();
  static final CryptoService instance = CryptoService._();

  static final Random _rng = Random.secure();
  final AesGcm _aes = AesGcm.with256bits();

  // OWASP-recommended Argon2id minimum (m=19 MiB, t=2, p=1).
  Argon2id get _kdf =>
      Argon2id(memory: 19456, parallelism: 1, iterations: 2, hashLength: 32);

  List<int> randomBytes(int n) =>
      List<int>.generate(n, (_) => _rng.nextInt(256));

  /// Derive a 256-bit key-encryption-key from a passphrase + salt.
  Future<List<int>> deriveKek(String passphrase, List<int> salt) async {
    final key = await _kdf.deriveKey(
      secretKey: SecretKey(utf8.encode(passphrase)),
      nonce: salt,
    );
    return key.extractBytes();
  }

  Future<String> encryptBytes(List<int> data, List<int> key) async {
    final box = await _aes.encrypt(data,
        secretKey: SecretKey(key), nonce: _aes.newNonce());
    return '${base64Encode(box.nonce)}.'
        '${base64Encode(box.cipherText)}.'
        '${base64Encode(box.mac.bytes)}';
  }

  Future<List<int>> decryptBytes(String blob, List<int> key) async {
    final parts = blob.split('.');
    if (parts.length != 3) {
      throw const FormatException('Malformed ciphertext blob');
    }
    final box = SecretBox(
      base64Decode(parts[1]),
      nonce: base64Decode(parts[0]),
      mac: Mac(base64Decode(parts[2])),
    );
    return _aes.decrypt(box, secretKey: SecretKey(key));
  }

  Future<String> encryptJson(Map<String, dynamic> map, List<int> key) =>
      encryptBytes(utf8.encode(jsonEncode(map)), key);

  Future<Map<String, dynamic>> decryptJson(String blob, List<int> key) async {
    final clear = await decryptBytes(blob, key);
    return jsonDecode(utf8.decode(clear)) as Map<String, dynamic>;
  }

  /// A human-friendly recovery key, e.g. "K7M2-9QFP-3RTX-...". Excludes
  /// ambiguous characters (0/O, 1/I/L).
  String generateRecoveryKey() {
    const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final raw = List.generate(24, (_) => alphabet[_rng.nextInt(alphabet.length)]);
    final blocks = <String>[];
    for (var i = 0; i < raw.length; i += 4) {
      blocks.add(raw.sublist(i, i + 4).join());
    }
    return blocks.join('-');
  }

  /// Normalise a recovery key the user typed (strip dashes/spaces, upper-case)
  /// before deriving a KEK from it.
  Future<List<int>> deriveRecoveryKek(String recoveryKey, List<int> salt) =>
      deriveKek(recoveryKey.replaceAll(RegExp(r'[\s-]'), '').toUpperCase(), salt);

  /// An opaque, deterministic tag for de-duplication (e.g. the processed-SMS
  /// ledger doc id). Keyed with the user's DEK via HMAC-SHA256 so it can't be
  /// brute-forced back to the amount/sender. Falls back to plain SHA-256 if no
  /// key is available. URL-safe so it's a valid Firestore document id.
  Future<String> dedupeTag(String input, List<int> key) async {
    final bytes = utf8.encode(input);
    final List<int> mac;
    if (key.isEmpty) {
      mac = (await Sha256().hash(bytes)).bytes;
    } else {
      mac = (await Hmac.sha256().calculateMac(bytes, secretKey: SecretKey(key)))
          .bytes;
    }
    return base64Url.encode(mac).replaceAll('=', '');
  }
}
