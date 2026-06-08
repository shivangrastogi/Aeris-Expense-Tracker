import { useMemo } from 'react';
import { formatRupees } from '../data/categories.js';

const WEEKS = 18;
const dateKey = (d) => `${d.getFullYear()}-${d.getMonth()}-${d.getDate()}`;

// GitHub-contributions-style calendar of daily spend over the last ~18 weeks.
export default function SpendingHeatmap({ txns }) {
  const { columns, max } = useMemo(() => {
    const now = new Date();
    const today = new Date(now.getFullYear(), now.getMonth(), now.getDate());
    const startRaw = new Date(today);
    startRaw.setDate(today.getDate() - (WEEKS * 7 - 1));
    const start = new Date(startRaw);
    start.setDate(startRaw.getDate() - ((startRaw.getDay() + 6) % 7)); // back to Monday

    const daily = {};
    for (const t of txns) {
      if (t.direction !== 'debit') continue;
      const d = t.timestamp;
      if (d < start || d > now) continue;
      const k = dateKey(new Date(d.getFullYear(), d.getMonth(), d.getDate()));
      daily[k] = (daily[k] || 0) + t.amount;
    }
    const vals = Object.values(daily);
    const max = vals.length ? Math.max(...vals) : 0;

    const totalDays = Math.round((today - start) / 86400000) + 1;
    const numWeeks = Math.ceil(totalDays / 7);
    const columns = [];
    for (let w = 0; w < numWeeks; w++) {
      const week = [];
      for (let dow = 0; dow < 7; dow++) {
        const d = new Date(start);
        d.setDate(start.getDate() + w * 7 + dow);
        const future = d > today;
        week.push({
          value: daily[dateKey(d)] || 0,
          future,
          label: d.toLocaleDateString('en-IN', { day: 'numeric', month: 'short' }),
        });
      }
      columns.push(week);
    }
    return { columns, max };
  }, [txns]);

  function color(v) {
    if (v <= 0) return 'rgba(255,255,255,0.05)';
    const r = max <= 0 ? 0 : v / max;
    const a = r < 0.25 ? 0.3 : r < 0.5 ? 0.55 : r < 0.75 ? 0.78 : 1;
    return `rgba(94,234,212,${a})`;
  }

  return (
    <div>
      <div className="flex gap-1 overflow-x-auto pb-1">
        <div className="flex flex-col gap-1 pr-1 text-[9px] text-muted shrink-0">
          {['Mon', '', 'Wed', '', 'Fri', '', ''].map((l, i) => (
            <div key={i} className="h-3 leading-3">{l}</div>
          ))}
        </div>
        {columns.map((week, wi) => (
          <div key={wi} className="flex flex-col gap-1 shrink-0">
            {week.map((cell, di) => (
              <div
                key={di}
                title={cell.future ? '' : `${cell.label}: ${formatRupees(cell.value)}`}
                className="h-3 w-3 rounded-[3px]"
                style={{ background: cell.future ? 'transparent' : color(cell.value) }}
              />
            ))}
          </div>
        ))}
      </div>
      <div className="flex items-center justify-end gap-1.5 mt-3 text-[10px] text-muted">
        <span>Less</span>
        {[0, 0.3, 0.55, 0.78, 1].map((a, i) => (
          <div key={i} className="h-2.5 w-2.5 rounded-[2px]"
            style={{ background: a === 0 ? 'rgba(255,255,255,0.05)' : `rgba(94,234,212,${a})` }} />
        ))}
        <span>More</span>
      </div>
    </div>
  );
}
