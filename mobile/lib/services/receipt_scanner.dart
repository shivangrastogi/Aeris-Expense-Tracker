import 'dart:io';
import 'dart:typed_data';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:path_provider/path_provider.dart';

import 'payment_shot_parser.dart';
import 'receipt_parser.dart';

/// Reads a receipt photo or a payment-app screenshot with Google ML Kit's
/// on-device text recognizer (the image never leaves the phone).
class ReceiptScanner {
  ReceiptScanner._();

  /// Total / merchant / date from a bill photo. A payment screenshot attached
  /// here is read as one, so it also carries paid-vs-received.
  /// Null if recognition isn't available or nothing useful was found.
  static Future<ReceiptInfo?> scan(Uint8List imageBytes) async {
    File? tmp;
    try {
      final dir = await getTemporaryDirectory();
      tmp = File(
          '${dir.path}/receipt_scan_${DateTime.now().millisecondsSinceEpoch}.jpg');
      await tmp.writeAsBytes(imageBytes);
      final text = await _read(tmp.path);
      if (text == null) return null;
      final pay = PaymentShotParser.parse(text.rows);
      if (pay != null) {
        return ReceiptInfo(
          total: pay.amount,
          merchant: pay.name,
          date: pay.when,
          direction: pay.directionGuessed ? null : pay.direction,
        );
      }
      final info = ReceiptParser.parse(text.plain);
      return info.isEmpty ? null : info;
    } catch (_) {
      return null;
    } finally {
      try {
        await tmp?.delete();
      } catch (_) {}
    }
  }

  /// A UPI payment screenshot (PhonePe, Google Pay, Paytm…) at [path], or
  /// null if it can't be read as one.
  static Future<PaymentShot?> scanPayment(String path) async {
    try {
      final text = await _read(path);
      return text == null ? null : PaymentShotParser.parse(text.rows);
    } catch (_) {
      return null;
    }
  }

  /// The recognised text twice: as the recogniser ordered it, and rebuilt
  /// into visual rows (see [PaymentShotParser.layout]).
  static Future<({String plain, String rows})?> _read(String path) async {
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final result = await recognizer.processImage(InputImage.fromFilePath(path));
      return (
        plain: result.text,
        rows: PaymentShotParser.layout([
          for (final b in result.blocks)
            for (final l in b.lines)
              OcrLine(l.text,
                  left: l.boundingBox.left,
                  top: l.boundingBox.top,
                  bottom: l.boundingBox.bottom),
        ]),
      );
    } finally {
      await recognizer.close();
    }
  }
}
