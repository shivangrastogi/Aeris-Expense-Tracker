import '../models/transaction.dart';
import 'merchant_directory.dart';
import 'payment_shot_parser.dart';
import 'receipt_parser.dart';

/// The language half of scanning a photo: payment screens, shop bills and
/// plain pen-and-paper notes ("Name: Ravi / Amt: 500 / UPI: ravi@ybl").
///
/// The pixels are read by ML Kit's on-device recogniser (a CNN that finds
/// the text, then reads it) in receipt_scanner.dart. This turns its lines into
/// a transaction in five steps:
///
///  1. **Normalise** — OCR and handwriting slips: "5OO" → 500, "Rs 500/-",
///     "ravi © ybl" → ravi@ybl.
///  2. **Labels** — "Name", "First name" + "Last name", "Amt", "Paid to",
///     "UPI ID", "Date"… matched fuzzily, so a misread "Nmae" or "Amout"
///     still counts. A value can sit after the label or on the next line.
///  3. **Typing** — each value is checked against what its label promises: a
///     number under "Paid" is an amount, a name under it is who was paid.
///  4. **Entities** in the unlabelled rest: ₹ amounts, UPI IDs, dates,
///     "paid 500 to Ravi", "Ravi ko 500 diye", "mila / received".
///  5. **Fusion** with the payment-screen and bill parsers; the strongest
///     evidence wins each field, and what's still missing is reported.
///
/// Pure string work, unit-tested in test/scan_reader_test.dart.
class ScanReader {
  ScanReader._();

  /// [rows] is the OCR text rebuilt into visual rows (cells joined by tabs,
  /// see [PaymentShotParser.layout]); [plain] the recogniser's own order.
  static ScanResult read({required String rows, String? plain, DateTime? now}) {
    now ??= DateTime.now();
    final lines = _lines(rows);
    if (lines.isEmpty) return const ScanResult(kind: ScanKind.note);
    final flat = lines.join('\n').toLowerCase();

    final labelled = _Facts();
    final free = _Facts();
    _entities(_labelled(lines, labelled, now), free, now);

    // A real payment-app screen: its dedicated parser knows the layouts.
    final pay = _screenSignals.any(flat.contains)
        ? PaymentShotParser.parse(rows, now: now)
        : null;
    if (pay != null) {
      return _fuse(ScanKind.payment, now, [
        _Facts()
          // A note that merely mentions "UTR": its own "Amount:" beats a
          // number the screen parser had to guess at.
          ..amount =
              pay.amountUncertain && labelled.amount != null ? null : pay.amount
          ..amountUnsure = pay.amountUncertain
          ..direction = pay.directionGuessed ? null : pay.direction
          ..name = pay.name
          ..upi = pay.upiVpa
          ..when = pay.when
          ..reference = pay.reference
          ..account = pay.account,
        labelled,
        free,
      ]);
    }

    // A shop bill: its total beats item prices ("Price: 120"), but a name
    // written on it beats the guess from the header.
    final bill = _billWords.any(flat.contains)
        ? ReceiptParser.parse(plain ?? lines.join('\n'))
        : null;
    if (bill?.total != null) {
      return _fuse(ScanKind.bill, now, [
        _Facts()..amount = bill!.total,
        labelled,
        _Facts()
          ..name = bill.merchant
          ..when = bill.date
          ..direction = TxnDirection.debit, // a bill is money you paid
        free,
      ]);
    }
    return _fuse(ScanKind.note, now, [labelled, free]);
  }

  /// Like [read], but a page listing several people with an amount each
  /// ("Ravi 500 / Neha 300 / Amit 1,200") gives one result per line. A
  /// heading such as "Udhaar diya" or a date applies to every line. Null when
  /// it isn't such a list.
  static List<ScanResult>? readList({required String rows, DateTime? now}) {
    now ??= DateTime.now();
    final lines = _lines(rows);
    final flat = lines.join('\n').toLowerCase();
    if (_screenSignals.any(flat.contains) || _billWords.any(flat.contains)) {
      return null; // a bill's item lines are one purchase, not a list
    }
    final entries = <({String name, double amount})>[];
    final other = <String>[];
    for (final l in lines) {
      final n = _nameIn(l);
      final a = n.name == null || _isLabel(l)
          ? null
          : _amountIn(n.rest!, labelled: true);
      if (a != null && _withoutMoney(n.rest!).isEmpty) {
        entries.add((name: n.name!, amount: a.value));
      } else {
        other.add(l);
      }
    }
    if (entries.length < 2 || other.length > 3) return null;
    final heading = other.join('\n').toLowerCase();
    final dir = _directionIn(heading);
    final when = _dateIn(heading, now);
    return [
      for (final e in entries)
        ScanResult(
          kind: ScanKind.note,
          amount: e.amount,
          name: e.name,
          direction: dir,
          when: when,
          fromList: true,
        ),
    ];
  }

  static List<String> _lines(String rows) => [
        for (final l
            in rows.replaceAll(' ', ' ').split(RegExp(r'[\r\n]+')))
          _normalise(l),
      ]..removeWhere((l) => l.isEmpty);

  /// A category id for words a note uses that the category keywords (all
  /// English brand / bill words) don't: "khana", "सब्जी", "dawai", "kiraya".
  static String? categoryHint(String text) {
    final t = _normalise(text).toLowerCase();
    for (final e in _hints.entries) {
      for (final raw in e.value) {
        final w = raw.replaceAll('़', ''); // as _normalise spells it
        final latin = RegExp(r'^[a-z ]+$').hasMatch(w);
        final re = latin
            ? RegExp('\\b$w\\b')
            : RegExp('(?<![ऀ-ॿ])$w$_hiEnd');
        if (re.hasMatch(t)) return e.key;
      }
    }
    return null;
  }

