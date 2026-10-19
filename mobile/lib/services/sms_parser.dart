import 'package:uuid/uuid.dart';

import '../models/category.dart';
import '../models/transaction.dart';
import 'merchant_directory.dart';

/// Parse Indian bank / UPI / card / wallet SMS into a [Transaction].
///
/// Bank alerts are machine-generated from a few hundred templates, so the hard
/// part isn't *finding* numbers — it's knowing what each one MEANS. A first-
/// match parser reads "200.0 is debited … Total Bal:Rs. 85610.82" as a
/// ₹85,610 spend (the balance is the first number with "Rs"), and reads
/// "A/C XXXX5174 credited" — the payee's account — as income. So this is a
/// small, deterministic entity + role pipeline:
///
///  1. Gate — trusted sender or bank-looking body; reject OTPs, statements,
///     reminders, collect requests, mandate set-ups, scams, failed payments.
///  2. Entities — mask dates, times, account/card masks, reference ids and
///     phone numbers, then every money-shaped number left is a candidate.
///  3. Roles — each candidate is labelled by the words before it: a balance
///     ("Avl Bal", "Total Bal", "Avlbl Amt", "Avl Limit", "New Bal"…), a fee,
///     or the transaction amount (bound to a verb like "debited"/"spent").
///  4. Direction — from the verb bound to the chosen amount, inside its own
///     clause, so "A/C XX268 debited…; A/C XX5174 credited" is a debit.
///  5. Accounts — split into yours vs the counterparty; the counterparty
///     becomes the payee when there's no merchant name.
///  6. Category — from merchant / narrative text, and it must agree with the
///     direction: a debit is never Salary or Refund.
///
/// Returns `null` when it can't bind an amount to a direction with
/// confidence, so the message is skipped instead of becoming a wrong entry.
class SmsParser {
  SmsParser._();

  static const _uuid = Uuid();

  /// Senders we trust for transactional parsing. Indian DLT bank headers look
  /// like `VM-SBIBNK`, `JD-HDFCBK-S`, `AX-ICICIB`; the operator prefix and
  /// the -S/-T suffix vary, so we only match the core.
  static final _trustedSenderFragments = <RegExp>[
    RegExp(r'(SBI|SBIBNK|SBINB)', caseSensitive: false),
    RegExp(r'(HDFC|HDFCBK)', caseSensitive: false),
    RegExp(r'(ICICI|ICICIB)', caseSensitive: false),
    RegExp(r'(AXIS|AXISBK)', caseSensitive: false),
    RegExp(r'(KOTAK|KOTAKB)', caseSensitive: false),
    RegExp(r'(IDFC|IDFCFB|IDFCBK)', caseSensitive: false),
    RegExp(r'(INDUS|INDBNK)', caseSensitive: false),
    RegExp(r'(YESBNK)', caseSensitive: false),
    RegExp(r'(IDBI)', caseSensitive: false),
    RegExp(r'(PNBSMS|PNB)', caseSensitive: false),
    RegExp(r'(BOBSMS|BOBTXN|BARODA)', caseSensitive: false),
    RegExp(
        r'(CANBNK|UNIONB|UBOI|BOIIND|CENTBK|CBOI|IOBCHN|IOBBNK|UCOBNK|'
        r'FEDBNK|FEDFIB|RBLBNK|AUBANK|AUBNK|EQUTAS|DBSBNK|SCBANK|HSBC|'
        r'CITIBK|BANDHN|KVBANK|SIBSMS|KARBNK|CSBBNK|JKBANK|DCBBNK|MAHABK|'
        r'PSBANK|IPPB|AIRBNK|JIOPBK|FINOBK|ONECRD|AMEX)',
        caseSensitive: false),
    RegExp(r'PAYTM', caseSensitive: false),
    RegExp(r'(PHONPE|PHONEPE)', caseSensitive: false),
    RegExp(r'(GPAY|GOOGPY)', caseSensitive: false),
    RegExp(r'(AMZPAY|AMAZONP|APAY)', caseSensitive: false),
    RegExp(r'JUSPAY', caseSensitive: false),
    RegExp(r'CRED', caseSensitive: false),
    RegExp(r'SLICE', caseSensitive: false),
    RegExp(r'NIYO', caseSensitive: false),
    RegExp(r'BHIM', caseSensitive: false),
    RegExp(r'(MOBIKWIK|FREECHARGE|OLAMONEY|JIOPAY|LAZYPAY)',
        caseSensitive: false),
    // UPI apps read from their notifications (sender NOTIF-<APP>).
    RegExp(r'^NOTIF-(NAVI|SUPERMONEY|JUPITER|EPIFI)$'),
  ];

  // ─ Gate: messages that are never a completed transaction ─────

  static final _hardRejects = <RegExp>[
    RegExp(r'\b(otp|verification code|one time password)\b',
        caseSensitive: false),
    // Statements and dues.
    RegExp(
        r'(view statement|statement (?:is|has been) (?:ready|generated)|'
        r'due date|minimum amount due|total amount due|\bis due\b|\bdue on\b|'
        r'\bdue by\b)',
        caseSensitive: false),
    // Lottery / prize / phishing scams that mimic bank wording.
    RegExp(
        r'\b(won|winner|win|prize|lottery|congratulations?|congrats|claim|'
        r'kyc|verify now|act now|urgent|blocked|suspended|pre-?approved|'
        r'loan offer|eligible for)\b',
        caseSensitive: false),
    // Card-control / informational notices (limit changes, enable/disable
    // card features) — not spends. Kept specific so genuine debit alerts
    // (which often include "Avl Bal") are not caught.
    RegExp(
        r'(limit\s*/?\s*usage|usage permission|permission for (?:debit|credit)|'
        r'processed successfully|daily tran|contactless\s*:|pos\s*/\s*ecom|'
        r'request via)',
        caseSensitive: false),
    // Future debits and reminders — the money hasn't moved yet, and counting
    // it would double up with the real alert when it executes.
    RegExp(
        r'(upcoming mandate|will\s+be\s+(?:debited|deducted|charged)|'
        r'account\s+will\s+be|scheduled\s+(?:for|debit|on)|pre-?debit|'
        r'reminder)',
        caseSensitive: false),
    // Mandate / autopay / SI set-up notices (registration, not execution).
    RegExp(
        r'(mandate|auto\s*-?pay|standing instruction|e-?nach|\bsi\b)'
        r'.{0,80}\b(registered|registration|activated|set ?up|created|'
        r'modified|revoked|cancelled|paused)\b',
        caseSensitive: false),
    // Money requests: nothing has moved until the user approves.
    RegExp(
        r'(has requested|requested money|collect request|requesting '
        r'(?:money|payment)|payment request)',
        caseSensitive: false),
  ];

