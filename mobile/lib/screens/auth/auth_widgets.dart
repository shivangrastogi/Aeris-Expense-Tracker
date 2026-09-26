import 'package:flutter/material.dart';

import '../../core/theme.dart';

/// Shared chrome for the login & signup screens so both match the new GUI
/// exactly (segmented tab, fields, primary button, footer).

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
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: c.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.onSurface.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: [
          _tab(context, 'Log in', isLogin, isLogin ? null : onLoginTap),
          _tab(context, 'Sign up', !isLogin, !isLogin ? null : onSignupTap),
        ],
      ),
    );
  }

  Widget _tab(
      BuildContext context, String label, bool active, VoidCallback? onTap) {
    final c = Theme.of(context).colorScheme;
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 11),
          decoration: BoxDecoration(
            color: active
                ? AerisColors.seed.withValues(alpha: 0.22)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: active
                ? Border.all(color: AerisColors.seed.withValues(alpha: 0.45))
                : null,
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: active ? c.onSurface : c.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

// ── Icon + input field ───────────────────────────────────────────────────────
class AuthField extends StatelessWidget {
  final TextEditingController controller;
  final IconData icon;
  final String hint;
  final bool obscure;
  final TextInputType? keyboardType;
  final TextCapitalization textCapitalization;
  final String? Function(String?)? validator;

  const AuthField({
    super.key,
    required this.controller,
    required this.icon,
    required this.hint,
    this.obscure = false,
    this.keyboardType,
    this.textCapitalization = TextCapitalization.none,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboardType,
      textCapitalization: textCapitalization,
      validator: validator,
      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: Icon(icon, size: 20, color: c.onSurfaceVariant),
        filled: true,
        fillColor: c.surfaceContainerHighest.withValues(alpha: 0.45),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: c.onSurface.withValues(alpha: 0.10)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AerisColors.seed, width: 1.4),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: c.error.withValues(alpha: 0.7)),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: c.error),
        ),
      ),
    );
  }
}

// ── Full-width primary button with busy state ────────────────────────────────
class AuthPrimaryButton extends StatelessWidget {
  final String label;
  final String? busyLabel;
  final bool busy;
  final VoidCallback onPressed;

  const AuthPrimaryButton({
    super.key,
    required this.label,
    this.busyLabel,
    required this.busy,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        onPressed: busy ? null : onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: AerisColors.seed,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AerisColors.seed.withValues(alpha: 0.6),
          disabledForegroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle:
              const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800),
        ),
        child: busy
            ? Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.5, color: Colors.white),
                  ),
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
    final c = Theme.of(context).colorScheme;
    final color = c.onSurface.withValues(alpha: 0.4);
    return Center(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.lock_outline, size: 15, color: color),
          const SizedBox(width: 7),
          Text(
            'End-to-end encrypted · your data stays yours',
            style: TextStyle(
                fontSize: 11.5, fontWeight: FontWeight.w600, color: color),
          ),
        ],
      ),
    );
  }
}