  static const _hints = {
    'food': [
      'khana', 'khaana', 'nashta', 'chai', 'nasta', 'dinner', 'lunch',
      'breakfast', 'खाना', 'खाने', 'भोजन', 'नाश्ता', 'चाय',
    ],
    'groceries': [
      'sabzi', 'sabji', 'rashan', 'ration', 'kirana', 'doodh', 'dudh',
      'सब्जी', 'राशन', 'किराना', 'दूध',
    ],
    'travel': [
      'auto', 'rickshaw', 'bus', 'train', 'cab', 'diesel', 'bhada',
      'पेट्रोल', 'डीजल', 'ऑटो', 'रिक्शा', 'भाड़ा',
    ],
    'rent': ['kiraya', 'kiraaya', 'rent', 'किराया'],
    'health': [
      'dawai', 'dawa', 'davai', 'medicine', 'doctor', 'dava', 'दवा', 'दवाई',
      'डॉक्टर', 'अस्पताल',
    ],
    'bills': [
      'bijli', 'light bill', 'paani', 'pani', 'gas', 'recharge', 'बिजली',
      'पानी', 'गैस', 'रिचार्ज',
    ],
    'education': ['fees', 'fee', 'tuition', 'school', 'फीस', 'स्कूल', 'ट्यूशन'],
    'shopping': ['kapde', 'kapda', 'joote', 'कपड़े', 'कपडे', 'जूते'],
    'salary': ['salary', 'tankhwah', 'pagar', 'तनख्वाह', 'वेतन', 'पगार'],
  };

  // ── 1. Normalise ──────────────────────────────────────────────────────────

  static const _hindiMonths = {
    'जनवरी': 'jan', 'फ़रवरी': 'feb', 'फरवरी': 'feb', 'मार्च': 'mar',
    'अप्रैल': 'apr', 'मई': 'may', 'जून': 'jun', 'जुलाई': 'jul',
    'अगस्त': 'aug', 'सितंबर': 'sep', 'सितम्बर': 'sep', 'अक्टूबर': 'oct',
    'अक्तूबर': 'oct', 'नवंबर': 'nov', 'नवम्बर': 'nov', 'दिसंबर': 'dec',
    'दिसम्बर': 'dec',
  };

  static String _normalise(String line) {
    // Hindi: ०-९ digits, the danda, nukta spellings, "रु / रुपये", "हज़ार",
    // month names — so everything below sees one form.
    var s = line
        .replaceAllMapped(RegExp('[०-९]'),
            (m) => '${m.group(0)!.codeUnitAt(0) - 0x0966}')
        .replaceAll(RegExp('[।॥]'), ' ')
        .replaceAll('़', '') // nukta: "फ़ोन" = "फोन"
        .replaceAll('ँ', 'ं') // chandrabindu as anusvara
        .replaceAll(RegExp('(?:रुपये|रुपए|रूपये|रुपया|रु|रू)\\.?(?![ऀ-ॿ])'),
            ' rs ')
        .replaceAllMapped(RegExp(r'(\d)\s*(?:हजार|hazaa?r)', caseSensitive: false),
            (m) => '${m.group(1)}k');
    for (final e in _hindiMonths.entries) {
      s = s.replaceAll(e.key.replaceAll('़', ''), e.value);
    }
    return _normaliseLatin(s);
  }

  static String _normaliseLatin(String line) => line
      .replaceAll(RegExp(r'[–—−]'), '-')
      .replaceAll(RegExp(r'[‘’`]'), "'")
      // "Rs.500", "Rs:500", "₹-500": the mark, a space, the number.
      .replaceAllMapped(
          RegExp(r'(₹|\brs|\binr)\s*[.:\-=]?\s*(?=\d)', caseSensitive: false),
          (m) => '${m.group(1)} ')
      // Handwritten "500/-" means "500 rupees".
      .replaceAllMapped(RegExp(r'(\d)\s*/\s*-+'), (m) => '${m.group(1)} rs')
      .replaceAll(RegExp(r' {2,}'), ' ')
      .trim();

  /// Letters handwriting OCR puts where digits were.
  static const _digitFix = {
    'o': '0', 'O': '0', 'D': '0', 'Q': '0', 'I': '1', 'l': '1', '|': '1',
    'i': '1', 'S': '5', 's': '5', 'B': '8', 'Z': '2', 'z': '2', 'G': '6',
    'g': '9', 'q': '9',
  };

  /// [token] with misread digits repaired, if it starts with or is mostly
  /// digits ("5OO", "1,2S0"); null if it isn't a number.
  static String? _repairNumber(String token) {
    final digits = RegExp(r'\d').allMatches(token).length;
    final len = token.replaceAll(RegExp(r'[,.]'), '').length;
    if (digits == 0 ||
        (digits * 2 < len && !RegExp(r'^\d').hasMatch(token))) {
      return null;
    }
    final out = token.split('').map((c) => _digitFix[c] ?? c).join();
    return RegExp(r'^\d[\d,]*(\.\d{1,2})?$').hasMatch(out) ? out : null;
  }

  // ── 2–3. Labels ───────────────────────────────────────────────────────────

