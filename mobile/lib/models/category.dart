import 'package:flutter/material.dart';

import '../core/theme.dart';

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

  static const List<ExpenseCategory> all = [
    ExpenseCategory(id: 'food', label: 'Food & Dining', icon: Icons.restaurant,
        color: Color(0xFFF59E0B),
        keywords: ['swiggy','zomato','mcdonald','starbucks','dominos','kfc',
                   'pizza','restaurant','cafe','dine','eat','burger','meal']),
    ExpenseCategory(id: 'groceries', label: 'Groceries', icon: Icons.local_grocery_store,
        color: Color(0xFF22C55E),
        keywords: ['bigbasket','blinkit','zepto','instamart','grofers',
                   'reliance fresh','dmart','grocery','supermart']),
    ExpenseCategory(id: 'travel', label: 'Travel & Transport', icon: Icons.directions_car,
        color: Color(0xFF3B82F6),
        keywords: ['uber','ola','rapido','irctc','indigo','airindia','airline',
                   'metro','redbus','flight','train','fuel','petrol','diesel',
                   'hpcl','iocl','bharat petroleum']),
    ExpenseCategory(id: 'shopping', label: 'Shopping', icon: Icons.shopping_bag,
        color: Color(0xFFEC4899),
        keywords: ['amazon','flipkart','myntra','ajio','nykaa','meesho',
                   'shopping','tata cliq','jiomart','snapdeal']),
    ExpenseCategory(id: 'bills', label: 'Bills & Utilities', icon: Icons.receipt_long,
        color: Color(0xFF8B5CF6),
        keywords: ['electricity','water','gas','recharge','airtel','jio','vi ',
                   'bsnl','bill','dth','tata sky','broadband','wifi','postpaid']),
    ExpenseCategory(id: 'entertainment', label: 'Entertainment', icon: Icons.movie,
        color: Color(0xFFA855F7),
        keywords: ['netflix','prime','hotstar','spotify','jiocinema','sonyliv',
                   'bookmyshow','pvr','inox','youtube premium','disney']),
    ExpenseCategory(id: 'health', label: 'Health & Medical', icon: Icons.favorite,
        color: Color(0xFFEF4444),
        keywords: ['pharmacy','apollo','medplus','1mg','pharmeasy','hospital',
                   'doctor','clinic','medical','health']),
    ExpenseCategory(id: 'rent', label: 'Rent & Housing', icon: Icons.home_work,
        color: Color(0xFF14B8A6),
        keywords: ['rent','nobroker','housing','society','maintenance']),
    ExpenseCategory(id: 'investment', label: 'Investment', icon: Icons.trending_up,
        color: Color(0xFF06B6D4),
        keywords: ['zerodha','groww','upstox','mutual fund','sip','equity',
                   'stocks','demat','etf']),
    ExpenseCategory(id: 'transfer', label: 'Bank Transfer', icon: Icons.swap_horiz,
        color: Color(0xFF84CC16),
        keywords: ['neft','rtgs','imps','transfer','to a/c','upi']),
    ExpenseCategory(id: 'salary', label: 'Salary / Income', icon: Icons.work,
        color: Color(0xFF22C55E),
        keywords: ['salary','payroll','credited','income','stipend']),
    ExpenseCategory(id: 'cash', label: 'Cash Withdrawal', icon: Icons.atm,
        color: Color(0xFFF97316),
        keywords: ['atm','cash withdrawal','withdrawn']),
    ExpenseCategory(id: 'other', label: 'Other', icon: Icons.more_horiz,
        color: AerisColors.seed,
        keywords: []),
  ];

  static ExpenseCategory byId(String id) =>
      all.firstWhere((c) => c.id == id, orElse: () => all.last);

  /// Heuristic category lookup from a free-text merchant or SMS body.
  static String classify(String text) {
    final t = text.toLowerCase();
    for (final c in all) {
      for (final k in c.keywords) {
        if (t.contains(k)) return c.id;
      }
    }
    return 'other';
  }
}
