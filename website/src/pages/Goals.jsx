import { useState } from 'react';
import { Plus, Trash2, Check, X, PartyPopper } from 'lucide-react';
import { motion } from 'framer-motion';
import { useData } from '../state/Data.jsx';
import { useVault } from '../state/Vault.jsx';
import { setGoal, deleteGoal } from '../data/repo.js';
import { formatRupees } from '../data/categories.js';

const EMOJIS = ['🎯', '✈️', '🏠', '🚗', '💍', '🎓', '📱', '🏖️', '💰', '🎁'];

export default function Goals() {
  const { goals } = useData();
  const { user, dek } = useVault();
  const [adding, setAdding] = useState(false);
  const [title, setTitle] = useState('');
  const [target, setTarget] = useState('');
  const [emoji, setEmoji] = useState('🎯');
  const [contribFor, setContribFor] = useState(null);
  const [contribVal, setContribVal] = useState('');

  async function addGoal() {
    const t = parseFloat(target);
    if (!title.trim() || !(t > 0)) return;
    await setGoal(user.uid, dek, {
      id: crypto.randomUUID(), title: title.trim(), target: t, saved: 0, emoji,
      deadline: null, createdAt: new Date(),
    });
    setAdding(false); setTitle(''); setTarget(''); setEmoji('🎯');
  }

  async function contribute(g) {
    const add = parseFloat(contribVal);
    if (!(add !== 0)) { setContribFor(null); return; }
    await setGoal(user.uid, dek, { ...g, saved: Math.max(0, g.saved + add) });
    setContribFor(null); setContribVal('');
  }

  return (
    <div className="space-y-5">
      <div className="flex items-center justify-between">
        <h1 className="font-display text-3xl font-semibold">Goals</h1>
        {!adding && <button onClick={() => setAdding(true)} className="btn-primary !py-2"><Plus size={16} /> New goal</button>}
      </div>

      {adding && (
        <div className="card space-y-3">
          <div className="flex gap-2 flex-wrap">
            {EMOJIS.map((e) => (
              <button key={e} onClick={() => setEmoji(e)}
                className={`h-10 w-10 rounded-xl grid place-items-center text-lg transition-colors ${emoji === e ? 'bg-mint/20 border border-mint/40' : 'glass'}`}>{e}</button>
            ))}
          </div>
          <input value={title} onChange={(e) => setTitle(e.target.value)} className="field" placeholder="Goal name (e.g. Trip to Goa)" autoFocus />
          <input type="number" value={target} onChange={(e) => setTarget(e.target.value)} className="field" placeholder="Target amount (₹)" />
          <div className="flex gap-2">
            <button onClick={addGoal} className="btn-primary flex-1">Create goal</button>
            <button onClick={() => setAdding(false)} className="btn-ghost">Cancel</button>
          </div>
        </div>
      )}

      {goals.length === 0 && !adding ? (
        <div className="card text-center text-muted py-12">No goals yet. Set one and watch your progress grow. 🌱</div>
      ) : (
        <div className="grid sm:grid-cols-2 gap-4">
          {goals.map((g) => {
            const pct = g.target > 0 ? Math.min(1, g.saved / g.target) : 0;
            const done = g.target > 0 && g.saved >= g.target;
            return (
              <motion.div key={g.id} layout className="card">
                <div className="flex items-start justify-between">
                  <div className="flex items-center gap-3">
                    <div className="h-12 w-12 rounded-2xl bg-white/[0.06] grid place-items-center text-2xl">{g.emoji}</div>
                    <div>
                      <div className="font-display text-lg font-semibold leading-tight">{g.title}</div>
                      <div className="text-xs text-muted">{formatRupees(g.saved)} of {formatRupees(g.target)}</div>
                    </div>
                  </div>
                  <button onClick={() => deleteGoal(user.uid, g.id)} className="text-muted hover:text-debit"><Trash2 size={15} /></button>
                </div>

                <div className="mt-4 h-3 rounded-full bg-white/10 overflow-hidden">
                  <motion.div className="h-full rounded-full bg-gradient-to-r from-teal to-mint"
                    initial={{ width: 0 }} animate={{ width: `${pct * 100}%` }} transition={{ duration: 0.7, ease: [0.16, 1, 0.3, 1] }} />
                </div>

                <div className="flex items-center justify-between mt-3">
                  {done ? (
                    <span className="inline-flex items-center gap-1.5 text-mint text-sm font-medium"><PartyPopper size={15} /> Goal reached!</span>
                  ) : (
                    <span className="text-sm text-muted">{Math.round(pct * 100)}% · {formatRupees(g.remaining ?? (g.target - g.saved))} to go</span>
                  )}
                  {contribFor === g.id ? (
                    <div className="flex items-center gap-1.5">
                      <input type="number" autoFocus value={contribVal} onChange={(e) => setContribVal(e.target.value)}
                        className="field !py-1.5 w-24" placeholder="₹" />
                      <button onClick={() => contribute(g)} className="text-credit"><Check size={18} /></button>
                      <button onClick={() => setContribFor(null)} className="text-muted"><X size={18} /></button>
                    </div>
                  ) : (
                    <button onClick={() => { setContribVal(''); setContribFor(g.id); }} className="text-mint text-sm hover:underline">+ Add money</button>
                  )}
                </div>
              </motion.div>
            );
          })}
        </div>
      )}
    </div>
  );
}