  static const _lexicon = <String, (_K, TxnDirection?)>{
    'name': (_K.name, null), 'full name': (_K.name, null),
    'naam': (_K.name, null), 'person': (_K.name, null),
    'party': (_K.name, null), 'party name': (_K.name, null),
    'merchant': (_K.name, null), 'shop': (_K.name, null),
    'store': (_K.name, null), 'vendor': (_K.name, null),
    'dukaan': (_K.name, null), 'account name': (_K.name, null),
    'first name': (_K.first, null), 'fname': (_K.first, null),
    'given name': (_K.first, null),
    'middle name': (_K.middle, null),
    'last name': (_K.last, null), 'surname': (_K.last, null),
    'lname': (_K.last, null), 'family name': (_K.last, null),
    'to': (_K.name, TxnDirection.debit),
    'paid to': (_K.name, TxnDirection.debit),
    'pay to': (_K.name, TxnDirection.debit),
    'sent to': (_K.name, TxnDirection.debit),
    'given to': (_K.name, TxnDirection.debit),
    'payee': (_K.name, TxnDirection.debit),
    'beneficiary': (_K.name, TxnDirection.debit),
    'receiver': (_K.name, TxnDirection.debit),
    'from': (_K.name, TxnDirection.credit),
    'received from': (_K.name, TxnDirection.credit),
    'got from': (_K.name, TxnDirection.credit),
    'payer': (_K.name, TxnDirection.credit),
    'sender': (_K.name, TxnDirection.credit),
    'amount': (_K.amount, null), 'amt': (_K.amount, null),
    'rs': (_K.amount, null), 'inr': (_K.amount, null),
    'rupees': (_K.amount, null), 'rupaye': (_K.amount, null),
    'price': (_K.amount, null), 'cost': (_K.amount, null),
    'value': (_K.amount, null), 'rakam': (_K.amount, null),
    'total': (_K.total, null), 'total amount': (_K.total, null),
    'grand total': (_K.total, null), 'net amount': (_K.total, null),
    'paid': (_K.amount, TxnDirection.debit),
    'spent': (_K.amount, TxnDirection.debit),
    'debit': (_K.amount, TxnDirection.debit),
    'debited': (_K.amount, TxnDirection.debit),
    'received': (_K.amount, TxnDirection.credit),
    'credit': (_K.amount, TxnDirection.credit),
    'credited': (_K.amount, TxnDirection.credit),
    'upi': (_K.upi, null), 'upi id': (_K.upi, null),
    'vpa': (_K.upi, null), 'upi handle': (_K.upi, null),
    'upi address': (_K.upi, null),
    'date': (_K.date, null), 'dt': (_K.date, null), 'dated': (_K.date, null),
    'day': (_K.date, null), 'on': (_K.date, null), 'tarikh': (_K.date, null),
    'time': (_K.time, null),
    'ref': (_K.ref, null), 'ref no': (_K.ref, null),
    'reference': (_K.ref, null), 'reference no': (_K.ref, null),
    'utr': (_K.ref, null), 'utr no': (_K.ref, null), 'rrn': (_K.ref, null),
    'txn id': (_K.ref, null), 'transaction id': (_K.ref, null),
    'upi ref': (_K.ref, null), 'upi ref no': (_K.ref, null),
    'a/c': (_K.account, null), 'ac': (_K.account, null),
    'acct': (_K.account, null), 'account': (_K.account, null),
    'account no': (_K.account, null), 'bank': (_K.account, null),
    'debited from': (_K.account, TxnDirection.debit),
    'credited to': (_K.account, TxnDirection.credit),
    'phone': (_K.phone, null), 'phone no': (_K.phone, null),
    'mobile': (_K.phone, null), 'mobile no': (_K.phone, null),
    'mob': (_K.phone, null), 'ph': (_K.phone, null),
    'contact': (_K.phone, null), 'cell': (_K.phone, null),
    'note': (_K.note, null), 'notes': (_K.note, null),
    'remark': (_K.note, null), 'remarks': (_K.note, null),
    'for': (_K.note, null), 'purpose': (_K.note, null),
    'reason': (_K.note, null), 'item': (_K.note, null),
    'items': (_K.note, null), 'description': (_K.note, null),
    'desc': (_K.note, null), 'details': (_K.note, null),
    'memo': (_K.note, null), 'comment': (_K.note, null),
    'kis liye': (_K.note, null),
    'category': (_K.category, null), 'cat': (_K.category, null),
    'expense type': (_K.category, null),
    'type': (_K.type, null), 'txn type': (_K.type, null),
    'transaction type': (_K.type, null), 'mode': (_K.type, null),
    'dr/cr': (_K.type, null), 'kind': (_K.type, null),
    // Hindi labels (written without nukta — see _normalise).
    'नाम': (_K.name, null), 'पूरा नाम': (_K.name, null),
    'दुकान': (_K.name, null), 'व्यक्ति': (_K.name, null),
    'पहला नाम': (_K.first, null), 'अंतिम नाम': (_K.last, null),
    'उपनाम': (_K.last, null), 'सरनेम': (_K.last, null),
    'प्राप्तकर्ता': (_K.name, TxnDirection.debit),
    'किसको': (_K.name, TxnDirection.debit),
    'भेजने वाला': (_K.name, TxnDirection.credit),
    'किससे': (_K.name, TxnDirection.credit),
    'राशि': (_K.amount, null), 'रकम': (_K.amount, null),
    'मूल्य': (_K.amount, null), 'कीमत': (_K.amount, null),
    'कुल': (_K.total, null), 'कुल राशि': (_K.total, null),
    'दिया': (_K.amount, TxnDirection.debit),
    'दिए': (_K.amount, TxnDirection.debit),
    'भेजा': (_K.amount, TxnDirection.debit),
    'भुगतान': (_K.amount, TxnDirection.debit),
    'खर्च': (_K.amount, TxnDirection.debit),
    'मिला': (_K.amount, TxnDirection.credit),
    'मिले': (_K.amount, TxnDirection.credit),
    'प्राप्त': (_K.amount, TxnDirection.credit),
    'यूपीआई': (_K.upi, null), 'यूपीआई आईडी': (_K.upi, null),
    'तारीख': (_K.date, null), 'तिथि': (_K.date, null),
    'दिनांक': (_K.date, null), 'समय': (_K.time, null),
    'संदर्भ': (_K.ref, null), 'खाता': (_K.account, null),
    'मोबाइल': (_K.phone, null), 'फोन': (_K.phone, null),
    'नोट': (_K.note, null), 'विवरण': (_K.note, null),
    'टिप्पणी': (_K.note, null), 'उद्देश्य': (_K.note, null),
    'किसलिए': (_K.note, null), 'श्रेणी': (_K.category, null),
    'प्रकार': (_K.type, null),
  };

  // "Name: Ravi", "Amt = 500", "UPI - ravi@ybl", "Name\tRavi" (a table row).
  static final _kvRe = RegExp(
      "^([A-Za-zऀ-ॿ][A-Za-zऀ-ॿ /.']{0,24}?)\\s*[:=|>\\t\\-]+\\s*(.*)\$");

