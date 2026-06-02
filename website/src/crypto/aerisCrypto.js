// AERIS Web crypto — a faithful port of lib/services/crypto_service.dart.
//
// Envelope model (must match the Flutter app byte-for-byte):
//   • Argon2id(password, salt) → 32-byte KEK     (m=19456 KiB, t=2, p=1, v=0x13)
//   • DEK (32 random bytes)    = AES-256-GCM-decrypt(keysDoc.wrapPw, KEK)
//   • All data                 = AES-256-GCM with the DEK
//   • Blob format everywhere   = base64(nonce) "." base64(cipher) "." base64(mac)
//     where mac = the trailing 16-byte GCM auth tag.
import { argon2id } from 'hash-wasm';

const te = new TextEncoder();
const td = new TextDecoder();

// ---- base64 helpers (standard alphabet, matching Dart base64Encode) --------
export function b64ToBytes(b64) {
  const bin = atob(b64);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}
export function bytesToB64(bytes) {
  const arr = bytes instanceof Uint8Array ? bytes : new Uint8Array(bytes);
  let bin = '';
  for (let i = 0; i < arr.length; i++) bin += String.fromCharCode(arr[i]);
  return btoa(bin);
}

// ---- KDF -------------------------------------------------------------------
// Mirrors Argon2id(memory: 19456, parallelism: 1, iterations: 2, hashLength: 32).
export async function deriveKek(passphrase, saltBytes) {
  return argon2id({
    password: te.encode(passphrase),
    salt: saltBytes instanceof Uint8Array ? saltBytes : new Uint8Array(saltBytes),
    parallelism: 1,
    iterations: 2,
    memorySize: 19456, // KiB
    hashLength: 32,
    outputType: 'binary', // Uint8Array(32)
  });
}

// Recovery key: strip dashes/spaces, upper-case, then same KDF (matches Dart).
export function deriveRecoveryKek(recoveryKey, saltBytes) {
  const normalised = recoveryKey.replace(/[\s-]/g, '').toUpperCase();
  return deriveKek(normalised, saltBytes);
}

// ---- AES-256-GCM -----------------------------------------------------------
async function importAesKey(rawKey) {
  const raw = rawKey instanceof Uint8Array ? rawKey : new Uint8Array(rawKey);
  return crypto.subtle.importKey('raw', raw, { name: 'AES-GCM' }, false, [
    'encrypt',
    'decrypt',
  ]);
}

export async function aesGcmDecrypt(blob, rawKey) {
  const parts = blob.split('.');
  if (parts.length !== 3) throw new Error('Malformed ciphertext blob');
  const nonce = b64ToBytes(parts[0]);
  const cipher = b64ToBytes(parts[1]);
  const mac = b64ToBytes(parts[2]); // 16-byte GCM tag
  // WebCrypto expects cipher || tag concatenated.
  const full = new Uint8Array(cipher.length + mac.length);
  full.set(cipher, 0);
  full.set(mac, cipher.length);
  const key = await importAesKey(rawKey);
  const plain = await crypto.subtle.decrypt(
    { name: 'AES-GCM', iv: nonce, tagLength: 128 },
    key,
    full,
  );
  return new Uint8Array(plain);
}

export async function aesGcmEncrypt(bytes, rawKey) {
  const nonce = crypto.getRandomValues(new Uint8Array(12));
  const key = await importAesKey(rawKey);
  const out = new Uint8Array(
    await crypto.subtle.encrypt(
      { name: 'AES-GCM', iv: nonce, tagLength: 128 },
      key,
      bytes,
    ),
  );
  // Split trailing 16-byte tag so the blob matches the app's read path.
  const cipher = out.slice(0, out.length - 16);
  const mac = out.slice(out.length - 16);
  return `${bytesToB64(nonce)}.${bytesToB64(cipher)}.${bytesToB64(mac)}`;
}

// ---- JSON wrappers ---------------------------------------------------------
export async function decryptJson(blob, rawKey) {
  const bytes = await aesGcmDecrypt(blob, rawKey);
  return JSON.parse(td.decode(bytes));
}
export async function encryptJson(obj, rawKey) {
  return aesGcmEncrypt(te.encode(JSON.stringify(obj)), rawKey);
}

// ---- DEK unwrap ------------------------------------------------------------
// keysDoc = { v, salt(b64), wrapPw(blob), wrapRec(blob) }
export async function unwrapDekWithPassword(keysDoc, password) {
  const salt = b64ToBytes(keysDoc.salt);
  const kek = await deriveKek(password, salt);
  return aesGcmDecrypt(keysDoc.wrapPw, kek); // 32-byte DEK
}
export async function unwrapDekWithRecovery(keysDoc, recoveryKey) {
  const salt = b64ToBytes(keysDoc.salt);
  const kek = await deriveRecoveryKek(recoveryKey, salt);
  return aesGcmDecrypt(keysDoc.wrapRec, kek);
}
