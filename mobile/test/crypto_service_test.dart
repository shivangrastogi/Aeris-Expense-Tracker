import 'package:flutter_test/flutter_test.dart';
import 'package:aeris_expense/services/crypto_service.dart';

void main() {
  final cs = CryptoService.instance;

  test('DEK wrap/unwrap by password round-trips', () async {
    final salt = cs.randomBytes(16);
    final dek = cs.randomBytes(32);
    final kek = await cs.deriveKek('hunter2-correct-horse', salt);

    final wrapped = await cs.encryptBytes(dek, kek);
    final kek2 = await cs.deriveKek('hunter2-correct-horse', salt);
    final unwrapped = await cs.decryptBytes(wrapped, kek2);

    expect(unwrapped, dek);
  });

  test('wrong password fails to unwrap', () async {
    final salt = cs.randomBytes(16);
    final dek = cs.randomBytes(32);
    final kek = await cs.deriveKek('right-password', salt);
    final wrapped = await cs.encryptBytes(dek, kek);

    final badKek = await cs.deriveKek('wrong-password', salt);
    expect(() => cs.decryptBytes(wrapped, badKek), throwsA(anything));
  });

  test('transaction JSON encrypts and decrypts with DEK', () async {
    final dek = cs.randomBytes(32);
    final data = {
      'amount': 499.0,
      'merchant': 'AMAZON',
      'smsBody': 'Rs.499 debited from a/c XX1234',
      'categoryId': 'shopping',
    };
    final blob = await cs.encryptJson(data, dek);
    expect(blob.contains('AMAZON'), isFalse); // ciphertext, not plaintext
    final back = await cs.decryptJson(blob, dek);
    expect(back['amount'], 499.0);
    expect(back['merchant'], 'AMAZON');
  });

  test('recovery key unwraps the same DEK', () async {
    final salt = cs.randomBytes(16);
    final dek = cs.randomBytes(32);
    final recovery = cs.generateRecoveryKey();

    final recKek = await cs.deriveRecoveryKek(recovery, salt);
    final wrapped = await cs.encryptBytes(dek, recKek);

    // User re-types it lower-case with spaces instead of dashes.
    final typed = recovery.replaceAll('-', ' ').toLowerCase();
    final recKek2 = await cs.deriveRecoveryKek(typed, salt);
    final unwrapped = await cs.decryptBytes(wrapped, recKek2);

    expect(unwrapped, dek);
  });
}