  /// The lexicon entry [raw] names, allowing [fuzzy] OCR slips.
  static (_K, TxnDirection?)? _key(String raw, {bool fuzzy = true}) {
    final k = raw
        .toLowerCase()
        .replaceAll(RegExp('[^a-z/ ऀ-ॣ॰-ॿ]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (k.isEmpty) return null;
    final hit = _lexicon[k] ?? _lexicon[k.replaceAll(' ', '')];
    if (hit != null || !fuzzy || k.length < 4) return hit;
    // "Nmae", "Amout", "Frist name": one slip, two in long labels. A short
    // word must also keep its first letter, so "Rice" never reads as "Price".
    (_K, TxnDirection?)? best;
    var bestD = 99;
    for (final e in _lexicon.entries) {
      if (e.key.length < 4) continue;
      if (k.length < 6 && k[0] != e.key[0]) continue;
      final d = _distance(k, e.key);
      if (d <= (e.key.length >= 8 ? 2 : 1) && d < bestD) {
        best = e.value;
        bestD = d;
      }
    }
    return best;
  }

  /// Fills [out] from labelled lines; returns the text left for step 4.
  static List<String> _labelled(List<String> lines, _Facts out, DateTime now) {
    final rest = <String>[];
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      (_K, TxnDirection?)? key;
      var value = '';
      final m = _kvRe.firstMatch(line);
      if (m != null) {
        key = _key(m.group(1)!);
        value = m.group(2)!.trim();
      }
      if (key == null) {
        // No separator: "Name Ravi Kumar", "Paid to Ravi 500", or a label
        // alone on its line with the value under it.
        final words = line.split(' ');
        for (var n = 3; n >= 1 && key == null; n--) {
          if (words.length < n) continue;
          final head = words.take(n).join(' ');
          if (RegExp(r'[0-9@₹]').hasMatch(head)) continue;
          key = _key(head, fuzzy: head.length >= 5);
          if (key != null) value = words.skip(n).join(' ').trim();
        }
      }
      if (key == null) {
        rest.add(line);
        continue;
      }
      if (value.isEmpty && i + 1 < lines.length && !_isLabel(lines[i + 1])) {
        value = lines[++i]; // "Amount" / "500" on two lines
      }
      if (value.isEmpty) {
        if (key.$2 != null) out.direction ??= key.$2; // a bare "Paid"
        continue;
      }
      final left = _assign(key.$1, key.$2, value, out, now);
      // Nothing usable: keep the whole line ("Bank of Baroda" is a name).
      if (identical(left, value)) {
        rest.add(line);
      } else if (left != null && RegExp(r'[A-Za-z0-9]').hasMatch(left)) {
        rest.add(left);
      }
    }
    return rest;
  }

  static bool _isLabel(String line) {
    final m = _kvRe.firstMatch(line);
    return (m != null && _key(m.group(1)!) != null) ||
        _key(line.split(' ').first, fuzzy: false) != null;
  }

  /// Puts [value] (found under a [k] label) into [out], checking it is what
  /// the label promises. Returns the part it didn't use — [value] itself if
  /// none of it fit.
  static String? _assign(
      _K k, TxnDirection? dir, String value, _Facts out, DateTime now) {
    switch (k) {
      case _K.name:
      case _K.first:
      case _K.middle:
      case _K.last:
        final n = _nameIn(value);
        if (n.name == null) {
          // "To: ravi@ybl" or "Paid: 500" — the value says what it is.
          final v = _vpaIn(value);
          final a = v == null ? _amountIn(value, labelled: true) : null;
          if (v == null && a == null) return value;
          if (v != null) out.upi ??= v;
          if (a != null) out.setAmount(a.value, unsure: !a.sure);
          if (dir != null) out.direction ??= dir;
          return null;
        }
        if (dir != null) out.direction ??= dir;
        switch (k) {
          case _K.first:
            out.first ??= n.name;
          case _K.middle:
            out.middle ??= n.name;
          case _K.last:
            out.last ??= n.name;
          default:
            out.name ??= n.name;
        }
        return n.rest;
      case _K.amount:
      case _K.total:
        final a = _amountIn(value, labelled: true);
        if (a == null) {
          // "Paid: Ravi" — a name under an amount-ish label.
          final n = _nameIn(value);
          if (n.name == null || dir == null) return value;
          out.name ??= n.name;
          out.direction ??= dir;
          return n.rest;
        }
        if (dir != null) out.direction ??= dir;
        // A total beats the item prices written above it.
        if (k == _K.total) out.amount = null;
        out.setAmount(a.value, unsure: !a.sure);
        return _withoutMoney(value);
      case _K.upi:
        final v = _vpaIn(value);
        // A UPI number written without the "@bank" part is a phone number.
        final p = v == null ? _phoneIn(value) : null;
        if (v == null && p == null) return value;
        out.upi ??= v;
        out.phone ??= p;
        return null;
      case _K.date:
        final d = _dateIn(value.toLowerCase(), now);
        final t = _timeIn(value.toLowerCase());
        if (d == null && t == null) return value;
        out.when ??= d;
        out.time ??= t;
        return null;
      case _K.time:
        final t = _timeIn(value.toLowerCase());
        if (t == null) return value;
        out.time ??= t;
        return null;
      case _K.ref:
        final r = RegExp(r'[A-Za-z0-9]{6,24}')
            .firstMatch(value.replaceAll(' ', ''))
            ?.group(0);
        if (r == null || !RegExp(r'\d').hasMatch(r)) return value;
        out.reference ??= r;
        return null;
      case _K.account:
        final d = RegExp(r'(\d{4})(?!\d)').allMatches(value);
        if (dir != null) out.direction ??= dir;
        if (d.isEmpty) return value;
        out.account ??= d.last.group(1);
        return null;
      case _K.phone:
        final p = _phoneIn(value);
        if (p == null) return value;
        out.phone ??= p;
        return null;
      case _K.note:
        out.note ??= value;
        return null;
      case _K.category:
        out.category ??= value;
        return null;
      case _K.type:
        final d = _directionIn(value.toLowerCase());
        if (d == null) return value;
        out.direction ??= d;
        return null;
    }
  }

  // ── 4. Entities in unlabelled text ────────────────────────────────────────

  static const _debitWords = {
    'paid', 'pay', 'sent', 'spent', 'gave', 'given', 'debit', 'debited',
    'dr', 'expense', 'bought', 'purchase', 'purchased', 'diya', 'diye', 'di',
    'bheja', 'bheje', 'kharcha', 'kharch', 'kharida', 'kharide',
    'transferred',
    'दिया', 'दिए', 'दिये', 'दी', 'भेजा', 'भेजे', 'खर्च', 'खर्चा', 'भुगतान',
    'चुकाया', 'खरीदा',
  };
  static const _creditWords = {
    'received', 'receive', 'got', 'credit', 'credited', 'cr', 'income',
    'refund', 'mila', 'mile', 'mili', 'liya', 'liye', 'aaya', 'aaye',
    'wapas', 'salary',
    'मिला', 'मिले', 'मिली', 'प्राप्त', 'आया', 'आए', 'आये', 'लिया', 'वापस',
    'तनख्वाह',
  };
  // Words that are never somebody's name.
  static const _notName = {
    'today', 'yesterday', 'aaj', 'kal', 'rs', 'rupees', 'rupaye', 'only',
    'thank', 'thanks', 'upi', 'cash', 'online', 'gpay', 'phonepe', 'paytm',
    'payment', 'transaction', 'successful', 'bill', 'invoice', 'receipt',
    'total', 'amount', 'and', 'the', 'for', 'via', 'by', 'ke', 'ko', 'se',
    'ne', 'ka', 'ki', 'hai', 'tha', 'was', 'is', 'to', 'from', 'on', 'at',
    'आज', 'कल', 'को', 'से', 'ने', 'का', 'की', 'के', 'लिए', 'और', 'है',
    'था', 'थे', 'नकद', 'कुल', 'राशि', 'बिल',
  };
  static const _months = {
    'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6, 'jul': 7,
    'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
  };
  static final _monthRe = RegExp(
      r'^(jan(uary)?|feb(ruary)?|mar(ch)?|apr(il)?|may|june?|july?|'
      r'aug(ust)?|sept?(ember)?|oct(ober)?|nov(ember)?|dec(ember)?)$');

  // "dinner ke liye" / "खाने के लिए" means *for*, not "liye" (took).
  static final _forPhrase = RegExp(r'\b(?:ke|ki)\s+liye\b|(?:के|की)\s+लिए',
      caseSensitive: false);

  static TxnDirection? _directionIn(String low) {
    final words = low
        .replaceAll(_forPhrase, ' ')
        .split(RegExp('[^a-zऀ-ॿ]+'))
        .toSet();
    final d = _debitWords.any(words.contains);
    final c = _creditWords.any(words.contains);
    if (d == c) return null;
    return d ? TxnDirection.debit : TxnDirection.credit;
  }

  static const _w = "[a-zऀ-ॿ][a-z.'ऀ-ॿ]+";
  // \b only knows ASCII letters; this ends a Hindi word.
  static const _hiEnd = '(?![ऀ-ॿ])';
  // Who, in English, Hinglish and Hindi: "paid 500 to Ravi", "got 200 from
  // Neha", "Ravi ko 500 diye", "रवि को 500 दिए", "नेहा से 200 मिले".
  static final _who = [
    (RegExp('\\b(?:to|paid|sent|gave)[ \\t]+($_w(?:[ \\t]+$_w){0,3})',
        caseSensitive: false), TxnDirection.debit),
    (RegExp('\\bfrom[ \\t]+($_w(?:[ \\t]+$_w){0,3})', caseSensitive: false),
        TxnDirection.credit),
    (RegExp('($_w(?:[ \\t]+$_w){0,2})[ \\t]+ko\\b', caseSensitive: false),
        TxnDirection.debit),
    (RegExp('($_w(?:[ \\t]+$_w){0,2})[ \\t]+se\\b', caseSensitive: false),
        TxnDirection.credit),
    (RegExp('($_w(?:[ \\t]+$_w){0,2})[ \\t]+को$_hiEnd'), TxnDirection.debit),
    (RegExp('($_w(?:[ \\t]+$_w){0,2})[ \\t]+से$_hiEnd'), TxnDirection.credit),
  ];

  static void _entities(List<String> lines, _Facts out, DateTime now) {
    if (lines.isEmpty) return;
    final text = lines.join('\n');
    final low = text.toLowerCase();
    out.direction = _directionIn(low);
    out.upi = _vpaIn(text);
    out.phone = _phoneIn(text);
    out.when = _dateIn(low, now);
    out.time = _timeIn(low);
    out.reference = RegExp(r'(?<!\d)\d{12}(?!\d)').firstMatch(text)?.group(0);
    out.note = (RegExp(r'\bfor[ \t]+([a-z][a-z \t]{1,40})',
                    caseSensitive: false)
                .firstMatch(text) ??
            // "dinner ke liye", "खाने के लिए": the word before it.
            RegExp('($_w)[ \\t]+(?:ke|ki|के|की)[ \\t]+(?:liye|लिए)',
                    caseSensitive: false)
                .firstMatch(text))
        ?.group(1)
        ?.trim();

    for (final (re, dir) in _who) {
      for (final m in re.allMatches(text)) {
        // "Aaj Ravi ko" → "Ravi": drop leading filler words.
        final words = m
            .group(1)!
            .split(RegExp(r'[ \t]+'))
            .skipWhile((w) => _notName.contains(w.toLowerCase()))
            .join(' ');
        final n = _nameIn(words).name;
        if (n == null) continue;
        out.name = n;
        out.nameUnsure = true;
        out.direction ??= dir;
        break;
      }
      if (out.name != null) break;
    }

    final a = _amountIn(text, labelled: false);
    if (a != null) out.setAmount(a.value, unsure: !a.sure);

    // Still no name: a short line of plain words ("Ravi", "Ravi 500").
    if (out.name == null) {
      for (final l in lines) {
        final n = _nameIn(l);
        if (n.name != null && _withoutMoney(n.rest!).isEmpty) {
          out.name = n.name;
          out.nameUnsure = true;
          break;
        }
      }
    }
  }

  // ── Value readers ─────────────────────────────────────────────────────────

  static final _vpaRe = RegExp(
      r'([a-z0-9][a-z0-9._\-]{1,48}) ?(?:@|©|\(a\)|\(@\)) ?([a-z][a-z0-9]{1,20})(?![a-z0-9]*\.[a-z])',
      caseSensitive: false);

  static String? _vpaIn(String s) {
    final m = _vpaRe.firstMatch(s);
    return m == null ? null : '${m.group(1)}@${m.group(2)}'.toLowerCase();
  }

  static final _phoneRe = RegExp(r'(?<!\d)(?:\+?91[\s\-]?)?([6-9]\d{4}\s?\d{5})(?!\d)');

  static String? _phoneIn(String s) =>
      _phoneRe.firstMatch(s)?.group(1)?.replaceAll(' ', '');

  /// [s] without its numbers and currency words: what's left once the amount
  /// is taken ("500 from Ravi" → "from Ravi").
  static String _withoutMoney(String s) => s
      .split(RegExp(r'\s+'))
      .where((w) =>
          !RegExp(r'\d').hasMatch(w) &&
          !const {'rs', 'inr', '₹', 'rupees', 'rupaye', 'k', '/-'}
              .contains(w.toLowerCase()))
      .join(' ');
  // A number as written, misread digits included ("1,250", "5OO", "12.50").
  static const _tail = r'[0-9OoIlSsBZz,]*(?:\.\d{1,2})?';
  static final _markedRe = RegExp(
      '(?:₹|\\brs\\b|\\binr\\b)\\s*([0-9OoIlSsBZz]$_tail)\\s*(k\\b)?|'
      '(\\d$_tail)\\s*(k)?\\s*(?:rs\\b|rupees|rupaye|inr\\b|₹)',
      caseSensitive: false);
  static final _bareRe =
      RegExp('(?<![\\w@.])(\\d$_tail)( ?k)?(?![\\w@])', caseSensitive: false);

  /// The money in [s]. A [labelled] value may be a bare number; free text
  /// needs a currency mark, or exactly one plausible number. [sure] when it
  /// was labelled or marked with ₹/Rs and no digit had to be repaired.
  static ({double value, bool sure})? _amountIn(String s,
      {required bool labelled}) {
    final cleaned = s
        .replaceAll(_vpaRe, ' ')
        .replaceAll(_phoneRe, ' ')
        .replaceAll(RegExp(r'\b\d{1,2}[/\-.]\d{1,2}[/\-.]\d{2,4}\b'), ' ')
        .replaceAll(
            RegExp(
                r'\b\d{1,2}(?:st|nd|rd|th)?[\s\-]*(?:jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*(?:[\s\-,]*(?:\d{4}|\d{2})(?!\d))?',
                caseSensitive: false),
            ' ')
        .replaceAll(
            RegExp(r'\b\d{1,2}:\d{2}(?:\s*[ap]\.?m\.?)?|\b\d{1,2}\.\d{2}\s*[ap]\.?m\b',
                caseSensitive: false),
            ' ');
    for (final m in _markedRe.allMatches(cleaned)) {
      final v = _number(m.group(1) ?? m.group(3)!, m.group(2) ?? m.group(4));
      if (v != null) return (value: v.value, sure: !v.repaired);
    }
    final bare = <({double value, bool repaired})>[];
    for (final m in _bareRe.allMatches(cleaned)) {
      final raw = m.group(1)!;
      // Ids and 12-digit UTRs are not amounts; nor, in free text, a year.
      if (raw.replaceAll(RegExp(r'\D'), '').length >= 8 && !raw.contains('.')) {
        continue;
      }
      if (!labelled && RegExp(r'^(19|20)\d{2}$').hasMatch(raw)) continue;
      final v = _number(raw, m.group(2));
      if (v != null) bare.add(v);
    }
    // Several bare numbers and no ₹: better to ask than guess.
    if (bare.isEmpty || (!labelled && bare.length > 1)) return null;
    return (value: bare.first.value, sure: labelled && !bare.first.repaired);
  }

  static ({double value, bool repaired})? _number(String raw, String? k) {
    final token = raw.trim().replaceAll(RegExp(r'[,.]$'), '');
    final fixed = _repairNumber(token);
    if (fixed == null) return null;
    var v = double.tryParse(fixed.replaceAll(',', ''));
    if (v == null) return null;
    if (k != null && k.trim().isNotEmpty) v *= 1000; // "2k"
    if (v <= 0 || v >= 10000000) return null;
    return (value: v, repaired: fixed != token);
  }

  static final _letter = RegExp('[A-Za-zऀ-ॿ]');
  static final _edgeJunk = RegExp(
      "^[^A-Za-zऀ-ॿ]+|[^A-Za-z.'ऀ-ॿ]+\$");

  /// A person / shop name at the start of [s], and what follows it: "Ravi
  /// Kumar 500 for dinner" → "Ravi Kumar" + "500 for dinner".
  static ({String? name, String? rest}) _nameIn(String s) {
    final words = s.trim().split(RegExp(r'\s+'));
    final kept = <String>[];
    var i = 0;
    for (; i < words.length && kept.length < 5; i++) {
      final raw = words[i];
      final w = raw.replaceAll(_edgeJunk, '');
      final lw = w.toLowerCase();
      if (w.isEmpty ||
          RegExp(r'\d').hasMatch(raw) ||
          raw.contains('@') ||
          _notName.contains(lw) ||
          _monthRe.hasMatch(lw) ||
          _debitWords.contains(lw) ||
          _creditWords.contains(lw)) {
        break;
      }
      kept.add(w);
    }
    final name = kept.join(' ');
    if (_letter.allMatches(name).length < 2) {
      return (name: null, rest: s);
    }
    return (name: _titleCase(name), rest: words.skip(i).join(' ').trim());
  }

  static String _titleCase(String s) => s
      .split(' ')
      .where((w) => w.isNotEmpty)
      .map((w) => w.length > 1 && w.length <= 3 && w == w.toUpperCase()
          ? w // initials: "SBI", "KK"
          : w[0].toUpperCase() + w.substring(1).toLowerCase())
      .join(' ');

  static DateTime? _dateIn(String low, DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    DateTime? check(int d, int mo, int? y) {
      if (d < 1 || d > 31 || mo < 1 || mo > 12) return null;
      if (y != null && y < 100) y += 2000;
      var when = DateTime(y ?? now.year, mo, d);
      if (when.month != mo) return null; // 31 Feb
      if (y == null && when.isAfter(today)) when = DateTime(now.year - 1, mo, d);
      return when.isAfter(today) ? null : when;
    }

    for (final t in RegExp(
            r"(?<!\d)([0-3]?\d)(?:st|nd|rd|th)?[\s\-,.]*(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*(?:[\s\-,.']*(\d{4}|\d{2}(?!\d)))?")
        .allMatches(low)) {
      final d = check(int.parse(t.group(1)!), _months[t.group(2)!]!,
          int.tryParse(t.group(3) ?? ''));
      if (d != null) return d;
    }
    // Numeric dates need a year, so "12.50" stays an amount.
    for (final n in RegExp(r'(?<![\d.])([0-3]?\d)[/\-.]([01]?\d)[/\-.](\d{4}|\d{2})(?![\d.])')
        .allMatches(low)) {
      final d = check(int.parse(n.group(1)!), int.parse(n.group(2)!),
          int.parse(n.group(3)!));
      if (d != null) return d;
    }
    const hiStart = '(?<![ऀ-ॿ])';
    if (RegExp('\\b(?:today|aaj)\\b|$hiStart' 'आज$_hiEnd').hasMatch(low)) {
      return today;
    }
    if (RegExp('\\b(?:yesterday|kal)\\b|$hiStart' 'कल$_hiEnd').hasMatch(low)) {
      return today.subtract(const Duration(days: 1));
    }
    return null;
  }

  static ({int h, int m})? _timeIn(String low) {
    final t12 = RegExp(r'(?<!\d)(1[0-2]|0?\d)[:.]([0-5]\d)\s*([ap])\.?\s?m\b')
        .firstMatch(low);
    if (t12 != null) {
      return (
        h: int.parse(t12.group(1)!) % 12 + (t12.group(3) == 'p' ? 12 : 0),
        m: int.parse(t12.group(2)!),
      );
    }
    final t24 = RegExp(r'(?<![\d:/.\-])([01]?\d|2[0-3]):([0-5]\d)(?![\d:])')
        .firstMatch(low);
    return t24 == null
        ? null
        : (h: int.parse(t24.group(1)!), m: int.parse(t24.group(2)!));
  }

  /// Edit distance where swapping two neighbouring letters ("Nmae") is one
  /// slip, like a typo or a misread.
  static int _distance(String a, String b) {
    final d = List.generate(
        a.length + 1, (i) => List<int>.generate(b.length + 1, (j) => 0));
    for (var i = 0; i <= a.length; i++) {
      d[i][0] = i;
    }
    for (var j = 0; j <= b.length; j++) {
      d[0][j] = j;
    }
    for (var i = 1; i <= a.length; i++) {
      for (var j = 1; j <= b.length; j++) {
        final cost = a[i - 1] == b[j - 1] ? 0 : 1;
        var v = d[i - 1][j] + 1;
        if (d[i][j - 1] + 1 < v) v = d[i][j - 1] + 1;
        if (d[i - 1][j - 1] + cost < v) v = d[i - 1][j - 1] + cost;
        if (i > 1 &&
            j > 1 &&
            a[i - 1] == b[j - 2] &&
            a[i - 2] == b[j - 1] &&
            d[i - 2][j - 2] + 1 < v) {
          v = d[i - 2][j - 2] + 1;
        }
        d[i][j] = v;
      }
    }
    return d[a.length][b.length];
  }

  // ── 5. Fusion ─────────────────────────────────────────────────────────────

  static const _screenSignals = [
    'successful', 'completed', 'transaction id', 'utr', 'upi ref',
    'upi transaction', 'phonepe', 'google pay', 'paytm', 'bhim',
    'banking name', 'debited from', 'credited to', 'money sent',
    'money received',
  ];
  static const _billWords = [
    'invoice', 'gst', 'qty', 'bill', 'receipt', 'sub total', 'subtotal',
    'grand total', 'cash memo', 'mrp', 'बिल', 'रसीद', 'चालान',
  ];

  /// The first value found per field across [ranked] (strongest first).
  static ScanResult _fuse(ScanKind kind, DateTime now, List<_Facts> ranked) {
    T? pick<T>(T? Function(_Facts f) get) {
      for (final f in ranked) {
        final v = get(f);
        if (v != null) return v;
      }
      return null;
    }

    final amountFrom =
        ranked.firstWhere((f) => f.amount != null, orElse: _Facts.new);
    final nameFrom =
        ranked.firstWhere((f) => f.fullName != null, orElse: _Facts.new);
    final upi = pick((f) => f.upi);
    var name = nameFrom.fullName;
    var nameUnsure = nameFrom.nameUnsure;
    if (name == null && upi != null) {
      name = MerchantDirectory.prettyName(upi, null);
      nameUnsure = true;
    }

    var when = pick((f) => f.when);
    final time = pick((f) => f.time);
    if (when != null && time != null && when.hour == 0 && when.minute == 0) {
      final timed = DateTime(when.year, when.month, when.day, time.h, time.m);
      if (!timed.isAfter(now)) when = timed;
    }

    final amount = amountFrom.amount;
    final today = DateTime(now.year, now.month, now.day);
    return ScanResult(
      kind: kind,
      amount: amount,
      direction: pick((f) => f.direction),
      name: name,
      upiVpa: upi,
      when: when,
      reference: pick((f) => f.reference),
      account: pick((f) => f.account),
      phone: pick((f) => f.phone),
      note: pick((f) => f.note),
      category: pick((f) => f.category),
      unsure: {
        // A lakh or more from paper is worth a second look before saving.
        if (amountFrom.amountUnsure ||
            (kind == ScanKind.note && amount != null && amount >= 100000))
          ScanField.amount,
        if (nameUnsure) ScanField.name,
        // Months back is more often a misread year ("2O25") than a fact.
        if (when != null && today.difference(when).inDays > 120)
          ScanField.date,
      },
    );
  }
}

/// What a transaction needs that a scan may not find (or should double-check).
enum ScanField { amount, name, direction, date }

/// What the photo turned out to be.
enum ScanKind { payment, bill, note }

/// Everything read from one photo. Null fields weren't found.
class ScanResult {
  final ScanKind kind;
  final double? amount;
  final TxnDirection? direction; // null: the photo didn't say paid/received
  final String? name; // who was paid / who paid (or the shop)
  final String? upiVpa;
  final DateTime? when;
  final String? reference;
  final String? account; // last 4
  final String? phone;
  final String? note;
  final String? category; // as written ("food", "petrol")

