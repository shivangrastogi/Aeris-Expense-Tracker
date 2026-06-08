import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/analytics_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/budgets_provider.dart';
import '../../providers/insights_provider.dart';
import '../../providers/transactions_provider.dart';
import '../home/root_shell.dart';
import '../splash_screen.dart';

/// Sits between auth and the app: ensures the end-to-end encryption vault is
/// unlocked before any encrypted data is shown. On a fresh login/signup the
/// DEK is already in memory; on app restart it's restored from secure storage;
/// only if neither works do we ask the user to unlock.
class KeyGate extends ConsumerStatefulWidget {
  final String uid;
  const KeyGate({super.key, required this.uid});

  @override
  ConsumerState<KeyGate> createState() => _KeyGateState();
}

class _KeyGateState extends ConsumerState<KeyGate> {
  late Future<bool> _boot;

  @override
  void initState() {
    super.initState();
    _boot = _runBoot();
  }

  /// Unlock the vault, then PRELOAD the dashboard's data while the splash is
  /// still showing — so when the splash hands off, the Home screen paints
  /// already populated instead of flashing skeletons. The splash also stays up
  /// for a minimum so the "A.E.R.I.S" animation plays through.
  Future<bool> _runBoot(
      {Duration minSplash = const Duration(milliseconds: 2200)}) async {
    final started = DateTime.now();
    final unlocked =
        await ref.read(authServiceProvider).ensureUnlocked(widget.uid);
    if (unlocked) {
      try {
        // First transactions emission = decrypt is done; warm the derived
        // dashboard providers off the back of it. Bounded so a slow network
        // can't keep the splash up forever (skeletons remain the fallback).
        await ref
            .read(transactionsStreamProvider.future)
            .timeout(const Duration(seconds: 6));
        ref.read(analyticsProvider);
        ref.read(budgetsStreamProvider);
        ref.read(insightsProvider);
      } catch (_) {/* reveal anyway; dashboard will show its skeleton */}
    }
    final elapsed = DateTime.now().difference(started);
    if (elapsed < minSplash) await Future.delayed(minSplash - elapsed);
    return unlocked;
  }

  // After a manual unlock, skip the long splash hold — go straight in.
  void _retry() => setState(() {
        _boot = _runBoot(minSplash: Duration.zero);
      });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _boot,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const SplashScreen();
        }
        if (snap.data == true) return const RootShell();
        return _UnlockScreen(uid: widget.uid, onUnlocked: _retry);
      },
    );
  }
}

class _UnlockScreen extends ConsumerStatefulWidget {
  final String uid;
  final VoidCallback onUnlocked;
  const _UnlockScreen({required this.uid, required this.onUnlocked});

  @override
  ConsumerState<_UnlockScreen> createState() => _UnlockScreenState();
}

class _UnlockScreenState extends ConsumerState<_UnlockScreen> {
  final _pwd = TextEditingController();
  bool _busy = false;
  String? _error;

  Future<void> _unlock() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(authServiceProvider)
          .unlockWithPassword(widget.uid, _pwd.text);
      widget.onUnlocked();
    } catch (e) {
      setState(() => _error = 'Wrong password, or data could not be unlocked.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _useRecovery() async {
    final recovery = TextEditingController();
    final newPwd = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Restore with recovery key'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: recovery,
              decoration: const InputDecoration(
                  labelText: 'Recovery key', hintText: 'XXXX-XXXX-…'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: newPwd,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'New password'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(d, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(d, true),
              child: const Text('Restore')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await ref.read(authServiceProvider).restoreWithRecovery(
            uid: widget.uid,
            recoveryKey: recovery.text,
            newPassword: newPwd.text,
          );
      widget.onUnlocked();
    } catch (e) {
      setState(() => _error = 'Recovery failed — check the key and try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.lock_outline, size: 56, color: c.primary),
              const SizedBox(height: 16),
              Text('Unlock your data',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      )),
              const SizedBox(height: 6),
              Text(
                'Your transactions are end-to-end encrypted. Enter your '
                'password to unlock them on this device.',
                textAlign: TextAlign.center,
                style: TextStyle(color: c.onSurfaceVariant),
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _pwd,
                obscureText: true,
                decoration: const InputDecoration(
                    labelText: 'Password', prefixIcon: Icon(Icons.lock_outline)),
                onSubmitted: (_) => _unlock(),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: TextStyle(color: c.error)),
              ],
              const SizedBox(height: 18),
              ElevatedButton(
                onPressed: _busy ? null : _unlock,
                child: _busy
                    ? const SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Unlock'),
              ),
              TextButton(
                onPressed: _busy ? null : _useRecovery,
                child: const Text('Forgot password? Use recovery key'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
