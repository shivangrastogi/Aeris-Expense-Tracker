import 'package:aeris_expense/services/receipt_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('restaurant bill: grand total beats sub total', () {
    const text = '''
CHAI POINT
Koramangala, Bengaluru
GSTIN 29ABCDE1234F1Z5
Date: 28/09/2026  Time 16:42
Masala Chai x2      120.00
Samosa x1            45.00
Sub Total           165.00
CGST 2.5%             4.13
SGST 2.5%             4.13
Grand Total      Rs 173.26
Thank you, visit again!
''';
    final r = ReceiptParser.parse(text);
    expect(r.total, 173.26);
    expect(r.merchant, 'Chai Point');
    expect(r.date, DateTime(2026, 9, 28));
  });

  test('total split onto the next line by OCR', () {
    const text = 'BigBasket\nTAX INVOICE\nTOTAL\n₹2,340.50\n12-Sep-26';
    final r = ReceiptParser.parse(text);
    expect(r.total, 2340.5);
    expect(r.merchant, 'Bigbasket');
    expect(r.date, DateTime(2026, 9, 12));
  });

  test('ignores phone numbers and falls back to the largest decimal', () {
    const text = 'Apollo Pharmacy\nPh 9876543210\nParacetamol 30.50\n'
        'Vitamin C 250.00\nAmount 280.50';
    final r = ReceiptParser.parse(text);
    expect(r.total, 280.5);
  });

  test('unreadable text gives nothing, not garbage', () {
    final r = ReceiptParser.parse('~~ ### ~~');
    expect(r.total, isNull);
    expect(r.merchant, isNull);
  });
}
