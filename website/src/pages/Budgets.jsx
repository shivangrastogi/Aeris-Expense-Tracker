import { useMemo, useState } from 'react';
import { Plus, Pencil, Trash2, Check, X, Wallet, Sparkles } from 'lucide-react';
import { useData } from '../state/Data.jsx';
import { useVault } from '../state/Vault.jsx';
import { setBudget, deleteBudget, saveIncome } from '../data/repo.js';
import { byCategory, thisMonth, categoryMonthlyAverages, monthSummary } from '../services/analytics.js';
import { CATEGORIES, categoryById, formatRupees, TOTAL_BUDGET_ID } from '../data/categories.js';
import CategoryIcon from '../components/CategoryIcon.jsx';

const SKIP_SUGGEST = new Set(['salary', 'transfer', 'cash', 'investment', 'other']);
function roundCap(v) {
  if (!(v > 0)) return 0;
  const step = v < 2000 ? 100 : v < 10000 ? 500 : 1000;
  return Math.ceil(v / step) * step;
}

export default function Budgets() {
  const { txns, budgets, profile, refreshProfile } = useData();
  const { user, dek } = useVault();
  const [editingIncome, setEditingIncome] = useState(false);
  const [incomeVal, setIncomeVal] = useState('');
  const [adding, setAdding] = useState(false);
  const [newCat, setNewCat] = useState('food');
  const [newCap, setNewCap] = useState('');
  const [editingTotal, setEditingTotal] = useState(false);
  const [totalVal, setTotalVal] = useState('');

  const total = budgets.find((b) => b.categoryId === TOTAL_BUDGET_ID) || null;
  const categoryBudgets = budgets.filter((b) => b.categoryId !== TOTAL_BUDGET_ID);
  const monthSpent = useMemo(() => monthSummary(txns).spent, [txns]);

  async function commitTotal() {
    const v = parseFloat(totalVal);
    if (v > 0) await setBudget(user.uid, dek, { categoryId: TOTAL_BUDGET_ID, monthlyCap: v });
    setEditingTotal(false);
  }
  async function removeTotal() {
    await deleteBudget(user.uid, TOTAL_BUDGET_ID);
  }

  const spentByCat = useMemo(() => {
    const m = {};
    for (const c of byCategory(thisMonth(txns))) m[c.id] = c.value;
    return m;
  }, [txns]);

  const usedCatIds = new Set(budgets.map((b) => b.categoryId));
  const available = CATEGORIES.filter((c) => !usedCatIds.has(c.id) && c.id !== 'salary');

  const [suggestions, setSuggestions] = useState(null); // null = panel closed

  function buildSuggestions() {
    const avg = categoryMonthlyAverages(txns, 3);
    const out = [];
    for (const [cat, v] of Object.entries(avg)) {
      if (SKIP_SUGGEST.has(cat) || usedCatIds.has(cat)) continue;
      const cap = roundCap(v);
      if (cap > 0) out.push({ categoryId: cat, cap });
    }
    out.sort((a, b) => b.cap - a.cap);
    setSuggestions(out);
  }

  async function applySuggestion(s) {
    await setBudget(user.uid, dek, { categoryId: s.categoryId, monthlyCap: s.cap });
    setSuggestions((cur) => (cur || []).filter((x) => x.categoryId !== s.categoryId));
  }

  async function applyAllSuggestions() {
    for (const s of suggestions || []) {
      await setBudget(user.uid, dek, { categoryId: s.categoryId, monthlyCap: s.cap });
    }
    setSuggestions(null);
  }

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

      {/* Total monthly budget (one overall cap) */}
      <div className="card">
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-3">
            <div className="h-11 w-11 rounded-2xl bg-mint/15 grid place-items-center"><Wallet className="text-mint" size={20} /></div>
            <div>
              <div className="text-xs text-muted">Total monthly budget</div>
              {editingTotal ? (
                <div className="flex items-center gap-2 mt-1">
                  <input type="number" autoFocus value={totalVal} onChange={(e) => setTotalVal(e.target.value)} className="field !py-1.5 w-32" placeholder="0" />
                  <button onClick={commitTotal} className="text-credit"><Check size={18} /></button>
                  <button onClick={() => setEditingTotal(false)} className="text-muted"><X size={18} /></button>
                </div>
              ) : (
                <div className="font-display text-2xl font-bold">{total ? formatRupees(total.monthlyCap) : 'Not set'}</div>
              )}
            </div>
          </div>
          {!editingTotal && (
            <div className="flex gap-2">
              {total && <button onClick={removeTotal} className="btn-ghost !py-2 text-debit"><Trash2 size={15} /></button>}
              <button onClick={() => { setTotalVal(total ? String(total.monthlyCap) : ''); setEditingTotal(true); }} className="btn-ghost !py-2"><Pencil size={15} /> {total ? 'Edit' : 'Set'}</button>
            </div>
          )}
        </div>
        {total && (
          <>
            <div className="mt-4 h-2.5 rounded-full bg-white/10 overflow-hidden">
              <div className="h-full rounded-full transition-all" style={{ width: `${Math.min(1, monthSpent / total.monthlyCap) * 100}%`, background: monthSpent > total.monthlyCap ? '#ef4444' : '#5eead4' }} />
            </div>
            <div className="flex justify-between text-sm mt-2">
              <span className={monthSpent > total.monthlyCap ? 'text-debit' : 'text-muted'}>{formatRupees(monthSpent)} spent</span>
              <span className="text-muted">of {formatRupees(total.monthlyCap)} {monthSpent > total.monthlyCap ? `· over by ${formatRupees(monthSpent - total.monthlyCap)}` : `· ${formatRupees(Math.max(0, total.monthlyCap - monthSpent))} left`}</span>
            </div>
          </>
        )}
      </div>

      {/* Category budgets */}
      <div className="flex items-center justify-between">
        <div className="font-display text-lg font-semibold">Category caps</div>
        <div className="flex gap-2">
          <button onClick={buildSuggestions} className="btn-ghost !py-2"><Sparkles size={16} /> Suggest</button>
          {!adding && available.length > 0 && (
            <button onClick={() => { setNewCat(available[0].id); setAdding(true); }} className="btn-primary !py-2"><Plus size={16} /> Add cap</button>
          )}
        </div>
      </div>

      {suggestions && (
        <div className="card space-y-3">
          <div className="flex items-center justify-between">
            <div>
              <div className="font-medium">Suggested from your spending</div>
              <div className="text-xs text-muted">Based on your last 3 months · adjust anytime</div>
            </div>
            <button onClick={() => setSuggestions(null)} className="text-muted hover:text-ink"><X size={18} /></button>
          </div>
          {suggestions.length === 0 ? (
            <div className="text-muted text-sm">Not enough history yet (or everything's already budgeted).</div>
          ) : (
            <>
              {suggestions.map((s) => {
                const c = categoryById(s.categoryId);
                return (
                  <div key={s.categoryId} className="flex items-center gap-3">
                    <div className="h-8 w-8 rounded-xl grid place-items-center" style={{ background: `${c.color}1f` }}>
                      <CategoryIcon id={s.categoryId} size={15} />
                    </div>
                    <div className="flex-1 min-w-0">
                      <div className="font-medium truncate">{c.label}</div>
                      <div className="text-xs text-muted">Cap {formatRupees(s.cap)} / month</div>
                    </div>
                    <button onClick={() => applySuggestion(s)} className="btn-ghost !py-1.5 text-mint"><Check size={15} /> Add</button>
                  </div>
                );
              })}
              <button onClick={applyAllSuggestions} className="btn-primary w-full">Apply all ({suggestions.length})</button>
            </>
          )}
        </div>
      )}

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

      {categoryBudgets.length === 0 && !adding ? (
        <div className="card text-center text-muted py-10">No category caps yet. Add one, or set a total budget above.</div>
      ) : (
        <div className="grid sm:grid-cols-2 gap-4">
          {categoryBudgets.map((b) => {
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
