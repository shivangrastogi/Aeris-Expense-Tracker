import 'package:flutter/services.dart';

/// Images sent to AERIS from another app's share sheet ("Share receipt" in
/// PhonePe, a screenshot in the gallery…). MainActivity copies them into the
/// app cache and hands over the file paths.
class ShareIntake {
  ShareIntake._();
  static const _ch = MethodChannel('aeris/share');

  /// Paths of images shared since the last call (each is handed over once).
  static Future<List<String>> take() async {
    try {
      return await _ch.invokeListMethod<String>('take') ?? const [];
    } catch (_) {
      return const []; // no native side (tests, other platforms)
    }
  }

  /// [onShared] fires when something is shared while the app is running.
  static void listen(void Function() onShared) {
    _ch.setMethodCallHandler((call) async {
      if (call.method == 'shared') onShared();
    });
  }

  static void stop() => _ch.setMethodCallHandler(null);
}
