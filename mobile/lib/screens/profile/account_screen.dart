import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/routes.dart';
import '../../core/theme.dart';
import '../../providers/auth_provider.dart';
import '../../providers/village_provider.dart';
import '../../widgets/aeris_toast.dart';
import '../../widgets/recovery_key_dialog.dart';
import '../../widgets/text_input_dialog.dart';
import '../auth/auth_widgets.dart';
import 'profile_screen.dart';
import '../../widgets/ds.dart';

/// Account & security: who's signed in, password, recovery key, sign out,
/// and deleting the account with all its data.
class AccountScreen extends ConsumerStatefulWidget {
  const AccountScreen({super.key});

  @override
  ConsumerState<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends ConsumerState<AccountScreen> {
  bool _busy = false;

  void _toast(String m) =>
      ScaffoldMessenger.of(context).showToast(SnackBar(content: Text(m)));

  String _err(Object e) => '$e'.replaceFirst('Exception: ', '');

  Future<void> _changePassword() async {
    final r = await showDialog<({String current, String next})>(
      context: context,
      builder: (_) => const _ChangePasswordDialog(),
    );
    if (r == null) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(authServiceProvider)
          .changePassword(current: r.current, next: r.next);
      _toast('Password changed — it now unlocks your data too');
    } catch (e) {
      _toast(_err(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _newRecoveryKey() async {
    final pw = await promptText(context,
        title: 'Make a new recovery key',
        hint: 'Your password',
        helper: 'Your current recovery key will stop working.',
        obscure: true,
        trim: false,
        confirmLabel: 'Continue');
    if (pw == null || pw.isEmpty || !mounted) return;
    setState(() => _busy = true);
    try {
      final key = await ref.read(authServiceProvider).regenerateRecoveryKey(pw);
      if (mounted) await showRecoveryKeyDialog(context, key, replacing: true);
    } catch (e) {
      _toast(_err(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteAccount() async {
    final pw = await showDialog<String>(
      context: context,
      builder: (_) => const _DeleteAccountDialog(),
    );
    if (pw == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref.read(authServiceProvider).deleteAccount(pw);
      ref.invalidate(villageProvider);
      if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    } catch (e) {
      _toast(_err(e));
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tk = context.tk;
    final profile = ref.watch(userProfileProvider).valueOrNull;
    String? email;
    try {
      email = ref.read(authServiceProvider).currentUser?.email;
    } catch (_) {/* auth not ready (e.g. tests) — show the generic line */}
    final name = (profile?.displayName ?? '').trim();

    Widget group(String head, List<Widget> rows) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
              child: Overline(head),
            ),
            ListGroup(inset: 64, children: rows),
          ],
        );

    return Scaffold(
      appBar: AppBar(title: const Text('Account and security')),
      body: AbsorbPointer(
        absorbing: _busy,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
          children: [
            if (_busy)
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: Center(child: RisingLoader()),
              ),
            AerisCard(
              padding: const EdgeInsets.all(16),
              onTap: () => Navigator.pushNamed(context, AppRoutes.editProfile),
              child: Row(children: [
                InitialAvatar(name.isEmpty ? (email ?? '?') : name,
                    size: 48, color: const Color(0xFF8A7ED3)),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name.isEmpty ? 'Your account' : name,
                            style: Ts.title.copyWith(color: tk.t1)),
                        Text(email ?? 'Signed in',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Ts.bodyS.copyWith(color: tk.t2)),
                      ]),
                ),
                Icon(Ph.caretRight, size: 16, color: tk.t3),
              ]),
            ),
            const SizedBox(height: 18),
            group('Security', [
              SettingsRow(
                  icon: Ph.password,
                  title: 'Change password',
                  sub: 'Also re-locks your encrypted data with it',
                  onTap: _busy ? null : _changePassword),
              SettingsRow(
                  icon: Ph.key,
                  title: 'Make a new recovery key',
                  sub: 'Lost the old one? Replace it',
                  onTap: _busy ? null : _newRecoveryKey),
            ]),
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 10, 4, 0),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2, right: 8),
                  child: Icon(Ph.info, size: 15, color: tk.t2),
                ),
                Expanded(
                  child: Text(
                      'Two locks protect you. Your password (or recovery key) '
                      'unlocks your encrypted data on a new phone. App lock '
                      '(Settings) is your fingerprint or PIN each time you '
                      'open the app on this phone.',
                      style: Ts.label.copyWith(
                          fontWeight: FontWeight.w400,
                          height: 18 / 12,
                          color: tk.t2)),
                ),
              ]),
            ),
            const SizedBox(height: 18),
            group('Session', [
              SettingsRow(
                  icon: Ph.signOut,
                  title: 'Sign out',
                  onTap: _busy ? null : () => confirmSignOut(context, ref)),
              SettingsRow(
                  icon: Ph.trash,
                  title: 'Delete account',
                  sub: 'Erases everything, everywhere',
                  iconColor: tk.bad,
                  titleColor: tk.bad,
                  onTap: _busy ? null : _deleteAccount),
            ]),
          ],
        ),
      ),
    );
  }
}

class _ChangePasswordDialog extends StatefulWidget {
  const _ChangePasswordDialog();

  @override
  State<_ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<_ChangePasswordDialog> {
  final _form = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _again = TextEditingController();

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _again.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Change password'),
        content: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              AuthField(
                  controller: _current,
                  icon: Ph.lockSimple,
                  hint: 'Current password',
                  obscure: true,
                  validator: (v) =>
                      (v == null || v.isEmpty) ? 'Enter your password' : null),
              const SizedBox(height: 10),
              AuthField(
                  controller: _next,
                  icon: Ph.lockKey,
                  hint: 'New password',
                  obscure: true,
                  validator: passwordProblem),
              const SizedBox(height: 10),
              AuthField(
                  controller: _again,
                  icon: Ph.lockKey,
                  hint: 'New password again',
                  obscure: true,
                  validator: (v) =>
                      v != _next.text ? 'The passwords don\'t match' : null),
            ]),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              if (_form.currentState?.validate() ?? false) {
                Navigator.pop(context, (current: _current.text, next: _next.text));
              }
            },
            child: const Text('Change'),
          ),
        ],
      );
}

class _DeleteAccountDialog extends StatefulWidget {
  const _DeleteAccountDialog();

  @override
  State<_DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<_DeleteAccountDialog> {
  final _pw = TextEditingController();
  bool _understood = false;

  @override
  void initState() {
    super.initState();
    _pw.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _pw.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final danger = AerisColors.danger(context);
    return AlertDialog(
      icon: Icon(Ph.warning, color: danger),
      title: const Text('Delete your account?'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text(
              'This permanently erases every transaction, budget, goal, '
              'shared bill and setting in your account, and the account '
              'itself. It can\'t be undone. Export to Excel first if you '
              'want a copy.',
              style: TextStyle(fontSize: 13.5)),
          const SizedBox(height: 14),
          AuthField(
              controller: _pw,
              icon: Ph.lockSimple,
              hint: 'Your password',
              obscure: true),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: _understood,
            onChanged: (v) => setState(() => _understood = v ?? false),
            title: const Text('I understand this is permanent',
                style: TextStyle(fontSize: 13)),
          ),
        ]),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Keep my account')),
        FilledButton(
          style: FilledButton.styleFrom(
              backgroundColor: danger, foregroundColor: context.tk.isDark ? const Color(0xFF1A0F0E) : Colors.white),
          onPressed: _understood && _pw.text.isNotEmpty
              ? () => Navigator.pop(context, _pw.text)
              : null,
          child: const Text('Delete forever'),
        ),
      ],
    );
  }
}
