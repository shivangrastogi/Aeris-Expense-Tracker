import 'package:flutter/material.dart';
import '../core/ph_icons.dart';

/// Built-in categories. Users can extend in Firestore (`categories` collection)
/// but every transaction must map to ONE of these IDs (or a custom one).
class ExpenseCategory {
  final String id;
  final String label;
  final IconData icon;
  final Color color;
  final List<String> keywords;   // for merchant→category auto-classification

  const ExpenseCategory({
    required this.id,
    required this.label,
    required this.icon,
    required this.color,
    this.keywords = const [],
  });
}

class Categories {
  Categories._();

  /// The built-in categories ("Other" last).
  static const List<ExpenseCategory> builtIn = [
    ExpenseCategory(id: 'food', label: 'Food', icon: PhosphorIconsRegular.forkKnife,
        color: Color(0xFFC97A52),
        keywords: ['swiggy','zomato','mcdonald','starbucks','dominos','kfc',
                   'pizza','restaurant','cafe','dine','eat','burger','meal',
                   'dhaba','hotel','food court','canteen','bakery','tea','chai',
                   'coffee','juice','ice cream','biryani','thali','lunch',
                   'dinner','breakfast','brunch']),
    ExpenseCategory(id: 'groceries', label: 'Groceries', icon: PhosphorIconsRegular.basket,
        color: Color(0xFF2FA287),
        keywords: ['bigbasket','blinkit','zepto','instamart','grofers',
                   'reliance fresh','dmart','grocery','supermart','kirana',
                   'milk','dairy','eggs','bread','vegetable','veggies','fruit',
                   'paneer','curd','atta','rice','flour','sugar','snacks',
                   'biscuit','chips','pepsi','coke','cola','cold drink',
                   'soft drink','beverage','maggi','jiomart','more','spencer',
                   'star bazaar','provision','general store']),
    ExpenseCategory(id: 'travel', label: 'Transport', icon: PhosphorIconsRegular.car,
        color: Color(0xFFB0902F),
        keywords: ['uber','ola','rapido','irctc','indigo','airindia','airline',
                   'metro','redbus','flight','train','fuel','petrol','diesel',
                   'hpcl','iocl','bharat petroleum','indian oil','shell',
                   'petrol pump','fuel station','toll','fastag','parking',
                   'auto','rickshaw','cab','taxi','bus','makemytrip','goibibo',
                   'cleartrip','yatra','easemytrip','ixigo','abhibus','oyo',
                   'airbnb']),
    ExpenseCategory(id: 'shopping', label: 'Shopping', icon: PhosphorIconsRegular.shoppingBag,
        color: Color(0xFFC9789A),
        keywords: ['amazon','flipkart','myntra','ajio','nykaa','meesho',
                   'shopping','tata cliq','jiomart','snapdeal','clothes',
                   'apparel','footwear','electronics','decathlon','lifestyle']),
    ExpenseCategory(id: 'bills', label: 'Bills', icon: PhosphorIconsRegular.receipt,
        color: Color(0xFF5F8CCB),
        keywords: ['electricity','water','gas','recharge','airtel','jio','vi ',
                   'bsnl','bill','dth','tata sky','broadband','wifi','postpaid',
                   'cylinder','lpg','indane','piped gas']),
    ExpenseCategory(id: 'entertainment', label: 'Entertainment', icon: PhosphorIconsRegular.filmSlate,
        color: Color(0xFF8A7ED3),
        keywords: ['netflix','prime','hotstar','spotify','jiocinema','sonyliv',
                   'bookmyshow','pvr','inox','youtube premium','disney','game',
                   'steam','playstation']),
    ExpenseCategory(id: 'health', label: 'Health', icon: PhosphorIconsRegular.heartbeat,
        color: Color(0xFF5F9A4C),
        keywords: ['pharmacy','apollo','medplus','1mg','pharmeasy','hospital',
                   'doctor','clinic','medical','health','medicine','lab',
                   'diagnostic','gym','fitness']),
    ExpenseCategory(id: 'education', label: 'Education', icon: PhosphorIconsRegular.graduationCap,
        color: Color(0xFF6C7FC4),
        keywords: ['school','college','university','tuition','fees','course',
                   'udemy','coursera','byju','unacademy','vedantu','books',
                   'stationery','exam','coaching']),
    ExpenseCategory(id: 'personal', label: 'Personal care', icon: PhosphorIconsRegular.scissors,
        color: Color(0xFFB98BA6),
        keywords: ['salon','barber','spa','parlour','parlor','cosmetics',
                   'grooming','haircut','beauty','urban company']),
    ExpenseCategory(id: 'rent', label: 'Rent', icon: PhosphorIconsRegular.house,
        color: Color(0xFFC96A66),
        keywords: ['rent','nobroker','housing','society','maintenance']),
    ExpenseCategory(id: 'investment', label: 'Investment', icon: PhosphorIconsRegular.chartLineUp,
        color: Color(0xFF4E97A8),
        keywords: ['zerodha','groww','upstox','mutual fund','sip','equity',
                   'stocks','demat','etf']),
    ExpenseCategory(id: 'transfer', label: 'Transfer', icon: PhosphorIconsRegular.arrowsLeftRight,
        color: Color(0xFF7D8796),
        keywords: ['neft','rtgs','imps','transfer','to a/c','upi']),
    ExpenseCategory(id: 'salary', label: 'Income', icon: PhosphorIconsRegular.briefcase,
        color: Color(0xFF4C9A6C),
        keywords: ['salary','payroll','credited','income','stipend']),
    ExpenseCategory(id: 'cash', label: 'Cash', icon: PhosphorIconsRegular.money,
        color: Color(0xFF8E8F45),
        keywords: ['atm','cash withdrawal','withdrawn']),
    // Money coming back for a purchase. Never counted as income; it's taken
    // off total spend instead (see AnalyticsSnapshot).
    ExpenseCategory(id: 'refund', label: 'Refund', icon: PhosphorIconsRegular.arrowUUpLeft,
        color: Color(0xFF6A9BB0),
        keywords: ['refund','reversal','reversed','cashback']),
    ExpenseCategory(id: 'other', label: 'Other', icon: PhosphorIconsRegular.dotsThreeOutline,
        color: Color(0xFF8B93A1),
        keywords: []),
  ];