  /// Read, but only guessed (no label, or digits repaired from handwriting).
  final Set<ScanField> unsure;

  /// One line of a list of entries on one page (see [ScanReader.readList]).
  final bool fromList;

  const ScanResult({
    required this.kind,
    this.amount,
    this.direction,
    this.name,
    this.upiVpa,
    this.when,
    this.reference,
    this.account,
    this.phone,
    this.note,
    this.category,
    this.unsure = const {},
    this.fromList = false,
  });

  /// What a transaction can't be saved without and the photo didn't give.
  List<ScanField> get missing => [
        if (amount == null) ScanField.amount,
        if (name == null) ScanField.name,
        if (direction == null) ScanField.direction,
      ];

  /// Something is missing or only guessed: ask before saving.
  bool get needsInput => missing.isNotEmpty || unsure.isNotEmpty;

  bool get isEmpty =>
      amount == null && name == null && upiVpa == null && note == null;

  String get kindLabel => switch (kind) {
        ScanKind.payment => 'payment screenshot',
        ScanKind.bill => 'bill',
        ScanKind.note => 'note',
      };
}

/// The text stored in place of the photo: worded like a bank SMS so it reads
/// (and searches) like every other entry, and signed so it's never mistaken
/// for one — see [Transaction.scanSender].
class ScanSms {
  ScanSms._();

