import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/routes.dart';
import '../../core/theme.dart';
import '../../models/avatar_skin.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/aeris_avatar.dart';
import 'auth_widgets.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});
  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _pwd = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _pwd.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authServiceProvider).signInWithEmail(
            email: _email.text,
            password: _pwd.text,
          );
    } catch (e) {
      setState(() => _error = _friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _forgotPassword() async {
    final ctrl = TextEditingController(text: _email.text.trim());
    final email = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Reset password',
            style: TextStyle(fontWeight: FontWeight.w800)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "We'll email you a link to set a new password. Your encrypted "
              'vault still needs your Recovery Key to unlock.',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: ctrl,
              autofocus: true,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'Email',
                prefixIcon: Icon(Icons.mail_outline),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(d), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(d, ctrl.text.trim()),
            child: const Text('Send link'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (email == null || email.isEmpty || !email.contains('@')) return;
    try {
      await ref.read(authServiceProvider).sendPasswordReset(email);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Reset link sent to $email')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(_friendlyError(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 14),
                      // ── Brand ──────────────────────────────────────
                      Row(
                        children: [
                          SizedBox(
                            width: 48,
                            height: 48,
                            child: AerisAvatar(
                              skin: Avatars.byId('sprout'),
                              stage: 1,
                              mood: AvatarMood.happy,
                              size: 48,
                              glow: false,
                              animate: true,
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Text('A.E.R.I.S',
                              style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.5)),
                        ],
                      ),
                      const SizedBox(height: 32),
                      const Text('Welcome back',
                          style: TextStyle(
                              fontSize: 27,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.8)),
                      const SizedBox(height: 6),
                      Text(
                        'Your password also unlocks your encrypted vault.',
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: c.onSurfaceVariant),
                      ),
                      const SizedBox(height: 24),

                      // ── Tabs ───────────────────────────────────────
                      AuthTabs(
                        isLogin: true,
                        onSignupTap: () =>
                            Navigator.pushNamed(context, AppRoutes.signup),
                      ),
                      const SizedBox(height: 20),

                      // ── Fields ─────────────────────────────────────
                      AuthField(
                        controller: _email,
                        icon: Icons.mail_outline,
                        hint: 'Email',
                        keyboardType: TextInputType.emailAddress,
                        validator: (v) => (v == null || !v.contains('@'))
                            ? 'Enter a valid email'
                            : null,
                      ),
                      const SizedBox(height: 12),
                      AuthField(
                        controller: _pwd,
                        icon: Icons.lock_outline,
                        hint: 'Password',
                        obscure: true,
                        validator: (v) => (v == null || v.length < 6)
                            ? 'Min 6 characters'
                            : null,
                      ),

                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: _forgotPassword,
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: Text('Forgot password?',
                              style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: AerisColors.ink(context))),
                        ),
                      ),

                      if (_error != null) ...[
                        const SizedBox(height: 4),
                        Text(_error!,
                            style: TextStyle(color: c.error, fontSize: 13)),
                      ],

                      const SizedBox(height: 18),
                      AuthPrimaryButton(
                        label: 'Log in',
                        busyLabel: 'Unlocking vault…',
                        busy: _busy,
                        onPressed: _submit,
                      ),

                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(24, 8, 24, 16),
                child: AuthFooter(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _friendlyError(Object e) {
  final s = e.toString();
  if (s.contains('wrong-password') || s.contains('invalid-credential')) {
    return 'Incorrect email or password.';
  }
  if (s.contains('user-not-found')) return 'No account with that email.';
  if (s.contains('too-many-requests')) {
    return 'Too many attempts. Try again later.';
  }
  if (s.contains('network')) return 'Network error. Check your connection.';
  return 'Something went wrong. Please try again.';
}
