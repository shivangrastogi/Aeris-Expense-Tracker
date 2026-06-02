import { useMemo } from 'react';
import {
  ResponsiveContainer,
  PieChart,
  Pie,
  Cell,
  BarChart,
  Bar,
  XAxis,
  YAxis,
  Tooltip,
  Legend,
  AreaChart,
  Area,
  CartesianGrid,
} from 'recharts';
import { useData } from '../state/Data.jsx';
import { byCategory, monthlySeries, topMerchants, dailySeries, thisMonth } from '../services/analytics.js';
import { formatRupees } from '../data/categories.js';

const tip = {
  contentStyle: { background: '#0e1c1a', border: '1px solid rgba(255,255,255,0.1)', borderRadius: 16, color: '#eafff8' },
  formatter: (v) => formatRupees(v),
};

function Card({ title, sub, children }) {
  return (
    <div className="card">
      <div className="font-display text-lg font-semibold">{title}</div>
      {sub && <div className="text-xs text-muted mb-3">{sub}</div>}
      <div className="h-64 mt-2">{children}</div>
    </div>
  );
}

export default function Charts() {
  const { txns } = useData();
  const cats = useMemo(() => byCategory(thisMonth(txns)), [txns]);
  const months = useMemo(() => monthlySeries(txns, 6), [txns]);
  const merchants = useMemo(() => topMerchants(thisMonth(txns), 6), [txns]);
  const daily = useMemo(() => dailySeries(txns), [txns]);

  const empty = txns.length === 0;

  return (
    <div className="space-y-5">
      <h1 className="font-display text-3xl font-semibold">Charts</h1>

      {empty ? (
        <div className="card text-center text-muted py-12">No data yet to chart.</div>
      ) : (
        <div className="grid lg:grid-cols-2 gap-5">
          <Card title="Spending by category" sub="This month">
            <ResponsiveContainer width="100%" height="100%">
              <PieChart>
                <Pie data={cats} dataKey="value" nameKey="label" innerRadius={55} outerRadius={90} paddingAngle={2} stroke="none">
                  {cats.map((c) => <Cell key={c.id} fill={c.color} />)}
                </Pie>
                <Tooltip {...tip} />
                <Legend wrapperStyle={{ fontSize: 11, color: '#8fb3ab' }} />
              </PieChart>
            </ResponsiveContainer>
          </Card>

          <Card title="Spent vs income" sub="Last 6 months">
            <ResponsiveContainer width="100%" height="100%">
              <BarChart data={months} margin={{ top: 6, right: 6, left: -10, bottom: 0 }}>
                <CartesianGrid strokeDasharray="3 3" stroke="rgba(255,255,255,0.05)" vertical={false} />
                <XAxis dataKey="label" stroke="#8fb3ab" fontSize={12} tickLine={false} axisLine={false} />
                <YAxis stroke="#8fb3ab" fontSize={11} tickLine={false} axisLine={false} tickFormatter={(v) => formatRupees(v, { compact: true })} />
                <Tooltip {...tip} cursor={{ fill: 'rgba(94,234,212,0.06)' }} />
                <Legend wrapperStyle={{ fontSize: 11 }} />
                <Bar dataKey="income" name="Income" fill="#22c55e" radius={[6, 6, 0, 0]} />
                <Bar dataKey="spent" name="Spent" fill="#5eead4" radius={[6, 6, 0, 0]} />
              </BarChart>
            </ResponsiveContainer>
          </Card>

          <Card title="Daily spend" sub="This month">
            <ResponsiveContainer width="100%" height="100%">
              <AreaChart data={daily} margin={{ top: 6, right: 6, left: -10, bottom: 0 }}>
                <defs>
                  <linearGradient id="gd" x1="0" y1="0" x2="0" y2="1">
                    <stop offset="0%" stopColor="#5eead4" stopOpacity={0.5} />
                    <stop offset="100%" stopColor="#5eead4" stopOpacity={0} />
                  </linearGradient>
                </defs>
                <CartesianGrid strokeDasharray="3 3" stroke="rgba(255,255,255,0.05)" vertical={false} />
                <XAxis dataKey="day" stroke="#8fb3ab" fontSize={11} tickLine={false} axisLine={false} interval={4} />
                <YAxis stroke="#8fb3ab" fontSize={11} tickLine={false} axisLine={false} tickFormatter={(v) => formatRupees(v, { compact: true })} />
                <Tooltip {...tip} cursor={{ stroke: 'rgba(94,234,212,0.3)' }} labelFormatter={(l) => `Day ${l}`} />
                <Area type="monotone" dataKey="spent" stroke="#5eead4" strokeWidth={2.5} fill="url(#gd)" />
              </AreaChart>
            </ResponsiveContainer>
          </Card>

          <Card title="Top merchants" sub="This month">
            <ResponsiveContainer width="100%" height="100%">
              <BarChart data={merchants} layout="vertical" margin={{ top: 6, right: 12, left: 10, bottom: 0 }}>
                <XAxis type="number" stroke="#8fb3ab" fontSize={11} tickLine={false} axisLine={false} tickFormatter={(v) => formatRupees(v, { compact: true })} />
                <YAxis type="category" dataKey="merchant" stroke="#8fb3ab" fontSize={11} width={90} tickLine={false} axisLine={false} />
                <Tooltip {...tip} cursor={{ fill: 'rgba(94,234,212,0.06)' }} />
                <Bar dataKey="value" name="Spent" fill="#5eead4" radius={[0, 6, 6, 0]} />
              </BarChart>
            </ResponsiveContainer>
          </Card>
        </div>
      )}
    </div>
  );
}