  /// Marketing words. From an unknown sender they mean promo/phishing; from a
  /// DLT-registered bank header with a real completed-transaction structure
  /// they're just a footer ("You earned 18 reward points", "Cashback of
  /// Rs 50 credited", "call toll free 1800…"), so we keep the transaction.
  static final _softPromo = RegExp(
    r'\b(offer|cashback|rewards?|discount|voucher|gift|free|click)\b',
    caseSensitive: false,
  );

  /// Failed / declined payments — no money moved. ("Amount if debited will
  /// be reversed" also lands here.) Real reversals arrive as their own
  /// "credited/reversed" alert.
  static final _failedRe = RegExp(
    r'\b(failed|declined|unsuccessful|not successful|could not be '
    r'(?:processed|completed)|insufficient (?:funds|balance)|'
    r'if debited)\b',
    caseSensitive: false,
  );

  /// Any URL in the body — legit bank txn alerts almost never contain links,
  /// but phishing/promo SMS do. Used to reject links from untrusted senders.
  static final _urlRe = RegExp(
    r'(https?:\/\/|www\.|bit\.ly|tinyurl|\b[a-z0-9-]+\.(?:com|in|co|net|link|xyz)\b)',
    caseSensitive: false,
  );

  // ─ Entities ────────────────────────────────────────────────

  static const _months =
      r'(?:jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*';

  /// Spans whose digits are never money: dates, times, account/card masks,
  /// reference ids, phone numbers.
  static final _nonMoneyRes = <RegExp>[
    RegExp(r'\b20\d{2}[-/.:]\d{1,2}[-/.:]\d{1,2}\b'),
    RegExp(r'\b\d{1,2}[-/.]\d{1,2}[-/.](?:20)?\d{2}\b'),
    RegExp('\\b\\d{1,2}[-\\s]?$_months(?:[-\\s,]*(?:20)?\\d{2}\\b)?',
        caseSensitive: false),
    RegExp('\\b$_months\\s\\d{1,2},?\\s(?:20)?\\d{2}\\b', caseSensitive: false),
    RegExp(r'\b\d{1,2}[-/]\d{1,2}\b'),
    RegExp(r'\b\d{1,2}:\d{2}(?::\d{2})?(?:\s?[ap]\.?m\b\.?)?',
        caseSensitive: false),
    _acctRe,
    RegExp(r'(?<![a-z])[x*]+\d{2,}', caseSensitive: false),
    RegExp(
        r'(?:ref(?:erence)?|refno|rrn|utr|txn\s*(?:id|no|ref)|trxn|chq|cheque|'
        r'upi|transaction\s*(?:id|no|number|ref(?:erence)?))\b\.?'
        r'(?:\s*(?:no|number|id))?\.?(?:\s*is)?[\s.:#\-/]*\d+',
        caseSensitive: false),
    RegExp(
        r'\b(?:call|contact|dial|sms|fwd|helpline|care|whatsapp|to|free)\b'
        r'[^0-9a-z]{0,4}\d[\d\s\-/]{5,}\d',
        caseSensitive: false),
    RegExp(r'\b(?:1800|1860)[\d\s\-]{4,}\d\b'),
    RegExp(r'\b(?:91)?[6-9]\d{9}\b'),
  ];

  /// Account / card mention: "A/c XX1234", "A/cX8208", "Acct XX123",
  /// "AC X1234", "Card no. XX1234", "Credit Card ending 1234",
  /// "Account 1234XXXX5678", "A/c ...1234". Group 1 is the masked token.
  static final _acctRe = RegExp(
    r'(?<![a-z])(?:a\/?c|acct|account|card|ac)(?![a-wyz])\.?'
    r'(?:\s*(?:no|number|ending(?:\s+(?:with|in))?)\.?)?[\s.:#\-]*'
    r'([x*.]*\d[\dx*]*)',
    caseSensitive: false,
  );

  /// A bare mask with no "A/c" label, e.g. "XX1234" or "*1234".
  static final _bareMaskRe =
      RegExp(r'(?<![\w/])([x*]{2,}\d{3,6})\b', caseSensitive: false);

  static final _currencyAmtRe = RegExp(
    r'(?<![a-z])(?:rs|inr|₹|rupees?)\s*[.:\-]?\s*(\d[\d,]*(?:\.\d{1,2})?)(?!\d)',
    caseSensitive: false,
  );

  static final _bareAmtRe = RegExp(
    r'(?<![\w*/:\-.,₹])(\d[\d,]*(?:\.\d{1,2})?)(?![\w:\-]|/(?!-)|[.,]\d)',
  );

  static final _currencyAfterRe =
      RegExp(r'^\s*(?:inr|rs\b|rupees|/-)', caseSensitive: false);

  /// Verbs that move money, and which way. Matched as whole words.
  static final _verbRe = RegExp(
    r'\b(debited|spent|paid|sent|withdrawn|withdrawal|purchased?|transferred|'
    r'deducted|charged|txn|dr|made|debit(?!\s*card)|credited|received|'
    r'deposited|refund(?:ed)?|reversed|added|recd|rcvd|cr|'
    r'credit(?!\s*(?:card|limit|alert)))\b',
    caseSensitive: false,
  );
  static const _creditVerbs = {
    'credited', 'received', 'deposited', 'refund', 'refunded', 'reversed',
    'added', 'recd', 'rcvd', 'cr', 'credit',
  };

  /// "debited by Rs.100 & credited to A/c X5678": a verb on the far side of
  /// "and"/"&" belongs to the other account, so it binds more weakly.
  static final _conjunctionRe = RegExp(r'(?:^|\s)(?:and|&)(?:\s|$)',
      caseSensitive: false);

  static final _tokenRe = RegExp(r"[a-z][a-z./']*", caseSensitive: false);

  static final _balanceTokRe = RegExp(
    r'^(?:(?:avl|avbl|avlbl|avail|available|total|new|updated|closing|'
    r'ledger|clr|clear|net|wallet)\.?)?bal(?:ance)?$|'
    r'^(?:avl|avbl|avlbl|avail|available)$|^(?:limit|lmt|outstanding|o/s)$',
  );
  static const _feeToks = {
    'fee', 'fees', 'charge', 'charges', 'gst', 'surcharge', 'penalty', 'tax',
  };
  static const _amountLabelToks = {
    'amt', 'amount', 'txn', 'of', 'for', 'by', 'with', 'worth',
  };

