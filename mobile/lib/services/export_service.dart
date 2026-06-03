import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:syncfusion_flutter_xlsio/xlsio.dart' as xlsio;
import 'package:syncfusion_officechart/officechart.dart';

import '../models/budget.dart';
import '../models/category.dart';
import '../models/transaction.dart';

/// Builds a polished, multi-sheet Excel workbook (with native charts) from the
/// user's decrypted data and shares it. Sheets: Summary, Transactions,
/// Categories (pie), Monthly trend (line), Top merchants (bar).
class ExportService {
  ExportService._();
  static final ExportService instance = ExportService._();

  static const _accent = '#0EA5A4';
  static const _money = r'"' '₹' r'"#,##0';

  Future<String> buildAndShare({
    required List<Transaction> txns,
    required List<Budget> budgets,
  }) async {
    final wb = xlsio.Workbook();
    _summary(wb, txns);
    _transactions(wb, txns);
    _accounts(wb, txns);
    _categories(wb, txns);
    _monthly(wb, txns);
    _topMerchants(wb, txns);

    final bytes = wb.saveAsStream();
    wb.dispose();

    final dir = await getTemporaryDirectory();
    final path =
        '${dir.path}/AERIS_report_${DateTime.now().millisecondsSinceEpoch}.xlsx';
    File(path).writeAsBytesSync(bytes, flush: true);
    await Share.shareXFiles([XFile(path)],
        text: 'My AERIS expense report', subject: 'AERIS Expense Report');
    return path;
  }

  void _header(xlsio.Range range) {
    range.cellStyle.bold = true;
    range.cellStyle.backColor = _accent;
    range.cellStyle.fontColor = '#FFFFFF';
  }

  void _summary(xlsio.Workbook wb, List<Transaction> txns) {
    final s = wb.worksheets[0];
    s.name = 'Summary';
    double income = 0, expense = 0;
    for (final t in txns) {
      if (t.isCredit) {
        income += t.amount;
      } else {
        expense += t.amount;
      }
    }
    s.getRangeByName('A1').setText('AERIS Expense Report');
    s.getRangeByName('A1').cellStyle.bold = true;
    s.getRangeByName('A1').cellStyle.fontSize = 18;
    s.getRangeByName('A2').setText('Generated ${DateTime.now().toString().split('.').first}');

    s.getRangeByName('A4').setText('Metric');
    s.getRangeByName('B4').setText('Value');
    _header(s.getRangeByName('A4:B4'));

    final rows = <(String, double)>[
      ('Total income', income),
      ('Total expense', expense),
      ('Net', income - expense),
      ('Transactions', txns.length.toDouble()),
    ];
    var r = 5;
    for (final row in rows) {
      s.getRangeByIndex(r, 1).setText(row.$1);
      final cell = s.getRangeByIndex(r, 2);
      cell.setNumber(row.$2);
      if (row.$1 != 'Transactions') cell.numberFormat = _money;
      r++;
    }
    s.getRangeByName('A1:B$r').autoFitColumns();
  }

  void _transactions(xlsio.Workbook wb, List<Transaction> txns) {
    final sh = wb.worksheets.addWithName('Transactions');
    const headers = [
      'Date', 'Merchant', 'Category', 'Type', 'Amount', 'Account', 'Source'
    ];
    for (var i = 0; i < headers.length; i++) {
      sh.getRangeByIndex(1, i + 1).setText(headers[i]);
    }
    _header(sh.getRangeByName('A1:G1'));
    final sorted = [...txns]..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    var r = 2;
    for (final t in sorted) {
      sh.getRangeByIndex(r, 1).setDateTime(t.timestamp);
      sh.getRangeByIndex(r, 1).numberFormat = 'dd-mmm-yyyy';
      sh.getRangeByIndex(r, 2).setText(t.merchant ?? '');
      sh.getRangeByIndex(r, 3).setText(Categories.byId(t.categoryId).label);
      sh.getRangeByIndex(r, 4).setText(t.isCredit ? 'Income' : 'Expense');
      final amt = sh.getRangeByIndex(r, 5);
      amt.setNumber(t.amount);
      amt.numberFormat = _money;
      sh.getRangeByIndex(r, 6).setText(t.account ?? '');
      sh.getRangeByIndex(r, 7).setText(t.source.name);
      r++;
    }
    sh.getRangeByName('A1:G1').autoFitColumns();
  }

  // Per-account totals (Spent / Received / Net / count), grouped by the
  // account tag on each transaction. Powers the "different per bank account"
  // breakdown in the export.
  void _accounts(xlsio.Workbook wb, List<Transaction> txns) {
    final sh = wb.worksheets.addWithName('Accounts');
    final spent = <String, double>{};
    final received = <String, double>{};
    final count = <String, int>{};
    for (final t in txns) {
      final k = (t.account == null || t.account!.trim().isEmpty)
          ? 'Unassigned'
          : 'A/C ${t.account!.trim()}';
      if (t.isCredit) {
        received[k] = (received[k] ?? 0) + t.amount;
      } else {
        spent[k] = (spent[k] ?? 0) + t.amount;
      }
      count[k] = (count[k] ?? 0) + 1;
    }
    const headers = ['Account', 'Spent', 'Received', 'Net', 'Transactions'];
    for (var i = 0; i < headers.length; i++) {
      sh.getRangeByIndex(1, i + 1).setText(headers[i]);
    }
    _header(sh.getRangeByName('A1:E1'));
    final keys = count.keys.toList()
      ..sort((a, b) => (count[b] ?? 0).compareTo(count[a] ?? 0));
    var r = 2;
    for (final k in keys) {
      final s = spent[k] ?? 0, rcv = received[k] ?? 0;
      sh.getRangeByIndex(r, 1).setText(k);
      sh.getRangeByIndex(r, 2)
        ..setNumber(s)
        ..numberFormat = _money;
      sh.getRangeByIndex(r, 3)
        ..setNumber(rcv)
        ..numberFormat = _money;
      sh.getRangeByIndex(r, 4)
        ..setNumber(rcv - s)
        ..numberFormat = _money;
      sh.getRangeByIndex(r, 5).setNumber((count[k] ?? 0).toDouble());
      r++;
    }
    sh.getRangeByName('A1:E1').autoFitColumns();
  }

