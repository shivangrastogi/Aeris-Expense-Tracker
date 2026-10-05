import 'package:aeris_expense/models/transaction.dart';
import 'package:aeris_expense/services/search_query.dart';
import 'package:flutter_test/flutter_test.dart';

final _now = DateTime(2026, 9, 30, 18);

Transaction _t(double amt, DateTime when,
        {String merchant = 'Swiggy',
        String cat = 'food',
        TxnDirection dir = TxnDirection.debit}) =>
    Transaction(
        id: '$amt$when',
        amount: amt,
        direction: dir,
        timestamp: when,
        categoryId: cat,
        merchant: merchant);

void main() {
  test('plain word is a text search, like before', () {
    final q = SearchQuery.parse('swiggy', now: _now);
    expect(q.words, ['swiggy']);
    expect(q.matches(_t(300, _now)), isTrue);
    expect(q.matches(_t(300, _now, merchant: 'Uber')), isFalse);
  });

  test('"above 1000 last month"', () {
    final q = SearchQuery.parse('above 1000 last month', now: _now);
    expect(q.minAmount, 1000);
    expect(q.from, DateTime(2026, 8, 1));
    expect(q.to!.day, 31);
    expect(q.words, isEmpty);
    expect(q.matches(_t(1500, DateTime(2026, 8, 12))), isTrue);
    expect(q.matches(_t(900, DateTime(2026, 8, 12))), isFalse);
    expect(q.matches(_t(1500, DateTime(2026, 9, 2))), isFalse);
  });

  test('"swiggy september" = text + month', () {
    final q = SearchQuery.parse('swiggy september', now: _now);
    expect(q.words, ['swiggy']);
    expect(q.from, DateTime(2026, 9, 1));
    expect(q.understood, contains('Sep 2026'));
  });

  test('a later month name means last year', () {
    final q = SearchQuery.parse('december', now: _now);
    expect(q.from, DateTime(2025, 12, 1));
  });

  test('shorthand amounts and ranges', () {
    expect(SearchQuery.parse('under 2k', now: _now).maxAmount, 2000);
    expect(SearchQuery.parse('over 1.5 lakh', now: _now).minAmount, 150000);
    final r = SearchQuery.parse('between 200 and 800', now: _now);
    expect((r.minAmount, r.maxAmount), (200, 800));
    final r2 = SearchQuery.parse('500-1000', now: _now);
    expect((r2.minAmount, r2.maxAmount), (500, 1000));
  });

  test('direction and category words', () {
    final q = SearchQuery.parse('food under 500 this week', now: _now);
    expect(q.categoryId, 'food');
    expect(q.maxAmount, 500);
    expect(q.from, DateTime(2026, 9, 28)); // Monday
    final r = SearchQuery.parse('received last 30 days', now: _now);
    expect(r.direction, TxnDirection.credit);
    expect(r.from, DateTime(2026, 9, 1));
  });

  test('a bare number still finds the amount', () {
    final q = SearchQuery.parse('486', now: _now);
    expect(q.matches(_t(486, _now)), isTrue);
    expect(q.matches(_t(120, _now)), isFalse);
  });
}
