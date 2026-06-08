// Web port of lib/services/category_rules.dart — remembers the user's
// merchant → category choices so future entries auto-categorise. Stored in
// localStorage (per browser/device); the merchant string itself is a label,
// not financial data.

const KEY = 'aeris_category_rules';

function load() {
  try {
    return JSON.parse(localStorage.getItem(KEY) || '{}');
  } catch {
    return {};
  }
}

export function learnedCategoryFor(merchant) {
  if (!merchant || !merchant.trim()) return null;
  return load()[merchant.toLowerCase().trim()] || null;
}

export function rememberCategory(merchant, categoryId) {
  if (!merchant || !merchant.trim()) return;
  const rules = load();
  rules[merchant.toLowerCase().trim()] = categoryId;
  try {
    localStorage.setItem(KEY, JSON.stringify(rules));
  } catch {
    /* ignore quota errors */
  }
}
