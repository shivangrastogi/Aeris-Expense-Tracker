import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../models/avatar_skin.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/aeris_avatar.dart';
import 'auth_widgets.dart';

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
      if (mounted) await _showRecoveryKey(recoveryKey);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() => _error = _friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showRecoveryKey(String key) {
    bool saved = false;
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (d) => StatefulBuilder(
        builder: (d, setLocal) => AlertDialog(
          title: const Text('Save your recovery key'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Your data is end-to-end encrypted — not even we can read it. '
                'If you forget your password, this key is the ONLY way to get '
                'your transactions back. Store it somewhere safe; we can\'t '
                'show it again or recover it for you.',
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .surfaceContainerHighest
                      .withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final block in key.split('-'))
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .surface
                              .withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          block,
                          style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 2),
                        ),
                      ),
                  ],
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: key));
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Recovery key copied')));
                  },
                  icon: const Icon(Icons.copy, size: 16),
                  label: const Text('Copy'),
                ),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: saved,
                onChanged: (v) => setLocal(() => saved = v ?? false),
                title: const Text("I've saved my recovery key",
                    style: TextStyle(fontSize: 13)),
              ),
            ],
          ),
          actions: [
            FilledButton(
              onPressed: saved ? () => Navigator.pop(d) : null,
              child: const Text('Continue'),
            ),
          ],
        ),
      ),
    );
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
                      const Text('Create account',
                          style: TextStyle(
                              fontSize: 27,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.8)),
                      const SizedBox(height: 6),
                      Text(
                        "We'll generate your encryption keys & recovery key.",
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: c.onSurfaceVariant),
                      ),
                      const SizedBox(height: 24),

                      // ── Tabs ───────────────────────────────────────
                      AuthTabs(
                        isLogin: false,
                        onLoginTap: () => Navigator.pop(context),
                      ),
                      const SizedBox(height: 20),

                      // ── Fields ─────────────────────────────────────
                      AuthField(
                        controller: _name,
                        icon: Icons.person_outline,
                        hint: 'Full name',
                        textCapitalization: TextCapitalization.words,
                        validator: (v) => (v == null || v.trim().length < 2)
                            ? 'Enter your name'
                            : null,
                      ),
                      const SizedBox(height: 12),
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

                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Text(_error!,
                            style: TextStyle(color: c.error, fontSize: 13)),
                      ],

                      const SizedBox(height: 22),
                      AuthPrimaryButton(
                        label: 'Create account',
                        busyLabel: 'Creating account…',
                        busy: _busy,
                        onPressed: _submit,
                      ),

                      const SizedBox(height: 18),
                      // ── Recovery-key notice ────────────────────────
                      Container(
                        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                        decoration: BoxDecoration(
                          color: AerisColors.info.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.vpn_key_outlined,
                                size: 20, color: AerisColors.info),
                            const SizedBox(width: 9),
                            Expanded(
                              child: Text.rich(
                                TextSpan(
                                  style: TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w600,
                                      height: 1.5,
                                      color: c.onSurfaceVariant),
                                  children: [
                                    const TextSpan(text: "You'll see a "),
                                    TextSpan(
                                      text: 'Recovery Key',
                                      style: TextStyle(
                                          fontWeight: FontWeight.w800,
                                          color: c.onSurface),
                                    ),
                                    const TextSpan(
                                        text:
                                            ' next — the only way back in if you '
                                            'forget your password.'),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
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
