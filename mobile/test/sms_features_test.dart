import 'package:flutter_test/flutter_test.dart';
import 'package:aeris_expense/models/transaction.dart';
import 'package:aeris_expense/providers/accounts_provider.dart';
import 'package:aeris_expense/services/ledger_links.dart';
import 'package:aeris_expense/services/notification_intake.dart';
import 'package:aeris_expense/services/sms_parser.dart';

Transaction _sms(String sender, String body, DateTime at) =>
    SmsParser.parse(sender: sender, body: body, receivedAt: at)!.txn;

void main() {
  final now = DateTime(2026, 10, 12, 11, 0);

  group('Hindi (Devanagari) bank SMS', () {
    test('SBI Hindi debit with balance', () {
      final p = SmsParser.parse(
        sender: 'VM-SBIBNK',
        body: 'प्रिय ग्राहक, आपके खाते XX1234 से रु 500.00 की राशि दिनांक '
            '12/10/26 को डेबिट की गई है। उपलब्ध शेष रु 10,000.00 -SBI',
        receivedAt: now,
      )!;
      expect(p.txn.direction, TxnDirection.debit);
      expect(p.txn.amount, 500);
      expect(p.txn.account, '1234');
      expect(p.balance, 10000);
    });

    test('PNB Hindi credit (जमा) with Devanagari digits', () {
      final p = SmsParser.parse(
        sender: 'VM-PNBSMS',
        body: 'आपके खाते XX१२३४ में रु.२,०००.०० जमा किए गए हैं। शेष: रु.१२,०००.०० -PNB',
        receivedAt: now,
      )!;
      expect(p.txn.direction, TxnDirection.credit);
      expect(p.txn.amount, 2000);
      expect(p.balance, 12000);
    });

    test('Hindi OTP is rejected', () {
      expect(
          SmsParser.parse(
              sender: 'VM-HDFCBK',
              body: 'रु.1,499 के लेनदेन के लिए ओटीपी 123456 है। किसी से साझा न करें।',
              receivedAt: now),
          isNull);
    });

    test('"विशेष" (special) is not read as a balance', () {
      final p = SmsParser.parse(
        sender: 'VM-SBIBNK',
        body: 'आपके खाते XX1234 से रु 250.00 डेबिट किए गए। विशेष सूचना',
        receivedAt: now,
      )!;
      expect(p.txn.amount, 250);
      expect(p.balance, isNull);
    });
  });

  group('Card statements', () {
    test('HDFC statement: total, minimum, due date, card', () {
      final s = SmsParser.parseStatement(
        sender: 'VM-HDFCBK',
        body: 'Your HDFC Bank Credit Card xx1234 statement is ready. Total '
            'amount due Rs.12,345.00, Minimum amount due Rs.620. Due date '
            '05-11-26.',
        receivedAt: now,
      )!;
      expect(s.total, 12345);
      expect(s.minimum, 620);
      expect(s.dueDate, DateTime(2026, 11, 5));
      expect(s.last4, '1234');
    });

    test('ICICI text-month due date', () {
      final s = SmsParser.parseStatement(
        sender: 'AX-ICICIB',
        body: 'ICICI Bank Credit Card XX4321 Statement: Total Amt Due INR '
            '8,765.40; Min Amt Due INR 440.00; Payment Due Date 20-Nov-26.',
        receivedAt: now,
      )!;
      expect(s.total, 8765.40);
      expect(s.minimum, 440);
      expect(s.dueDate, DateTime(2026, 11, 20));
    });

    test('SBI Card "Pay by" — the statement date is not the due date', () {
      final s = SmsParser.parseStatement(
        sender: 'VM-SBICRD',
        body: 'Your SBI Card ending 1234 e-statement dated 12/10/2026 is sent. '
            'Total Amt Due Rs 5,432.10; Min Amt Due Rs 271.61; Pay by '
            '01/11/2026.',
        receivedAt: now,
      )!;
      expect(s.dueDate, DateTime(2026, 11, 1));
      expect(s.total, 5432.10);
    });

    test('a spend alert is not a statement', () {
      expect(
          SmsParser.parseStatement(
              sender: 'VM-HDFCBK',
              body: 'Rs.899.00 spent on HDFC Bank Credit Card xx1234 at SWIGGY '
                  'on 12-10-26.',
              receivedAt: now),
          isNull);
    });
  });

  group('Duplicates', () {
    test('bank SMS + UPI-app SMS with the same reference', () {
      final bank = _sms('VM-HDFCBK',
          'Rs.120.00 debited from A/c XX1234 to VPA chaipoint@ybl on 12-10-26. '
          'UPI Ref 628512345678', now);
      final app = _sms('VM-PHONPE',
          'Paid Rs 120 to Chai Point via PhonePe UPI. UPI Ref No 628512345678.',
          now.add(const Duration(minutes: 1)));
      expect(LedgerLinks.duplicateOf(app, [bank])?.id, bank.id);
    });

    test('bank SMS + GPay notification without a reference', () {
      final bank = _sms('VM-HDFCBK',
          'Rs.50.00 debited from A/c XX1234 on 12-10-26.', now);
      final notif = NotificationIntake.parse(
              app: 'GPAY',
              title: 'Rohan Sharma',
              text: 'Paid ₹50',
              postedAt: now.add(const Duration(minutes: 2)))!
          .txn;
      final dup = LedgerLinks.duplicateOf(notif, [bank]);
      expect(dup?.id, bank.id);
      // Merging keeps the person's name the bank SMS didn't have.
      expect(LedgerLinks.enrich(bank, notif).merchant, 'Rohan Sharma');
    });

    test('two ₹20 payments from the same sender are two payments', () {
      final a = _sms('VM-HDFCBK', 'Rs.20.00 debited from A/c XX1234 on 12-10-26.', now);
      final b = _sms('VM-HDFCBK', 'Rs.20.00 debited from A/c XX1234 on 12-10-26.',
          now.add(const Duration(minutes: 3)));
      expect(LedgerLinks.duplicateOf(b, [a]), isNull);
    });

    test('different references are different payments', () {
      final a = _sms('VM-HDFCBK',
          'Rs.20.00 debited from A/c XX1234 on 12-10-26. UPI Ref 628500000001', now);
      final b = _sms('VM-PHONPE',
          'Paid Rs 20 to Chai Point. UPI Ref No 628500000002.', now);
      expect(LedgerLinks.duplicateOf(b, [a]), isNull);
    });
  });

  group('Transfers between your own accounts', () {
    test('BOB debit naming the other account + credit on that account', () {
      final out = _sms('JX-BOBSMS-T',
          '200.0 is debited from A/C XX268 on 11/10/2026 11:59:08; A/C '
          'XXXX5174 credited. TXN ID-1513152745.Total Bal:Rs. 85610.82.', now);
      final into = _sms('VM-SBIBNK',
          'Your A/C XXXXX5174 Credited INR 200.00 on 11/10/26 -Deposit by '
          'transfer from SHIVANG. Avl Bal INR 5,200.00-SBI',
          now.add(const Duration(hours: 5)));
      final partner = LedgerLinks.transferPartner(into, [out]);
      expect(partner?.id, out.id);
      final (a, b) = LedgerLinks.pairTransfer(into, out);
      expect(a.selfTransfer && b.selfTransfer, isTrue);
      expect(a.isSpend || a.isIncoming || b.isSpend || b.isIncoming, isFalse);
    });

    test('a payment to a friend and money from another friend are not one',
        () {
      final paid = _sms('VM-HDFCBK',
          'Rs.500.00 debited from A/c XX1234 to VPA rohan@okaxis on 12-10-26.', now);
      final got = _sms('VM-SBIBNK',
          'Rs.500 credited to your A/c XX9999 received from priya@oksbi on '
          '12-10-26', now.add(const Duration(minutes: 5)));
      expect(LedgerLinks.transferPartner(got, [paid]), isNull);
    });
  });

  group('Refunds', () {
    test('a Flipkart refund links to the Flipkart purchase', () {
      final bought = _sms('VM-HDFCBK',
          'Rs.1,450.00 spent on HDFC Bank Card x1234 at FLIPKART on 01-10-26.',
          DateTime(2026, 10, 1, 10));
      final other = _sms('VM-HDFCBK',
          'Rs.450.00 spent on HDFC Bank Card x1234 at ZOMATO on 02-10-26.',
          DateTime(2026, 10, 2, 10));
      final refund = _sms('AD-HDFCBK',
          'Refund of Rs.450 has been credited to your A/c XX1234 from FLIPKART.',
          now);
      expect(refund.isRefund, isTrue);
      expect(LedgerLinks.refundedPurchase(refund, [bought, other])?.id,
          bought.id);
    });
  });

  group('Bank balance per account', () {
    test('latest printed balance, moved by later balance-less payments', () {
      final a = _sms('VM-HDFCBK',
          'Rs.100.00 debited from A/c XX1234 on 12-10-26. Avl bal Rs.5,000.00',
          now).copyWith(balance: 5000);
      final b = _sms('VM-HDFCBK', 'Rs.40.00 debited from A/c XX1234 on 12-10-26.',
          now.add(const Duration(hours: 1)));
      final s = summarizeAccounts([a, b], const {}).single;
      expect(s.bankBalance, 4960);
      expect(s.balance, 4960);
    });
  });

  group('UPI app notifications', () {
    test('Google Pay: payee comes from the title', () {
      final p = NotificationIntake.parse(
          app: 'GPAY', title: 'Rohan Sharma', text: 'Paid ₹10', postedAt: now)!;
      expect(p.txn.direction, TxnDirection.debit);
      expect(p.txn.amount, 10);
      expect(p.txn.merchant, 'Rohan Sharma');
      expect(NotificationIntake.appNameOf(p.txn.smsSender), 'Google Pay');
    });

    test('PhonePe received', () {
      final p = NotificationIntake.parse(
          app: 'PHONEPE',
          title: 'Money received',
          text: 'Received ₹500 from Priya',
          postedAt: now)!;
      expect(p.txn.direction, TxnDirection.credit);
      expect(p.txn.amount, 500);
    });

    test('a collect request or promo is not a payment', () {
      expect(
          NotificationIntake.parse(
              app: 'GPAY',
              title: 'Rohan Sharma',
              text: 'Rohan Sharma has requested ₹500',
              postedAt: now),
          isNull);
      expect(
          NotificationIntake.parse(
              app: 'PHONEPE',
              title: 'Win ₹100 cashback',
              text: 'Pay your electricity bill and win',
              postedAt: now),
          isNull);
    });
  });

  test('amountSpans marks every money number in the shown text', () {
    final r = SmsParser.amountSpans(
        '200.0 is debited from A/C XX268; Total Bal:Rs. 85610.82.');
    expect([for (final s in r.spans) s.value], [200.0, 85610.82]);
    expect(r.text.substring(r.spans.first.start, r.spans.first.end), '200.0');
  });
}
