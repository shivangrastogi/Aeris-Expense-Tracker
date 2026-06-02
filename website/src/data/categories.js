// Port of lib/models/category.dart + lib/utils/formatters.dart.
// Icon names map to lucide-react components (resolved in the UI layer).

export const CATEGORIES = [
  { id: 'food', label: 'Food & Dining', icon: 'Utensils', color: '#F59E0B',
    keywords: ['swiggy','zomato','mcdonald','starbucks','dominos','kfc','pizza','restaurant','cafe','dine','eat','burger','meal'] },
  { id: 'groceries', label: 'Groceries', icon: 'ShoppingCart', color: '#22C55E',
    keywords: ['bigbasket','blinkit','zepto','instamart','grofers','reliance fresh','dmart','grocery','supermart'] },
  { id: 'travel', label: 'Travel & Transport', icon: 'Car', color: '#3B82F6',
    keywords: ['uber','ola','rapido','irctc','indigo','airindia','airline','metro','redbus','flight','train','fuel','petrol','diesel','hpcl','iocl','bharat petroleum'] },
  { id: 'shopping', label: 'Shopping', icon: 'ShoppingBag', color: '#EC4899',
    keywords: ['amazon','flipkart','myntra','ajio','nykaa','meesho','shopping','tata cliq','jiomart','snapdeal'] },
  { id: 'bills', label: 'Bills & Utilities', icon: 'ReceiptText', color: '#8B5CF6',
    keywords: ['electricity','water','gas','recharge','airtel','jio','vi ','bsnl','bill','dth','tata sky','broadband','wifi','postpaid'] },
  { id: 'entertainment', label: 'Entertainment', icon: 'Clapperboard', color: '#A855F7',
    keywords: ['netflix','prime','hotstar','spotify','jiocinema','sonyliv','bookmyshow','pvr','inox','youtube premium','disney'] },
  { id: 'health', label: 'Health & Medical', icon: 'HeartPulse', color: '#EF4444',
    keywords: ['pharmacy','apollo','medplus','1mg','pharmeasy','hospital','doctor','clinic','medical','health'] },
  { id: 'rent', label: 'Rent & Housing', icon: 'Home', color: '#14B8A6',
    keywords: ['rent','nobroker','housing','society','maintenance'] },
  { id: 'investment', label: 'Investment', icon: 'TrendingUp', color: '#06B6D4',
    keywords: ['zerodha','groww','upstox','mutual fund','sip','equity','stocks','demat','etf'] },
  { id: 'transfer', label: 'Bank Transfer', icon: 'ArrowLeftRight', color: '#84CC16',
    keywords: ['neft','rtgs','imps','transfer','to a/c','upi'] },
  { id: 'salary', label: 'Salary / Income', icon: 'Briefcase', color: '#22C55E',
    keywords: ['salary','payroll','credited','income','stipend'] },
  { id: 'cash', label: 'Cash Withdrawal', icon: 'Banknote', color: '#F97316',
    keywords: ['atm','cash withdrawal','withdrawn'] },
  { id: 'other', label: 'Other', icon: 'MoreHorizontal', color: '#0EA5A4', keywords: [] },
];

const _byId = Object.fromEntries(CATEGORIES.map((c) => [c.id, c]));
export const categoryById = (id) => _byId[id] || CATEGORIES[CATEGORIES.length - 1];

export function classify(text) {
  const t = (text || '').toLowerCase();
  for (const c of CATEGORIES) {
    for (const k of c.keywords) if (t.includes(k)) return c.id;
  }
  return 'other';
}

// ── Indian-style money formatting (matches formatters.dart) ──
function trim(x) {
  const r = x.toFixed(1);
  return r.endsWith('.0') ? r.slice(0, -2) : r;
}
export function formatRupees(n, { compact = false, decimals = false } = {}) {
  const v = Number(n) || 0;
  if (compact) {
    const neg = v < 0;
    const a = Math.abs(v);
    let s;
    if (a < 1000) s = `₹${a.toFixed(0)}`;
    else if (a < 100000) s = `₹${trim(a / 1000)}K`;
    else if (a < 10000000) s = `₹${trim(a / 100000)}L`;
    else s = `₹${trim(a / 10000000)}Cr`;
    return neg ? `-${s}` : s;
  }
  // en-IN grouping (lakh/crore), 0 or 2 decimals.
  return v.toLocaleString('en-IN', {
    style: 'currency',
    currency: 'INR',
    minimumFractionDigits: decimals ? 2 : 0,
    maximumFractionDigits: decimals ? 2 : 0,
  });
}

export function relativeDate(d) {
  const now = new Date();
  const days = Math.floor((now - d) / 86400000);
  if (d.toDateString() === now.toDateString())
    return d.toLocaleTimeString('en-IN', { hour: 'numeric', minute: '2-digit' });
  const y = new Date(now); y.setDate(now.getDate() - 1);
  if (d.toDateString() === y.toDateString()) return 'Yesterday';
  if (days < 7) return d.toLocaleDateString('en-IN', { weekday: 'long' });
  if (d.getFullYear() === now.getFullYear())
    return d.toLocaleDateString('en-IN', { day: 'numeric', month: 'short' });
  return d.toLocaleDateString('en-IN', { day: 'numeric', month: 'short', year: 'numeric' });
}
