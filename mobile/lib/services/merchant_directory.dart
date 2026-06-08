/// On-device enrichment for UPI/bank transactions.
///
/// Two jobs, both fully local (nothing leaves the device — preserves the
/// app's end-to-end privacy):
///   1. Infer the payment app from a VPA's @handle (PhonePe, GPay, Paytm…).
///   2. Resolve a friendly merchant name + category for well-known payees from
///      a small bundled dictionary, layered under the user's learned rules.
class MerchantDirectory {
  MerchantDirectory._();

  /// VPA handle (the part after `@`) → payment app name.
  static const Map<String, String> _appByHandle = {
    // PhonePe
    'ybl': 'PhonePe', 'ibl': 'PhonePe', 'axl': 'PhonePe',
    // Google Pay
    'okhdfcbank': 'Google Pay', 'okaxis': 'Google Pay', 'oksbi': 'Google Pay',
    'okicici': 'Google Pay',
    // Paytm
    'paytm': 'Paytm', 'ptaxis': 'Paytm', 'ptsbi': 'Paytm', 'ptyes': 'Paytm',
    'pthdfc': 'Paytm',
    // Amazon Pay
    'apl': 'Amazon Pay', 'yapl': 'Amazon Pay', 'rapl': 'Amazon Pay',
    // Others
    'upi': 'BHIM', 'cred': 'CRED', 'axisb': 'CRED', 'slc': 'Slice',
    'jupiteraxis': 'Jupiter', 'fam': 'FamPay', 'jio': 'JioPay',
    'mbk': 'MobiKwik', 'freecharge': 'Freecharge',
  };

  /// The payment app inferred from a VPA's `@handle`, or null if unknown.
  static String? appFor(String? vpa) {
    if (vpa == null) return null;
    final at = vpa.indexOf('@');
    if (at < 0 || at == vpa.length - 1) return null;
    final handle = vpa.substring(at + 1).toLowerCase().trim();
    return _appByHandle[handle];
  }

  /// Known merchant signatures (lowercase substring) → (display name, category).
  static const Map<String, (String, String)> _known = {
    'zomato': ('Zomato', 'food'),
    'swiggy': ('Swiggy', 'food'),
    'dominos': ("Domino's", 'food'),
    'mcdonald': ("McDonald's", 'food'),
    'kfc': ('KFC', 'food'),
    'starbucks': ('Starbucks', 'food'),
    'bigbasket': ('BigBasket', 'groceries'),
    'blinkit': ('Blinkit', 'groceries'),
    'zepto': ('Zepto', 'groceries'),
    'instamart': ('Swiggy Instamart', 'groceries'),
    'dmart': ('DMart', 'groceries'),
    'jiomart': ('JioMart', 'groceries'),
    'amazon': ('Amazon', 'shopping'),
    'flipkart': ('Flipkart', 'shopping'),
    'myntra': ('Myntra', 'shopping'),
    'ajio': ('AJIO', 'shopping'),
    'nykaa': ('Nykaa', 'shopping'),
    'meesho': ('Meesho', 'shopping'),
    'uber': ('Uber', 'travel'),
    'ola': ('Ola', 'travel'),
    'rapido': ('Rapido', 'travel'),
    'irctc': ('IRCTC', 'travel'),
    'redbus': ('redBus', 'travel'),
    'indigo': ('IndiGo', 'travel'),
    'hpcl': ('HP Petrol', 'travel'),
    'iocl': ('Indian Oil', 'travel'),
    'bharatpetroleum': ('Bharat Petroleum', 'travel'),
    'netflix': ('Netflix', 'entertainment'),
    'hotstar': ('Disney+ Hotstar', 'entertainment'),
    'spotify': ('Spotify', 'entertainment'),
    'bookmyshow': ('BookMyShow', 'entertainment'),
    'pharmeasy': ('PharmEasy', 'health'),
    'apollo': ('Apollo', 'health'),
    'medplus': ('MedPlus', 'health'),
    '1mg': ('Tata 1mg', 'health'),
    'airtel': ('Airtel', 'bills'),
    'jio': ('Jio', 'bills'),
    'zerodha': ('Zerodha', 'investment'),
    'groww': ('Groww', 'investment'),
    'upstox': ('Upstox', 'investment'),
    'byju': ("BYJU'S", 'education'),
    'unacademy': ('Unacademy', 'education'),
    'urbancompany': ('Urban Company', 'personal'),
  };

  /// Resolve a friendly name + category from a merchant string or VPA, or null.
  static ({String name, String categoryId})? lookup(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final t = raw.toLowerCase();
    for (final e in _known.entries) {
      if (t.contains(e.key)) {
        return (name: e.value.$1, categoryId: e.value.$2);
      }
    }
    return null;
  }

  /// A cleaner display name: a known-merchant name if we recognise it, else the
  /// VPA's readable prefix (title-cased), else the original merchant string.
  static String? prettyName(String? vpa, String? merchant) {
    final hit = lookup(merchant) ?? lookup(vpa);
    if (hit != null) return hit.name;
    if (vpa != null && vpa.contains('@')) {
      final prefix = vpa.substring(0, vpa.indexOf('@'));
      if (_looksReadable(prefix)) return _titleCase(prefix);
    }
    return merchant;
  }

  // A prefix is "readable" if it's mostly letters and not an opaque QR/code id
  // (e.g. "paytmqr2810…", "q629f3…").
  static bool _looksReadable(String s) {
    final p = s.toLowerCase();
    if (p.length < 3 || p.length > 24) return false;
    if (p.startsWith('paytmqr') || p.startsWith('q') && RegExp(r'^q\d').hasMatch(p)) {
      return false;
    }
    final letters = RegExp(r'[a-z]').allMatches(p).length;
    final digits = RegExp(r'\d').allMatches(p).length;
    return letters >= 3 && digits <= 3;
  }

  static String _titleCase(String s) {
    final cleaned = s.replaceAll(RegExp(r'[._\-]+'), ' ').trim();
    return cleaned
        .split(' ')
        .where((w) => w.isNotEmpty)
        .map((w) => w[0].toUpperCase() + w.substring(1))
        .join(' ');
  }
}
