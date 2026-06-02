// On-device assistant — faithful port of lib/services/assistant_service.dart.
// Pure intent + keyword matching over decoded transactions. No network, no LLM.
import { CATEGORIES, categoryById, formatRupees } from '../data/categories.js';

const has = (q, words) => words.some((w) => q.includes(w));

function findCategory(q) {
  for (const c of CATEGORIES) {
    if (q.includes(c.label.toLowerCase()) || q.includes(c.id)) return c;
  }
  return null;
}

function periodOf(q) {
  const now = new Date();
  const sod = (d) => new Date(d.getFullYear(), d.getMonth(), d.getDate());
  const eod = (d) => new Date(d.getFullYear(), d.getMonth(), d.getDate(), 23, 59, 59);
  if (q.includes('today')) return { start: sod(now), end: eod(now), label: 'today', isMonth: false };
  if (q.includes('yesterday')) {
    const y = new Date(now); y.setDate(now.getDate() - 1);
    return { start: sod(y), end: eod(y), label: 'yesterday', isMonth: false };
  }
  if (q.includes('this week') || q.includes('last 7')) {
    const s = new Date(now); s.setDate(now.getDate() - 6);
    return { start: sod(s), end: eod(now), label: 'this week', isMonth: false };
  }
  if (q.includes('last month')) {
    const lm = new Date(now.getFullYear(), now.getMonth() - 1, 1);
    const end = new Date(now.getFullYear(), now.getMonth(), 0, 23, 59, 59);
    return { start: lm, end, label: 'last month', isMonth: true };
  }
  if (q.includes('last 30')) {
    const s = new Date(now); s.setDate(now.getDate() - 29);
    return { start: sod(s), end: eod(now), label: 'in the last 30 days', isMonth: false };
  }
  if (q.includes('this year')) return { start: new Date(now.getFullYear(), 0, 1), end: eod(now), label: 'this year', isMonth: false };
  if (q.includes('all time') || q.includes('ever') || q.includes('total ')) {
    return { start: new Date(2000, 0, 1), end: eod(now), label: 'all-time', isMonth: false };
  }
  return { start: new Date(now.getFullYear(), now.getMonth(), 1), end: eod(now), label: 'this month', isMonth: true };
}

