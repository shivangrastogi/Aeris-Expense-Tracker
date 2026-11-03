import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../providers/auth_provider.dart';
import 'auth_widgets.dart';
import '../../widgets/recovery_key_dialog.dart';
import '../../widgets/ds.dart';

class SignupScreen extends ConsumerStatefulWidget {
  const SignupScreen({super.key});
  @override
  ConsumerState<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends ConsumerState<SignupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _pwd = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
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
      final recoveryKey = await ref.read(authServiceProvider).signUpWithEmail(
          email: _email.text,
          password: _pwd.text,
          displayName: _name.text.trim());
      if (mounted) await showRecoveryKeyDialog(context, recoveryKey);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() => _error = _friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
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
                      AuthHeader(
                        title: 'Create account',
                        subtitle:
                            "Everything is encrypted on this phone before it's backed up.",
                        onBack: Navigator.canPop(context)
                            ? () => Navigator.pop(context)
                            : null,
                      ),
                      const SizedBox(height: 20),

                      // ── Tabs ───────────────────────────────────────
                      AuthTabs(
                        isLogin: false,
                        onLoginTap: () => Navigator.pop(context),
                      ),
                      const SizedBox(height: 20),

                      // ── Fields ─────────────────────────────────────
                      AuthField(
                        controller: _name,
                        icon: Ph.user,
                        hint: 'Full name',
                        textCapitalization: TextCapitalization.words,
                        validator: (v) => (v == null || v.trim().length < 2)
                            ? 'Enter your name'
                            : null,
                      ),
                      const SizedBox(height: 16),
                      AuthField(
                        controller: _email,
                        icon: Ph.envelopeSimple,
                        hint: 'Email',
                        keyboardType: TextInputType.emailAddress,
                        validator: (v) => (v == null || !v.contains('@'))
                            ? 'Enter a valid email'
                            : null,
                      ),
                      const SizedBox(height: 16),
                      AuthField(
                        controller: _pwd,
                        icon: Ph.lock,
                        hint: 'Password',
                        placeholder: 'Create a password',
                        obscure: true,
                        onChanged: (_) => setState(() {}),
                        validator: passwordProblem,
                      ),
                      AuthPasswordRules(_pwd.text),

                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        AuthError(_error!),
                      ],

                      const SizedBox(height: 20),
                      // ── Recovery-key notice ────────────────────────
                      AuthNote(
                        icon: Ph.key,
                        text: TextSpan(children: [
                          const TextSpan(text: "Next you'll get a "),
                          TextSpan(
                            text: 'Recovery Key',
                            style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: context.tk.t1),
                          ),
                          const TextSpan(
                              text: ". It's the only way back in if you "
                                  'forget your password.'),
                        ]),
                      ),

                      const SizedBox(height: 24),
                      AuthPrimaryButton(
                        label: 'Create account',
                        busyLabel: 'Creating account…',
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
  if (s.contains('email-already-in-use')) {
    return 'That email is already registered. Try logging in.';
  }
  if (s.contains('weak-password')) return 'Choose a stronger password.';
  if (s.contains('invalid-email')) return 'That email looks invalid.';
  if (s.contains('network')) return 'Network error. Check your connection.';
  return 'Something went wrong. Please try again.';
}
