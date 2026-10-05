import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/theme.dart';

/// "Hide in recent apps" — on by default. When the app leaves the
/// foreground, balances are covered so they don't show in the recent-apps
/// preview:
///  • Android 13+: the OS switch that removes the preview entirely (still
///    allows screenshots inside the app);
///  • every version: a blur shield painted the moment the app goes inactive.
final recentsPrivacyProvider =
    StateNotifierProvider<RecentsPrivacy, bool>((_) => RecentsPrivacy());

class RecentsPrivacy extends StateNotifier<bool> {
  static const _channel = MethodChannel('aeris/privacy');
  static const _key = 'hide_in_recents';

  RecentsPrivacy() : super(true) {
    SharedPreferences.getInstance().then((p) {
      if (!mounted) return;
      state = p.getBool(_key) ?? true;
      _apply(state);
    });
  }

  Future<void> set(bool v) async {
    state = v;
    await _apply(v);
    (await SharedPreferences.getInstance()).setBool(_key, v);
  }

  static Future<void> _apply(bool hidden) async {
    try {
      await _channel.invokeMethod('setRecentsHidden', {'hidden': hidden});
    } catch (_) {/* not Android / older plugin host — shield still works */}
  }
}

/// Covers the whole app with a blur + lock while it isn't in the foreground.
class PrivacyShield extends ConsumerStatefulWidget {
  final Widget child;
  const PrivacyShield({super.key, required this.child});

  @override
  ConsumerState<PrivacyShield> createState() => _PrivacyShieldState();
}

class _PrivacyShieldState extends ConsumerState<PrivacyShield>
    with WidgetsBindingObserver {
  bool _covered = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ref.read(recentsPrivacyProvider); // applies the saved setting at launch
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final cover = state != AppLifecycleState.resumed &&
        ref.read(recentsPrivacyProvider);
    if (cover != _covered) setState(() => _covered = cover);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      textDirection: TextDirection.ltr,
      children: [
        widget.child,
        if (_covered)
          Positioned.fill(
            child: ClipRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
                child: Container(
                  color: AerisColors.bgDark.withValues(alpha: 0.72),
                  alignment: Alignment.center,
                  child: const Icon(Icons.lock_rounded,
                      size: 48, color: AerisColors.arc),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