  /// "… is your available balance" — a balance named after the number.
  static final _balanceAfterRe = RegExp(
    r'^\s*(?:is\s+)?(?:your\s+)?(?:avl|avbl|available|avail)?\.?\s*(?:bal|balance)\b',
    caseSensitive: false,
  );

  /// Abbreviations whose trailing "." doesn't end a clause.
  static const _abbrev = {
    'rs', 'no', 'bal', 'avl', 'avbl', 'avlbl', 'avail', 'a/c', 'ac', 'acct',
    'amt', 'ltd', 'pvt', 'dt', 'txn', 'trxn', 'ref', 'info', 'mr', 'mrs', 'ms',
    'dr', 'cr', 'inr', 'st', 'co', 'bk', 'lmt', 'chq', 'nos', 'vpa', 'id',
    'ph', 'tel', 'mob',
  };

  // ─ Merchant / payee ────────────────────────────────────────

  /// "UPI/P2M/628512345678/BLINKIT", "UPI-628512345678-SWIGGY",
  /// "UPI/628512345678/rahul@ybl".
  static final _upiNarrRe = RegExp(
    r'\bupi[/\-:](?:(?:p2[am]|dr|cr|in|out)[/\-])?\d{6,}[/\-]'
    r'([a-z][a-z0-9 .&@_\-]*?)(?=\s*(?:[/\n(]|\.\s|\.$|$|\s-\s|\s(?:not|avl|bal|on|ref)\b))',
    caseSensitive: false,
  );

  /// ICICI style: "Acct XX123 debited for Rs 250.00 …; ZOMATO credited."
  static final _payeeCreditedRe = RegExp(
    r";\s*([A-Za-z][A-Za-z0-9 .&'\-]{1,40}?)\s+(?:is\s+)?credited",
  );

  static final _atMerchantRe = RegExp(
    r'(?:\b[Aa]t|@)\s+([A-Z][A-Z0-9 &\-_\.\*]{2,40})',
  );
  static final _toVpaRe = RegExp(
    r'(?:\bto\s+(?:vpa\s+)?|trf to\s+|sent to\s+)([A-Za-z0-9 .@_\-]{3,40})',
    caseSensitive: false,
  );
  static final _fromVpaRe = RegExp(
    r'(?:\bfrom\s+(?:vpa\s+)?|recvd from\s+|received from\s+)([A-Za-z0-9 .@_\-]{3,40})',
    caseSensitive: false,
  );
  static final _towardsRe = RegExp(
    r'\btowards\s+([A-Za-z][A-Za-z0-9 &.\-]{2,40})',
    caseSensitive: false,
  );
  static final _forCapsRe = RegExp(r'\bfor\s+([A-Z][A-Z0-9 &.\-]{2,40})');

  /// Card-spend alerts name the merchant after "on": "INR 1,299 spent using
  /// ICICI Bank Card XX4321 on 02-Oct-26 on AMAZON." Only ALL-CAPS words are
  /// taken, so dates ("on 02-Oct-26") and prose ("on your card") are skipped.
  static final _onMerchantRe = RegExp(
    r'\bon\s+([A-Z][A-Z0-9&_*\-]*\b(?:\s[A-Z0-9&_*\-]+\b)*)',
  );

  /// Words that are a channel, bank or pronoun, never the payee.
  static const _notMerchant = {
    'upi', 'imps', 'neft', 'rtgs', 'pos', 'atm', 'ecom', 'card', 'netbanking',
    'sbi', 'hdfc', 'icici', 'axis', 'kotak', 'idfc', 'indusind', 'yes', 'idbi',
    'pnb', 'bob', 'paytm', 'phonepe', 'gpay', 'bhim', 'your', 'ur', 'a/c',
    'ac', 'acct', 'account', 'the', 'beneficiary', 'inr', 'rs', 'rs.', 'mob',
    'mobile', 'date', 'credit', 'debit', 'loan', 'cash',
  };

  /// Reference / UTR / RRN number — "UPI Ref no 453812345678", "Ref 123456",
  /// "RRN 123456789012", "txn id 123456", "UPI:123456789012".
  static final _refRe = RegExp(
    r'(?:transaction\s*reference(?:\s*(?:number|no))?|upi\s*ref(?:\s*no)?|'
    r'reference\s*(?:number|no)?|ref(?:\s*no)?|rrn|utr|txn\s*(?:id|ref)|upi)'
    r'[^0-9]{0,8}([0-9]{6,18})', // allow "no"/"is"/":" filler before the digits
    caseSensitive: false,
  );

  /// A UPI VPA / handle anywhere in the body, e.g. `name@okhdfcbank`, `q12@ybl`.
  static final _vpaRe = RegExp(
    r'([a-z0-9][a-z0-9._\-]{1,}@[a-z]{2,})',
    caseSensitive: false,
  );

  // ─ Category signals ────────────────────────────────────────

  static final _refundRe = RegExp(
      r'\b(refund(?:ed)?|reversed|reversal|cashback)\b',
      caseSensitive: false);
  static final _salaryRe = RegExp(r'\b(salary|payroll|sal|stipend)\b',
      caseSensitive: false);
  // Paying a credit-card bill moves money between your own accounts — the
  // spends were already counted when the card was swiped.
  static final _cardPaymentRe = RegExp(
    r'credit\s*card\b.{0,40}\b(payment|bill|dues?)\b|'
    r'\b(payment|paid)\b.{0,50}\bcredit\s*card',
    caseSensitive: false,
  );
  static final _atmRe = RegExp(r'\batm\b', caseSensitive: false);
  static final _cashRe =
      RegExp(r'\b(withdrawn|withdrawal|cash)\b', caseSensitive: false);
  static final _boilerplateRe = RegExp(
    r'\b(not you|if not|not u\b|not done by you|call\b|sms block|to report|'
    r'report\b|dispute|never share|helpline|customer care|t&c)',
    caseSensitive: false,
  );
  static final _balancePhraseRe = RegExp(
    r'\b(?:avl|avbl|avlbl|avail|available|total|new|updated|closing|ledger)?'
    r'\.?\s*(?:bal|balance|limit|lmt)\b[^a-z]*',
    caseSensitive: false,
  );

  // ─ Dates ───────────────────────────────────────────────────

  /// SMS time hints — most alerts include date "30-05-26" or "30/05/2026".
  static final _dateRe = RegExp(
    r'\b([0-3]?[0-9])[-\/]([0-1]?[0-9])[-\/](20[0-9]{2}|[0-9]{2})\b',
  );
  static final _isoDateRe =
      RegExp(r'\b(20[0-9]{2})[-\/:]([0-1]?[0-9])[-\/:]([0-3]?[0-9])\b');