  static const _mon = [
    '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct',
    'Nov', 'Dec'
  ];

  /// "Rs.500.00 debited on 27-Oct-26 14:05 to Ravi Kumar (VPA ravi@ybl).
  /// Ref 4123…. Info: dinner.\n-AERIS-SCAN: generated by AERIS from a
  /// scanned note. Not sent by any bank."
  static String compose({
    required double amount,
    required TxnDirection direction,
    required DateTime when,
    required String kindLabel,
    String? name,
    String? upiVpa,
    String? reference,
    String? account,
    String? phone,
    String? note,
  }) {
    String two(int n) => n.toString().padLeft(2, '0');
    final debit = direction == TxnDirection.debit;
    final who = [
      if (name != null && name.trim().isNotEmpty) name.trim(),
      if (upiVpa != null) '(VPA $upiVpa)',
    ].join(' ');
    final b = StringBuffer('Rs.${amount.toStringAsFixed(2)} ')
      ..write(debit ? 'debited' : 'credited');
    if (account != null) b.write(debit ? ' from A/c XX$account' : ' to A/c XX$account');
    b.write(' on ${two(when.day)}-${_mon[when.month]}-${two(when.year % 100)}'
        ' ${two(when.hour)}:${two(when.minute)}');
    if (who.isNotEmpty) b.write(debit ? ' to $who' : ' from $who');
    b.write('.');
    if (reference != null) b.write(' Ref $reference.');
    if (phone != null) b.write(' Ph $phone.');
    if (note != null && note.trim().isNotEmpty) b.write(' Info: ${note.trim()}.');
    b.write('\n-${Transaction.scanSender}: generated by AERIS from a scanned '
        '$kindLabel. Not sent by any bank.');
    return b.toString();
  }

