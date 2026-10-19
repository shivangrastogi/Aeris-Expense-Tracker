import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:aeris_expense/models/transaction.dart';
import 'package:aeris_expense/services/sms_parser.dart';
import 'package:aeris_expense/services/sms_templates.dart';

void main() {
  final now = DateTime(2026, 10, 12, 18);

  // Two alerts from the same (made-up) bank template: different amounts,
  // payee, refs and balances. The parser reads 450 as the amount; suppose
  // this bank's quirk is that the first number is what moved — the parser
  // can't know that, the user can.
  const a = 'Bal Rs.9,000.00 after txn 450.00 debited A/c XX1234 to '
      'SHOP ONE ref 628512345678';
  const b = 'Bal Rs.4,000.00 after txn 1,250.50 debited A/c XX1234 to '
      'BIG STORE ref 628599999999';

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await SmsTemplates.instance.clear();
  });

  test('alerts from one template share a key; other banks do not', () {
    expect(SmsParser.templateKey('VM-XYZBNK', a),
        SmsParser.templateKey('JD-XYZBNK-S', b));
    expect(SmsParser.templateKey('VM-XYZBNK', a),
        isNot(SmsParser.templateKey('VM-ABCBNK', a)));
  });

  test('amount slots list every money number in order', () {
    expect(SmsParser.amountSlots(a), [9000.0, 450.0]);
  });

  test('a corrected amount is replayed on the next alert of that template',
      () async {
    final first = SmsParser.parse(sender: 'VM-XYZBNK', body: a, receivedAt: now);
    expect(first!.txn.amount, 450.0);
    // User fixes the amount to the first number in the SMS.
    await SmsTemplates.instance.learn(first.txn, first.txn.copyWith(amount: 9000));

    final next = SmsParser.parse(sender: 'VM-XYZBNK', body: b, receivedAt: now)!;
    expect(next.txn.amount, 1250.50); // parser alone
    final applied = await SmsTemplates.instance.apply(next);
    expect(applied.txn.amount, 4000.0); // learned slot wins
  });

  test('a corrected direction is replayed too', () async {
    const body = 'Rs.500.00 credited to A/c XX1234 on 12-10-26. Ref 628512345678';
    final p = SmsParser.parse(sender: 'VM-HDFCBK', body: body, receivedAt: now)!;
    expect(p.txn.direction, TxnDirection.credit);
    await SmsTemplates.instance
        .learn(p.txn, p.txn.copyWith(direction: TxnDirection.debit));
    final again = await SmsTemplates.instance.apply(p);
    expect(again.txn.direction, TxnDirection.debit);
  });

  test('manual transactions are never learned from', () async {
    final t = Transaction(
        id: 'x', amount: 10, direction: TxnDirection.debit,
        timestamp: now, categoryId: 'food');
    await SmsTemplates.instance.learn(t, t.copyWith(amount: 20));
    final p = SmsParser.parse(sender: 'VM-XYZBNK', body: a, receivedAt: now)!;
    expect((await SmsTemplates.instance.apply(p)).txn.amount, p.txn.amount);
  });
}
