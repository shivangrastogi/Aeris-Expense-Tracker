import 'package:aeris_expense/models/transaction.dart';
import 'package:aeris_expense/services/scan_reader.dart';
import 'package:aeris_expense/services/sms_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 10, 27, 18, 30);
  ScanResult read(String rows) => ScanReader.read(rows: rows, now: now);

  group('pen-and-paper notes', () {
    test('labelled fields go where their labels say', () {
      final r = read('Name: Ravi Kumar\nAmount: 500\nUPI: ravi@okaxis\n'
          'Date: 25/10/2026\nPaid');
      expect(r.kind, ScanKind.note);
      expect(r.name, 'Ravi Kumar');
      expect(r.amount, 500);
      expect(r.upiVpa, 'ravi@okaxis');
      expect(r.when, DateTime(2026, 10, 25));
      expect(r.direction, TxnDirection.debit);
      expect(r.missing, isEmpty);
      expect(r.needsInput, isFalse);
    });

    test('first + last name are joined; "Type: received" is income', () {
      final r = read('First name - Ravi\nLast name - KUMAR\nAmt = 1,250\n'
          'Type: received');
      expect(r.name, 'Ravi Kumar');
      expect(r.amount, 1250);
      expect(r.direction, TxnDirection.credit);
    });

    test('misread labels and digits still land, flagged for checking', () {
      final r = read('Nmae: Neha\nAmout: 5OO');
      expect(r.name, 'Neha');
      expect(r.amount, 500);
      expect(r.unsure, contains(ScanField.amount));
      expect(r.missing, [ScanField.direction]);
      expect(r.needsInput, isTrue);
    });

    test('a label alone on its line takes the value under it', () {
      final r = read('Name\nSuresh\nAmount\n750\nReceived');
      expect(r.name, 'Suresh');
      expect(r.amount, 750);
      expect(r.direction, TxnDirection.credit);
    });

    test('UPI number without @bank is kept as a phone', () {
      final r = read('Name: Amit\nUPI: 98765 43210\nAmount: 300');
      expect(r.upiVpa, isNull);
      expect(r.phone, '9876543210');
      expect(r.amount, 300);
    });

    test('"Paid to Amit 500/-": who, how much, which way', () {
      final r = read('Paid to Amit 500/-\nfor dinner');
      expect(r.name, 'Amit');
      expect(r.amount, 500);
      expect(r.unsure, isNot(contains(ScanField.amount))); // ₹-marked
      expect(r.direction, TxnDirection.debit);
      expect(r.note, 'dinner');
    });

    test('Hinglish: "Ravi ko 500 diye"', () {
      final r = read('Aaj Ravi ko 500 diye');
      expect(r.name, 'Ravi');
      expect(r.amount, 500);
      expect(r.direction, TxnDirection.debit);
      expect(r.when, DateTime(2026, 10, 27));
    });

    test('free English sentence', () {
      final r = read('Got Rs 2,000 from Neha Sharma for rent');
      expect(r.name, 'Neha Sharma');
      expect(r.amount, 2000);
      expect(r.direction, TxnDirection.credit);
      expect(r.note, 'rent');
    });

    test('"Ravi 500": found, but only guessed — asks', () {
      final r = read('Ravi 500');
      expect(r.name, 'Ravi');
      expect(r.amount, 500);
      expect(r.missing, [ScanField.direction]);
      expect(r.unsure, containsAll([ScanField.amount, ScanField.name]));
    });

    test('only an amount: name and direction are missing', () {
      final r = read('Amount: 1200');
      expect(r.amount, 1200);
      expect(r.missing, [ScanField.name, ScanField.direction]);
    });

    test('several bare numbers: asks rather than guessing the amount', () {
      final r = read('Suresh\n200\n350');
      expect(r.amount, isNull);
      expect(r.missing, contains(ScanField.amount));
    });

    test('a date is not an amount, and an item list total wins', () {
      final r = read('Shop: Sharma Store\nPrice: 120\nPrice: 80\n'
          'Total: 200\n12 Oct');
      expect(r.name, 'Sharma Store');
      expect(r.amount, 200);
      expect(r.when, DateTime(2026, 10, 12));
    });
  });

  group('Hindi (Devanagari)', () {
    test('labelled note with Hindi digits', () {
      final r = read('नाम: रवि कुमार\nराशि: ५००\nतारीख: २५/१०/२०२६\nभुगतान');
      expect(r.name, 'रवि कुमार');
      expect(r.amount, 500);
      expect(r.when, DateTime(2026, 10, 25));
      expect(r.direction, TxnDirection.debit);
      expect(r.needsInput, isFalse);
    });

    test('first + last name, रुपये, मिले', () {
      final r = read('पहला नाम - नेहा\nउपनाम - शर्मा\n1200 रुपये मिले');
      expect(r.name, 'नेहा शर्मा');
      expect(r.amount, 1200);
      expect(r.direction, TxnDirection.credit);
    });

    test('sentence: "रवि को 500 दिए खाने के लिए"', () {
      final r = read('आज रवि को 500 दिए खाने के लिए');
      expect(r.name, 'रवि');
      expect(r.amount, 500);
      expect(r.direction, TxnDirection.debit);
      expect(r.when, DateTime(2026, 10, 27));
      expect(r.note, 'खाने');
    });

    test('"2 हज़ार" is 2000, from "नेहा से"', () {
      final r = read('नेहा से 2 हज़ार मिले');
      expect(r.name, 'नेहा');
      expect(r.amount, 2000);
      expect(r.direction, TxnDirection.credit);
    });

    test('"ke liye" means for, not received', () {
      final r = read('Ravi ko 300 diye petrol ke liye');
      expect(r.direction, TxnDirection.debit);
      expect(r.note, 'petrol');
    });
  });

  group('loopholes', () {
    test('a page listing several people becomes one entry each', () {
      final list = ScanReader.readList(
          rows: 'Udhaar diya 20/10/2026\nRavi 500\nNeha 300\nAmit Kumar 1,200',
          now: now)!;
      expect(list.map((r) => r.name), ['Ravi', 'Neha', 'Amit Kumar']);
      expect(list.map((r) => r.amount), [500, 300, 1200]);
      expect(list.every((r) => r.direction == TxnDirection.debit), isTrue);
      expect(list.every((r) => r.when == DateTime(2026, 10, 20)), isTrue);
    });

    test('a single entry, a labelled note or a bill is not a list', () {
      expect(ScanReader.readList(rows: 'Ravi 500', now: now), isNull);
      expect(
          ScanReader.readList(rows: 'Name: Ravi\nAmount: 500', now: now),
          isNull);
      expect(
          ScanReader.readList(
              rows: 'Chai 20.00\nSamosa 15.00\nBill total 35.00', now: now),
          isNull);
    });

    test('a handwritten note that mentions UTR keeps its own Amount', () {
      final r = read('Name: Ravi\nAmount: 750\nUTR 123456789012\nPaid');
      expect(r.amount, 750);
      expect(r.name, 'Ravi');
      expect(r.reference, '123456789012');
    });

    test('a date months back is flagged (likely a misread year)', () {
      final r = read('Name: Ravi\nAmount: 500\nPaid\nDate: 12/03/2025');
      expect(r.when, DateTime(2025, 3, 12));
      expect(r.unsure, contains(ScanField.date));
      expect(r.needsInput, isTrue);
    });

    test('a lakh or more from paper is flagged', () {
      final r = read('Name: Ravi\nAmount: 1,50,000\nPaid');
      expect(r.amount, 150000);
      expect(r.unsure, contains(ScanField.amount));
    });

    test('Hindi / Hinglish purposes map to categories', () {
      expect(ScanReader.categoryHint('sabzi'), 'groceries');
      expect(ScanReader.categoryHint('दवाई के लिए'), 'health');
      expect(ScanReader.categoryHint('ghar ka kiraya'), 'rent');
      expect(ScanReader.categoryHint('Ravi'), isNull);
    });

    test('generated text: only the amount is tappable, not phone or ref', () {
      final body = ScanSms.compose(
        amount: 500,
        direction: TxnDirection.debit,
        when: DateTime(2026, 10, 25, 14, 5),
        kindLabel: 'note',
        name: 'Ravi',
        reference: '123456789012',
        phone: '9876543210',
      );
      expect(SmsParser.amountSpans(body).spans.map((s) => s.value), [500]);
    });

    test('an edited scan entry is rewritten, keeping kind and phone', () {
      final body = ScanSms.compose(
          amount: 500,
          direction: TxnDirection.debit,
          when: DateTime(2026, 10, 25),
          kindLabel: 'bill',
          name: 'Ravi',
          phone: '9876543210');
      final again = ScanSms.recompose(body,
          amount: 650,
          direction: TxnDirection.debit,
          when: DateTime(2026, 10, 25),
          name: 'Ravi Kumar');
      expect(again, startsWith('Rs.650.00 debited'));
      expect(again, contains('Ravi Kumar'));
      expect(again, contains('Ph 9876543210.'));
      expect(again, contains('from a scanned bill.'));
    });
  });

  test('shop bill: total, merchant, and it is a spend', () {
    const text = 'CHAI POINT\nGSTIN 29ABCDE1234F1Z5\nDate: 28/09/2026\n'
        'Masala Chai x2 120.00\nSub Total 165.00\nGrand Total Rs 173.26';
    final r = ScanReader.read(rows: text, plain: text, now: now);
    expect(r.kind, ScanKind.bill);
    expect(r.amount, 173.26);
    expect(r.name, 'Chai Point');
    expect(r.direction, TxnDirection.debit);
    expect(r.when, DateTime(2026, 9, 28));
  });

  test('payment screenshot goes through the payment-screen parser', () {
    const text = 'Transaction Successful\n09:05 pm on 28 Sep 2026\n'
        'Paid to\nRAHUL VERMA\t₹389\nrahulv@ybl\n'
        'Debited from\nXXXXXX1268\t₹389\nUTR: 512345678901';
    final r = read(text);
    expect(r.kind, ScanKind.payment);
    expect(r.amount, 389);
    expect(r.name, 'Rahul Verma');
    expect(r.direction, TxnDirection.debit);
    expect(r.reference, '512345678901');
    expect(r.account, '1268');
    expect(r.needsInput, isFalse);
  });

  test('generated SMS reads like a bank SMS and says it is not one', () {
    final body = ScanSms.compose(
      amount: 500,
      direction: TxnDirection.debit,
      when: DateTime(2026, 10, 25, 14, 5),
      kindLabel: 'note',
      name: 'Ravi Kumar',
      upiVpa: 'ravi@okaxis',
      note: 'dinner',
    );
    expect(body,
        startsWith('Rs.500.00 debited on 25-Oct-26 14:05 to Ravi Kumar (VPA ravi@okaxis).'));
    expect(body, contains('Info: dinner.'));
    expect(body, contains('-${Transaction.scanSender}: generated by AERIS'));
    expect(body, contains('Not sent by any bank.'));
  });
}
