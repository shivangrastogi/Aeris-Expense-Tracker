import { useMemo } from 'react';
import { Share2 } from 'lucide-react';
import { useData } from '../state/Data.jsx';
import { formatRupees, categoryById } from '../data/categories.js';

function compute(txns) {
  const now = new Date();
  const y = now.getFullYear();
  const mo = now.getMonth();
  const lastM = new Date(y, mo - 1, 1);

  let spent = 0, income = 0, txnCount = 0, lastMonthSpent = 0;
  const byCat = {}, byMerchant = {}, byDay = {};
  const spendDays = new Set();

  for (const t of txns) {
    const d = t.timestamp;
    if (d.getFullYear() === lastM.getFullYear() && d.getMonth() === lastM.getMonth() && t.direction === 'debit') {
      lastMonthSpent += t.amount;
    }
    if (d.getFullYear() !== y || d.getMonth() !== mo) continue;
    txnCount++;
    if (t.direction === 'credit') { income += t.amount; continue; }
    spent += t.amount;
    byCat[t.categoryId] = (byCat[t.categoryId] || 0) + t.amount;
    if (t.merchant?.trim()) byMerchant[t.merchant.trim()] = (byMerchant[t.merchant.trim()] || 0) + t.amount;
    byDay[d.getDate()] = (byDay[d.getDate()] || 0) + t.amount;
    spendDays.add(d.getDate());
  }

  const top = (m) => Object.entries(m).sort((a, b) => b[1] - a[1])[0] || null;
  const topCat = top(byCat);
  const topMerchant = top(byMerchant);
  const biggestDay = top(byDay);
  const noSpendDays = Math.max(0, now.getDate() - spendDays.size);
  const momPct = lastMonthSpent > 0 ? ((spent - lastMonthSpent) / lastMonthSpent) * 100 : null;

  return { spent, income, txnCount, topCat, topMerchant, biggestDay, noSpendDays, momPct, net: income - spent };
}

function CardBlock({ gradient, children }) {
  return (
    <div className="rounded-3xl p-8 text-white text-center shadow-lg" style={{ background: gradient }}>
      {children}
    </div>
  );
}
const Big = ({ children }) => <div className="font-display text-4xl font-extrabold leading-tight">{children}</div>;
const Sub = ({ children }) => <div className="text-white/80 mt-2">{children}</div>;

export default function Wrapped() {
  const { txns } = useData();
  const s = useMemo(() => compute(txns), [txns]);
  const month = new Date().toLocaleDateString('en-IN', { month: 'long' });

  function share() {
    const lines = [
      `My ${month} in money (via AERIS):`,
      `• Spent ${formatRupees(s.spent)} across ${s.txnCount} transactions`,
      s.topCat && `• Top category: ${categoryById(s.topCat[0]).label} (${formatRupees(s.topCat[1])})`,
      s.topMerchant && `• Most at: ${s.topMerchant[0]} (${formatRupees(s.topMerchant[1])})`,
      `• ${s.noSpendDays} no-spend days`,
      `• ${s.net >= 0 ? 'Saved' : 'Overspent'} ${formatRupees(Math.abs(s.net))}`,
    ].filter(Boolean).join('\n');
    if (navigator.share) navigator.share({ text: lines }).catch(() => {});
    else { navigator.clipboard?.writeText(lines); }
  }

  return (
    <div className="space-y-5 max-w-xl mx-auto">
      <div className="flex items-center justify-between">
        <h1 className="font-display text-3xl font-semibold">{month} Wrapped</h1>
        <button onClick={share} className="btn-ghost !py-2"><Share2 size={16} /> Share</button>
      </div>

      {s.txnCount === 0 ? (
        <div className="card text-center text-muted py-12">No activity yet this month — add a few transactions and check back.</div>
      ) : (
        <div className="space-y-4">
          <CardBlock gradient="linear-gradient(135deg,#0EA5A4,#0F766E)">
            <div className="text-5xl mb-2">🗓️</div>
            <Big>Your {month} in money</Big>
            <Sub>A quick recap of where it went.</Sub>
          </CardBlock>

          <CardBlock gradient="linear-gradient(135deg,#EF4444,#991B1B)">
            <Sub>This month you spent</Sub>
            <Big>{formatRupees(s.spent)}</Big>
            <Sub>across {s.txnCount} transaction{s.txnCount === 1 ? '' : 's'}</Sub>
          </CardBlock>

          {s.topCat && (
            <CardBlock gradient={`linear-gradient(135deg, ${categoryById(s.topCat[0]).color}, #1f2937)`}>
              <Sub>Your top category</Sub>
              <Big>{categoryById(s.topCat[0]).label}</Big>
              <Sub>{formatRupees(s.topCat[1])} · {Math.round((s.topCat[1] / s.spent) * 100)}% of spend</Sub>
            </CardBlock>
          )}

          {s.topMerchant && (
            <CardBlock gradient="linear-gradient(135deg,#8B5CF6,#6366F1)">
              <div className="text-5xl mb-2">🏆</div>
              <Sub>You spent most at</Sub>
              <Big>{s.topMerchant[0]}</Big>
              <Sub>{formatRupees(s.topMerchant[1])}</Sub>
            </CardBlock>
          )}

          {s.biggestDay && (
            <CardBlock gradient="linear-gradient(135deg,#F59E0B,#B45309)">
              <div className="text-5xl mb-2">💥</div>
              <Sub>Your biggest day</Sub>
              <Big>{s.biggestDay[0]} {month}</Big>
              <Sub>{formatRupees(s.biggestDay[1])} in one day</Sub>
            </CardBlock>
          )}

          <CardBlock gradient="linear-gradient(135deg,#22C55E,#15803D)">
            <div className="text-6xl font-extrabold">{s.noSpendDays}</div>
            <Big>no-spend day{s.noSpendDays === 1 ? '' : 's'}</Big>
            <Sub>{s.noSpendDays === 0 ? 'Spent something every day so far.' : 'Days you didn’t spend a rupee 🎉'}</Sub>
          </CardBlock>

          {s.momPct != null && (
            <CardBlock gradient={s.momPct < 0 ? 'linear-gradient(135deg,#22C55E,#15803D)' : 'linear-gradient(135deg,#EF4444,#991B1B)'}>
              <Sub>vs last month</Sub>
              <Big>{Math.abs(Math.round(s.momPct))}% {s.momPct < 0 ? 'less' : 'more'}</Big>
              <Sub>{s.momPct < 0 ? 'Nice — spending is down.' : 'Spending crept up.'}</Sub>
            </CardBlock>
          )}

          <CardBlock gradient="linear-gradient(135deg,#0EA5A4,#0F766E)">
            <Sub>{s.net >= 0 ? 'You saved' : 'You overspent'}</Sub>
            <Big>{formatRupees(Math.abs(s.net))}</Big>
            <button onClick={share} className="mt-4 inline-flex items-center gap-2 rounded-full bg-white text-[#0F766E] font-semibold px-5 py-2">
              <Share2 size={16} /> Share my month
            </button>
          </CardBlock>
        </div>
      )}
    </div>
  );
}
