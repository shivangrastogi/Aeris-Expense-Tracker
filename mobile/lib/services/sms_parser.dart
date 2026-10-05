import 'package:uuid/uuid.dart';

import '../models/category.dart';
import '../models/transaction.dart';
import 'merchant_directory.dart';

/// Parse Indian bank / UPI SMS into a [Transaction].
///
/// We assume Hinglish + English alerts from the dominant senders:
/// SBI, HDFC, ICICI, AXIS, KOTAK, IDFC, INDUSIND, YES, IDBI, PNB, BOB,
/// Paytm, PhonePe, Google Pay, Amazon Pay, Cred, Slice, Niyo.
///
/// The parser is intentionally regex-based and conservative — it returns
/// `null` when it can't extract amount + direction with high confidence,
/// so the inbox screen can flag the SMS for manual review instead of
/// creating wrong transactions.
class SmsParser {
  SmsParser._();

  static const _uuid = Uuid();

  /// Senders we trust for transactional parsing. Most Indian DLT-registered
  /// bank senders look like `VM-SBIBNK`, `JD-HDFCBK`, `AX-ICICIB`, etc.
  /// The 2-letter prefix changes by operator, so we only match the suffix.
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
    RegExp(r'(BOBSMS|BOBTXN)', caseSensitive: false),
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
  ];

  /// Amount patterns — covers all the variants we've seen in real inboxes.
  ///   Rs.500.00     Rs 500     INR 1,234.50     ₹500
  // Match a full number after the currency token: a leading digit then any
  // mix of digits/commas, with optional 1-2 decimal places. Commas are
  // stripped before parsing, so this handles plain "1200", Indian "1,50,000",
  // western "1,250,000", and "1200.00" alike. (The earlier `[0-9]{1,3}`
  // form mis-read comma-free "1200.00" as just "120".)
  static final _amountRe = RegExp(
    r'(?:rs\.?|inr|₹)\s*([0-9][0-9,]*(?:\.[0-9]{1,2})?)',
    caseSensitive: false,
  );

  /// Fallback when no currency token is present — many SBI/UPI alerts say
  /// "debited by 101.00" or "credited by 500" with no Rs/₹. Anchored to a
  /// transaction verb so it doesn't grab a reference/account number.
  static final _amountAltRe = RegExp(
    r'(?:debited|credited|debit|credit|paid|sent|withdrawn|received|deducted|spent)\s+'
    r'(?:by|for|of|with)?\s*(?:rs\.?|inr|₹)?\s*([0-9][0-9,]*(?:\.[0-9]{1,2})?)',
    caseSensitive: false,
  );

  /// Direction signals (case-insensitive substring scan).
  // NOTE: bare 'debit'/'credit' are intentionally excluded — they match
  // "Debit Card"/"Credit Card" in non-transaction notices. We require the
  // verb forms ('debited'/'credited') etc.
  static const _debitWords = <String>[
    'debited',
    'spent',
    'paid',
    'withdrawn',
    'purchase',
    'sent',
    'transferred to',
    'txn of',
    'has been used',
    'charged',
    'deducted',
    'dr ',
    ' dr.',
    'pos txn',
  ];
  static const _creditWords = <String>[
    'credited',
    'received',
    'deposited',
    'refund',
    'reversed',
    'cr ',
    ' cr.',
    'salary credited',
    'income',
  ];

  /// Account fragment — "A/c XX1234", "A/c ending 1234", "card xx1234".
  static final _acctRe = RegExp(
    r'(?:a\/?c|account|card)\s*(?:no\.?|number|ending|xx+|x+|\*+)?\s*([0-9]{3,6})',
    caseSensitive: false,
  );

  /// Merchant fragments — many alerts say "at AMAZON" or "to VPA xyz@oksbi".
  static final _atMerchantRe = RegExp(
    r'(?:at|@)\s+([A-Z][A-Z0-9 &\-_\.\*]{2,40})',
  );
  static final _toVpaRe = RegExp(
    r'(?:to\s+(?:vpa\s+)?|trf to\s+|sent to\s+)([A-Za-z0-9 .@_\-]{3,40})',
    caseSensitive: false,
  );
  static final _fromVpaRe = RegExp(
    r'(?:from\s+(?:vpa\s+)?|recvd from\s+|received from\s+)([A-Za-z0-9 .@_\-]{3,40})',
    caseSensitive: false,
  );

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

  /// SMS time hints — most alerts include date "30-05-26" or "30/05/2026".
  static final _dateRe = RegExp(
    r'\b([0-3]?[0-9])[-\/]([0-1]?[0-9])[-\/](20[0-9]{2}|[0-9]{2})\b',
  );

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

  /// Spam / promotional / phishing markers — short-circuit reject.
  static final _promoMarkers = <RegExp>[
    RegExp(r'\b(otp|verification code|one time password)\b',
        caseSensitive: false),
    RegExp(r'\b(offer|cashback|reward|discount|loan offer)\b',
        caseSensitive: false),
    RegExp(r'\b(view statement|due date|minimum amount due)\b',
        caseSensitive: false),
    // Lottery / prize / phishing scams that mimic bank wording.
    RegExp(
      r'\b(won|winner|win|prize|lottery|congratulation|congrats|claim|'
      r'voucher|gift|free recharge|free|kyc|click|verify now|act now|'
      r'urgent|blocked|suspended)\b',
      caseSensitive: false,
    ),
    // Card-control / informational notices (limit changes, enable/disable
    // card features, e-mandate setup) — NOT actual spends. Kept specific so
    // genuine debit alerts (which often include "Avl Bal") are not caught.
    RegExp(
      r'(limit\s*/?\s*usage|usage permission|permission for (?:debit|credit)|'
      r'processed successfully|daily tran|contactless\s*:|pos\s*/\s*ecom|'
      r'request via|e-?mandate|standing instruction)',
      caseSensitive: false,
    ),
    // Pre-debit / autopay / mandate REMINDERS — the money hasn't moved yet.
    // These say the account *will be* debited on a future date (e.g. "For the
    // upcoming mandate set for 16-06-26, your account will be debited with
    // Rs.1000..."). Creating a spend here double-counts against the real debit
    // alert that arrives when the mandate actually executes, so we reject them.
    RegExp(
      r'(upcoming mandate|mandate\s+(?:set|registered|created|is paused)|'
      r'will\s+be\s+debited|account\s+will\s+be|scheduled\s+(?:for|debit)|'
      r'auto\s*-?pay|auto\s*-?debit|e-?nach\b)',
      caseSensitive: false,
    ),
  ];

  /// Failed / declined payments — no money actually moved, so they must not
  /// become an expense. ("Amount if debited will be reversed" also lands
  /// here.) Real reversals arrive as their own "credited/reversed" alert.
  static final _failedRe = RegExp(
    r'\b(failed|declined|unsuccessful|not successful|could not be '
    r'(?:processed|completed)|insufficient (?:funds|balance)|'
    r'if debited)\b',
    caseSensitive: false,
  );

  /// Card-spend alerts name the merchant after "on": "INR 1,299 spent using
  /// ICICI Bank Card XX4321 on 02-Oct-26 on AMAZON." Only ALL-CAPS words are
  /// taken, so dates ("on 02-Oct-26") and prose ("on your card") are skipped.
  static final _onMerchantRe = RegExp(
    r'\bon\s+([A-Z][A-Z0-9&_*\-]*\b(?:\s[A-Z0-9&_*\-]+\b)*)',
  );

  /// First words after "on" that are a channel or bank, not a merchant.
  static const _notMerchant = {
    'upi', 'imps', 'neft', 'rtgs', 'pos', 'atm', 'ecom', 'card', 'netbanking',
    'sbi', 'hdfc', 'icici', 'axis', 'kotak', 'idfc', 'indusind', 'yes', 'idbi',
    'pnb', 'bob', 'paytm', 'phonepe', 'gpay', 'bhim', 'your', 'a/c',
  };

  /// Any URL in the body — legit bank txn alerts almost never contain links,
  /// but phishing/promo SMS do. Used to reject links from untrusted senders.
  static final _urlRe = RegExp(
    r'(https?:\/\/|www\.|bit\.ly|tinyurl|\b[a-z0-9-]+\.(?:com|in|co|net|link|xyz)\b)',
    caseSensitive: false,
  );

  /// Public API.
  static ParsedSms? parse({
    required String sender,
    required String body,
    required DateTime receivedAt,
  }) {
    final clean = body.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (clean.isEmpty) return null;
    final trusted = isTrustedSender(sender);
    if (!trusted && !looksLikeBankBody(clean)) {
      return null;
    }
    if (_promoMarkers.any((r) => r.hasMatch(clean))) return null;
    // Links from an untrusted sender → almost always phishing/promo, never a
    // genuine bank debit/credit alert.
    if (!trusted && _urlRe.hasMatch(clean)) return null;

    final amountMatch =
        _amountRe.firstMatch(clean) ?? _amountAltRe.firstMatch(clean);
    if (amountMatch == null) return null;
    final amount = double.tryParse(amountMatch.group(1)!.replaceAll(',', ''));
    if (amount == null || amount <= 0) return null;

    final direction = _directionFrom(clean);
    if (direction == null) return null;
    if (direction == TxnDirection.debit && _failedRe.hasMatch(clean)) {
      return null;
    }
    // Scammers fake "credited" messages ("You won Rs 50000, claim now") to
    // look like income. Only trust a credit if it comes from a known
    // bank / UPI sender — debits from bank-like bodies are still allowed.
    if (direction == TxnDirection.credit && !trusted) return null;

    final acct = _acctRe.firstMatch(clean)?.group(1);
    final vpa = _vpaRe.firstMatch(clean)?.group(1)?.toLowerCase();
    final reference = _refRe.firstMatch(clean)?.group(1);
    var merchant = _extractMerchant(clean, direction);

    // Enrich on-device: a known payee gets a friendly name + category; an
    // unknown one gets a cleaned-up name from its VPA prefix where readable.
    final dirHit =
        MerchantDirectory.lookup(merchant) ?? MerchantDirectory.lookup(vpa);
    merchant = MerchantDirectory.prettyName(vpa, merchant) ?? merchant;
    final categoryId = (dirHit != null && direction == TxnDirection.debit)
        ? dirHit.categoryId
        : _categoryFor(direction, '${merchant ?? ''} ${vpa ?? clean}');
    final ts = _extractDate(clean, fallback: receivedAt);

    return ParsedSms(
      txn: Transaction(
        id: _uuid.v4(),
        amount: amount,
        direction: direction,
        timestamp: ts,
        merchant: merchant,
        account: acct,
        categoryId: categoryId,
        source: TxnSource.sms,
        smsBody: body,
        smsSender: sender,
        reviewed: false,
        reference: reference,
        upiVpa: vpa,
      ),
      confidence: _scoreConfidence(clean, merchant, acct),
    );
  }

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

  static TxnDirection? _directionFrom(String body) {
    final b = body.toLowerCase();
    final hasDebit = _debitWords.any(b.contains);
    final hasCredit = _creditWords.any(b.contains);
    if (hasDebit && !hasCredit) return TxnDirection.debit;
    if (hasCredit && !hasDebit) return TxnDirection.credit;
    if (hasDebit && hasCredit) {
      // Both seen — favour the first one in the text.
      final dIdx = _firstIndex(b, _debitWords);
      final cIdx = _firstIndex(b, _creditWords);
      return dIdx < cIdx ? TxnDirection.debit : TxnDirection.credit;
    }
    return null;
  }

  static int _firstIndex(String hay, List<String> needles) {
    var lowest = hay.length;
    for (final n in needles) {
      final i = hay.indexOf(n);
      if (i != -1 && i < lowest) lowest = i;
    }
    return lowest;
  }

  static String? _extractMerchant(String body, TxnDirection dir) {
    if (dir == TxnDirection.credit) {
      final m = _fromVpaRe.firstMatch(body);
      if (m != null) return _trimMerchant(m.group(1)!);
    }
    final at = _atMerchantRe.firstMatch(body);
    if (at != null) return _trimMerchant(at.group(1)!);
    final to = _toVpaRe.firstMatch(body);
    if (to != null) return _trimMerchant(to.group(1)!);
    if (dir == TxnDirection.debit) {
      for (final m in _onMerchantRe.allMatches(body)) {
        final name = _trimMerchant(m.group(1)!);
        final first = name.split(' ').first.toLowerCase();
        if (name.length >= 3 && !_notMerchant.contains(first)) return name;
      }
    }
    return null;
  }

  static String _trimMerchant(String raw) {
    var m = raw.trim();
    // Cut at common trailing tokens.
    for (final cut in [' on ', ' Refno', ' Ref ', ' Avl ', ' UPI ', '.', ',']) {
      final idx = m.indexOf(cut);
      if (idx > 4) m = m.substring(0, idx);
    }
    return m.trim();
  }

  static String _categoryFor(TxnDirection dir, String hint) {
    if (dir == TxnDirection.credit) {
      final low = hint.toLowerCase();
      if (low.contains('salary') || low.contains('payroll')) return 'salary';
      if (low.contains('refund') || low.contains('reversed')) return 'refund';
      return 'transfer';
    }
    return Categories.classify(hint);
  }

  static DateTime _extractDate(String body, {required DateTime fallback}) {
    int dd, mm, yy;
    final m = _dateRe.firstMatch(body);
    if (m != null) {
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
    try {
      // Preserve receivedAt hour/min so we still know when it landed.
      return DateTime(yy, mm, dd, fallback.hour, fallback.minute);
    } catch (_) {
      return fallback;
    }
  }

  static double _scoreConfidence(String body, String? merchant, String? acct) {
    double s = 0.5;
    if (acct != null) s += 0.2;
    if (merchant != null) s += 0.2;
    if (RegExp(r'avl\s*bal', caseSensitive: false).hasMatch(body)) s += 0.1;
    return s.clamp(0.0, 1.0);
  }
}

class ParsedSms {
  final Transaction txn;
  final double confidence;
  const ParsedSms({required this.txn, required this.confidence});
}
