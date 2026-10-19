import 'package:flutter_test/flutter_test.dart';
import 'package:aeris_expense/models/transaction.dart';
import 'package:aeris_expense/services/sms_parser.dart';

/// Golden corpus: real-world Indian bank / card / wallet SMS shapes, each with
/// the fields the parser must get right. Every message here is a trap for a
/// first-match parser — a balance printed with "Rs" while the amount isn't, a
/// counterparty account that is "credited" inside a debit alert, boilerplate
/// words ("credited", "more", "free") that look like category keywords.
///
/// `dir: null` means the SMS must be REJECTED (no transaction created).
class _Case {
  final String name;
  final String sender;
  final String body;
  final TxnDirection? dir;
  final double? amount;
  final String? category;
  final String? account;
  final double? balance;
  final String? merchant; // case-insensitive "contains"
  const _Case(this.name, this.sender, this.body,
      {this.dir,
      this.amount,
      this.category,
      this.account,
      this.balance,
      this.merchant});
}

const _d = TxnDirection.debit;
const _c = TxnDirection.credit;

const corpus = <_Case>[
  // ── Bank of Baroda ─────────────────────────────────────────────
  _Case(
    'BOB A/C-to-A/C debit (amount has no Rs, balance does)',
    'JX-BOBSMS-T',
    '200.0 is debited from A/C XX268 on 11/10/2026 11:59:08; A/C XXXX5174 '
        'credited. TXN ID-1513152745.Total Bal:Rs. 85610.82. Avlbl Amt:Rs. '
        '85610.82. If not you, call 1800 5700/1800 5000-BOB',
    dir: _d, amount: 200, category: 'transfer', account: '268',
    balance: 85610.82, merchant: '5174',
  ),
  _Case(
    'BOB UPI Dr./Cr. abbreviations',
    'VM-BOBTXN',
    'Rs.150.00 Dr. from A/C XXXXXX1234 and Cr. to swiggy@axisbank. '
        'Ref:612345678901. AvlBal:Rs10234.50(2026:10:11 09:12:33). Not you? '
        'Call 18005700-BOB',
    dir: _d, amount: 150, category: 'food', account: '1234',
    balance: 10234.50, merchant: 'swiggy',
  ),
  _Case(
    'BOB UPI credit with CR-suffixed balance',
    'AD-BOBSMS',
    'Rs.5000.00 Credited to A/c ...1234 thru UPI/612345678901 by '
        'rohan@okaxis. Total Bal:Rs.15234.50CR. Avlbl Amt:Rs.15234.50'
        '(11-10-2026 10:12:33) - Bank of Baroda',
    dir: _c, amount: 5000, category: 'transfer', account: '1234',
    balance: 15234.50,
  ),
  _Case(
    'BOB credit from another account (amount has no Rs)',
    'JX-BOBSMS-T',
    '1000.0 is credited to A/C XX268 on 12/10/2026 10:02:11 from A/C '
        'XXXX5174. TXN ID-1513198765.Total Bal:Rs. 86610.82. Avlbl Amt:Rs. '
        '86610.82. If not you, call 1800 5700/1800 5000-BOB',
    dir: _c, amount: 1000, category: 'transfer', account: '268',
    balance: 86610.82,
  ),

  // ── HDFC ───────────────────────────────────────────────────────
  _Case(
    'HDFC UPI "Sent" multi-line',
    'JD-HDFCBK-S',
    'Sent Rs.20.00\nFrom HDFC Bank A/C *1234\nTo SWIGGY\nOn 12/10/26\n'
        'Ref 628512345678\nNot You?\nCall 18002586161/SMS BLOCK UPI to '
        '7308080808',
    dir: _d, amount: 20, category: 'food', account: '1234', merchant: 'swiggy',
  ),
  _Case(
    'HDFC money received via VPA',
    'VM-HDFCBK',
    'Money Received - INR 500.00 in your HDFC Bank A/c xx1234 on 12-10-26 '
        'by A/c linked to VPA rohan@okicici (UPI Ref No 628512345678).',
    dir: _c, amount: 500, category: 'transfer', account: '1234',
  ),
  _Case(
    'HDFC credit card UPI "Txn"',
    'AX-HDFCBK',
    'Txn Rs.649.00\nOn HDFC Bank Card 1234\nAt bigbasket@ybl \nby UPI '
        '628512345678\nOn 12-10\nNot You?\nCall 18002586161/SMS BLOCK CC 1234 '
        'to 7308080808',
    dir: _d, amount: 649, category: 'groceries', account: '1234',
  ),
  _Case(
    'HDFC debit card, ISO date, balance after',
    'JD-HDFCBK',
    'Rs.1,250.00 spent on HDFC Bank Card x1234 at ZOMATO on '
        '2026-10-12:13:45:10.Avl bal: Rs.23,456.00.Not you? Call 18002586161',
    dir: _d, amount: 1250, category: 'food', account: '1234',
    balance: 23456, merchant: 'zomato',
  ),
  _Case(
    'HDFC credit card spend with reward-points footer',
    'VM-HDFCBK',
    'Rs.899.00 spent on HDFC Bank Credit Card xx1234 at SWIGGY on 12-10-26. '
        'You earned 18 reward points. Not you? Call 18002586161',
    dir: _d, amount: 899, category: 'food',
  ),
  _Case(
    'HDFC executed AutoPay is a real spend',
    'VM-HDFCBK',
    'Your AutoPay of Rs.199.00 for NETFLIX has been successfully debited '
        'from A/c XX1234 on 12-10-26. UPI Ref 628512345678',
    dir: _d, amount: 199, category: 'entertainment',
  ),
  _Case(
    'HDFC credit card bill payment received (not income)',
    'VM-HDFCBK',
    'Payment of Rs.15,000.00 received towards your HDFC Bank Credit Card '
        'ending 1234 on 12-10-26. Thank you.',
    dir: _c, amount: 15000, category: 'transfer',
  ),

  // ── ICICI ──────────────────────────────────────────────────────
  _Case(
    'ICICI UPI debit, payee named in "; X credited"',
    'AX-ICICIB',
    'ICICI Bank Acct XX123 debited for Rs 250.00 on 12-Oct-26; ZOMATO '
        'credited. UPI:628512345678. Call 18002662 for dispute. SMS BLOCK 123 '
        'to 9215676766.',
    dir: _d, amount: 250, category: 'food', account: '123', merchant: 'zomato',
  ),
  _Case(
    'ICICI card spend, merchant after "on", Avl Limit',
    'AX-ICICIB',
    'INR 1,299.00 spent using ICICI Bank Card XX4321 on 02-Oct-26 on AMAZON. '
        'Avl Limit: INR 50,000.00. If not you, call 1800 2662/SMS BLOCK 4321 '
        'to 9215676766',
    dir: _d, amount: 1299, category: 'shopping', account: '4321',
    balance: 50000, merchant: 'amazon',
  ),
  _Case(
    'ICICI NEFT salary, balance in Info line',
    'VM-ICICIB',
    'Dear Customer, your Acct XX123 has been credited with INR 85,000.00 on '
        '30-Sep-26. Info: NEFT-ACME TECH PVT LTD-SALARY SEP. The Available '
        'Balance is INR 1,02,345.00.',
    dir: _c, amount: 85000, category: 'salary', account: '123',
    balance: 102345,
  ),
  _Case(
    'ICICI credit from a company (not salary)',
    'VM-ICICIB',
    'Dear Customer, Acct XX123 is credited with Rs 25,000.00 on 01-Oct-26 '
        'from ACME TECHNOLOGIES PVT. UPI:628512345678-ICICI Bank.',
    dir: _c, amount: 25000, category: 'transfer', merchant: 'acme',
  ),

  // ── SBI ────────────────────────────────────────────────────────
  _Case(
    'SBI UPI "debited by" no currency',
    'JM-SBIBNK',
    'Dear UPI user A/C X8208 debited by 101.00 on date 07Jun26 trf to Naib '
        'Subedar San Refno 615809770746 If not u? call-1800111109 for other '
        'services-18001234-SBI',
    dir: _d, amount: 101, account: '8208', merchant: 'naib',
  ),
  _Case(
    'SBI UPI credit, A/c glued to mask',
    'VM-SBIUPI',
    'Dear SBI UPI User, ur A/cX8208 credited by Rs500 on 12Oct26 by  '
        '(Ref no 628512345678)',
    dir: _c, amount: 500, account: '8208',
  ),
  _Case(
    'SBI ATM withdrawal',
    'VM-SBIBNK',
    'Dear Customer, Rs.2000 withdrawn at SBI ATM S1NW000093009 from A/cX8208 '
        'on 12Oct26 Transaction Number 1234. Available Balance Rs.12345.67. If '
        'not withdrawn by you, call 1800 1234 - SBI',
    dir: _d, amount: 2000, category: 'cash', account: '8208',
    balance: 12345.67,
  ),
  _Case(
    'SBI debit card POS "Transferred to"',
    'VM-SBIBNK',
    'Your A/C XXXXX8208 Debited INR 450.00 on 12/10/26 -Transferred to '
        'DOMINOS PIZZA. Avl Balance INR 12,345.00-SBI',
    dir: _d, amount: 450, category: 'food', balance: 12345,
  ),
  _Case(
    'SBI NEFT credit with Indian grouping',
    'VM-SBIBNK',
    'Your A/C XXXXX8208 Credited INR 1,00,000.00 on 12/10/26 -Deposit by '
        'transfer from ACME LTD. Avl Bal INR 1,12,345.00-SBI',
    dir: _c, amount: 100000, balance: 112345,
  ),
  _Case(
    'SBI Card spend with link footer',
    'VM-SBICRD',
    'Rs.2,500.00 spent on your SBI Credit Card ending 1234 at MYNTRA on '
        '12/10/26. Trxn. 628512345678. Not you? Report at '
        'https://sbicard.com/Dispute',
    dir: _d, amount: 2500, category: 'shopping', account: '1234',
  ),

  // ── Axis ───────────────────────────────────────────────────────
  _Case(
    'Axis UPI debit, payee in UPI/P2M narrative',
    'AX-AXISBK',
    'INR 500.00 debited\nA/c no. XX1234\n12-10-26, 10:20:11\n'
        'UPI/P2M/628512345678/BLINKIT\nNot you? SMS BLOCKUPI Cust ID to '
        '919951860002\nAxis Bank',
    dir: _d, amount: 500, category: 'groceries', account: '1234',
    merchant: 'blinkit',
  ),
  _Case(
    'Axis UPI credit, payer in UPI/P2A narrative',
    'AX-AXISBK',
    'INR 2,000.00 credited\nA/c no. XX1234\n12-10-26, 10:20:11 IST\n'
        'UPI/P2A/628512345678/ROHAN SHARMA\n- Axis Bank',
    dir: _c, amount: 2000, account: '1234', merchant: 'rohan',
  ),
  _Case(
    'Axis credit card, verb on its own line',
    'AX-AXISBK',
    'Spent\nCard no. XX1234\nINR 799\n12-10-26 10:20:11\nNETFLIX\n'
        'Avl Lmt INR 45,000\nSMS BLOCK 1234 to 919951860002, if not you - '
        'Axis Bank',
    dir: _d, amount: 799, category: 'entertainment', account: '1234',
    balance: 45000,
  ),

  // ── Kotak / PNB / Canara / Union / IDFC / Yes / IndusInd / others ──
  _Case(
    'Kotak UPI sent with link',
    'VM-KOTAKB',
    'Sent Rs.100.00 from Kotak Bank AC X1234 to zepto@ybl on 12-10-26.UPI '
        'Ref 628512345678. Not you, https://kotak.com/KBANKT/Fraud',
    dir: _d, amount: 100, category: 'groceries', account: '1234',
  ),
  _Case(
    'Kotak UPI received',
    'VM-KOTAKB',
    'Received Rs.750.00 in your Kotak Bank AC X1234 from priya@okhdfcbank on '
        '12-10-26.UPI Ref:628512345678.',
    dir: _c, amount: 750, account: '1234', merchant: 'priya',
  ),
  _Case(
    'Kotak debit towards merchant',
    'VM-KOTAKB',
    'Your Kotak Bank A/c X1234 has been debited for Rs.3,499.00 on 12-10-26 '
        'towards AMAZON PAY. Avl Bal Rs.12,000.00',
    dir: _d, amount: 3499, category: 'shopping', balance: 12000,
  ),
  _Case(
    'PNB debit with CR balance',
    'VM-PNBSMS',
    'Your A/c XX1234 is debited for Rs.500.00 on 12-10-2026 15:30:12 by '
        'UPI/628512345678/PHONEPE. Avl Bal Rs.10,000.00 CR. -PNB',
    dir: _d, amount: 500, account: '1234', balance: 10000,
  ),
  _Case(
    'PNB short form',
    'VM-PNBSMS',
    'A/c XX1234 debited INR 300.00 Dt 12-10-26 15:30:12 thru '
        'UPI:628512345678. Bal INR 9,700.00 Not u?Fwd this SMS to 9264092640 '
        'to block UPI.-PNB',
    dir: _d, amount: 300, account: '1234', balance: 9700,
  ),
  _Case(
    'Canara "An amount of" (sender not on the trusted list)',
    'VM-CANBNK',
    'An amount of INR 1,500.00 has been DEBITED to your account XXX123 on '
        '12/10/2026 towards UPI. Total Avail.bal INR 20,000.00. - Canara Bank',
    dir: _d, amount: 1500, account: '123', balance: 20000,
  ),
  _Case(
    'Union Bank "Rs:" with colon',
    'AD-UNIONB',
    'A/c *1234 Debited for Rs:250.00 on 12-10-2026 15:30:12 by Mob Bk ref no '
        '628512345678 Avl Bal Rs:10,000.00.If not you, Call 1800222243 -Union '
        'Bank of India',
    dir: _d, amount: 250, account: '1234', balance: 10000,
  ),
  _Case(
    'IDFC "New Bal"',
    'VM-IDFCFB',
    'Your A/C XXXXXXX1234 is debited by INR 999.00 on 12/10/26 15:30. New Bal '
        ':INR 5,000.00. Not you? Call 18001080 - IDFC FIRST Bank',
    dir: _d, amount: 999, account: '1234', balance: 5000,
  ),
  _Case(
    'Yes Bank UPI narrative with merchant',
    'VM-YESBNK',
    'INR 1,000.00 debited from A/c XX1234 on 12-OCT-2026 for '
        'UPI-628512345678-SWIGGY. Avl Bal: INR 2,345.00. Not you? Call '
        '18001200',
    dir: _d, amount: 1000, category: 'food', balance: 2345,
  ),
  _Case(
    'IndusInd full-width masked account',
    'VM-INDUSB',
    'Your IndusInd Account 1234XXXX5678 has been debited for INR 2,000.00 '
        'towards UPI/628512345678/rahul@ybl. Available Balance INR 10,000.00.',
    dir: _d, amount: 2000, account: '5678', balance: 10000,
  ),
  _Case(
    'Federal Bank UPI to Rapido',
    'VM-FEDBNK',
    'Rs 230.00 debited from your A/c XX1234 to VPA rapido@ybl on 12-10-2026 '
        '15:30:12. Bal: Rs 4,321.00 - Federal Bank',
    dir: _d, amount: 230, category: 'travel', balance: 4321,
  ),
  _Case(
    'AU Bank no-decimal amounts',
    'VM-AUBANK',
    'Dear Customer, INR 1,499 has been debited from your AU Bank A/c XX1234 '
        'on 12-OCT-26 via UPI to spotify@hdfcbank. Avl Bal INR 3,000',
    dir: _d, amount: 1499, category: 'entertainment', balance: 3000,
  ),
  _Case(
    'Generic "Available Balance is" after amount',
    'VM-CENTBK',
    'Dear Customer, Your Ac XXXX1234 is debited with INR 500.00 on 12 Oct '
        '2026 for UPI-UBER. Available Balance is INR 9,500.00.',
    dir: _d, amount: 500, category: 'travel', balance: 9500,
  ),
  _Case(
    'IMPS account-to-account transfer',
    'VM-HDFCBK',
    'Rs.10,000.00 transferred from A/c XX1234 to A/c XX9876 (IMPS Ref '
        '628512345678) on 12-10-26. Avl Bal Rs.5,000.00',
    dir: _d, amount: 10000, category: 'transfer', account: '1234',
    merchant: '9876', balance: 5000,
  ),
  _Case(
    'EMI debit: own account is the "your" one, not the loan',
    'VM-HDFCBK',
    'EMI of Rs.4,500.00 for Loan A/c XX5678 has been debited from your A/c '
        'XX1234 on 05-10-26. Avl Bal: Rs.12,000.00',
    dir: _d, amount: 4500, account: '1234', balance: 12000,
  ),
  _Case(
    'Cheque debit — cheque number is not the amount',
    'VM-SBIBNK',
    'Chq no 000123 for Rs.3,000.00 debited from A/c XX1234 on 12-10-26',
    dir: _d, amount: 3000,
  ),
  _Case(
    'Amount with /- suffix, bill payment',
    'VM-PNBSMS',
    'Rs 1,200/- debited from your account XX1234 towards ELECTRICITY BILL on '
        '12-10-26',
    dir: _d, amount: 1200, category: 'bills',
  ),
  _Case(
    'Currency after the number',
    'VM-CANBNK',
    'Amount of 750.00 INR has been debited from your account XX1234 on '
        '12/10/26 for BESCOM BILL',
    dir: _d, amount: 750, category: 'bills',
  ),
  _Case(
    'Credit card payment from the bank side (not a spend category)',
    'VM-ICICIB',
    'Rs.15,000.00 debited from A/c XX1234 towards CREDIT CARD payment on '
        '12-10-26.',
    dir: _d, amount: 15000, category: 'transfer',
  ),
  _Case(
    'Toll-free footer is not a promo',
    'VM-IOBCHN',
    'Your a/c no. XX1234 is debited for Rs.640.00 on 12-10-26 and credited '
        'to a/c no. XX4455 (UPI Ref no 628512345678). For queries call toll '
        'free 1800 425 4445 -IOB',
    dir: _d, amount: 640, category: 'transfer', account: '1234',
    merchant: '4455',
  ),

  _Case(
    'Debit "& credited to" another account stays a debit',
    'VM-SBIBNK',
    'Dear Customer, your A/c X1234 is debited by Rs.100 & credited to A/c '
        'X5678 on 12Oct26 (IMPS Ref 628512345678). If not done by you call '
        '1800111109-SBI',
    dir: _d, amount: 100, category: 'transfer', account: '1234',
    merchant: '5678',
  ),
  _Case(
    'Credit "and debited from" another account stays a credit',
    'VM-SBIBNK',
    'Rs.500 credited to your A/c XX1234 and debited from A/c XX5678 on '
        '12-10-26 (IMPS Ref 628512345678).',
    dir: _c, amount: 500, account: '1234', merchant: '5678',
  ),
  _Case(
    '"has a debit by transfer of" (noun form)',
    'VM-HDFCBK',
    'Your A/C XX1234 has a debit by transfer of Rs 750.00 on 12-10-26. Avl '
        'Bal Rs 2,250.00.',
    dir: _d, amount: 750, balance: 2250,
  ),
  _Case(
    'Salary via IMPS from a payroll account',
    'VM-SBIBNK',
    'Your a/c no. XXXXXXXX1234 is credited by Rs.25,000.00 on 01-10-2026 by '
        'a/c linked to mobile 9XXXXXX999-ACME PAYROLL (IMPS Ref no '
        '628512345678).',
    dir: _c, amount: 25000, category: 'salary', account: '1234',
  ),
  _Case(
    'Net-banking travel booking',
    'AD-SBIINB',
    'Dear Customer, Your A/c X1234 has been debited by Rs. 2,999.00 on '
        '12-Oct-26 for MAKEMYTRIP via Net Banking. Avl Bal: Rs. 10,001.00',
    dir: _d, amount: 2999, category: 'travel', balance: 10001,
  ),

  // ── Wallets / apps ─────────────────────────────────────────────
  _Case(
    'Amazon Pay wallet (Juspay)',
    'JM-APAYIN',
    'Your Apay Wallet balance is debited for INR 20.00. Transaction Reference '
        'Number is 652732468322. If not you? call 180012001637 - SMS via '
        'Juspay',
    dir: _d, amount: 20,
  ),
  _Case(
    'Paytm wallet with Updated Balance',
    'VM-PAYTMB',
    'Paid Rs.350 to Bigbasket from Paytm Balance. Updated Balance: Rs.1,234. '
        'Txn ID 9988776655',
    dir: _d, amount: 350, category: 'groceries', balance: 1234,
  ),
  _Case(
    'Paytm cashback credit from a trusted sender',
    'VM-PAYTMB',
    'Cashback of Rs.50.00 has been credited to your Paytm Wallet. Updated '
        'balance Rs.1,284.',
    dir: _c, amount: 50, category: 'refund',
  ),

  // ── Refunds / reversals / other credits ────────────────────────
  _Case(
    'Failed-txn reversal is a refund credit',
    'VM-HDFCBK',
    'Rs.500.00 reversed to your A/c XX1234 for failed UPI txn 628512345678 on '
        '12-10-26.',
    dir: _c, amount: 500, category: 'refund',
  ),
  _Case(
    'Interest credit',
    'VM-SBIBNK',
    'Interest of Rs.123.00 credited to your A/c XX1234 on 30-09-26. Avl Bal '
        'Rs.12,123.00',
    dir: _c, amount: 123, balance: 12123,
  ),
  _Case(
    'Cash deposit',
    'VM-SBIBNK',
    'Rs.5,000.00 deposited in A/c XX1234 by cash on 12-10-26. Avl Bal '
        'Rs.17,000.00',
    dir: _c, amount: 5000, balance: 17000,
  ),

  // ── Must be rejected ───────────────────────────────────────────
  _Case('OTP that quotes an amount', 'VM-HDFCBK',
      'OTP for txn of Rs.2,499.00 at AMAZON on HDFC Bank Card xx1234 is '
          '123456. Valid for 5 mins. Do not share.'),
  _Case('UPI collect request', 'VM-GPAYIN',
      'rohan@okaxis has requested money of Rs.500 from you on Google Pay. '
          'Approve to pay.'),
  _Case('Balance enquiry', 'VM-SBIBNK',
      'Your A/c XX1234 balance is Rs.12,345.00 as on 12-10-26 15:30. -SBI'),
  _Case('Credit card statement', 'VM-HDFCBK',
      'Your HDFC Bank Credit Card xx1234 statement is ready. Total amount due '
          'Rs.12,345.00, Minimum amount due Rs.620. Due date 05-11-26.'),
  _Case('Future autopay debit', 'VM-HDFCBK',
      'Rs.199.00 will be debited from your A/c XX1234 on 15-10-26 towards '
          'NETFLIX autopay.'),
  _Case('Phishing "credited" with link', 'VK-OFFERS',
      'Congratulations! Rs.50,000 credited to your account. Click bit.ly/claim '
          'to receive'),
  _Case('Bill-due reminder', 'VM-HDFCBK',
      'Your electricity bill of Rs.1,234 is due on 20-10-26. Pay now via HDFC '
          'Bank PayZapp.'),
  _Case('Mandate registration notice', 'VM-HDFCBK',
      'Your e-mandate for NETFLIX of Rs.199.00 has been successfully '
          'registered on A/c XX1234.'),
  _Case('Declined card payment', 'AX-ICICIB',
      'Txn of INR 2,500.00 on ICICI Bank Card XX4321 at MYNTRA was declined '
          'due to insufficient balance.'),
  _Case('Order shipped from a shop', 'AX-AMAZON',
      'Your Amazon order of Rs.499 has been shipped.'),
];

void main() {
  final now = DateTime(2026, 10, 12, 18, 0);

  group('SMS corpus', () {
    for (final k in corpus) {
      test(k.name, () {
        final p = SmsParser.parse(sender: k.sender, body: k.body, receivedAt: now);
        if (k.dir == null) {
          expect(p, isNull, reason: 'should be rejected');
          return;
        }
        expect(p, isNotNull, reason: 'should parse');
        final t = p!.txn;
        expect(t.direction, k.dir, reason: 'direction');
        if (k.amount != null) expect(t.amount, k.amount, reason: 'amount');
        if (k.category != null) {
          expect(t.categoryId, k.category, reason: 'category');
        }
        if (k.account != null) expect(t.account, k.account, reason: 'account');
        if (k.balance != null) expect(p.balance, k.balance, reason: 'balance');
        if (k.merchant != null) {
          expect(t.merchant?.toLowerCase() ?? '', contains(k.merchant),
              reason: 'merchant');
        }
        // A money-out transaction can never land in an income category.
        if (t.isDebit) {
          expect(t.categoryId, isNot(anyOf('salary', 'refund')));
        }
      });
    }
  });
}
