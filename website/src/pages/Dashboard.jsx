import { useMemo } from 'react';
import { Link } from 'react-router-dom';
import { motion } from 'framer-motion';
import {
  TrendingDown,
  TrendingUp,
  CalendarDays,
  ArrowUpRight,
  ArrowDownRight,
  Loader2,
  Wallet,
} from 'lucide-react';
import { useData } from '../state/Data.jsx';
import { useVault } from '../state/Vault.jsx';
import { monthSummary, monthlySeries } from '../services/analytics.js';
import { formatRupees, relativeDate, categoryById } from '../data/categories.js';
import CategoryIcon from '../components/CategoryIcon.jsx';
import {
  ResponsiveContainer,
  AreaChart,
  Area,
  XAxis,
  Tooltip,
} from 'recharts';

const ease = [0.16, 1, 0.3, 1];

function Stat({ label, value, sub, tone = 'ink', icon: Icon, delay = 0 }) {
  return (
    <motion.div
      initial={{ opacity: 0, y: 16 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ duration: 0.4, ease, delay }}
      className="card"
    >
      <div className="flex items-center justify-between text-muted text-xs">
        {label}
        {Icon && <Icon size={16} className="text-mint" />}
      </div>
      <div className={`font-display text-3xl font-bold mt-2 ${tone === 'credit' ? 'text-credit' : tone === 'debit' ? 'text-debit' : 'text-ink'}`}>
        {value}
      </div>
      {sub && <div className="text-xs text-muted mt-1">{sub}</div>}
    </motion.div>
  );
}

export default function Dashboard() {
  const { txns, profile, loading } = useData();
  const { user } = useVault();
  const s = useMemo(() => monthSummary(txns, profile?.monthlyIncome || 0), [txns, profile]);
  const series = useMemo(() => monthlySeries(txns, 6), [txns]);
  const recent = useMemo(() => txns.slice(0, 6), [txns]);

  const name = profile?.displayName || user?.displayName || (user?.email || '').split('@')[0];
  const hour = new Date().getHours();
  const greet = hour < 12 ? 'Good morning' : hour < 17 ? 'Good afternoon' : 'Good evening';

  if (loading) {
    return <div className="grid place-items-center h-[60vh]"><Loader2 className="animate-spin text-mint" size={28} /></div>;
  }

  return (
    <div className="space-y-6">
      <div>
        <div className="text-muted text-sm">{greet},</div>
        <h1 className="font-display text-3xl font-semibold capitalize">{name} 👋</h1>
      </div>

      <div className="grid sm:grid-cols-2 lg:grid-cols-4 gap-4">
        <Stat label="Spent this month" value={formatRupees(s.spent)} icon={TrendingDown}
          sub={`${s.txCount} transactions`} delay={0.02} />
        <Stat label="Income this month" value={formatRupees(s.earned)} tone="credit" icon={TrendingUp}
          sub={profile?.monthlyIncome ? `Set income ${formatRupees(profile.monthlyIncome)}` : 'From credits'} delay={0.06} />
        <Stat label="Net" value={formatRupees(s.net)} tone={s.net >= 0 ? 'credit' : 'debit'} icon={Wallet}
          sub={s.incomeLeft != null ? `${formatRupees(s.incomeLeft)} of income left` : 'Income − expenses'} delay={0.1} />
        <Stat label="Avg / day" value={formatRupees(s.avgPerDay)} icon={CalendarDays}
          sub={s.top ? `Top: ${s.top.label}` : '—'} delay={0.14} />
      </div>

      {/* Trend */}
      <motion.div
        initial={{ opacity: 0, y: 16 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ duration: 0.4, ease, delay: 0.18 }}
        className="card"
      >
        <div className="flex items-center justify-between mb-4">
          <div>
            <div className="font-display text-lg font-semibold">Spending trend</div>
            <div className="text-xs text-muted">Last 6 months</div>
          </div>
          <Link to="/charts" className="text-mint text-sm hover:underline">All charts →</Link>
        </div>
        <div className="h-48">
          <ResponsiveContainer width="100%" height="100%">
            <AreaChart data={series} margin={{ top: 6, right: 6, left: 6, bottom: 0 }}>
              <defs>
                <linearGradient id="g" x1="0" y1="0" x2="0" y2="1">
                  <stop offset="0%" stopColor="#5eead4" stopOpacity={0.5} />
                  <stop offset="100%" stopColor="#5eead4" stopOpacity={0} />
                </linearGradient>
              </defs>
              <XAxis dataKey="label" stroke="#8fb3ab" fontSize={12} tickLine={false} axisLine={false} />
              <Tooltip
                contentStyle={{ background: '#0e1c1a', border: '1px solid rgba(255,255,255,0.1)', borderRadius: 16, color: '#eafff8' }}
                formatter={(v) => formatRupees(v)}
                cursor={{ stroke: 'rgba(94,234,212,0.3)' }}
              />
              <Area type="monotone" dataKey="spent" stroke="#5eead4" strokeWidth={2.5} fill="url(#g)" />
            </AreaChart>
          </ResponsiveContainer>
        </div>
      </motion.div>

      {/* Recent */}
      <motion.div
        initial={{ opacity: 0, y: 16 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ duration: 0.4, ease, delay: 0.22 }}
        className="card"
      >
        <div className="flex items-center justify-between mb-3">
          <div className="font-display text-lg font-semibold">Recent activity</div>
          <Link to="/transactions" className="text-mint text-sm hover:underline">View all →</Link>
        </div>
        {recent.length === 0 ? (
          <div className="text-muted text-sm py-8 text-center">No transactions yet. Add SMS on the phone app, or add one from Transactions.</div>
        ) : (
          <div className="divide-y divide-white/[0.05]">
            {recent.map((t) => (
              <div key={t.id} className="flex items-center gap-3 py-3">
                <div className="h-10 w-10 rounded-2xl grid place-items-center shrink-0" style={{ background: `${categoryById(t.categoryId).color}1f` }}>
                  <CategoryIcon id={t.categoryId} />
                </div>
                <div className="min-w-0 flex-1">
                  <div className="truncate font-medium">{t.merchant || categoryById(t.categoryId).label}</div>
                  <div className="text-xs text-muted">{relativeDate(t.timestamp)} · {categoryById(t.categoryId).label}</div>
                </div>
                <div className={`flex items-center gap-1 font-semibold ${t.direction === 'credit' ? 'text-credit' : 'text-ink'}`}>
                  {t.direction === 'credit' ? <ArrowDownRight size={15} /> : <ArrowUpRight size={15} />}
                  {formatRupees(t.amount)}
                </div>
              </div>
            ))}
          </div>
        )}
      </motion.div>
    </div>
  );
}
