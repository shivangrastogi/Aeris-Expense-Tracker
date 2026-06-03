import 'package:flutter/material.dart';

import '../services/app_lock_service.dart';

/// Wraps the authenticated app. When app-lock is enabled and the app returns
/// from the background, it covers the UI with a lock screen until the user
/// passes biometric / device-credential auth. The child stays mounted behind
/// the overlay so app state is preserved.
class AppLockGate extends StatefulWidget {
  final Widget child;
  const AppLockGate({super.key, required this.child});

  @override
  State<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends State<AppLockGate> with WidgetsBindingObserver {
  bool _enabled = false;
  bool _locked = false;
  bool _wentBackground = false;
  bool _authing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    AppLockService.instance.isEnabled().then((v) {
      if (mounted) setState(() => _enabled = v);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _wentBackground = true;
    } else if (state == AppLifecycleState.resumed) {
      // Re-read the flag in case it changed in Settings this session.
      _enabled = await AppLockService.instance.isEnabled();
      if (_enabled && _wentBackground && !_locked) {
        setState(() => _locked = true);
        _promptAuth();
      }
      _wentBackground = false;
    }
  }

  Future<void> _promptAuth() async {
    if (_authing) return;
    _authing = true;
    final ok = await AppLockService.instance.authenticate();
    _authing = false;
    if (ok && mounted) setState(() => _locked = false);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (_locked)
          Positioned.fill(
            child: _LockScreen(onUnlock: _promptAuth),
          ),
      ],
    );
  }
}

class _LockScreen extends StatelessWidget {
  final VoidCallback onUnlock;
  const _LockScreen({required this.onUnlock});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 40,
              backgroundColor: scheme.primary.withValues(alpha: 0.12),
              child: Icon(Icons.lock, size: 40, color: scheme.primary),
            ),
            const SizedBox(height: 20),
            Text('AERIS is locked',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 6),
            Text('Verify it\'s you to continue',
                style: TextStyle(color: scheme.onSurfaceVariant)),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onUnlock,
              icon: const Icon(Icons.fingerprint),
              label: const Text('Unlock'),
            ),
          ],
        ),
      ),
    );
  }
}
