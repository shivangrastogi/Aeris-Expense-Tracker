import 'package:flutter_test/flutter_test.dart';
import 'package:aeris_expense/models/split.dart';
import 'package:aeris_expense/models/transaction.dart';
import 'package:aeris_expense/providers/analytics_provider.dart';
import 'package:aeris_expense/services/split_links.dart';

Transaction _t(String id, double amount, TxnDirection dir, DateTime at,
        {String category = 'other', String? merchant, String? vpa}) =>
    Transaction(
      id: id,
      amount: amount,
      direction: dir,
      timestamp: at,
      categoryId: category,
      merchant: merchant,
      upiVpa: vpa,
      source: TxnSource.sms,
      smsSender: 'VM-HDFCBK',
    );

void main() {
  final day1 = DateTime(2026, 10, 1, 10);
  const flat = SplitGroup(
    id: 'flat',
    name: 'Flat',
    members: [SplitMember(name: 'Rahul'), SplitMember(name: 'Amit')],
    autoPayees: ['owner@okicici'],
  );

  Transaction rentBill() {
    final bill = _t('rent', 12000, TxnDirection.debit, day1,
        category: 'rent', merchant: 'Mr Sharma', vpa: 'owner@okicici');
    return bill.copyWith(split: SplitLinks.shareOut(flat, bill.amount));
  }

  group('Splitting a bill', () {
    test('₹12,000 rent ÷ 3: you count ₹4,000', () {
      final bill = rentBill();
      expect([for (final s in bill.split!.shares) s.amount], [4000, 4000]);
      expect(bill.spendAmount, 4000);
      expect(bill.amount, 12000); // the bank still moved ₹12,000
    });

    test('unequal shares by weight (bigger room 1.5x)', () {
      final g = flat.copyWith(members: [
        const SplitMember(name: 'Rahul', weight: 1.5),
        const SplitMember(name: 'Amit'),
      ]);
      final split = SplitLinks.shareOut(g, 14000);
      // Weights 1 (you) + 1.5 + 1 = 3.5 → 4,000 / 6,000 / 4,000.
      expect([for (final s in split.shares) s.amount], [6000, 4000]);
      expect(split.myShare(14000), 4000);
    });

    test('a payment to the landlord auto-splits into the Flat', () {
      final next = _t('rent2', 12000, TxnDirection.debit,
          DateTime(2026, 11, 1), vpa: 'owner@okicici');
      expect(SplitLinks.autoGroupFor(next, [flat])?.id, 'flat');
      final other = _t('x', 500, TxnDirection.debit, day1, vpa: 'zomato@hdfc');
      expect(SplitLinks.autoGroupFor(other, [flat]), isNull);
    });
  });

  group('Paybacks', () {
    test("Rahul's UPI payment settles Rahul's share", () {
      final bill = rentBill();
      final credit = _t('c1', 4000, TxnDirection.credit,
          day1.add(const Duration(days: 2)),
          merchant: 'Rahul', vpa: 'rahulsharma99@okaxis');
      final hit = SplitLinks.paybackTarget(credit, [bill], [flat])!;
      expect(hit.$1.id, 'rent');
      expect(bill.split!.shares[hit.$2].name, 'Rahul');
      final paid = SplitLinks.receive(bill, hit.$2, credit.amount);
      expect(paid.split!.shares[hit.$2].settled, isTrue);
      final marked = SplitLinks.markPayback(credit, bill, hit.$2);
      expect(marked.isSettlement && !marked.isIncoming, isTrue);
    });

    test('UPI ID alone (no name in the SMS) still finds Rahul', () {
      final credit = _t('c1', 4000, TxnDirection.credit, day1,
          vpa: 'rahul.k@ybl');
      expect(SplitLinks.paybackTarget(credit, [rentBill()], [flat]), isNotNull);
    });

    test('a learned handle recognises a payer the name never would', () {
      final first = _t('c0', 4000, TxnDirection.credit, day1,
          merchant: 'Amit', vpa: 'q81726@paytm');
      final g = SplitLinks.learnHandle(flat, 'Amit', first);
      expect(g.members[1].handles, contains('q81726@paytm'));
      final next = _t('c2', 4000, TxnDirection.credit, day1, vpa: 'q81726@paytm');
      final bill = rentBill();
      final hit = SplitLinks.paybackTarget(next, [bill], [g])!;
      expect(bill.split!.shares[hit.$2].name, 'Amit');
    });

    test('partial payback, then the rest', () {
      var bill = rentBill();
      final part = _t('c1', 2000, TxnDirection.credit, day1, merchant: 'Rahul');
      final hit = SplitLinks.paybackTarget(part, [bill], [flat])!;
      bill = SplitLinks.receive(bill, hit.$2, 2000);
      expect(bill.split!.shares[hit.$2].outstanding, 2000);
      expect(SplitLinks.owedToYou([bill]), {'Rahul': 2000, 'Amit': 4000});
      final rest = _t('c2', 2000, TxnDirection.credit, day1, merchant: 'Rahul');
      expect(SplitLinks.paybackTarget(rest, [bill], [flat])?.$2, hit.$2);
      // More than Rahul still owes is not his payback.
      final tooMuch = _t('c3', 5000, TxnDirection.credit, day1, merchant: 'Rahul');
      expect(SplitLinks.paybackTarget(tooMuch, [bill], [flat]), isNull);
    });

    test('an unnamed bank credit matches only an exact, unique share', () {
      final bill = rentBill();
      final anon = _t('c1', 4000, TxnDirection.credit, day1);
      // Rahul and Amit both owe ₹4,000 — ambiguous, so no guess.
      expect(SplitLinks.paybackTarget(anon, [bill], [flat]), isNull);
      final oneLeft = SplitLinks.receive(bill, 0, 4000); // Rahul paid
      final hit = SplitLinks.paybackTarget(anon, [oneLeft], [flat])!;
      expect(oneLeft.split!.shares[hit.$2].name, 'Amit');
    });

    test('money from someone not on the bill is not a payback', () {
      final credit = _t('c1', 4000, TxnDirection.credit, day1,
          merchant: 'Priya', vpa: 'priya@oksbi');
      expect(SplitLinks.paybackTarget(credit, [rentBill()], [flat]), isNull);
    });

    test('a payment months later is not matched to an old bill', () {
      final credit = _t('c1', 4000, TxnDirection.credit,
          day1.add(const Duration(days: 90)), merchant: 'Rahul');
      expect(SplitLinks.paybackTarget(credit, [rentBill()], [flat]), isNull);
    });
  });

  test('totals: rent counts ₹4,000; paybacks are not income', () {
    final now = DateTime.now();
    final d = DateTime(now.year, now.month, 1, 9);
    final bill = _t('rent', 12000, TxnDirection.debit, d,
            category: 'rent', vpa: 'owner@okicici')
        .copyWith(split: SplitLinks.shareOut(flat, 12000));
    final salary = _t('sal', 85000, TxnDirection.credit, d, category: 'salary');
    final r1 = _t('r1', 4000, TxnDirection.credit, d, merchant: 'Rahul')
        .copyWith(settles: 'rent', settlesMember: 'Rahul');
    final r2 = _t('r2', 4000, TxnDirection.credit, d, merchant: 'Amit')
        .copyWith(settles: 'rent', settlesMember: 'Amit');
    final s = AnalyticsSnapshot.from(
        [bill, salary, r1, r2], AnalyticsRange.thisMonth());
    expect(s.monthExpense, 4000);
    expect(s.byCategory['rent'], 4000);
    expect(s.monthIncome, 85000);
  });

  test('split survives the encrypted round-trip (toMap / fromMap)', () {
    final bill = SplitLinks.receive(rentBill(), 0, 1500);
    final map = bill.toMap();
    final back = Transaction.fromMap('rent', map);
    expect(back.split!.shares[0].received, 1500);
    expect(back.spendAmount, 4000);
    final credit = _t('c', 4000, TxnDirection.credit, day1)
        .copyWith(settles: 'rent', settlesMember: 'Amit');
    final cBack = Transaction.fromMap('c', credit.toMap());
    expect(cBack.isSettlement, isTrue);
    expect(cBack.settlesMember, 'Amit');
  });
}