  /// Text-month date, no separators needed — e.g. "07Jun26", "7 Jun 2026".
  static final _dateTextRe = RegExp(
    r'\b([0-3]?[0-9])[-\s]?(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*[-\s]?(20[0-9]{2}|[0-9]{2})\b',
    caseSensitive: false,
  );
  static const _monthNames = {
    'jan': 1,
    'feb': 2,
    'mar': 3,
    'apr': 4,
    'may': 5,
    'jun': 6,
    'jul': 7,
    'aug': 8,
    'sep': 9,
    'oct': 10,
    'nov': 11,
    'dec': 12,
  };

  /// Public API.
  static ParsedSms? parse({
    required String sender,
    required String body,
    required DateTime receivedAt,
  }) {
    final doc = _Doc(body);
    final flat = doc.flat;
    if (flat.isEmpty) return null;
    final trusted = isTrustedSender(sender);
    if (!trusted && !looksLikeBankBody(flat)) return null;
    if (_hardRejects.any((r) => r.hasMatch(flat))) return null;
    // Links from an untrusted sender → almost always phishing/promo, never a
    // genuine bank debit/credit alert.
    if (!trusted && _urlRe.hasMatch(flat)) return null;
    if (!trusted && _softPromo.hasMatch(flat)) return null;

    final pick = _pickAmount(doc);
    if (pick == null) return null;
    final amount = pick.amount.value;

    final direction = pick.direction;
    if (direction == TxnDirection.debit && _failedRe.hasMatch(flat)) {
      return null;
    }
    // Scammers fake "credited" messages ("You won Rs 50000, claim now") to
    // look like income. Only trust a credit if it comes from a known
    // bank / UPI sender — debits from bank-like bodies are still allowed.
    if (direction == TxnDirection.credit && !trusted) return null;

    final accounts = _accounts(doc, direction);
    final vpa = _vpaRe.firstMatch(flat)?.group(1)?.toLowerCase();
    final reference = _refRe.firstMatch(flat)?.group(1);
    final atm = direction == TxnDirection.debit &&
        _atmRe.hasMatch(flat) &&
        _cashRe.hasMatch(flat);

    var merchant = atm ? 'ATM' : _extractMerchant(doc.norm, direction);
    // Enrich on-device: a known payee gets a friendly name + category; an
    // unknown one gets a cleaned-up name from its VPA prefix where readable.
    final dirHit = atm
        ? null
        : MerchantDirectory.lookup(merchant) ?? MerchantDirectory.lookup(vpa);
    if (!atm) {
      merchant = MerchantDirectory.prettyName(vpa, merchant) ?? merchant;
    }
    // No name anywhere, but the other side is an account ("…; A/C XXXX5174
    // credited", "to A/c XX9876"): that account is the payee/payer.
    final viaAccount = merchant == null && accounts.counterparty != null;
    if (viaAccount) merchant = 'A/c ••${accounts.counterparty}';

    final categoryId = _categoryFor(
      dir: direction,
      flat: flat,
      merchant: merchant,
      vpa: vpa,
      dirHit: dirHit,
      atm: atm,
      viaAccount: viaAccount,
    );
    final ts = _extractDate(flat, fallback: receivedAt);

    return ParsedSms(
      txn: Transaction(
        id: _uuid.v4(),
        amount: amount,
        direction: direction,
        timestamp: ts,
        merchant: merchant,
        account: accounts.own,
        categoryId: categoryId,
        source: TxnSource.sms,
        smsBody: body,
        smsSender: sender,
        reviewed: false,
        reference: reference,
        upiVpa: vpa,
      ),
      confidence: _scoreConfidence(pick, merchant, accounts.own),
      balance: pick.balance,
    );
  }

  /// Every money-shaped number in [body], in reading order — including
  /// balances. Stable for a given bank template, so a user's correction
  /// ("the amount is the 1st number, not the 2nd") can be remembered as a
  /// slot index and replayed on that bank's future alerts.
  static List<double> amountSlots(String body) =>
      [for (final c in _candidates(_Doc(body))) c.value];

  /// A key shared by every alert built from the same bank template: the
  /// sender core plus the message skeleton with numbers, names and ids
  /// abstracted away.
  static String templateKey(String sender, String body) {
    final doc = _Doc(body);
    final cands = _candidates(doc);
    final b = StringBuffer();
    var last = 0;
    for (final c in cands) {
      b
        ..write(doc.flat.substring(last, c.start))
        ..write(' \u00A7 ');
      last = c.end;
    }
    b.write(doc.flat.substring(last));
    final words = <String>[];
    for (final m in RegExp(r'\S+').allMatches(b.toString().toLowerCase())) {
      var w = m.group(0)!.replaceAll(RegExp(r'^[^\w\u00A7/]+|[^\w\u00A7/]+$'), '');
      if (w.isEmpty) continue;
      if (w != '\u00A7') {
        if (RegExp(r'\d').hasMatch(w)) {
          w = '#';
        } else if (!_skeletonVocab.contains(w)) {
          w = '*';
        }
      }
      if (words.isNotEmpty && words.last == w && (w == '*' || w == '#')) {
        continue;
      }
      words.add(w);
    }
    return '${senderCore(sender)}|${words.join(' ')}';
  }

  /// A credit-card bill payment ("Payment of Rs 15,000 received towards your
  /// Credit Card", "debited towards CREDIT CARD payment").
  static bool isCardPayment(String body) =>
      _cardPaymentRe.hasMatch(_Doc(body).flat);

  /// "JX-BOBSMS-T" → "BOBSMS": the DLT header without the operator prefix
  /// and the -S/-T/-P suffix.
  static String senderCore(String sender) => sender
      .trim()
      .toUpperCase()
      .replaceAll(RegExp(r'^[A-Z]{2}-'), '')
      .replaceAll(RegExp(r'-[A-Z]$'), '');

  /// The SMS as the parser reads it (whitespace tidied, Hindi mapped), with
  /// the position and value of every money number in it — for showing the
  /// numbers as tappable ("this one is the amount").
  static ({String text, List<({int start, int end, double value})> spans})
      amountSpans(String body) {
    final doc = _Doc(body);
    return (
      text: doc.norm,
      spans: [
        for (final c in _candidates(doc))
          (start: c.start, end: c.end, value: c.value)
      ],
    );
  }

  // ─ Card statements ─────────────────────────────────────────