export function answer(question, { txns = [], budgets = [], monthlyIncome = null } = {}) {
  const q = (question || '').toLowerCase().trim();
  if (!q) return 'Ask me anything about your spending!';

  if (['hi', 'hii', 'hello', 'hey'].includes(q) || has(q, ['namaste', 'good morning', 'good evening'])) {
    return 'Hey! 👋 I read your transactions in your browser and answer money questions privately. Try “how much on food this month?” or tap a suggestion below.';
  }
  if (has(q, ['thank', 'thx'])) return 'Anytime! 💚 Ask me whenever you want a quick money check-in.';
  if (has(q, ['help', 'what can you', 'what do you', 'how to use', 'how do you'])) {
    return 'I can tell you:\n• Spend by category or total\n• Income & savings\n• Biggest category or merchant\n• Budget status\n• Largest expense, daily average & counts\nJust ask in plain words.';
  }

  const period = periodOf(q);
  const rows = txns.filter((t) => t.timestamp >= period.start && t.timestamp <= period.end);
  const debits = rows.filter((t) => t.direction === 'debit');
  const credits = rows.filter((t) => t.direction === 'credit');
  const total = (ts) => ts.reduce((a, b) => a + b.amount, 0);
  const cat = findCategory(q);

  if (cat && has(q, ['spend', 'spent', 'spend on', 'expense', 'how much', 'cost'])) {
    const v = total(debits.filter((t) => t.categoryId === cat.id));
    return v === 0 ? `No ${cat.label} spending ${period.label}.` : `You spent ${formatRupees(v)} on ${cat.label} ${period.label}.`;
  }

  if (has(q, ['income', 'earn', 'earned', 'credited', 'salary'])) {
    return `You received ${formatRupees(total(credits))} ${period.label}.`;
  }

  if (has(q, ['save', 'saved', 'saving', 'net', 'left', 'balance'])) {
    const net = total(credits) - total(debits);
    if (monthlyIncome != null && monthlyIncome > 0 && period.isMonth) {
      const rate = ((monthlyIncome - total(debits)) / monthlyIncome) * 100;
      return `Net ${period.label}: ${formatRupees(net)}. You've kept ${rate.toFixed(0)}% of your ₹${monthlyIncome.toFixed(0)} income.`;
    }
    return `Net ${period.label}: ${formatRupees(net)} (${formatRupees(total(credits))} in − ${formatRupees(total(debits))} out).`;
  }

  if (has(q, ['biggest', 'top category', 'most', 'highest', 'where'])) {
    if (debits.length === 0) return `No spending ${period.label} yet.`;
    if (has(q, ['merchant', 'shop', 'store', 'where'])) {
      const byMerch = {};
      for (const t of debits.filter((t) => t.merchant)) byMerch[t.merchant] = (byMerch[t.merchant] || 0) + t.amount;
      const entries = Object.entries(byMerch);
      if (entries.length) {
        const top = entries.reduce((a, b) => (a[1] > b[1] ? a : b));
        return `Most went to ${top[0]}: ${formatRupees(top[1])} ${period.label}.`;
      }
    }
    const byCat = {};
    for (const t of debits) byCat[t.categoryId] = (byCat[t.categoryId] || 0) + t.amount;
    const top = Object.entries(byCat).reduce((a, b) => (a[1] > b[1] ? a : b));
    return `Your biggest category ${period.label} is ${categoryById(top[0]).label} at ${formatRupees(top[1])}.`;
  }

  if (has(q, ['budget', 'over budget', 'on track', 'cap'])) {
    if (budgets.length === 0) return "You haven't set any budgets yet. Set one from the Budgets page and I'll track your pace.";
    const byCat = {};
    for (const t of debits) byCat[t.categoryId] = (byCat[t.categoryId] || 0) + t.amount;
    const over = budgets.filter((b) => b.monthlyCap > 0 && (byCat[b.categoryId] || 0) > b.monthlyCap);
    if (over.length === 0) return `You're within all your budgets ${period.label}. 👍`;
    return `Over budget on: ${over.map((b) => categoryById(b.categoryId).label).join(', ')}.`;
  }

  if (has(q, ['largest', 'biggest transaction', 'biggest payment', 'most expensive'])) {
    if (debits.length === 0) return `No expenses ${period.label}.`;
    const big = debits.reduce((a, b) => (a.amount > b.amount ? a : b));
    return `Your largest expense ${period.label} was ${formatRupees(big.amount)}${big.merchant ? ` at ${big.merchant}` : ''}.`;
  }

  if (has(q, ['how many', 'number of', 'count', 'transactions'])) {
    return `You have ${rows.length} transactions ${period.label} (${debits.length} expenses, ${credits.length} income).`;
  }

  if (has(q, ['average', 'avg', 'per day', 'daily'])) {
    const now = new Date();
    const effEnd = period.end < now ? period.end : now;
    const days = Math.max(1, Math.floor((effEnd - period.start) / 86400000) + 1);
    return `You're spending about ${formatRupees(total(debits) / days)} per day ${period.label}.`;
  }

  if (has(q, ['recent', 'last transaction', 'last expense', 'what did i buy'])) {
    if (debits.length === 0) return `No recent expenses ${period.label}.`;
    const recent = [...debits].sort((a, b) => b.timestamp - a.timestamp).slice(0, 3);
    return 'Your most recent expenses:\n' + recent.map((t) => `• ${formatRupees(t.amount)}${t.merchant ? ` at ${t.merchant}` : ''}`).join('\n');
  }

  if (has(q, ['spend', 'spent', 'expense', 'how much', 'total'])) {
    return `You spent ${formatRupees(total(debits))} ${period.label} across ${debits.length} transactions.`;
  }

  return 'I can answer things like:\n• "How much did I spend on food this month?"\n• "What\'s my biggest category?"\n• "Am I over budget?"\n• "How much did I earn this month?"\n• "What was my largest expense?"';
}

export const SUGGESTIONS = [
  'How much did I spend this month?',
  "What's my biggest category?",
  'Am I over budget?',
  'How much did I earn this month?',
  'What was my largest expense?',
  'Spend on food this month',
];