  /// [body] (an earlier [compose]) rewritten after the entry was edited; the
  /// kind of photo and the phone number it recorded are kept.
  static String recompose(
    String body, {
    required double amount,
    required TxnDirection direction,
    required DateTime when,
    String? name,
    String? upiVpa,
    String? reference,
    String? account,
    String? note,
  }) =>
      compose(
        amount: amount,
        direction: direction,
        when: when,
        kindLabel:
            RegExp(r'from a scanned (.+?)\. Not sent').firstMatch(body)?.group(1) ??
                'photo',
        name: name,
        upiVpa: upiVpa,
        reference: reference,
        account: account,
        phone: RegExp(r' Ph (\d{10})\.').firstMatch(body)?.group(1),
        note: note,
      );
}

enum _K {
  name, first, middle, last, amount, total, upi, date, time, ref, account,
  phone, note, category, type,
}

/// One evidence source's findings, before fusion.
class _Facts {
  double? amount;
  bool amountUnsure = false;
  TxnDirection? direction;
  String? name, first, middle, last;
  bool nameUnsure = false;
  String? upi, reference, account, phone, note, category;
  DateTime? when;
  ({int h, int m})? time;

  void setAmount(double v, {required bool unsure}) {
    if (amount != null) return;
    amount = v;
    amountUnsure = unsure;
  }

  /// "Name", or "First name" + "Middle name" + "Last name".
  String? get fullName {
    final base = name ?? first;
    final l = last;
    final parts = [
      if (base != null) base,
      if (middle != null) middle!,
      if (l != null && !(base ?? '').toLowerCase().contains(l.toLowerCase())) l,
    ];
    return parts.isEmpty ? null : parts.join(' ');
  }
}