  static const _amt = r'(\d[\d,]*(?:\.\d{1,2})?)';
  static final _stmtTotalRe = RegExp(
    r'(?:total\s*(?:amount|amt)?\.?\s*due|total\s*outstanding|'
    r'(?:statement|stmt)\.?\s*(?:balance|amount|amt)|amount\s*due)'
    '[^0-9]{0,16}?$_amt',
    caseSensitive: false,
  );
  static final _stmtMinRe = RegExp(
    r'(?:min(?:imum)?\.?\s*(?:amount|amt)?\.?\s*due|\bmad\b)'
    '[^0-9]{0,16}?$_amt',
    caseSensitive: false,
  );
  static final _stmtDueKeyRe = RegExp(
    r'(?:due\s*(?:date|by|on)?|pay(?:ment)?\s*(?:due\s*)?(?:by|before)|'
    r'payable\s*by)\b[\s:\-is]*',
    caseSensitive: false,
  );
  static final _cardRe =
      RegExp(r'\bcredit\s*card\b|\bcard\b', caseSensitive: false);
  static final _stmtWordRe = RegExp(
      r'\b(statement|stmt|e-?statement|bill|due)\b',
      caseSensitive: false);

  /// A credit-card statement or payment-due alert, or null. These are not
  /// transactions (no money moved), so [parse] rejects them; this reads what
  /// is owed and by when, to become a bill reminder.
  static CardStatement? parseStatement({
    required String sender,
    required String body,
    required DateTime receivedAt,
  }) {
    final flat = _Doc(body).flat;
    if (!isTrustedSender(sender)) return null;
    if (!_cardRe.hasMatch(flat) || !_stmtWordRe.hasMatch(flat)) return null;
    if (RegExp(r'\b(otp|received|credited|thank you for (?:the )?payment)\b',
            caseSensitive: false)
        .hasMatch(flat)) {
      return null;
    }
    DateTime? due;
    for (final m in _stmtDueKeyRe.allMatches(flat)) {
      final rest = flat.substring(m.end, (m.end + 24).clamp(0, flat.length));
      final d = _parseLeadingDate(rest);
      if (d != null) {
        due = d;
        break;
      }
    }
    if (due == null) return null;
    double? num(RegExpMatch? m) =>
        m == null ? null : double.tryParse(m.group(1)!.replaceAll(',', ''));
    var total = num(_stmtTotalRe.firstMatch(flat));
    // "Payment of Rs 5,432 for your card … is due on 01/11/26": the only
    // money figure is what's owed.
    total ??= num(_currencyAmtRe.firstMatch(flat));
    if (total == null || total <= 0) return null;
    String? last4;
    for (final m in _acctRe.allMatches(flat)) {
      final d = RegExp(r'(\d{3,6})$').firstMatch(m.group(1)!)?.group(1);
      if (d != null) {
        last4 = d;
        break;
      }
    }
    return CardStatement(
      bank: senderCore(sender),
      last4: last4,
      total: total,
      minimum: num(_stmtMinRe.firstMatch(flat)),
      dueDate: due,
      receivedAt: receivedAt,
    );
  }

  /// A date at the very start of [s]: 05-11-26, 05/11/2026, 20-Nov-26,
  /// 20 Nov 2026, 2026-11-05.
  static DateTime? _parseLeadingDate(String s) {
    final t = s.trimLeft();
    int? y, mo, d;
    var m = RegExp(r'^(\d{1,2})[-/.](\d{1,2})[-/.](\d{2,4})\b').firstMatch(t);
    if (m != null) {
      d = int.parse(m.group(1)!);
      mo = int.parse(m.group(2)!);
      y = int.parse(m.group(3)!);
    } else if ((m = RegExp(r'^(20\d{2})[-/.](\d{1,2})[-/.](\d{1,2})\b')
            .firstMatch(t)) !=
        null) {
      y = int.parse(m!.group(1)!);
      mo = int.parse(m.group(2)!);
      d = int.parse(m.group(3)!);
    } else if ((m = RegExp(
                r'^(\d{1,2})[-\s]?(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*[-\s,]*(\d{2,4})\b',
                caseSensitive: false)
            .firstMatch(t)) !=
        null) {
      d = int.parse(m!.group(1)!);
      mo = _monthNames[m.group(2)!.toLowerCase()];
      y = int.parse(m.group(3)!);
    }
    if (y == null || mo == null || d == null) return null;
    if (y < 100) y += 2000;
    final out = DateTime(y, mo, d);
    return out.month == mo && out.day == d ? out : null;
  }

  static const _skeletonVocab = {
    'debited', 'credited', 'spent', 'paid', 'sent', 'received', 'withdrawn',
    'deposited', 'transferred', 'refund', 'reversed', 'txn', 'transaction',
    'a/c', 'ac', 'acct', 'account', 'card', 'bal', 'balance', 'avl', 'avbl',
    'avlbl', 'available', 'total', 'amt', 'amount', 'rs', 'inr', 'upi', 'ref',
    'no', 'on', 'from', 'to', 'by', 'for', 'at', 'via', 'thru', 'towards',
    'your', 'is', 'has', 'been', 'of', 'and', 'info', 'limit', 'lmt', 'new',
    'updated', 'wallet', 'dr', 'cr', 'id',
  };

  // ─ Helpers ─────────────────────────────────────────────────

  static bool isTrustedSender(String sender) {
    final s = sender.trim();
    return _trustedSenderFragments.any((r) => r.hasMatch(s));
  }

  static bool looksLikeBankBody(String body) {
    final b = body.toLowerCase();
    return b.contains('a/c') ||
        b.contains('account') ||
        b.contains('upi') ||
        b.contains('vpa') ||
        b.contains('available balance') ||
        b.contains('avl bal') ||
        b.contains('wallet') || // Amazon Pay / Mobikwik etc.
        b.contains('debited for') ||
        b.contains('credited for') ||
        b.contains('transaction reference') ||
        b.contains('txn ref');
  }

