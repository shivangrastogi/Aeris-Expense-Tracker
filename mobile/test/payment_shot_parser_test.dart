import 'package:aeris_expense/models/transaction.dart';
import 'package:aeris_expense/services/payment_shot_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 10, 2, 20, 50);

  // The PhonePe "Received from" screen, as rows (cells tab-separated).
  const phonePeReceived = '8:48\t55\n'
      'Transaction Successful\n'
      '10:56 am on 02 Oct 2026\n'
      'Received from\n'
      'AP\tAYUSH PATEL\t₹4,750\n'
      'ayushpatel5735@okicici\n'
      'Transfer Details\n'
      'PhonePe Transaction ID\n'
      'T2610021056374347734844\n'
      'Credited to\n'
      'XXXXXX1268\t₹4,750\n'
      'UTR: 664187463389\n'
      'Check Balance\tView History\tShare Receipt\n'
      'Contact PhonePe Support\n'
      'Powered by\nUPI';

  test('PhonePe received: everything on the screen is picked up', () {
    final p = PaymentShotParser.parse(phonePeReceived, now: now)!;
    expect(p.amount, 4750);
    expect(p.direction, TxnDirection.credit);
    expect(p.name, 'Ayush Patel');
    expect(p.upiVpa, 'ayushpatel5735@okicici');
    expect(p.when, DateTime(2026, 10, 2, 10, 56));
    expect(p.reference, '664187463389');
    expect(p.account, '1268');
    expect(p.amountUncertain, isFalse);
    expect(p.directionGuessed, isFalse);
  });

  test('same screen in raw block order (one cell per line)', () {
    final p = PaymentShotParser.parse(
        phonePeReceived.replaceAll('\t', '\n'),
        now: now)!;
    expect(p.amount, 4750);
    expect(p.direction, TxnDirection.credit);
    expect(p.name, 'Ayush Patel');
    expect(p.when, DateTime(2026, 10, 2, 10, 56));
    expect(p.reference, '664187463389');
  });

  test('PhonePe paid: debit, pm time, known merchant name', () {
    const text = 'Transaction Successful\n09:05 pm on 28 Sep 2026\n'
        'Paid to\nZOMATO LIMITED\t₹389\nzomato-order@ptybl\n'
        'Debited from\nXXXXXX1268\t₹389\nUTR: 512345678901';
    final p = PaymentShotParser.parse(text, now: now)!;
    expect(p.amount, 389);
    expect(p.direction, TxnDirection.debit);
    expect(p.name, 'Zomato');
    expect(p.when, DateTime(2026, 9, 28, 21, 5));
    expect(p.account, '1268');
  });

  test('Google Pay: bare "To NAME", date before time, UPI transaction ID', () {
    const text = 'To Ravi Kumar\n₹1,200.50\nCompleted\n'
        '1 Oct 2026, 7:15 pm\nUPI transaction ID\n627412345678\n'
        'To: Ravi Kumar\nGoogle Pay • ravi.k@oksbi\n'
        'From: Shivang (HDFC Bank)\nGoogle Pay • shivang@okhdfcbank';
    final p = PaymentShotParser.parse(text, now: now)!;
    expect(p.amount, 1200.5);
    expect(p.direction, TxnDirection.debit);
    expect(p.name, 'Ravi Kumar');
    expect(p.upiVpa, 'ravi.k@oksbi');
    expect(p.when, DateTime(2026, 10, 1, 19, 15));
    expect(p.reference, '627412345678');
  });

  test('Paytm: "Paid Successfully to", time before date, UPI Ref No', () {
    const text = 'Paid Successfully to\nSharma Kirana Store\n₹ 240\n'
        '06:42 PM, 30 Sep 2026\nUPI Ref No: 627398765432\nPaytm';
    final p = PaymentShotParser.parse(text, now: now)!;
    expect(p.amount, 240);
    expect(p.direction, TxnDirection.debit);
    expect(p.name, 'Sharma Kirana Store');
    expect(p.when, DateTime(2026, 9, 30, 18, 42));
    expect(p.reference, '627398765432');
  });

  test('rupee sign misread as a letter still counts as the amount', () {
    final p = PaymentShotParser.parse(
        phonePeReceived.replaceAll('₹4,750', 'F4,750'),
        now: now)!;
    expect(p.amount, 4750);
    expect(p.amountUncertain, isFalse);
  });

  test('no currency mark: amount is flagged, status bar is ignored', () {
    final p = PaymentShotParser.parse(
        phonePeReceived.replaceAll('₹4,750', '4,750'),
        now: now)!;
    expect(p.amount, 4750);
    expect(p.amountUncertain, isTrue);
  });

  test('a name that starts like a month is not a date', () {
    const text = 'Paid to\nMayank Sharma\t₹20\nmayank@ybl\nUTR: 512345678902';
    final p = PaymentShotParser.parse(text, now: now)!;
    expect(p.amount, 20);
    expect(p.name, 'Mayank Sharma');
    expect(p.when, isNull);
  });

  test('not a payment screen → null', () {
    expect(PaymentShotParser.parse('Good morning\nLunch at 1:30 pm', now: now),
        isNull);
    expect(
        PaymentShotParser.parse('CHAI POINT\nGrand Total Rs 173.26', now: now),
        isNull);
  });

  test('layout puts lines on the same row together, left to right', () {
    final text = PaymentShotParser.layout(const [
      OcrLine('₹4,750', left: 560, top: 313, bottom: 343),
      OcrLine('ayushpatel5735@okicici', left: 160, top: 360, bottom: 386),
      OcrLine('AYUSH PATEL', left: 160, top: 313, bottom: 343),
      OcrLine('Received from', left: 48, top: 238, bottom: 265),
      OcrLine('AP', left: 68, top: 325, bottom: 355),
    ]);
    expect(text,
        'Received from\nAP\tAYUSH PATEL\t₹4,750\nayushpatel5735@okicici');
  });
}
