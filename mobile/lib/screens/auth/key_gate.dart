import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/analytics_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/budgets_provider.dart';
import '../../providers/insights_provider.dart';
import '../../providers/transactions_provider.dart';
import '../home/root_shell.dart';
import '../splash_screen.dart';
import '../../core/theme.dart';
import '../../widgets/ds.dart';
import 'auth_widgets.dart';

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
  /// already populated instead of flashing skeletons. The splash holds for a
  /// short minimum only so the "A.E.R.I.S" word finishes typing (~0.6s);
  /// real work (unlock + decrypt) is what normally decides how long it shows.
  Future<bool> _runBoot(
      {Duration minSplash = const Duration(milliseconds: 650)}) async {
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
    final tk = context.tk;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 32),
                      Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                            color: tk.accSoft,
                            borderRadius: BorderRadius.circular(18)),
                        child: Icon(Ph.lockKey, size: 30, color: tk.acc),
                      ),
                      const SizedBox(height: 20),
                      const AuthHeader(
                        title: 'Unlock your data',
                        subtitle:
                            'Your transactions are end-to-end encrypted. Enter '
                            'your password to unlock them on this phone.',
                      ),
                      const SizedBox(height: 24),
                      Text('Password',
                          style: Ts.label.copyWith(color: tk.t2)),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _pwd,
                        obscureText: true,
                        style: TextStyle(fontSize: 15, color: tk.t1),
                        decoration: InputDecoration(
                          hintText: 'Your password',
                          errorText: _error == null ? null : ' ',
                          errorStyle: const TextStyle(height: 0, fontSize: 0),
                        ),
                        onSubmitted: (_) => _unlock(),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 10),
                        AuthError(_error!),
                      ],
                    ],
                  ),
                ),
              ),
              AuthPrimaryButton(
                label: 'Unlock',
                busyLabel: 'Unlocking…',
                busy: _busy,
                onPressed: _unlock,
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: _busy ? null : _useRecovery,
                style: TextButton.styleFrom(minimumSize: const Size(0, 48)),
                child: const Text('Forgot password? Use recovery key'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