  /// All money candidates with their role, in reading order.
  static List<_Amount> _candidates(_Doc doc) {
    final flat = doc.flat;
    final blocked = <(int, int)>[];
    for (final r in _nonMoneyRes) {
      for (final m in r.allMatches(flat)) {
        blocked.add((m.start, m.end));
      }
    }
    bool isBlocked(int s, int e) =>
        blocked.any((b) => s < b.$2 && e > b.$1);

    final out = <_Amount>[];
    for (final m in _currencyAmtRe.allMatches(flat)) {
      final v = _num(m.group(1)!);
      if (v == null) continue;
      out.add(_Amount(v, m.start, m.end, true, m.group(1)!.contains('.')));
    }
    for (final m in _bareAmtRe.allMatches(flat)) {
      if (out.any((c) => m.start < c.end && m.end > c.start)) continue;
      if (isBlocked(m.start, m.end)) continue;
      final raw = m.group(1)!;
      final v = _num(raw);
      if (v == null) continue;
      final hasDecimal = raw.contains('.');
      // A long comma-free integer is a reference or phone number.
      if (!hasDecimal && !raw.contains(',') && raw.length >= 7) continue;
      final hasCurrency = _currencyAfterRe.hasMatch(flat.substring(m.end));
      out.add(_Amount(v, m.start, m.end, hasCurrency, hasDecimal));
    }
    out.sort((a, b) => a.start.compareTo(b.start));

    for (var i = 0; i < out.length; i++) {
      final c = out[i];
      final clauseStart = doc.clauseStart(c.start);
      final prevEnd = i > 0 ? out[i - 1].end : 0;
      var from = [clauseStart, prevEnd, c.start - 40].reduce(_max);
      if (from > c.start) from = c.start;
      final prefix = flat.substring(from, c.start);
      final toks = [
        for (final m in _tokenRe.allMatches(prefix))
          m.group(0)!.toLowerCase().replaceAll(RegExp(r'[.:]+$'), '')
      ];
      var steps = 0;
      for (final t in toks.reversed) {
        if (++steps > 5) break;
        if (_balanceTokRe.hasMatch(t)) {
          c.role = _Role.balance;
          break;
        }
        if (_feeToks.contains(t)) {
          c.role = _Role.fee;
          break;
        }
        if (_verbRe.hasMatch(t)) break;
      }
      if (c.role == _Role.txn) {
        final end = doc.clauseEnd(c.end);
        if (_balanceAfterRe.hasMatch(flat.substring(c.end, end))) {
          c.role = _Role.balance;
        }
      }
      final last2 = toks.length > 2 ? toks.sublist(toks.length - 2) : toks;
      c.labelled = last2.any(_amountLabelToks.contains);
    }
    return out;
  }

  static int _max(int a, int b) => a > b ? a : b;

  static double? _num(String raw) {
    final v = double.tryParse(raw.replaceAll(',', ''));
    return v == null || v <= 0 ? null : v;
  }

  /// Choose the transaction amount and the direction bound to it.
  static _Pick? _pickAmount(_Doc doc) {
    final cands = _candidates(doc);
    if (cands.isEmpty) return null;
    final verbs = [
      for (final m in _verbRe.allMatches(doc.flat))
        _Verb(m.start, m.end, !_creditVerbs.contains(m.group(1)!.toLowerCase()))
    ];

    _Verb? nearest(_Amount c, {required bool sameClause}) {
      _Verb? best;
      var bestD = 1 << 30;
      final clause = doc.clauseOf(c.start);
      for (final v in verbs) {
        if (sameClause && doc.clauseOf(v.start) != clause) continue;
        final lo = v.start >= c.end ? c.end : v.end;
        final hi = v.start >= c.end ? v.start : c.start;
        if (hi < lo) continue;
        // A verb can't reach past another amount to bind to this one.
        if (cands.any((o) => !identical(o, c) && o.start >= lo && o.end <= hi)) {
          continue;
        }
        var d = hi - lo;
        if (_conjunctionRe.hasMatch(doc.flat.substring(lo, hi))) d += 25;
        if (d < bestD) {
          bestD = d;
          best = v;
        }
      }
      if (best != null) best.distance = bestD;
      return best;
    }

    _Amount? best;
    var bestScore = double.negativeInfinity;
    _Verb? bestVerb;
    var bestCross = false;
    for (var i = 0; i < cands.length; i++) {
      final c = cands[i];
      var s = 0.0;
      if (c.role == _Role.balance) s -= 10;
      if (c.role == _Role.fee) s -= 4;
      if (c.hasCurrency) s += 2;
      if (c.hasDecimal) s += 0.5;
      if (c.labelled) s += 1;
      if (i == 0) s += 0.3;
      var verb = nearest(c, sameClause: true);
      var cross = false;
      final d = verb?.distance;
      if (verb != null && d! <= 60) {
        s += d <= 12 ? 4 : (d <= 30 ? 3 : 1.5);
      } else {
        verb = nearest(c, sameClause: false);
        cross = true;
        if (verb != null && verb.distance <= 60) s += 1;
        // A bare number with no verb next to it is an id, not money.
        if (!c.hasCurrency) continue;
      }
      if (s > bestScore) {
        bestScore = s;
        best = c;
        bestVerb = verb;
        bestCross = cross;
      }
    }
    if (best == null || best.role == _Role.balance || bestScore < 2) {
      return null;
    }
    final verb = bestVerb ?? nearest(best, sameClause: false);
    if (verb == null) return null;
    final balance = cands
        .where((c) => c.role == _Role.balance && !identical(c, best))
        .map((c) => c.value)
        .firstOrNull;
    return _Pick(
      amount: best,
      direction: verb.debit ? TxnDirection.debit : TxnDirection.credit,
      verbBound: !bestCross,
      balance: balance,
    );
  }

  /// Your account vs the other side's.
  static ({String? own, String? counterparty}) _accounts(
      _Doc doc, TxnDirection dir) {
    final flat = doc.flat;
    final low = flat.toLowerCase();
    final mentions = <({int start, int end, String digits})>[];
    void add(RegExpMatch m) {
      final token = m.group(1)!;
      final digits = RegExp(r'(\d{3,6})$').firstMatch(token)?.group(1);
      if (digits == null) return;
      if (mentions.any((x) => m.start < x.end && m.end > x.start)) return;
      mentions.add((start: m.start, end: m.end, digits: digits));
    }

    _acctRe.allMatches(flat).forEach(add);
    _bareMaskRe.allMatches(flat).forEach(add);
    mentions.sort((a, b) => a.start.compareTo(b.start));

    String? own, yours, counterparty;
    for (final m in mentions) {
      final pre = low.substring(_max(0, m.start - 24), m.start);
      final post = low.substring(m.end, (m.end + 16).clamp(0, low.length));
      if (RegExp(r'\b(loan|emi)\s*$').hasMatch(pre)) continue;
      if (RegExp(r'\b(your|ur)\b[a-z ]{0,20}$').hasMatch(pre)) {
        yours ??= m.digits;
        continue;
      }
      final other = dir == TxnDirection.debit
          ? RegExp(r'(\bto|\bbeneficiary|\bbenef)\s*$').hasMatch(pre) ||
              RegExp(r'^\W*(?:is\s+|has been\s+)?(credited|cr\b)').hasMatch(post)
          : RegExp(r'(\bfrom|\bby)\s*$').hasMatch(pre) ||
              RegExp(r'^\W*(?:is\s+|has been\s+)?(debited|dr\b)').hasMatch(post);
      if (other) {
        counterparty ??= m.digits;
      } else {
        own ??= m.digits;
      }
    }
    return (own: yours ?? own, counterparty: counterparty);
  }

