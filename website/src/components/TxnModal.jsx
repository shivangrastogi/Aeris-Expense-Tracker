import { useEffect, useMemo, useState } from 'react';
import { motion, AnimatePresence } from 'framer-motion';
import { X, Trash2, Loader2 } from 'lucide-react';
import { CATEGORIES, classify } from '../data/categories.js';
import { saveTransaction, deleteTransaction } from '../data/repo.js';
import { learnedCategoryFor, rememberCategory } from '../data/categoryRules.js';
import { lookupMerchant } from '../data/merchantDirectory.js';
import { useVault } from '../state/Vault.jsx';
import { useData } from '../state/Data.jsx';

function toInputDate(d) {
  const p = (n) => String(n).padStart(2, '0');
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}T${p(d.getHours())}:${p(d.getMinutes())}`;
}

export default function TxnModal({ open, initial, onClose }) {
  const { user, dek } = useVault();
  const { txns } = useData();
  const editing = !!initial;
  const [amount, setAmount] = useState('');
  const [direction, setDirection] = useState('debit');
  const [categoryId, setCategoryId] = useState('other');
  const [catTouched, setCatTouched] = useState(false);
  const [merchant, setMerchant] = useState('');
  const [note, setNote] = useState('');
  const [when, setWhen] = useState(toInputDate(new Date()));
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState(null);

  // Distinct past merchants for the autofill datalist.
  const knownMerchants = useMemo(() => {
    const s = new Set();
    for (const t of txns) if (t.merchant?.trim()) s.add(t.merchant.trim());
    return [...s].sort();
  }, [txns]);

  useEffect(() => {
    if (open) {
      setErr(null);
      setAmount(initial ? String(initial.amount) : '');
      setDirection(initial?.direction || 'debit');
      setCategoryId(initial?.categoryId || 'other');
      setCatTouched(!!initial); // editing → don't auto-override their category
      setMerchant(initial?.merchant || '');
      setNote(initial?.note || '');
      setWhen(toInputDate(initial?.timestamp || new Date()));
    }
  }, [open, initial]);

  // Auto-pick a category from the merchant: learned rule → directory → keyword.
  // Stops once the user has manually chosen a category.
  function onMerchantChange(v) {
    setMerchant(v);
    if (catTouched) return;
    const m = v.trim();
    if (!m) return;
    const cat =
      learnedCategoryFor(m) || lookupMerchant(m)?.categoryId || classify(m);
    if (cat && cat !== 'other') setCategoryId(cat);
  }

  async function save() {
    const amt = parseFloat(amount);
    if (!(amt > 0)) { setErr('Enter an amount greater than 0.'); return; }
    setBusy(true);
    setErr(null);
    try {
      const t = {
        id: initial?.id || crypto.randomUUID(),
        amount: amt,
        direction,
        timestamp: new Date(when),
        merchant: merchant.trim() || null,
        account: initial?.account || null,
        categoryId,
        note: note.trim() || null,
        source: initial?.source || 'manual',
        smsBody: initial?.smsBody || null,
        smsSender: initial?.smsSender || null,
        reviewed: true,
        // Preserve UPI enrichment the phone app wrote (don't drop on edit).
        reference: initial?.reference || null,
        upiVpa: initial?.upiVpa || null,
      };
      await saveTransaction(user.uid, dek, t);
      // Teach the app this merchant → category for next time.
      if (t.merchant) rememberCategory(t.merchant, categoryId);
      onClose();
    } catch (e) {
      setErr(e?.message || 'Could not save.');
      setBusy(false);
    }
  }

  async function remove() {
    setBusy(true);
    try {
      await deleteTransaction(user.uid, initial.id);
      onClose();
    } catch (e) {
      setErr(e?.message || 'Could not delete.');
      setBusy(false);
    }
  }

  return (
    <AnimatePresence>
      {open && (
        <motion.div
          className="fixed inset-0 z-50 grid place-items-end sm:place-items-center bg-black/60 backdrop-blur-sm p-0 sm:p-6"
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          exit={{ opacity: 0 }}
          onClick={onClose}
        >
          <motion.div
            onClick={(e) => e.stopPropagation()}
            initial={{ y: 40, opacity: 0 }}
            animate={{ y: 0, opacity: 1 }}
            exit={{ y: 40, opacity: 0 }}
            transition={{ type: 'spring', stiffness: 320, damping: 30 }}
            className="w-full sm:max-w-md glass rounded-t-3xl sm:rounded-3xl p-6 max-h-[90vh] overflow-y-auto"
          >
            <div className="flex items-center justify-between mb-5">
              <h3 className="font-display text-xl font-semibold">{editing ? 'Edit transaction' : 'Add transaction'}</h3>
              <button onClick={onClose} className="text-muted hover:text-ink"><X size={20} /></button>
            </div>

            <div className="flex gap-2 mb-4">
              {['debit', 'credit'].map((d) => (
                <button
                  key={d}
                  onClick={() => setDirection(d)}
                  className={`flex-1 rounded-2xl py-2.5 text-sm font-medium capitalize transition-colors border ${
                    direction === d
                      ? d === 'debit' ? 'bg-debit/15 border-debit/40 text-debit' : 'bg-credit/15 border-credit/40 text-credit'
                      : 'border-white/10 text-muted'
                  }`}
                >
                  {d === 'debit' ? 'Expense' : 'Income'}
                </button>
              ))}
            </div>

            <div className="space-y-3">
              <div>
                <span className="text-xs text-muted ml-1">Amount (₹)</span>
                <input type="number" inputMode="decimal" min="0" step="0.01" value={amount}
                  onChange={(e) => setAmount(e.target.value)} className="field mt-1" placeholder="0" autoFocus />
              </div>
              <div>
                <span className="text-xs text-muted ml-1">Category</span>
                <select value={categoryId} onChange={(e) => { setCategoryId(e.target.value); setCatTouched(true); }} className="field mt-1 appearance-none">
                  {CATEGORIES.map((c) => <option key={c.id} value={c.id} className="bg-card">{c.label}</option>)}
                </select>
              </div>
              <div>
                <span className="text-xs text-muted ml-1">Merchant / description</span>
                <input value={merchant} onChange={(e) => onMerchantChange(e.target.value)} className="field mt-1" placeholder="e.g. Swiggy" list="aeris-merchants" autoComplete="off" />
                <datalist id="aeris-merchants">
                  {knownMerchants.map((m) => <option key={m} value={m} />)}
                </datalist>
              </div>
              <div>
                <span className="text-xs text-muted ml-1">Date & time</span>
                <input type="datetime-local" value={when} onChange={(e) => setWhen(e.target.value)} className="field mt-1" />
              </div>
              <div>
                <span className="text-xs text-muted ml-1">Note (optional)</span>
                <input value={note} onChange={(e) => setNote(e.target.value)} className="field mt-1" placeholder="Anything to remember" />
              </div>
            </div>

            {err && <div className="text-debit text-sm mt-3">{err}</div>}

            <div className="flex gap-2 mt-6">
              {editing && (
                <button onClick={remove} disabled={busy} className="btn-ghost text-debit border-debit/30 px-4">
                  <Trash2 size={16} />
                </button>
              )}
              <button onClick={save} disabled={busy} className="btn-primary flex-1">
                {busy ? <Loader2 className="animate-spin" size={18} /> : editing ? 'Save changes' : 'Add transaction'}
              </button>
            </div>
          </motion.div>
        </motion.div>
      )}
    </AnimatePresence>
  );
}
