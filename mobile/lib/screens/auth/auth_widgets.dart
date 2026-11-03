import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../widgets/ds.dart';

/// Shared chrome for the login & signup screens (AERIS Onboarding Flow):
/// a segmented Log in / Sign up switch, labelled 56 dp fields, a 48 dp
/// primary button with the rising-line loader, and the encryption footer.

// ── Log in / Sign up segmented control ───────────────────────────────────────
class AuthTabs extends StatelessWidget {
  final bool isLogin;
  final VoidCallback? onLoginTap;
  final VoidCallback? onSignupTap;

  const AuthTabs({
    super.key,
    required this.isLogin,
    this.onLoginTap,
    this.onSignupTap,
  });

  @override
  Widget build(BuildContext context) => DsSegmented(
        labels: const ['Log in', 'Sign up'],
        index: isLogin ? 0 : 1,
        onChanged: (i) => (i == 0 ? onLoginTap : onSignupTap)?.call(),
      );
}

/// What's wrong with a NEW password, or null if it's fine. (Login accepts
/// older 6-character passwords; new ones must be stronger, because the
/// password also protects the encrypted data.)
String? passwordProblem(String? v) {
  final s = v ?? '';
  if (s.length < 8) return 'Use at least 8 characters';
  if (!RegExp(r'[A-Za-z]').hasMatch(s) || !RegExp(r'\d').hasMatch(s)) {
    return 'Mix letters and numbers';
  }
  return null;
}

// ── Labelled input field ─────────────────────────────────────────────────────
class AuthField extends StatefulWidget {
  final TextEditingController controller;

  /// Kept for callers; the design labels fields instead of icon-prefixing.
  final IconData icon;

  /// The label shown above the field.
  final String hint;

  /// Placeholder inside the field (optional).
  final String? placeholder;

  /// A password: hidden, with a show/hide eye.
  final bool obscure;
  final TextInputType? keyboardType;
  final TextCapitalization textCapitalization;
  final String? Function(String?)? validator;
  final ValueChanged<String>? onChanged;

  /// Shown under the field (e.g. password rules).
  final String? helper;

  const AuthField({
    super.key,
    required this.controller,
    required this.icon,
    required this.hint,
    this.placeholder,
    this.obscure = false,
    this.keyboardType,
    this.textCapitalization = TextCapitalization.none,
    this.validator,
    this.onChanged,
    this.helper,
  });

  @override
  State<AuthField> createState() => _AuthFieldState();
}

class _AuthFieldState extends State<AuthField> {
  bool _hidden = true;

  @override
  Widget build(BuildContext context) {
    final tk = context.tk;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(widget.hint, style: Ts.label.copyWith(color: tk.t2)),
      ),
      TextFormField(
        controller: widget.controller,
        obscureText: widget.obscure && _hidden,
        keyboardType: widget.keyboardType,
        textCapitalization: widget.textCapitalization,
        validator: widget.validator,
        onChanged: widget.onChanged,
        style: TextStyle(fontSize: 15, color: tk.t1),
        decoration: InputDecoration(
          hintText: widget.placeholder,
          helperText: widget.helper,
          helperMaxLines: 2,
          errorMaxLines: 2,
          suffixIcon: widget.obscure
              ? IconButton(
                  tooltip: _hidden ? 'Show password' : 'Hide password',
                  icon: Icon(_hidden ? Ph.eye : Ph.eyeSlash,
                      size: 20, color: tk.t2),
                  onPressed: () => setState(() => _hidden = !_hidden),
                )
              : null,
        ),
      ),
    ]);
  }
}

/// Live password rules: 8+ characters, a letter, a number. Each turns into a
/// green check as it's met (icon + word, never colour alone).
class AuthPasswordRules extends StatelessWidget {
  final String value;
  const AuthPasswordRules(this.value, {super.key});

  @override
  Widget build(BuildContext context) {
    final tk = context.tk;
    final rules = [
      ('8+ characters', value.length >= 8),
      ('A letter', RegExp(r'[A-Za-z]').hasMatch(value)),
      ('A number', RegExp(r'\d').hasMatch(value)),
    ];
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (final (label, ok) in rules)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(children: [
              Icon(ok ? PhFill.checkCircle : Ph.circle,
                  size: 16, color: ok ? tk.ok : tk.t3),
              const SizedBox(width: 8),
              Text(label,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: ok ? tk.t1 : tk.t2)),
            ]),
          ),
      ]),
    );
  }
}

/// A soft accent note with an icon ("Next you'll get a Recovery Key…").
class AuthNote extends StatelessWidget {
  final IconData icon;
  final InlineSpan text;
  const AuthNote({super.key, required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final tk = context.tk;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: tk.accSoft,
        borderRadius: BorderRadius.circular(Rad.input),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 20, color: tk.acc),
        const SizedBox(width: 12),
        Expanded(
          child: Text.rich(text,
              style: TextStyle(fontSize: 13, height: 1.45, color: tk.t1)),
        ),
      ]),
    );
  }
}

// ── Full-width primary button with busy state ────────────────────────────────
class AuthPrimaryButton extends StatelessWidget {
  final String label;
  final String? busyLabel;
  final bool busy;
  final VoidCallback? onPressed;

  const AuthPrimaryButton({
    super.key,
    required this.label,
    this.busyLabel,
    required this.busy,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final tk = context.tk;
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: FilledButton(
        onPressed: busy ? null : onPressed,
        style: busy
            ? FilledButton.styleFrom(
                disabledBackgroundColor: tk.acc,
                disabledForegroundColor: tk.onAcc)
            : null,
        child: busy
            ? Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  RisingLoader(color: tk.onAcc),
                  const SizedBox(width: 10),
                  Text(busyLabel ?? label),
                ],
              )
            : Text(label),
      ),
    );
  }
}

// ── Bottom reassurance line ──────────────────────────────────────────────────
class AuthFooter extends StatelessWidget {
  const AuthFooter({super.key});

  @override
  Widget build(BuildContext context) {
    final tk = context.tk;
    return Center(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Ph.lockSimple, size: 14, color: tk.t2),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              'End-to-end encrypted · your data stays yours',
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w600, color: tk.t2),
            ),
          ),
        ],
      ),
    );
  }
}

/// The auth page frame: back arrow, 28/700 title, a sub-line.
class AuthHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final VoidCallback? onBack;
  const AuthHeader(
      {super.key, required this.title, required this.subtitle, this.onBack});

  @override
  Widget build(BuildContext context) {
    final tk = context.tk;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (onBack != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: IconButton(
            onPressed: onBack,
            tooltip: 'Back',
            icon: Icon(Ph.arrowLeft, size: 22, color: tk.t1),
          ),
        ),
      Text(title,
          style: TextStyle(
              fontSize: 28,
              height: 34 / 28,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.5,
              color: tk.t1)),
      const SizedBox(height: 6),
      Text(subtitle, style: Ts.bodyS.copyWith(color: tk.t2)),
    ]);
  }
}

/// A form-level error: red icon + words (never colour alone).
class AuthError extends StatelessWidget {
  final String text;
  const AuthError(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    final tk = context.tk;
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(PhFill.warningCircle, size: 16, color: tk.bad),
      const SizedBox(width: 6),
      Expanded(
        child: Text(text,
            style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w600, color: tk.bad)),
      ),
    ]);
  }
}