  void _categories(xlsio.Workbook wb, List<Transaction> txns) {
    final sh = wb.worksheets.addWithName('Categories');
    final byCat = <String, double>{};
    for (final t in txns.where((t) => t.isDebit)) {
      byCat[t.categoryId] = (byCat[t.categoryId] ?? 0) + t.amount;
    }
    final entries = byCat.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    sh.getRangeByName('A1').setText('Category');
    sh.getRangeByName('B1').setText('Amount');
    _header(sh.getRangeByName('A1:B1'));
    var r = 2;
    for (final e in entries) {
      sh.getRangeByIndex(r, 1).setText(Categories.byId(e.key).label);
      sh.getRangeByIndex(r, 2).setNumber(e.value);
      sh.getRangeByIndex(r, 2).numberFormat = _money;
      r++;
    }
    final last = r - 1;
    if (last >= 2) {
      final charts = ChartCollection(sh);
      final c = charts.add();
      c.chartType = ExcelChartType.pie;
      c.dataRange = sh.getRangeByName('A1:B$last');
      c.isSeriesInRows = false;
      c.chartTitle = 'Spending by Category';
      c.topRow = 1;
      c.bottomRow = 20;
      c.leftColumn = 4;
      c.rightColumn = 13;
      sh.charts = charts;
    }
    sh.getRangeByName('A1:B1').autoFitColumns();
  }

  void _monthly(xlsio.Workbook wb, List<Transaction> txns) {
    final sh = wb.worksheets.addWithName('Monthly');
    final exp = <String, double>{};
    final inc = <String, double>{};
    for (final t in txns) {
      final k = '${t.timestamp.year}-${t.timestamp.month.toString().padLeft(2, '0')}';
      if (t.isCredit) {
        inc[k] = (inc[k] ?? 0) + t.amount;
      } else {
        exp[k] = (exp[k] ?? 0) + t.amount;
      }
    }
    final keys = ({...exp.keys, ...inc.keys}.toList()..sort());
    sh.getRangeByName('A1').setText('Month');
    sh.getRangeByName('B1').setText('Expense');
    sh.getRangeByName('C1').setText('Income');
    _header(sh.getRangeByName('A1:C1'));
    var r = 2;
    for (final k in keys) {
      sh.getRangeByIndex(r, 1).setText(k);
      sh.getRangeByIndex(r, 2).setNumber(exp[k] ?? 0);
      sh.getRangeByIndex(r, 2).numberFormat = _money;
      sh.getRangeByIndex(r, 3).setNumber(inc[k] ?? 0);
      sh.getRangeByIndex(r, 3).numberFormat = _money;
      r++;
    }
    final last = r - 1;
    if (last >= 2) {
      final charts = ChartCollection(sh);
      final c = charts.add();
      c.chartType = ExcelChartType.line;
      c.dataRange = sh.getRangeByName('A1:C$last');
      c.isSeriesInRows = false;
      c.chartTitle = 'Monthly Expense vs Income';
      c.topRow = 1;
      c.bottomRow = 20;
      c.leftColumn = 5;
      c.rightColumn = 14;
      sh.charts = charts;
    }
    sh.getRangeByName('A1:C1').autoFitColumns();
  }

  void _topMerchants(xlsio.Workbook wb, List<Transaction> txns) {
    final sh = wb.worksheets.addWithName('Top Merchants');
    final byM = <String, double>{};
    for (final t in txns.where((t) => t.isDebit && (t.merchant ?? '').isNotEmpty)) {
      byM[t.merchant!] = (byM[t.merchant!] ?? 0) + t.amount;
    }
    final entries = byM.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    sh.getRangeByName('A1').setText('Merchant');
    sh.getRangeByName('B1').setText('Amount');
    _header(sh.getRangeByName('A1:B1'));
    var r = 2;
    for (final e in entries.take(12)) {
      sh.getRangeByIndex(r, 1).setText(e.key);
      sh.getRangeByIndex(r, 2).setNumber(e.value);
      sh.getRangeByIndex(r, 2).numberFormat = _money;
      r++;
    }
    final last = r - 1;
    if (last >= 2) {
      final charts = ChartCollection(sh);
      final c = charts.add();
      c.chartType = ExcelChartType.bar;
      c.dataRange = sh.getRangeByName('A1:B$last');
      c.isSeriesInRows = false;
      c.chartTitle = 'Top Merchants';
      c.topRow = 1;
      c.bottomRow = 20;
      c.leftColumn = 4;
      c.rightColumn = 13;
      sh.charts = charts;
    }
    sh.getRangeByName('A1:B1').autoFitColumns();
  }
}
