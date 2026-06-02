// Aggregation helpers — port of the logic behind analytics_provider.dart.
// All operate on decoded transaction objects: { amount, direction, timestamp(Date), categoryId, merchant }.
import { categoryById } from '../data/categories.js';

export const isDebit = (t) => t.direction === 'debit';
export const isCredit = (t) => t.direction === 'credit';
export const sum = (ts) => ts.reduce((a, b) => a + (b.amount || 0), 0);

export function monthRange(ref = new Date()) {
  const start = new Date(ref.getFullYear(), ref.getMonth(), 1);
  const end = new Date(ref.getFullYear(), ref.getMonth() + 1, 0, 23, 59, 59);
  return { start, end };
}

export function inRange(txns, start, end) {
  return txns.filter((t) => t.timestamp >= start && t.timestamp <= end);
}

export function thisMonth(txns) {
  const { start, end } = monthRange();
  return inRange(txns, start, end);
}

// Spend grouped by category → [{ id, label, color, value }] sorted desc.
export function byCategory(txns) {
  const map = {};
  for (const t of txns.filter(isDebit)) {
    map[t.categoryId] = (map[t.categoryId] || 0) + t.amount;
  }
  return Object.entries(map)
    .map(([id, value]) => {
      const c = categoryById(id);
      return { id, label: c.label, color: c.color, value };
    })
    .sort((a, b) => b.value - a.value);
}

// Top merchants → [{ merchant, value }] sorted desc.
export function topMerchants(txns, limit = 6) {
  const map = {};
  for (const t of txns.filter((x) => isDebit(x) && x.merchant)) {
    map[t.merchant] = (map[t.merchant] || 0) + t.amount;
  }
  return Object.entries(map)
    .map(([merchant, value]) => ({ merchant, value }))
    .sort((a, b) => b.value - a.value)
    .slice(0, limit);
}

// Last `months` months of spend vs income → [{ label, spent, income }] oldest→newest.
export function monthlySeries(txns, months = 6) {
  const now = new Date();
  const out = [];
  for (let i = months - 1; i >= 0; i--) {
    const ref = new Date(now.getFullYear(), now.getMonth() - i, 1);
    const { start, end } = monthRange(ref);
    const rows = inRange(txns, start, end);
    out.push({
      label: ref.toLocaleDateString('en-IN', { month: 'short' }),
      spent: sum(rows.filter(isDebit)),
      income: sum(rows.filter(isCredit)),
    });
  }
  return out;
}

// Daily spend for current month → [{ day, spent }].
export function dailySeries(txns) {
  const { start, end } = monthRange();
  const rows = inRange(txns, start, end).filter(isDebit);
  const map = {};
  for (const t of rows) {
    const d = t.timestamp.getDate();
    map[d] = (map[d] || 0) + t.amount;
  }
  const daysInMonth = end.getDate();
  const out = [];
  for (let d = 1; d <= daysInMonth; d++) out.push({ day: d, spent: map[d] || 0 });
  return out;
}

// Headline numbers for the dashboard.
export function monthSummary(txns, monthlyIncome = 0) {
  const rows = thisMonth(txns);
  const debits = rows.filter(isDebit);
  const credits = rows.filter(isCredit);
  const spent = sum(debits);
  const earned = sum(credits);
  const now = new Date();
  const dayOfMonth = now.getDate();
  return {
    spent,
    earned,
    net: earned - spent,
    txCount: rows.length,
    avgPerDay: spent / Math.max(1, dayOfMonth),
    top: byCategory(rows)[0] || null,
    monthlyIncome,
    incomeLeft: monthlyIncome > 0 ? monthlyIncome - spent : null,
  };
}
