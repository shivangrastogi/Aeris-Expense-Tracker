// Firestore data layer — mirrors lib/services/firestore_service.dart doc shapes
// exactly so the web client reads/writes the same encrypted documents the phone
// app does. Every function takes the in-memory DEK (32-byte Uint8Array).
import {
  collection,
  doc,
  getDoc,
  getDocs,
  onSnapshot,
  setDoc,
  deleteDoc,
  query,
  orderBy,
  Timestamp,
} from 'firebase/firestore';
import { db } from '../firebase.js';
import { decryptJson, encryptJson } from '../crypto/aerisCrypto.js';

const txCol = (uid) => collection(db, 'users', uid, 'transactions');
const budgetCol = (uid) => collection(db, 'users', uid, 'budgets');
const goalsCol = (uid) => collection(db, 'users', uid, 'goals');
const keysDocRef = (uid) => doc(db, 'users', uid, 'security', 'keys');
const profileRef = (uid) => doc(db, 'users', uid);

export async function fetchKeys(uid) {
  const snap = await getDoc(keysDocRef(uid));
  return snap.exists() ? snap.data() : null;
}

// ── Transactions ───────────────────────────────────────────
async function decodeTxn(id, data, dek) {
  if (typeof data.enc === 'string') {
    const m = await decryptJson(data.enc, dek);
    return {
      id,
      amount: Number(m.amount) || 0,
      direction: m.direction === 'credit' ? 'credit' : 'debit',
      timestamp: new Date(Number(m.timestamp)),
      merchant: m.merchant ?? null,
      account: m.account ?? null,
      categoryId: m.categoryId ?? 'other',
      note: m.note ?? null,
      source: m.source ?? 'manual',
      smsBody: m.smsBody ?? null,
      smsSender: m.smsSender ?? null,
      reviewed: m.reviewed ?? true,
    };
  }
  // Legacy plaintext doc.
  const ts = data.timestamp;
  return {
    id,
    amount: Number(data.amount) || 0,
    direction: data.direction === 'credit' ? 'credit' : 'debit',
    timestamp: ts?.toDate ? ts.toDate() : new Date(),
    merchant: data.merchant ?? null,
    account: data.account ?? null,
    categoryId: data.categoryId ?? 'other',
    note: data.note ?? null,
    source: data.source ?? 'manual',
    smsBody: data.smsBody ?? null,
    smsSender: data.smsSender ?? null,
    reviewed: data.reviewed ?? true,
  };
}

async function encodeTxn(t, dek) {
  const json = {
    amount: t.amount,
    direction: t.direction,
    timestamp: t.timestamp.getTime(),
    merchant: t.merchant ?? null,
    account: t.account ?? null,
    categoryId: t.categoryId,
    note: t.note ?? null,
    source: t.source ?? 'manual',
    smsBody: t.smsBody ?? null,
    smsSender: t.smsSender ?? null,
    reviewed: t.reviewed ?? true,
  };
  return {
    timestamp: Timestamp.fromDate(t.timestamp),
    enc: await encryptJson(json, dek),
    v: 1,
  };
}

// Live subscription. cb(transactions[]) | err(error).
export function watchTransactions(uid, dek, cb, err) {
  const q = query(txCol(uid), orderBy('timestamp', 'desc'));
  return onSnapshot(
    q,
    async (snap) => {
      try {
        const out = [];
        for (const d of snap.docs) out.push(await decodeTxn(d.id, d.data(), dek));
        cb(out);
      } catch (e) {
        err?.(e);
      }
    },
    err,
  );
}

// One-shot fetch of the newest txn — used by the unlock self-test.
export async function fetchNewestTxnDoc(uid) {
  const q = query(txCol(uid), orderBy('timestamp', 'desc'));
  const snap = await getDocs(q);
  return snap.empty ? null : snap.docs[0];
}

export async function saveTransaction(uid, dek, t) {
  await setDoc(doc(txCol(uid), t.id), await encodeTxn(t, dek));
}
export async function deleteTransaction(uid, id) {
  await deleteDoc(doc(txCol(uid), id));
}

