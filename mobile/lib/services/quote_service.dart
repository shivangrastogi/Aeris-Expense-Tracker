import 'dart:convert';
import 'package:http/http.dart' as http;

class Quote {
  final String text;
  final String author;
  const Quote(this.text, this.author);
}

/// Fetches a motivational quote online for freshness, with a curated
/// budgeting/saving fallback list so Home always shows something even offline.
class QuoteService {
  QuoteService._();

  static const _fallback = <Quote>[
    Quote('A budget is telling your money where to go instead of wondering where it went.',
        'John C. Maxwell'),
    Quote('Do not save what is left after spending, but spend what is left after saving.',
        'Warren Buffett'),
    Quote('Beware of little expenses; a small leak will sink a great ship.',
        'Benjamin Franklin'),
    Quote('The art is not in making money, but in keeping it.', 'Proverb'),
    Quote('A penny saved is a penny earned.', 'Benjamin Franklin'),
    Quote('Wealth consists not in having great possessions, but in having few wants.',
        'Epictetus'),
    Quote('Money looks better in the bank than on your feet.', 'Sophia Amoruso'),
    Quote('Every time you borrow money, you’re robbing your future self.',
        'Nathan W. Morris'),
  ];

  /// Fetch several quotes for the Home carousel (online, with offline
  /// fallback). Always returns at least a few items.
  static Future<List<Quote>> fetchMany(int n) async {
    try {
      final res = await http
          .get(Uri.parse(
              'https://api.quotable.io/quotes/random?limit=$n&maxLength=130&tags=success|wisdom|business'))
          .timeout(const Duration(seconds: 6));
      if (res.statusCode == 200) {
        final list = (jsonDecode(res.body) as List)
            .map((j) => Quote(
                  ((j as Map)['content'] as String?)?.trim() ?? '',
                  (j['author'] as String?)?.trim() ?? '',
                ))
            .where((q) => q.text.isNotEmpty)
            .toList();
        if (list.isNotEmpty) return list;
      }
    } catch (_) {/* offline / API down → fallback */}
    final list = List<Quote>.from(_fallback)..shuffle();
    return list.take(n).toList();
  }
}