  static String? _extractMerchant(String body, TxnDirection dir) {
    final candidates = <String? Function()>[
      () => _upiNarrRe.firstMatch(body)?.group(1),
      if (dir == TxnDirection.debit)
        () => _payeeCreditedRe.firstMatch(body)?.group(1),
      if (dir == TxnDirection.credit) () => _fromVpaRe.firstMatch(body)?.group(1),
      () => _atMerchantRe.firstMatch(body)?.group(1),
      // "to …" in a credit alert is your own account ("credited to your A/c").
      if (dir == TxnDirection.debit) () => _toVpaRe.firstMatch(body)?.group(1),
      () => _towardsRe.firstMatch(body)?.group(1),
      if (dir == TxnDirection.debit) () => _forCapsRe.firstMatch(body)?.group(1),
    ];
    for (final get in candidates) {
      final raw = get();
      if (raw == null) continue;
      final name = _trimMerchant(raw);
      if (_plausibleMerchant(name)) return name;
    }
    if (dir == TxnDirection.debit) {
      for (final m in _onMerchantRe.allMatches(body)) {
        final name = _trimMerchant(m.group(1)!);
        if (_plausibleMerchant(name)) return name;
      }
    }
    return null;
  }

  static bool _plausibleMerchant(String name) {
    if (name.length < 3) return false;
    if (!RegExp(r'[a-z]{2}', caseSensitive: false).hasMatch(name)) {
      return false;
    }
    final first = name.split(RegExp(r'[\s/]')).first.toLowerCase();
    if (_notMerchant.contains(first)) return false;
    // An account mask is a counterparty account, handled separately.
    if (RegExp(r'^(?:a\/?c|acct|account)\b|[x*]{2,}\d', caseSensitive: false)
        .hasMatch(name)) {
      return false;
    }
    return true;
  }

  static String _trimMerchant(String raw) {
    var m = raw.split('\n').first.trim();
    // Cut at common trailing tokens (case-insensitive).
    final low = m.toLowerCase();
    var cutAt = m.length;
    for (final cut in [
      ' on ', ' refno', ' ref ', ' avl ', ' upi ', ' from ', ' via ',
      ' thru ', ' by ', ' using ', ' with ', ' for ', ' towards ', ' not ',
      ' bal ', ' (', '.', ',', ';',
    ]) {
      final idx = low.indexOf(cut);
      if (idx > 2 && idx < cutAt) cutAt = idx;
    }
    m = m.substring(0, cutAt);
    return m.trim().replaceAll(RegExp(r'[\s\-_*]+$'), '');
  }

  static String _categoryFor({
    required TxnDirection dir,
    required String flat,
    required String? merchant,
    required String? vpa,
    required ({String name, String categoryId})? dirHit,
    required bool atm,
    required bool viaAccount,
  }) {
    if (dir == TxnDirection.credit) {
      if (_refundRe.hasMatch(flat)) return 'refund';
      if (_salaryRe.hasMatch(flat)) return 'salary';
      return 'transfer';
    }
    // Money out is never income: Salary / Refund are not options here.
    const incomeOnly = {'salary', 'refund'};
    if (_cardPaymentRe.hasMatch(flat)) return 'transfer';
    if (atm) return 'cash';
    if (dirHit != null && !incomeOnly.contains(dirHit.categoryId)) {
      return dirHit.categoryId;
    }
    if (viaAccount) return 'transfer';
    var c = Categories.classify('${merchant ?? ''} ${vpa ?? ''}',
        exclude: incomeOnly);
    if (c == 'other') {
      c = Categories.classify(_narrative(flat), exclude: incomeOnly);
    }
    return c;
  }

  /// The part of the SMS that describes the payment: footer boilerplate
  /// ("Not you? Call…") and balance phrases removed, so their words can't
  /// pick the category.
  static String _narrative(String flat) {
    var s = flat;
    final cut = _boilerplateRe.firstMatch(s);
    if (cut != null && cut.start > 10) s = s.substring(0, cut.start);
    return s.replaceAll(_balancePhraseRe, ' ');
  }

  static DateTime _extractDate(String body, {required DateTime fallback}) {
    int dd, mm, yy;
    final iso = _isoDateRe.firstMatch(body);
    final m = _dateRe.firstMatch(body);
    if (iso != null) {
      yy = int.parse(iso.group(1)!);
      mm = int.parse(iso.group(2)!);
      dd = int.parse(iso.group(3)!);
    } else if (m != null) {
      dd = int.tryParse(m.group(1)!) ?? fallback.day;
      mm = int.tryParse(m.group(2)!) ?? fallback.month;
      yy = int.tryParse(m.group(3)!) ?? fallback.year;
    } else {
      // Try a text-month date like "07Jun26".
      final t = _dateTextRe.firstMatch(body);
      if (t == null) return fallback;
      dd = int.tryParse(t.group(1)!) ?? fallback.day;
      mm = _monthNames[t.group(2)!.toLowerCase()] ?? fallback.month;
      yy = int.tryParse(t.group(3)!) ?? fallback.year;
    }
    if (yy < 100) yy += 2000;
    if (mm < 1 || mm > 12 || dd < 1 || dd > 31) return fallback;
    // Preserve receivedAt hour/min so we still know when it landed.
    final d = DateTime(yy, mm, dd, fallback.hour, fallback.minute);
    // DateTime rolls invalid days over (31 Feb → 3 Mar), and a misread date
    // can land in the future — either way trust when the SMS arrived.
    if (d.month != mm || d.day != dd) return fallback;
    if (d.isAfter(fallback.add(const Duration(days: 1)))) return fallback;
    return d;
  }

  static double _scoreConfidence(_Pick pick, String? merchant, String? acct) {
    var s = 0.35;
    s += pick.verbBound ? 0.25 : 0.1;
    if (pick.amount.hasCurrency) s += 0.1;
    if (acct != null) s += 0.1;
    if (merchant != null) s += 0.15;
    if (pick.balance != null) s += 0.05;
    return s.clamp(0.0, 1.0);
  }
}

/// The SMS text in two aligned forms: [norm] keeps line breaks (merchant
/// names stop at them), [flat] has them as spaces. Same length, same offsets.
class _Doc {
  final String norm;
  final String flat;
  late final List<int> _bounds = _boundaries();

  _Doc._(this.norm) : flat = norm.replaceAll('\n', ' ');

  factory _Doc(String body) => _Doc._(_Hindi.normalize(body)
      .replaceAll('\r', '')
      .replaceAll(RegExp(r'[ \t\u00A0]+'), ' ')
      .replaceAll(RegExp(r' *\n\s*'), '\n')
      .trim());