// ── Budgets ────────────────────────────────────────────────
export function watchBudgets(uid, dek, cb, err) {
  return onSnapshot(
    budgetCol(uid),
    async (snap) => {
      try {
        const out = [];
        for (const d of snap.docs) {
          const data = d.data();
          if (typeof data.enc === 'string') {
            const m = await decryptJson(data.enc, dek);
            out.push({
              id: d.id,
              categoryId: data.categoryId || d.id,
              monthlyCap: Number(m.monthlyCap) || 0,
              updatedAt: m.updatedAt ? new Date(Number(m.updatedAt)) : new Date(),
            });
          } else {
            out.push({
              id: d.id,
              categoryId: data.categoryId || d.id,
              monthlyCap: Number(data.monthlyCap) || 0,
              updatedAt: data.updatedAt?.toDate ? data.updatedAt.toDate() : new Date(),
            });
          }
        }
        cb(out);
      } catch (e) {
        err?.(e);
      }
    },
    err,
  );
}

export async function setBudget(uid, dek, b) {
  const docData = {
    categoryId: b.categoryId,
    enc: await encryptJson(
      { monthlyCap: b.monthlyCap, updatedAt: Date.now() },
      dek,
    ),
    v: 1,
  };
  await setDoc(doc(budgetCol(uid), b.categoryId), docData);
}
export async function deleteBudget(uid, categoryId) {
  await deleteDoc(doc(budgetCol(uid), categoryId));
}

// ── Goals ──────────────────────────────────────────────────
export function watchGoals(uid, dek, cb, err) {
  const q = query(goalsCol(uid), orderBy('createdAt', 'desc'));
  return onSnapshot(
    q,
    async (snap) => {
      try {
        const out = [];
        for (const d of snap.docs) {
          const data = d.data();
          const m = typeof data.enc === 'string' ? await decryptJson(data.enc, dek) : data;
          out.push({
            id: d.id,
            title: m.title || 'Goal',
            target: Number(m.target) || 0,
            saved: Number(m.saved) || 0,
            emoji: m.emoji || '🎯',
            deadline: m.deadline ? new Date(Number(m.deadline)) : null,
            createdAt: m.createdAt ? new Date(Number(m.createdAt)) : new Date(),
          });
        }
        cb(out);
      } catch (e) {
        err?.(e);
      }
    },
    err,
  );
}

export async function setGoal(uid, dek, g) {
  const json = {
    title: g.title,
    target: g.target,
    saved: g.saved,
    emoji: g.emoji,
    deadline: g.deadline ? g.deadline.getTime() : null,
    createdAt: (g.createdAt || new Date()).getTime(),
  };
  await setDoc(doc(goalsCol(uid), g.id), {
    createdAt: Timestamp.fromDate(g.createdAt || new Date()),
    enc: await encryptJson(json, dek),
    v: 1,
  });
}
export async function deleteGoal(uid, id) {
  await deleteDoc(doc(goalsCol(uid), id));
}

// ── Profile (income encrypted into incomeEnc) ──────────────
export async function fetchProfile(uid, dek) {
  const snap = await getDoc(profileRef(uid));
  if (!snap.exists()) return null;
  const data = snap.data();
  let monthlyIncome = Number(data.monthlyIncome) || 0;
  if (typeof data.incomeEnc === 'string') {
    try {
      const dec = await decryptJson(data.incomeEnc, dek);
      monthlyIncome = Number(dec.income) || 0;
    } catch {
      /* leave fallback */
    }
  }
  return {
    uid,
    email: data.email || '',
    displayName: data.displayName || null,
    currency: data.currency || 'INR',
    monthlyIncome,
  };
}

export async function saveIncome(uid, dek, income) {
  await setDoc(
    profileRef(uid),
    { incomeEnc: await encryptJson({ income }, dek) },
    { merge: true },
  );
}
