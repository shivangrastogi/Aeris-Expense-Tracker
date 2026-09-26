/// A display currency. All amounts in the app are stored in INR; [rate] is
/// the number of units of this currency per ₹1, used to convert for display
/// only. [indian] selects lakh/crore digit grouping (vs thousands/millions).
class Currency {
  final String code;
  final String symbol;
  final String name;
  final String flag;
  final double rate;
  final bool indian;

  const Currency({
    required this.code,
    required this.symbol,
    required this.name,
    required this.flag,
    required this.rate,
    required this.indian,
  });
}

class Currencies {
  Currencies._();

  static const all = <Currency>[
    Currency(
        code: 'INR',
        symbol: '₹',
        name: 'Indian Rupee',
        flag: '🇮🇳',
        rate: 1,
        indian: true),
    Currency(
        code: 'USD',
        symbol: '\$',
        name: 'US Dollar',
        flag: '🇺🇸',
        rate: 83.2,
        indian: false),
    Currency(
        code: 'EUR',
        symbol: '€',
        name: 'Euro',
        flag: '🇪🇺',
        rate: 90.1,
        indian: false),
    Currency(
        code: 'GBP',
        symbol: '£',
        name: 'British Pound',
        flag: '🇬🇧',
        rate: 105.4,
        indian: false),
    Currency(
        code: 'AED',
        symbol: 'AED ',
        name: 'UAE Dirham',
        flag: '🇦🇪',
        rate: 22.65,
        indian: false),
    Currency(
        code: 'SGD',
        symbol: 'S\$',
        name: 'Singapore Dollar',
        flag: '🇸🇬',
        rate: 61.4,
        indian: false),
    Currency(
        code: 'JPY',
        symbol: '¥',
        name: 'Japanese Yen',
        flag: '🇯🇵',
        rate: 0.55,
        indian: false),
  ];

  static Currency byCode(String code) =>
      all.firstWhere((c) => c.code == code, orElse: () => all.first);
}
