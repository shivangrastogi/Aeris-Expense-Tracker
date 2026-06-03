import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:collection/collection.dart';
import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:uuid/uuid.dart';
import 'package:xml/xml.dart';

import '../models/category.dart';
import '../models/transaction.dart';
import 'crypto_service.dart';
import 'firestore_service.dart';
import 'key_vault.dart';

/// Imports bank statements (PDF / CSV / XLSX) and turns them into transactions.
///
/// Design goal: **work for any bank**, not just one format. Tabular files
/// (CSV / Excel) are parsed generically — we detect the header row and map
/// columns (Date / Description / Debit / Credit / Amount / Type) by fuzzy
/// keyword matching, and the UI lets the user re-map if auto-detect is wrong.
/// PDF e-statements are best-effort: text is extracted (with password support)
/// and parsed line-by-line. Everything lands in a review screen before saving,
/// so the user confirms/edits/categorises and nothing wrong is written blindly.
class StatementImportService {
  StatementImportService._();
  static final StatementImportService instance = StatementImportService._();

  static const _uuid = Uuid();

  // ── Public entry: pick a file and parse it ──────────────────
  Future<ParsedStatement?> pickAndParse({String? pdfPassword}) async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'csv', 'xlsx', 'xls', 'txt'],
      withData: true,
    );
    if (res == null || res.files.isEmpty) return null;
    final f = res.files.first;
    final bytes = f.bytes;
    if (bytes == null) {
      throw const StatementException('Could not read the selected file.');
    }
    final ext = (f.extension ?? '').toLowerCase();
    return parseBytes(bytes, ext, fileName: f.name, pdfPassword: pdfPassword);
  }

  Future<ParsedStatement> parseBytes(
    Uint8List bytes,
    String ext, {
    required String fileName,
    String? pdfPassword,
  }) async {
    switch (ext) {
      case 'csv':
      case 'txt':
        return _fromTable(_readCsv(bytes), fileName);
      case 'xlsx':
        return _fromTable(_readXlsx(bytes), fileName);
      case 'xls':
        throw const StatementException(
            'Old .xls format isn\'t supported. Please re-export the statement '
            'as .xlsx or .csv from your bank\'s site.');
      case 'pdf':
        return _fromPdf(bytes, fileName, pdfPassword);
      default:
        throw StatementException('Unsupported file type: .$ext');
    }
  }

  // ── Tabular (CSV / XLSX) ────────────────────────────────────
  List<List<String>> _readCsv(Uint8List bytes) {
    // Normalise line endings so the converter splits rows regardless of \r\n,
    // \r or \n in the source file.
    final text = utf8
        .decode(bytes, allowMalformed: true)
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n');
    final rows = const CsvToListConverter(
      shouldParseNumbers: false,
      eol: '\n',
    ).convert(text);
    return rows
        .map((r) => r.map((c) => (c ?? '').toString()).toList())
        .toList();
  }

  List<List<String>> _readXlsx(Uint8List bytes) {
    final archive = ZipDecoder().decodeBytes(bytes);
    // Shared strings table.
    final shared = <String>[];
    final ss = archive.files
        .firstWhereOrNull((f) => f.name == 'xl/sharedStrings.xml');
    if (ss != null) {
      final doc = XmlDocument.parse(utf8.decode(ss.content as List<int>));
      for (final si in doc.findAllElements('si')) {
        final buf = StringBuffer();
        for (final t in si.findAllElements('t')) {
          buf.write(t.innerText);
        }
        shared.add(buf.toString());
      }
    }
    // First worksheet.
    final sheet = archive.files
            .firstWhereOrNull((f) => f.name == 'xl/worksheets/sheet1.xml') ??
        archive.files.firstWhereOrNull((f) =>
            f.name.startsWith('xl/worksheets/sheet') &&
            f.name.endsWith('.xml'));
    if (sheet == null) return [];
    final doc = XmlDocument.parse(utf8.decode(sheet.content as List<int>));
    final rows = <List<String>>[];
    for (final row in doc.findAllElements('row')) {
      final cells = <String>[];
      var expected = 0;
      for (final c in row.findElements('c')) {
        final col = _colIndex(c.getAttribute('r') ?? '');
        while (expected < col) {
          cells.add('');
          expected++;
        }
        final t = c.getAttribute('t');
        var val = '';
        final v = c.findElements('v').firstOrNull;
        if (t == 's') {
          final idx = int.tryParse(v?.innerText ?? '');
          if (idx != null && idx >= 0 && idx < shared.length) val = shared[idx];
        } else if (t == 'inlineStr') {
          val = c.findAllElements('t').map((e) => e.innerText).join();
        } else {
          val = v?.innerText ?? '';
        }
        cells.add(val);
        expected++;
      }
      rows.add(cells);
    }
    return rows;
  }

  /// Convert an Excel cell ref ("B7") to a 0-based column index.
  int _colIndex(String ref) {
    var i = 0, col = 0;
    while (i < ref.length && _isLetter(ref.codeUnitAt(i))) {
      col = col * 26 + (ref.codeUnitAt(i) - 64); // 'A' = 65
      i++;
    }
    return col > 0 ? col - 1 : 0;
  }

  bool _isLetter(int c) => c >= 65 && c <= 90 || c >= 97 && c <= 122;

  ParsedStatement _fromTable(List<List<String>> table, String fileName) {
    // Drop fully-empty rows.
    final rows = table
        .where((r) => r.any((c) => c.trim().isNotEmpty))
        .toList();
    if (rows.isEmpty) {
      throw const StatementException('The file has no rows to import.');
    }
    final headerRow = _detectHeaderRow(rows);
    final map = _detectColumns(rows[headerRow]);
    final txns = applyMapping(rows, headerRow, map);
    return ParsedStatement(
      isTabular: true,
      table: rows,
      headerRow: headerRow,
      map: map,
      txns: txns,
      fileName: fileName,
    );
  }

  // Score each of the first 15 rows by how many column keywords it matches;
  // the best-scoring row is the header.
  int _detectHeaderRow(List<List<String>> rows) {
    var best = 0, bestScore = -1;
    final limit = rows.length < 15 ? rows.length : 15;
    for (var i = 0; i < limit; i++) {
      final m = _detectColumns(rows[i]);
      final score = m.score;
      if (score > bestScore) {
        bestScore = score;
        best = i;
      }
    }
    return best;
  }

  ColumnMap _detectColumns(List<String> header) {
    int find(List<String> keys) {
      for (var i = 0; i < header.length; i++) {
        final h = header[i].toLowerCase().trim();
        if (h.isEmpty) continue;
        if (keys.any((k) => h.contains(k))) return i;
      }
      return -1;
    }

    final date = find(['txn date', 'transaction date', 'value date', 'tran date', 'date', 'posting date']);
    final desc = find(['narration', 'particular', 'description', 'remarks', 'details', 'transaction remarks', 'transaction']);
    final debit = find(['withdrawal', 'debit', 'paid out', 'withdrawals', 'dr amount', 'amount debited']);
    final credit = find(['deposit', 'credit', 'paid in', 'deposits', 'cr amount', 'amount credited']);
    final amount = find(['amount', 'txn amount', 'transaction amount']);
    final type = find(['dr / cr', 'dr/cr', 'cr/dr', 'type', 'transaction type']);
    return ColumnMap(
      dateCol: date,
      descCol: desc,
      debitCol: debit,
      creditCol: credit,
      // Avoid treating a "debit amount" column as the generic amount column.
      amountCol: (amount == debit || amount == credit) ? -1 : amount,
      typeCol: type,
    );
  }

  /// (Re-)build candidate transactions from a table + chosen column mapping.
  List<StatementTxn> applyMapping(
      List<List<String>> rows, int headerRow, ColumnMap map) {
    final out = <StatementTxn>[];
    for (var i = headerRow + 1; i < rows.length; i++) {
      final r = rows[i];
      String cell(int c) => (c >= 0 && c < r.length) ? r[c].trim() : '';

      final date = _parseDate(cell(map.dateCol));
      final desc = cell(map.descCol);

      double? amount;
      TxnDirection? dir;

      final debit = _money(cell(map.debitCol));
      final credit = _money(cell(map.creditCol));
      if (map.debitCol >= 0 && debit != null && debit != 0) {
        amount = debit.abs();
        dir = TxnDirection.debit;
      } else if (map.creditCol >= 0 && credit != null && credit != 0) {
        amount = credit.abs();
        dir = TxnDirection.credit;
      } else {
        final amt = _money(cell(map.amountCol));
        if (amt != null && amt != 0) {
          final typeCell = cell(map.typeCol).toLowerCase();
          if (typeCell.contains('cr')) {
            dir = TxnDirection.credit;
          } else if (typeCell.contains('dr')) {
            dir = TxnDirection.debit;
          } else {
            // No type column: use the sign (debits negative, credits positive).
            dir = amt < 0 ? TxnDirection.debit : TxnDirection.credit;
          }
          amount = amt.abs();
        }
      }

      if (amount == null || amount <= 0) continue; // not a transaction row
      out.add(_candidate(date, desc, amount, dir ?? TxnDirection.debit));
    }
    return out;
  }

  // ── PDF (best-effort line parsing) ──────────────────────────
  ParsedStatement _fromPdf(Uint8List bytes, String fileName, String? password) {
    PdfDocument doc;
    try {
      doc = PdfDocument(inputBytes: bytes, password: password);
    } catch (e) {
      final msg = e.toString().toLowerCase();
      if (msg.contains('password') || msg.contains('encrypt')) {
        throw const StatementException.passwordRequired();
      }
      throw StatementException('Could not open the PDF: $e');
    }
    String text;
    try {
      text = PdfTextExtractor(doc).extractText();
    } finally {
      doc.dispose();
    }
    final txns = _parsePdfText(text);
    return ParsedStatement(
      isTabular: false,
      table: const [],
      headerRow: 0,
      map: const ColumnMap.empty(),
      txns: txns,
      fileName: fileName,
    );
  }

  List<StatementTxn> _parsePdfText(String text) {
    final out = <StatementTxn>[];
    final money = RegExp(r'\d[\d,]*\.\d{2}');
    for (final raw in text.split('\n')) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      final date = _parseDateInText(line);
      if (date == null) continue; // transaction lines start with a date
      final amounts = money.allMatches(line).toList();
      if (amounts.isEmpty) continue;
      // Heuristic: in "date  narration  amount  balance", the txn amount is the
      // second-to-last money token when there are >=2 (last is running balance),
      // otherwise the only token.
      final amtMatch = amounts.length >= 2 ? amounts[amounts.length - 2] : amounts.last;
      final amount = _money(amtMatch.group(0)!);
      if (amount == null || amount <= 0) continue;

      final low = line.toLowerCase();
      TxnDirection dir;
      if (RegExp(r'\bcr\b').hasMatch(low) || low.contains('credit')) {
        dir = TxnDirection.credit;
      } else if (RegExp(r'\bdr\b').hasMatch(low) || low.contains('debit')) {
        dir = TxnDirection.debit;
      } else {
        dir = TxnDirection.debit; // default; user can flip in review
      }

      // Description = text between the date and the first money token.
      var desc = line;
      final dateEnd = _firstDateEnd(line);
      final firstMoney = amounts.first.start;
      if (dateEnd >= 0 && firstMoney > dateEnd) {
        desc = line.substring(dateEnd, firstMoney);
      }
      desc = desc.replaceAll(RegExp(r'\s+'), ' ').trim();
      out.add(_candidate(date, desc, amount, dir));
    }
    return out;
  }

  // ── Shared helpers ──────────────────────────────────────────
  StatementTxn _candidate(
      DateTime? date, String desc, double amount, TxnDirection dir) {
    final merchant = _cleanMerchant(desc);
    final categoryId = dir == TxnDirection.credit
        ? _creditCategory(desc)
        : Categories.classify(desc.isEmpty ? 'other' : desc);
    return StatementTxn(
      id: _uuid.v4(),
      amount: amount,
      direction: dir,
      date: date ?? DateTime.now(),
      hasDate: date != null,
      description: merchant,
      categoryId: categoryId,
    );
  }

  String _creditCategory(String hint) {
    final l = hint.toLowerCase();
    if (l.contains('salary') || l.contains('payroll')) return 'salary';
    if (l.contains('refund') || l.contains('reversal')) return 'shopping';
    return 'transfer';
  }

  String _cleanMerchant(String raw) {
    var m = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
    // Trim common UPI/ref noise.
    for (final cut in ['/Ref', ' Ref ', 'UPI/', '//', '  ']) {
      final i = m.indexOf(cut);
      if (i > 4) m = m.substring(0, i);
    }
    if (m.length > 48) m = m.substring(0, 48).trim();
    return m;
  }

  static final _dateFormats = <DateFormat>[
    DateFormat('dd/MM/yyyy'), DateFormat('dd-MM-yyyy'), DateFormat('dd.MM.yyyy'),
    DateFormat('dd-MMM-yyyy'), DateFormat('dd MMM yyyy'), DateFormat('dd-MMM-yy'),
    DateFormat('yyyy-MM-dd'), DateFormat('dd/MM/yy'), DateFormat('dd-MM-yy'),
    DateFormat('MM/dd/yyyy'),
  ];

  DateTime? _parseDate(String s) {
    s = s.trim();
    if (s.isEmpty) return null;
    for (final f in _dateFormats) {
      try {
        return f.parseStrict(s);
      } catch (_) {/* try next */}
    }
    return _parseDateInText(s);
  }

  static final _dateInText = RegExp(
      r'(\d{1,2})[-/.](\d{1,2}|[A-Za-z]{3,9})[-/.](\d{2,4})');

  DateTime? _parseDateInText(String line) {
    final m = _dateInText.firstMatch(line);
    if (m == null) return null;
    final dd = int.tryParse(m.group(1)!) ?? 1;
    var mm = int.tryParse(m.group(2)!) ?? _monthFromName(m.group(2)!);
    var yy = int.tryParse(m.group(3)!) ?? DateTime.now().year;
    if (yy < 100) yy += 2000;
    if (mm < 1 || mm > 12 || dd < 1 || dd > 31) return null;
    try {
      return DateTime(yy, mm, dd);
    } catch (_) {
      return null;
    }
  }

  int _firstDateEnd(String line) {
    final m = _dateInText.firstMatch(line);
    return m?.end ?? -1;
  }

  int _monthFromName(String s) {
    const months = [
      'jan', 'feb', 'mar', 'apr', 'may', 'jun',
      'jul', 'aug', 'sep', 'oct', 'nov', 'dec'
    ];
    final i = months.indexOf(s.toLowerCase().substring(
        0, s.length < 3 ? s.length : 3));
    return i >= 0 ? i + 1 : 1;
  }

  /// Parse a money string: "1,234.56", "(1,234.50)", "₹500 Dr", "-200".
  double? _money(String s) {
    if (s.trim().isEmpty) return null;
    var t = s.replaceAll(RegExp(r'[₹$£\s]'), '');
    var neg = false;
    if (t.startsWith('(') && t.endsWith(')')) {
      neg = true;
      t = t.substring(1, t.length - 1);
    }
    final low = t.toLowerCase();
    if (low.endsWith('dr')) neg = true;
    t = t.replaceAll(RegExp(r'(dr|cr)$', caseSensitive: false), '');
    t = t.replaceAll(',', '');
    final m = RegExp(r'-?\d+(\.\d+)?').firstMatch(t);
    if (m == null) return null;
    final v = double.tryParse(m.group(0)!);
    if (v == null) return null;
    return neg ? -v.abs() : v;
  }

  // ── Persistence ─────────────────────────────────────────────
  String _dedupeRaw(StatementTxn t) =>
      'stmt|${t.date.year}${t.date.month}${t.date.day}|${t.amount}|'
      '${t.description.length > 20 ? t.description.substring(0, 20) : t.description}';

  /// Save the selected candidates as transactions (encrypted, deduped).
  /// Returns how many new transactions were written.
  Future<int> importSelected(String uid, List<StatementTxn> selected,
      {void Function(int done, int total)? onProgress}) async {
    final fs = FirestoreService.instance;
    final dek = KeyVault.instance.dek ?? const <int>[];
    var saved = 0;
    for (var i = 0; i < selected.length; i++) {
      onProgress?.call(i, selected.length);
      final t = selected[i];
      final hash = await CryptoService.instance.dedupeTag(_dedupeRaw(t), dek);
      if (await fs.alreadyImported(uid, hash)) continue;
      await fs.addTransaction(
        uid,
        Transaction(
          id: t.id,
          amount: t.amount,
          direction: t.direction,
          timestamp: t.date,
          merchant: t.description.isEmpty ? null : t.description,
          categoryId: t.categoryId,
          source: TxnSource.imported,
          note: 'Imported from statement',
          reviewed: true,
        ),
      );
      await fs.markImported(uid, hash);
      saved++;
      if (i % 8 == 7) await Future<void>.delayed(Duration.zero);
    }
    onProgress?.call(selected.length, selected.length);
    return saved;
  }
}

