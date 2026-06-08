import 'package:flutter/services.dart';

/// One event from the native speech recognizer.
class VoiceEvent {
  final String type; // status | rms | partial | final | error
  final dynamic value;
  const VoiceEvent(this.type, this.value);
}

/// Thin Dart wrapper over the native Android `SpeechRecognizer` bridge in
/// `MainActivity.kt` (MethodChannel `aeris/voice` + EventChannel
/// `aeris/voice/events`). No third-party plugin — works offline where the
/// device's recognizer supports it.
class VoiceService {
  VoiceService._();
  static final VoiceService instance = VoiceService._();

  static const _method = MethodChannel('aeris/voice');
  static const _events = EventChannel('aeris/voice/events');

  Stream<VoiceEvent>? _stream;

  Stream<VoiceEvent> events() {
    _stream ??= _events.receiveBroadcastStream().map((e) {
      final m = (e as Map);
      return VoiceEvent(m['type'] as String? ?? 'error', m['value']);
    });
    return _stream!;
  }

  Future<bool> isAvailable() async {
    try {
      return await _method.invokeMethod<bool>('isAvailable') ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> start({String locale = 'en-IN'}) =>
      _method.invokeMethod('start', {'locale': locale});

  Future<void> stop() => _method.invokeMethod('stop');

  Future<void> cancel() => _method.invokeMethod('cancel');
}
