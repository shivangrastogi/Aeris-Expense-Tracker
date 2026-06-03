import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Optional biometric / device-credential lock that gates the app when it
/// returns from the background. Independent of the E2E vault unlock (which
/// happens at login) — this is a quick re-entry guard.
class AppLockService {
  AppLockService._();
  static final AppLockService instance = AppLockService._();

  static const _prefKey = 'app_lock_enabled';
  final _auth = LocalAuthentication();

  Future<bool> isEnabled() async =>
      (await SharedPreferences.getInstance()).getBool(_prefKey) ?? false;

  Future<void> setEnabled(bool v) async =>
      (await SharedPreferences.getInstance()).setBool(_prefKey, v);

  /// Whether the device can authenticate at all (biometric OR device PIN).
  Future<bool> isAvailable() async {
    try {
      return await _auth.isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  /// Prompt the OS auth sheet. Allows device-credential fallback so users
  /// without enrolled biometrics can still unlock with their PIN/pattern.
  Future<bool> authenticate([String reason = 'Unlock AERIS']) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: false,
        ),
      );
    } catch (_) {
      return false;
    }
  }
}