  /// Clause breaks: line breaks, ; ! ? | and sentence-ending periods (not
  /// decimal points, not "Rs." / "A/c no." style abbreviations).
  List<int> _boundaries() {
    final s = flat;
    final out = <int>[];
    for (var i = 0; i < norm.length; i++) {
      final ch = norm[i];
      if ('\n;!?|'.contains(ch)) {
        out.add(i);
        continue;
      }
      if (ch != '.') continue;
      final prev = i > 0 ? s[i - 1] : '';
      final next = i + 1 < s.length ? s[i + 1] : '';
      if (_isDigit(prev) && _isDigit(next)) continue;
      final after = s.substring(i + 1).trimLeft();
      if (after.isEmpty || !RegExp(r'^[A-Za-z]').hasMatch(after)) continue;
      final word = RegExp(r'([A-Za-z/]+)$')
              .firstMatch(s.substring(0, i))
              ?.group(1)
              ?.toLowerCase() ??
          '';
      if (SmsParser._abbrev.contains(word)) continue;
      out.add(i);
    }
    return out;
  }

  static bool _isDigit(String c) =>
      c.isNotEmpty && c.codeUnitAt(0) >= 48 && c.codeUnitAt(0) <= 57;

  int clauseOf(int pos) {
    var n = 0;
    for (final b in _bounds) {
      if (b < pos) n++;
    }
    return n;
  }

  int clauseStart(int pos) {
    var start = 0;
    for (final b in _bounds) {
      if (b < pos) start = b + 1;
    }
    return start;
  }

  int clauseEnd(int pos) {
    for (final b in _bounds) {
      if (b >= pos) return b;
    }
    return flat.length;
  }
}

/// Hindi (Devanagari) bank alerts — SBI, PNB, BOB and others send them — are
/// mapped onto the English vocabulary the pipeline understands: Devanagari
/// digits, "रु" → Rs, "खाते" → A/c, "डेबिट/नामे" → debited, "जमा" →
/// credited, "उपलब्ध शेष" → Avl Bal, "।" → ".". Words are only replaced
/// whole (not inside a longer word), so "विशेष" never becomes a balance.
class _Hindi {
  static final _devanagari = RegExp(r'[ऀ-ॿ]');

  // Longest phrases first.
  static const _phrases = <(String, String)>[
    ('उपलब्ध शेष राशि', 'Avl Bal'),
    ('उपलब्ध शेष', 'Avl Bal'),
    ('उपलब्ध बैलेंस', 'Avl Bal'),
    ('शेष राशि', 'Avl Bal'),
    ('कुल बकाया', 'total amount due'),
    ('न्यूनतम देय', 'minimum amount due'),
    ('देय तिथि', 'due date'),
    ('खाता संख्या', 'A/c'),
    ('डेबिट किया गया', 'debited'),
    ('डेबिट किए गए', 'debited'),
    ('डेबिट की गई', 'debited'),
    ('क्रेडिट किया गया', 'credited'),
    ('क्रेडिट किए गए', 'credited'),
    ('क्रेडिट की गई', 'credited'),
    ('जमा किया गया', 'credited'),
    ('जमा किए गए', 'credited'),
    ('जमा की गई', 'credited'),
    ('निकाले गए', 'withdrawn'),
    ('भुगतान किया', 'paid'),
    ('संदर्भ संख्या', 'Ref'),
    ('रुपये', 'Rs'),
    ('रुपए', 'Rs'),
    ('रु', 'Rs'),
    ('रू', 'Rs'),
    ('शेष', 'Avl Bal'),
    ('बैलेंस', 'Avl Bal'),
    ('खाते', 'A/c'),
    ('खाता', 'A/c'),
    ('ए/सी', 'A/c'),
    ('कार्ड', 'card'),
    ('डेबिट', 'debited'),
    ('नामे', 'debited'),
    ('निकासी', 'withdrawn'),
    ('क्रेडिट', 'credited'),
    ('जमा', 'credited'),
    ('भुगतान', 'paid'),
    ('प्राप्त', 'received'),
    ('ओटीपी', 'OTP'),
    ('दिनांक', 'on'),
    ('संदर्भ', 'Ref'),
    ('असफल', 'failed'),
    ('विफल', 'failed'),
    ('वेतन', 'salary'),
    ('ऑफर', 'offer'),
    ('बधाई', 'congratulations'),
    ('से', 'from'),
  ];

  static final _res = [
    for (final (hi, en) in _phrases)
      (
        RegExp('(?<![\\u0900-\\u097F])${RegExp.escape(hi)}(?![\\u0900-\\u097F])'),
        ' $en ',
      )
  ];

  static String normalize(String body) {
    if (!_devanagari.hasMatch(body)) return body;
    var s = body.replaceAllMapped(RegExp('[०-९]'),
        (m) => String.fromCharCode(m.group(0)!.codeUnitAt(0) - 0x0966 + 48));
    s = s.replaceAll('।', '. ');
    for (final (re, en) in _res) {
      s = s.replaceAll(re, en);
    }
    return s;
  }
}

/// A credit-card statement / payment-due alert: what's owed and by when.
class CardStatement {
  final String bank; // sender core, e.g. HDFCBK
  final String? last4;
  final double total;
  final double? minimum;
  final DateTime dueDate;
  final DateTime receivedAt;
  const CardStatement({
    required this.bank,
    required this.last4,
    required this.total,
    required this.minimum,
    required this.dueDate,
    required this.receivedAt,
  });

  /// Identifies the card across statements.
  String get key => '$bank|${last4 ?? '?'}';
}

enum _Role { txn, balance, fee }

class _Amount {
  final double value;
  final int start, end;
  final bool hasCurrency, hasDecimal;
  _Role role = _Role.txn;
  bool labelled = false;
  _Amount(this.value, this.start, this.end, this.hasCurrency, this.hasDecimal);
}

class _Verb {
  final int start, end;
  final bool debit;
  int distance = 0;
  _Verb(this.start, this.end, this.debit);
}

class _Pick {
  final _Amount amount;
  final TxnDirection direction;
  final bool verbBound;
  final double? balance;
  const _Pick({
    required this.amount,
    required this.direction,
    required this.verbBound,
    required this.balance,
  });
}

class ParsedSms {
  final Transaction txn;
  final double confidence;

  /// Account balance printed in the alert ("Avl Bal", "Total Bal"…), if any.
  final double? balance;
  const ParsedSms({required this.txn, required this.confidence, this.balance});

  ParsedSms withTxn(Transaction t) =>
      ParsedSms(txn: t, confidence: confidence, balance: balance);
}