// ── Data classes ──────────────────────────────────────────────
enum ColumnRole { date, description, debit, credit, amount, type }

class ColumnMap {
  final int dateCol, descCol, debitCol, creditCol, amountCol, typeCol;
  const ColumnMap({
    required this.dateCol,
    required this.descCol,
    required this.debitCol,
    required this.creditCol,
    required this.amountCol,
    required this.typeCol,
  });
  const ColumnMap.empty()
      : dateCol = -1,
        descCol = -1,
        debitCol = -1,
        creditCol = -1,
        amountCol = -1,
        typeCol = -1;

  /// How confident auto-detect is — number of recognised columns, weighted so a
  /// usable amount source (debit/credit pair, or an amount col) counts.
  int get score {
    var s = 0;
    if (dateCol >= 0) s++;
    if (descCol >= 0) s++;
    if (debitCol >= 0) s++;
    if (creditCol >= 0) s++;
    if (amountCol >= 0) s++;
    if (typeCol >= 0) s++;
    return s;
  }

  bool get hasAmountSource =>
      debitCol >= 0 || creditCol >= 0 || amountCol >= 0;

  ColumnMap withRole(ColumnRole role, int col) => ColumnMap(
        dateCol: role == ColumnRole.date ? col : dateCol,
        descCol: role == ColumnRole.description ? col : descCol,
        debitCol: role == ColumnRole.debit ? col : debitCol,
        creditCol: role == ColumnRole.credit ? col : creditCol,
        amountCol: role == ColumnRole.amount ? col : amountCol,
        typeCol: role == ColumnRole.type ? col : typeCol,
      );
}

/// A candidate transaction parsed from a statement (mutable for review-screen edits).
class StatementTxn {
  final String id;
  double amount;
  TxnDirection direction;
  DateTime date;
  bool hasDate;
  String description;
  String categoryId;
  bool selected;
  bool duplicate; // matches an existing transaction (same day/amount/direction)

  StatementTxn({
    required this.id,
    required this.amount,
    required this.direction,
    required this.date,
    required this.hasDate,
    required this.description,
    required this.categoryId,
    this.selected = true,
    this.duplicate = false,
  });
}

class ParsedStatement {
  final bool isTabular;
  final List<List<String>> table;
  final int headerRow;
  final ColumnMap map;
  final List<StatementTxn> txns;
  final String fileName;
  const ParsedStatement({
    required this.isTabular,
    required this.table,
    required this.headerRow,
    required this.map,
    required this.txns,
    required this.fileName,
  });
}

class StatementException implements Exception {
  final String message;
  final bool needsPassword;
  const StatementException(this.message) : needsPassword = false;
  const StatementException.passwordRequired()
      : message = 'This PDF is password-protected.',
        needsPassword = true;
  @override
  String toString() => message;
}
