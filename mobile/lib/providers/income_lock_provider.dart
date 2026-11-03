import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/app_lock_service.dart';
import '../utils/formatters.dart';

/// Salary privacy: income amounts (salary credits, monthly income) stay
/// masked as "₹••••" — even while every other amount is shown — until the
/// user unlocks them with their fingerprint (or phone PIN). They hide again
/// once the app has been away for [AppLockService.grace] or more.
class IncomeLock {
  /// The "Hide salary" switch (on the Edit profile screen).
  final bool enabled;

  /// Unlocked for this visit (cleared after being away a while).
  final bool revealed;
  const IncomeLock({this.enabled = false, this.revealed = false});

  bool get masked => enabled && !revealed;
}

final incomeLockProvider =
    StateNotifierProvider<IncomeLockController, IncomeLock>(
        (ref) => IncomeLockController());

class IncomeLockController extends StateNotifier<IncomeLock>
    with WidgetsBindingObserver {
  IncomeLockController() : super(IncomeLock(enabled: kIncomeMasked)) {
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  static const key = 'income_locked';

  /// The fingerprint sheet itself briefly takes the app off screen; don't
  /// re-hide because of that.
  bool _authing = false;

  Future<void> _load() async {
    final on = (await SharedPreferences.getInstance()).getBool(key) ?? false;
    _set(IncomeLock(enabled: on, revealed: state.revealed));
  }

  void _set(IncomeLock v) {
    kIncomeMasked = v.masked;
    state = v;
  }

  Future<bool> _auth(String reason) async {
    _authing = true;
    try {
      return await AppLockService.instance.authenticate(reason);
    } finally {
      _authing = false;
    }
  }

  /// Ask for the fingerprint, then show income for this visit.
  Future<bool> reveal() async {
    if (!state.masked) return true;
    if (!await _auth('Show your income')) return false;
    _set(IncomeLock(enabled: state.enabled, revealed: true));
    return true;
  }

  /// Profile holds the salary and phone number, so opening it always asks
  /// for the phone's lock (fingerprint, face or PIN). Passing counts as an
  /// unlock for the visit. Phones with no lock set up open straight in.
  Future<bool> verifyForProfile() async {
    if (state.revealed) return true;
    if (!await AppLockService.instance.isAvailable()) return true;
    if (!await _auth('Open your profile')) return false;
    _set(IncomeLock(enabled: state.enabled, revealed: true));
    return true;
  }

  /// Hide income again now (leaving Profile ends the unlocked visit).
  void relock() {
    if (state.revealed) _set(IncomeLock(enabled: state.enabled));
  }

  /// Turn the setting on or off. Both directions need the fingerprint, so
  /// someone holding the phone can't simply switch it off. Returns false if
  /// the device has no lock set up or the check failed.
  Future<bool> setEnabled(bool on, {bool alreadyVerified = false}) async {
    if (on == state.enabled) return true;
    if (!alreadyVerified) {
      if (!await AppLockService.instance.isAvailable()) return false;
      if (!await _auth(on ? 'Hide your salary' : 'Always show your salary')) {
        return false;
      }
    }
    await (await SharedPreferences.getInstance()).setBool(key, on);
    // Switched from inside an unlocked Profile: stay unlocked there.
    _set(IncomeLock(enabled: on, revealed: alreadyVerified && state.revealed));
    return true;
  }

  DateTime? _leftAt;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused && !_authing) {
      _leftAt ??= DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      final left = _leftAt;
      _leftAt = null;
      // A screenshot or a quick look elsewhere keeps it unlocked.
      final lock = this.state;
      if (left != null &&
          lock.revealed &&
          DateTime.now().difference(left) >= AppLockService.grace) {
        _set(IncomeLock(enabled: lock.enabled, revealed: false));
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
