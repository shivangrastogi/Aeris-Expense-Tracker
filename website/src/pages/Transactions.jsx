import { useMemo, useState } from 'react';
import { Plus, Search, Pencil, ArrowUpRight, ArrowDownRight, Loader2 } from 'lucide-react';
import { useData } from '../state/Data.jsx';
import { formatRupees, relativeDate, categoryById, CATEGORIES } from '../data/categories.js';
import { paymentAppFor } from '../data/merchantDirectory.js';
import CategoryIcon from '../components/CategoryIcon.jsx';
import TxnModal from '../components/TxnModal.jsx';

const RANGES = [
  { id: 'month', label: 'This month' },
  { id: '30', label: 'Last 30 days' },
  { id: 'all', label: 'All time' },
];

export default function Transactions() {
  const { txns, loading } = useData();
  const [q, setQ] = useState('');
  const [cat, setCat] = useState('all');
  const [range, setRange] = useState('month');
  const [modal, setModal] = useState({ open: false, initial: null });

  const filtered = useMemo(() => {
    const now = new Date();
    let start = new Date(0);
    if (range === 'month') start = new Date(now.getFullYear(), now.getMonth(), 1);
    else if (range === '30') { start = new Date(now); start.setDate(now.getDate() - 30); }
    const term = q.toLowerCase().trim();
    return txns.filter((t) => {
      if (t.timestamp < start) return false;
      if (cat !== 'all' && t.categoryId !== cat) return false;
      if (term) {
        const hay = `${t.merchant || ''} ${categoryById(t.categoryId).label} ${t.note || ''}`.toLowerCase();
        if (!hay.includes(term)) return false;
      }
      return true;
    });
  }, [txns, q, cat, range]);

  const total = filtered.filter((t) => t.direction === 'debit').reduce((a, b) => a + b.amount, 0);

  // Group by day.
  const groups = useMemo(() => {
    const m = new Map();
    for (const t of filtered) {
      const key = t.timestamp.toDateString();
      if (!m.has(key)) m.set(key, []);
      m.get(key).push(t);
    }
    return [...m.entries()];
  }, [filtered]);

  return (
    <div className="space-y-5">
      <div className="flex items-center justify-between flex-wrap gap-3">
        <div>
          <h1 className="font-display text-3xl font-semibold">Transactions</h1>
          <div className="text-muted text-sm">{filtered.length} shown · {formatRupees(total)} spent</div>
        </div>
        <button onClick={() => setModal({ open: true, initial: null })} className="btn-primary">
          <Plus size={18} /> Add
        </button>
      </div>

      {/* Filters */}
      <div className="flex flex-col sm:flex-row gap-3">
        <div className="relative flex-1">
          <Search size={16} className="absolute left-3.5 top-1/2 -translate-y-1/2 text-muted" />
          <input value={q} onChange={(e) => setQ(e.target.value)} className="field pl-10" placeholder="Search merchant, note, category…" />
        </div>
        <select value={cat} onChange={(e) => setCat(e.target.value)} className="field sm:w-48 appearance-none">
          <option value="all" className="bg-card">All categories</option>
          {CATEGORIES.map((c) => <option key={c.id} value={c.id} className="bg-card">{c.label}</option>)}
        </select>
      </div>
      <div className="flex gap-2">
        {RANGES.map((r) => (
          <button key={r.id} onClick={() => setRange(r.id)}
            className={`rounded-full px-4 py-1.5 text-sm transition-colors ${range === r.id ? 'bg-mint/15 text-mint border border-mint/30' : 'glass text-muted'}`}>
            {r.label}
          </button>
        ))}
      </div>

      {loading ? (
        <div className="grid place-items-center h-[40vh]"><Loader2 className="animate-spin text-mint" size={28} /></div>
      ) : groups.length === 0 ? (
        <div className="card text-center text-muted py-12">No transactions match your filters.</div>
      ) : (
        <div className="space-y-5">
          {groups.map(([day, items]) => (
            <div key={day}>
              <div className="text-xs text-muted uppercase tracking-wider mb-2 ml-1">{relativeDate(items[0].timestamp)}</div>
              <div className="card divide-y divide-white/[0.05] !p-2">
                {items.map((t) => (
                  <button key={t.id} onClick={() => setModal({ open: true, initial: t })}
                    className="group w-full flex items-center gap-3 p-3 rounded-2xl hover:bg-white/[0.04] transition-colors text-left">
                    <div className="h-10 w-10 rounded-2xl grid place-items-center shrink-0" style={{ background: `${categoryById(t.categoryId).color}1f` }}>
                      <CategoryIcon id={t.categoryId} />
                    </div>
                    <div className="min-w-0 flex-1">
                      <div className="truncate font-medium">{t.merchant || categoryById(t.categoryId).label}</div>
                      <div className="text-xs text-muted truncate">{categoryById(t.categoryId).label}{paymentAppFor(t.upiVpa) ? ` · ${paymentAppFor(t.upiVpa)}` : ''}{t.note ? ` · ${t.note}` : ''}</div>
                    </div>
                    <div className={`flex items-center gap-1 font-semibold ${t.direction === 'credit' ? 'text-credit' : 'text-ink'}`}>
                      {t.direction === 'credit' ? <ArrowDownRight size={15} /> : <ArrowUpRight size={15} />}
                      {formatRupees(t.amount)}
                    </div>
                    <Pencil size={14} className="text-muted opacity-0 group-hover:opacity-100 transition-opacity shrink-0" />
                  </button>
                ))}
              </div>
            </div>
          ))}
        </div>
      )}

      <TxnModal open={modal.open} initial={modal.initial} onClose={() => setModal({ open: false, initial: null })} />
    </div>
  );
}
