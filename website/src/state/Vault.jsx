import { createContext, useContext, useEffect, useState } from 'react';
import {
  signInWithEmailAndPassword,
  signOut,
  onAuthStateChanged,
} from 'firebase/auth';
import { auth } from '../firebase.js';
import {
  unwrapDekWithPassword,
  unwrapDekWithRecovery,
  deriveKek,
  aesGcmEncrypt,
  b64ToBytes,
  decryptJson,
} from '../crypto/aerisCrypto.js';
import { fetchKeys, fetchNewestTxnDoc } from '../data/repo.js';
import { doc, setDoc } from 'firebase/firestore';
import { db } from '../firebase.js';

const VaultCtx = createContext(null);
export const useVault = () => useContext(VaultCtx);

// status: 'loading' | 'signedOut' | 'locked' | 'unlocked'
export function VaultProvider({ children }) {
  const [user, setUser] = useState(null);
  const [dek, setDek] = useState(null); // Uint8Array, in memory only
  const [status, setStatus] = useState('loading');

  useEffect(() => {
    return onAuthStateChanged(auth, (u) => {
      setUser(u);
      if (!u) {
        setDek(null);
        setStatus('signedOut');
      } else {
        // Authed but DEK only lives in memory — require unlock each session.
        setStatus((s) => (dek ? 'unlocked' : 'locked'));
      }
    });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // Decrypt the newest transaction as an interop self-test. A wrong password
  // unwraps to a bad DEK; the GCM tag check then throws → we reject the unlock.
  async function selfTest(uid, key) {
    const newest = await fetchNewestTxnDoc(uid);
    if (!newest) return; // no data yet — nothing to validate against
    const data = newest.data();
    if (typeof data.enc !== 'string') return; // legacy plaintext doc
    await decryptJson(data.enc, key); // throws on wrong key
  }

  async function login(email, password) {
    const cred = await signInWithEmailAndPassword(auth, email.trim(), password);
    return unlock(password, cred.user.uid);
  }

  // Unlock the in-memory vault from the password.
  async function unlock(password, uidArg) {
    const uid = uidArg || auth.currentUser?.uid;
    if (!uid) throw new Error('Not signed in.');
    const keys = await fetchKeys(uid);
    if (!keys) {
      // Account never enabled encryption on the phone — nothing to unlock.
      throw new Error(
        'This account has no encryption keys yet. Open the AERIS phone app once to set them up.',
      );
    }
    let key;
    try {
      key = await unwrapDekWithPassword(keys, password);
    } catch {
      throw new Error('Wrong password — could not unlock your vault.');
    }
    try {
      await selfTest(uid, key);
    } catch {
      throw new Error('Wrong password — could not decrypt your data.');
    }
    setDek(key);
    setStatus('unlocked');
  }

  // Recover with the one-time recovery key, then re-wrap the DEK under a new
  // password so future logins work (matches the phone app's restore flow).
  async function restore(recoveryKey, newPassword) {
    const uid = auth.currentUser?.uid;
    if (!uid) throw new Error('Not signed in.');
    const keys = await fetchKeys(uid);
    if (!keys) throw new Error('No encryption keys for this account.');
    let key;
    try {
      key = await unwrapDekWithRecovery(keys, recoveryKey);
    } catch {
      throw new Error('That recovery key did not work.');
    }
    const salt = b64ToBytes(keys.salt);
    const pwKek = await deriveKek(newPassword, salt);
    const wrapPw = await aesGcmEncrypt(key, pwKek);
    await setDoc(doc(db, 'users', uid, 'security', 'keys'), { ...keys, wrapPw });
    setDek(key);
    setStatus('unlocked');
  }

  function lock() {
    setDek(null);
    setStatus(auth.currentUser ? 'locked' : 'signedOut');
  }

  async function logout() {
    setDek(null);
    await signOut(auth);
  }

  return (
    <VaultCtx.Provider
      value={{ user, dek, status, login, unlock, restore, lock, logout }}
    >
      {children}
    </VaultCtx.Provider>
  );
}
