import { useMemo, useState } from 'react';
import { Plus, Pencil, Trash2, Check, X, Wallet } from 'lucide-react';
import { useData } from '../state/Data.jsx';
import { useVault } from '../state/Vault.jsx';
import { setBudget, deleteBudget, saveIncome } from '../data/repo.js';
import { byCategory, thisMonth } from '../services/analytics.js';
import { CATEGORIES, categoryById, formatRupees } from '../data/categories.js';
import CategoryIcon from '../components/CategoryIcon.jsx';

export default function Budgets() {
  const { txns, budgets, profile, refreshProfile } = useData();
  const { user, dek } = useVault();
  const [editingIncome, setEditingIncome] = useState(false);
  const [incomeVal, setIncomeVal] = useState('');
  const [adding, setAdding] = useState(false);
  const [newCat, setNewCat] = useState('food');
  const [newCap, setNewCap] = useState('');

  const spentByCat = useMemo(() => {
    const m = {};
    for (const c of byCategory(thisMonth(txns))) m[c.id] = c.value;
    return m;
  }, [txns]);

  const usedCatIds = new Set(budgets.map((b) => b.categoryId));
  const available = CATEGORIES.filter((c) => !usedCatIds.has(c.id) && c.id !== 'salary');

  async function saveNewBudget() {
    const cap = parseFloat(newCap);
    if (!(cap > 0)) return;
    await setBudget(user.uid, dek, { categoryId: newCat, monthlyCap: cap });
    setAdding(false);
    setNewCap('');
  }

  async function commitIncome() {
    const v = parseFloat(incomeVal);
    await saveIncome(user.uid, dek, isNaN(v) ? 0 : v);
    setEditingIncome(false);
    refreshProfile();
  }

  return (
    <div className="space-y-5">
      <h1 className="font-display text-3xl font-semibold">Budgets</h1>

      {/* Monthly income */}
      <div className="card flex items-center justify-between">
        <div className="flex items-center gap-3">
          <div className="h-11 w-11 rounded-2xl bg-credit/15 grid place-items-center"><Wallet className="text-credit" size={20} /></div>
          <div>
            <div className="text-xs text-muted">Monthly income (encrypted)</div>
            {editingIncome ? (
              <div className="flex items-center gap-2 mt-1">
                <input type="number" autoFocus value={incomeVal} onChange={(e) => setIncomeVal(e.target.value)}
                  className="field !py-1.5 w-32" placeholder="0" />
                <button onClick={commitIncome} className="text-credit"><Check size={18} /></button>
                <button onClick={() => setEditingIncome(false)} className="text-muted"><X size={18} /></button>
              </div>
            ) : (
              <div className="font-display text-2xl font-bold">{formatRupees(profile?.monthlyIncome || 0)}</div>
            )}
          </div>
        </div>
        {!editingIncome && (
          <button onClick={() => { setIncomeVal(String(profile?.monthlyIncome || '')); setEditingIncome(true); }} className="btn-ghost !py-2">
            <Pencil size={15} /> Edit
          </button>
        )}
      </div>

      {/* Category budgets */}
      <div className="flex items-center justify-between">
        <div className="font-display text-lg font-semibold">Category caps</div>
        {!adding && available.length > 0 && (
          <button onClick={() => { setNewCat(available[0].id); setAdding(true); }} className="btn-primary !py-2"><Plus size={16} /> Add cap</button>
        )}
      </div>

      {adding && (
        <div className="card flex flex-col sm:flex-row gap-3 items-stretch sm:items-end">
          <div className="flex-1">
            <span className="text-xs text-muted ml-1">Category</span>
            <select value={newCat} onChange={(e) => setNewCat(e.target.value)} className="field mt-1 appearance-none">
              {available.map((c) => <option key={c.id} value={c.id} className="bg-card">{c.label}</option>)}
            </select>
          </div>
          <div className="flex-1">
            <span className="text-xs text-muted ml-1">Monthly cap (₹)</span>
            <input type="number" value={newCap} onChange={(e) => setNewCap(e.target.value)} className="field mt-1" placeholder="0" />
          </div>
          <div className="flex gap-2">
            <button onClick={saveNewBudget} className="btn-primary">Save</button>
            <button onClick={() => setAdding(false)} className="btn-ghost">Cancel</button>
          </div>
        </div>
      )}

      {budgets.length === 0 && !adding ? (
        <div className="card text-center text-muted py-10">No budgets yet. Add a cap to track your pace this month.</div>
      ) : (
        <div className="grid sm:grid-cols-2 gap-4">
          {budgets.map((b) => {
            const spent = spentByCat[b.categoryId] || 0;
            const pct = b.monthlyCap > 0 ? Math.min(1, spent / b.monthlyCap) : 0;
            const over = spent > b.monthlyCap;
            const c = categoryById(b.categoryId);
            return (
              <div key={b.id} className="card">
                <div className="flex items-center justify-between">
                  <div className="flex items-center gap-2.5">
                    <div className="h-9 w-9 rounded-xl grid place-items-center" style={{ background: `${c.color}1f` }}>
                      <CategoryIcon id={b.categoryId} size={16} />
                    </div>
                    <div className="font-medium">{c.label}</div>
                  </div>
                  <button onClick={() => deleteBudget(user.uid, b.categoryId)} className="text-muted hover:text-debit"><Trash2 size={15} /></button>
                </div>
                <div className="mt-4 h-2.5 rounded-full bg-white/10 overflow-hidden">
                  <div className="h-full rounded-full transition-all" style={{ width: `${pct * 100}%`, background: over ? '#ef4444' : c.color }} />
                </div>
                <div className="flex justify-between text-sm mt-2">
                  <span className={over ? 'text-debit' : 'text-muted'}>{formatRupees(spent)} spent</span>
                  <span className="text-muted">of {formatRupees(b.monthlyCap)}</span>
                </div>
                {over && <div className="text-debit text-xs mt-1">Over by {formatRupees(spent - b.monthlyCap)}</div>}
              </div>
            );
          })}
        </div>
      )}
    </div>
  );
}