  /// The user's own categories (Settings → Categories), kept in step with
  /// their account by the app shell. Appended after the built-ins.
  static List<ExpenseCategory> custom = const [];

  /// Every category: built-in first, then the user's own.
  static List<ExpenseCategory> get all => [...builtIn, ...custom];

  /// A category by id; unknown (e.g. a deleted custom one) reads as "Other".
  static ExpenseCategory byId(String id) =>
      all.firstWhere((c) => c.id == id, orElse: () => builtIn.last);

  /// Heuristic category lookup from a free-text merchant or SMS body.
  ///
  /// A keyword must start at the beginning of a word, so "rent" doesn't fire
  /// inside "Torrent" and "ola" doesn't fire inside "Motorola". Short keywords
  /// (≤ 4 letters, e.g. "sip", "gas", "eat") must be the whole word (an
  /// optional plural "s" is allowed), so "Gossip" or "Vegas" don't match.
  /// Longer brand names may run on ("amazonpay", "swiggyinstamart").
  ///
  /// [exclude] skips categories that can't apply — e.g. a debit is never
  /// Salary, so "A/C XX5174 credited" in a debit alert can't pick it.
  static String classify(String text, {Set<String> exclude = const {}}) {
    final t = text.toLowerCase();
    for (final c in all) {
      if (c.id == 'refund') continue; // only set explicitly by the parsers
      if (exclude.contains(c.id)) continue;
      for (final k in c.keywords) {
        if (_keywordRe(k).hasMatch(t)) return c.id;
      }
    }
    return 'other';
  }

  static final Map<String, RegExp> _reCache = {};

  static RegExp _keywordRe(String keyword) =>
      _reCache.putIfAbsent(keyword, () {
        final k = keyword.trim();
        final body = RegExp.escape(k);
        final whole = k.replaceAll(RegExp(r'[^a-z0-9]'), '').length <= 4;
        return RegExp('(?<![a-z0-9])$body${whole ? r's?(?![a-z0-9])' : ''}');
      });
}
