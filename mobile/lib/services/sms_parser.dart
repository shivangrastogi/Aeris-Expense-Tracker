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
    RegExp(r'(MOBIKWIK|FREECHARGE|OLAMONEY|JIOPAY|LAZYPAY)', caseSensitive: false),
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

  /// Direction signals (case-insensitive substring scan).
  // NOTE: bare 'debit'/'credit' are intentionally excluded — they match
  // "Debit Card"/"Credit Card" in non-transaction notices. We require the
  // verb forms ('debited'/'credited') etc.
  static const _debitWords = <String>[
    'debited', 'spent', 'paid', 'withdrawn', 'purchase', 'sent',
    'transferred to', 'txn of', 'has been used', 'charged', 'deducted',
    'dr ', ' dr.', 'pos txn',
  ];
  static const _creditWords = <String>[
    'credited', 'received', 'deposited', 'refund', 'reversed',
    'cr ', ' cr.', 'salary credited', 'income',
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
    r'(?:upi(?:\s*ref(?:\s*no)?)?|ref(?:erence)?\s*(?:no\.?|number|id)?|rrn|utr|txn\s*(?:id|ref))[:\s#\-]*([0-9]{6,18})',
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

  /// Spam / promotional / phishing markers — short-circuit reject.
  static final _promoMarkers = <RegExp>[
    RegExp(r'\b(otp|verification code|one time password)\b', caseSensitive: false),
    RegExp(r'\b(offer|cashback|reward|discount|loan offer)\b', caseSensitive: false),
    RegExp(r'\b(view statement|due date|minimum amount due)\b', caseSensitive: false),
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
  ];

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

    final amountMatch = _amountRe.firstMatch(clean);
    if (amountMatch == null) return null;
    final amount = double.tryParse(
        amountMatch.group(1)!.replaceAll(',', ''));
    if (amount == null || amount <= 0) return null;

    final direction = _directionFrom(clean);
    if (direction == null) return null;
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
    final dirHit = MerchantDirectory.lookup(merchant) ??
        MerchantDirectory.lookup(vpa);
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
        b.contains('wallet') ||              // Amazon Pay / Mobikwik etc.
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
      if (low.contains('refund') || low.contains('reversed')) return 'shopping';
      return 'transfer';
    }
    return Categories.classify(hint);
  }

  static DateTime _extractDate(String body, {required DateTime fallback}) {
    final m = _dateRe.firstMatch(body);
    if (m == null) return fallback;
    final dd = int.tryParse(m.group(1)!) ?? fallback.day;
    final mm = int.tryParse(m.group(2)!) ?? fallback.month;
    var yy = int.tryParse(m.group(3)!) ?? fallback.year;
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
