import 'dart:io';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:path_provider/path_provider.dart';

import 'payment_shot_parser.dart';
import 'scan_reader.dart';

/// Reads photos — payment screenshots, bills, handwritten notes — with
/// Google ML Kit's on-device text recognizer (the image never leaves the
/// phone), then [ScanReader] makes sense of the text.
class ReceiptScanner {
  ReceiptScanner._();

  /// True when the last read failed because Google Play services is still
  /// downloading the text-recognition model (first use after install).
  static bool modelDownloading = false;

  /// Any photo at [path] read into one transaction's fields. Null if no text
  /// could be read at all. [path] is the full-size original: a downscaled
  /// copy blurs small print.
  static Future<ScanResult?> read(String path) async =>
      (await _best(path))?.result;

  /// Like [read], but a page listing several entries ("Ravi 500 / Neha
  /// 300") gives one result per line. Empty if nothing could be read.
  static Future<List<ScanResult>> readAll(String path) async {
    final best = await _best(path);
    if (best == null) return const [];
    return ScanReader.readList(rows: best.rows) ?? [best.result];
  }

  /// Latin script first. When that leaves gaps, the photo is read again
  /// with the Hindi (Devanagari) model — "नाम: रवि, राशि: ५००" — and the
  /// fuller reading wins.
  static Future<({ScanResult result, String rows})?> _best(String path) async {
    final latin = await _readAs(path, TextRecognitionScript.latin);
    if (latin != null &&
        latin.result.missing.isEmpty &&
        latin.result.unsure.isEmpty) {
      return latin;
    }
    final latinDownloading = modelDownloading;
    final hindi = await _readAs(path, TextRecognitionScript.devanagiri);
    // The Hindi model failing (still downloading) mustn't hide a Latin one.
    modelDownloading = latinDownloading || (latin == null && modelDownloading);
    if (hindi == null) return latin;
    if (latin == null) return hindi;
    return _score(hindi.result) > _score(latin.result) ? hindi : latin;
  }

  /// More found, and less of it guessed, is better.
  static int _score(ScanResult r) =>
      (3 - r.missing.length) * 4 -
      r.unsure.length +
      [r.upiVpa, r.when, r.note].where((v) => v != null).length;

  static Future<({ScanResult result, String rows})?> _readAs(
      String path, TextRecognitionScript script) async {
    try {
      final text = await _read(path, script: script);
      if (text == null) return null;
      final r = ScanReader.read(rows: text.rows, plain: text.plain);
      return r.isEmpty ? null : (result: r, rows: text.rows);
    } catch (_) {
      return null;
    }
  }

  /// Deletes the picked photo once it has been read, if it is AERIS's own
  /// copy (camera shots, gallery picks and shared images all land in the
  /// app cache) — the scan keeps text, not the image. Files elsewhere, such
  /// as the user's gallery, are never touched.
  static Future<void> forget(String path) async {
    try {
      final cache = (await getTemporaryDirectory()).absolute.path;
      final f = File(path).absolute;
      if (f.path.startsWith(cache) && await f.exists()) await f.delete();
    } catch (_) {
      // Best effort: the OS clears the cache eventually anyway.
    }
  }

  /// The recognised text twice: as the recogniser ordered it, and rebuilt
  /// into visual rows (see [PaymentShotParser.layout]).
  static Future<({String plain, String rows})?> _read(String path,
      {TextRecognitionScript script = TextRecognitionScript.latin}) async {
    final recognizer = TextRecognizer(script: script);
    try {
      modelDownloading = false;
      final RecognizedText result;
      try {
        result = await recognizer.processImage(InputImage.fromFilePath(path));
      } catch (e) {
        // "Waiting for the text optional module to be downloaded."
        modelDownloading = '$e'.toLowerCase().contains('download');
        rethrow;
      }
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
