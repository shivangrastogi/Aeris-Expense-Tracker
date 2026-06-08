// Web port of lib/services/merchant_directory.dart — on-device enrichment.
// Infers the payment app from a UPI VPA's @handle, and resolves friendly
// names/categories for well-known payees. Nothing leaves the browser.

const APP_BY_HANDLE = {
  ybl: 'PhonePe', ibl: 'PhonePe', axl: 'PhonePe',
  okhdfcbank: 'Google Pay', okaxis: 'Google Pay', oksbi: 'Google Pay', okicici: 'Google Pay',
  paytm: 'Paytm', ptaxis: 'Paytm', ptsbi: 'Paytm', ptyes: 'Paytm', pthdfc: 'Paytm',
  apl: 'Amazon Pay', yapl: 'Amazon Pay', rapl: 'Amazon Pay',
  upi: 'BHIM', cred: 'CRED', axisb: 'CRED', slc: 'Slice',
  jupiteraxis: 'Jupiter', fam: 'FamPay', jio: 'JioPay', mbk: 'MobiKwik', freecharge: 'Freecharge',
};

export function paymentAppFor(vpa) {
  if (!vpa || typeof vpa !== 'string') return null;
  const at = vpa.indexOf('@');
  if (at < 0 || at === vpa.length - 1) return null;
  return APP_BY_HANDLE[vpa.slice(at + 1).toLowerCase().trim()] || null;
}

// signature substring → [display name, category id]
const KNOWN = {
  zomato: ['Zomato', 'food'], swiggy: ['Swiggy', 'food'], dominos: ["Domino's", 'food'],
  mcdonald: ["McDonald's", 'food'], kfc: ['KFC', 'food'], starbucks: ['Starbucks', 'food'],
  bigbasket: ['BigBasket', 'groceries'], blinkit: ['Blinkit', 'groceries'], zepto: ['Zepto', 'groceries'],
  instamart: ['Swiggy Instamart', 'groceries'], dmart: ['DMart', 'groceries'], jiomart: ['JioMart', 'groceries'],
  amazon: ['Amazon', 'shopping'], flipkart: ['Flipkart', 'shopping'], myntra: ['Myntra', 'shopping'],
  ajio: ['AJIO', 'shopping'], nykaa: ['Nykaa', 'shopping'], meesho: ['Meesho', 'shopping'],
  uber: ['Uber', 'travel'], ola: ['Ola', 'travel'], rapido: ['Rapido', 'travel'], irctc: ['IRCTC', 'travel'],
  redbus: ['redBus', 'travel'], indigo: ['IndiGo', 'travel'], hpcl: ['HP Petrol', 'travel'],
  iocl: ['Indian Oil', 'travel'], bharatpetroleum: ['Bharat Petroleum', 'travel'],
  netflix: ['Netflix', 'entertainment'], hotstar: ['Disney+ Hotstar', 'entertainment'],
  spotify: ['Spotify', 'entertainment'], bookmyshow: ['BookMyShow', 'entertainment'],
  pharmeasy: ['PharmEasy', 'health'], apollo: ['Apollo', 'health'], medplus: ['MedPlus', 'health'],
  '1mg': ['Tata 1mg', 'health'], airtel: ['Airtel', 'bills'], jio: ['Jio', 'bills'],
  zerodha: ['Zerodha', 'investment'], groww: ['Groww', 'investment'], upstox: ['Upstox', 'investment'],
  byju: ["BYJU'S", 'education'], unacademy: ['Unacademy', 'education'], urbancompany: ['Urban Company', 'personal'],
};

export function lookupMerchant(raw) {
  if (!raw) return null;
  const t = String(raw).toLowerCase();
  for (const [k, v] of Object.entries(KNOWN)) {
    if (t.includes(k)) return { name: v[0], categoryId: v[1] };
  }
  return null;
}
