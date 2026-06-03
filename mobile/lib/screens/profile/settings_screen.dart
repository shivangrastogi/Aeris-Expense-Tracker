import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import 'package:shared_preferences/shared_preferences.dart';

import '../../providers/auth_provider.dart';
import '../../providers/budgets_provider.dart';
import '../../providers/transactions_provider.dart';
import '../../services/app_lock_service.dart';
import '../../services/export_service.dart';
import '../../services/notification_service.dart';
import '../../services/prediction_service.dart';
import '../../services/sms_import_service.dart';
import '../../services/sms_service.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});
  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _smsGranted = false;
  bool _busy = false;
  bool _encrypting = false;
  bool _reminders = false;
  bool _exporting = false;
  bool _appLock = false;
  bool _bgAllowed = false;

  Future<void> _export() async {
    final messenger = ScaffoldMessenger.of(context);
    final txns = ref.read(transactionsStreamProvider).valueOrNull ?? const [];
    final budgets = ref.read(budgetsStreamProvider).valueOrNull ?? const [];
    if (txns.isEmpty) {
      messenger.showSnackBar(
          const SnackBar(content: Text('No transactions to export yet.')));
      return;
    }
    setState(() => _exporting = true);
    try {
      await ExportService.instance.buildAndShare(txns: txns, budgets: budgets);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Export failed: $e')));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final g = await SmsService.instance.hasPermission();
    final prefs = await SharedPreferences.getInstance();
    final lock = await AppLockService.instance.isEnabled();
    final bg = await Permission.ignoreBatteryOptimizations.isGranted;
    if (mounted) {
      setState(() {
        _smsGranted = g;
        _reminders = prefs.getBool('reminders_on') ?? false;
        _appLock = lock;
        _bgAllowed = bg;
      });
    }
  }

  /// Ask the OS to exempt AERIS from battery optimisation (one-tap system
  /// dialog). On OEMs that also gate "auto-launch", we point the user to the
  /// app's system settings page as a fallback.
  Future<void> _allowBackground() async {
    final messenger = ScaffoldMessenger.of(context);
    final status = await Permission.ignoreBatteryOptimizations.request();
    if (mounted) setState(() => _bgAllowed = status.isGranted);
    if (!status.isGranted) {
      messenger.showSnackBar(const SnackBar(
        content: Text(
            'On Realme/Xiaomi also turn on "Auto-launch" / set battery to '
            '"Unrestricted" in app settings.'),
      ));
    }
  }

  Future<void> _toggleAppLock(bool v) async {
    final messenger = ScaffoldMessenger.of(context);
    if (v) {
      if (!await AppLockService.instance.isAvailable()) {
        messenger.showSnackBar(const SnackBar(
            content: Text(
                'No biometric or device PIN set up. Add one in your phone settings first.')));
        return;
      }
      // Verify it works before turning it on.
      if (!await AppLockService.instance.authenticate('Enable app lock')) {
        return;
      }
    }
    await AppLockService.instance.setEnabled(v);
    if (mounted) setState(() => _appLock = v);
  }

  Future<void> _toggleReminders(bool v) async {
    final messenger = ScaffoldMessenger.of(context);
    final prefs = await SharedPreferences.getInstance();
    if (v) {
      final ok = await NotificationService.instance.requestPermission();
      if (!ok) {
        messenger.showSnackBar(const SnackBar(
            content: Text('Notification permission denied.')));
        return;
      }
      await NotificationService.instance.scheduleWeeklySummary();
      final txns = ref.read(transactionsStreamProvider).valueOrNull ?? const [];
      final recurring = PredictionService.instance.detectRecurring(txns);
      for (var i = 0; i < recurring.length; i++) {
        await NotificationService.instance.scheduleBillReminder(
            i, recurring[i].merchant, recurring[i].approxAmount,
            recurring[i].dayOfMonth);
      }
      messenger.showSnackBar(SnackBar(
          content: Text(
              'Reminders on — weekly summary + ${recurring.length} bill reminders.')));
    } else {
      await NotificationService.instance.cancelAll();
    }
    await prefs.setBool('reminders_on', v);
    if (mounted) setState(() => _reminders = v);
  }

  Future<void> _backfill() async {
    final uid = ref.read(currentUserIdProvider);
    if (uid == null) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final blocked = ref.read(blockedSendersProvider).valueOrNull ?? const {};
    final progress = ref.read(importProgressProvider.notifier);
    try {
      final n = await SmsImportService.instance.backfill(
        uid,
        blocked: blocked,
        days: 90,
        onProgress: (d, t) {
          if (mounted) progress.state = d >= t ? null : (done: d, total: t);
        },
      );
      messenger.showSnackBar(SnackBar(
          content: Text('Imported $n transactions from the last 90 days.')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Backfill failed: $e')));
    } finally {
      progress.state = null;
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _encryptExisting() async {
    final pwd = await _promptPassword();
    if (pwd == null || pwd.isEmpty) return;
    final uid = ref.read(currentUserIdProvider);
    if (uid == null) return;
    setState(() => _encrypting = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final rk =
          await ref.read(authServiceProvider).setupEncryptionNow(uid, pwd);
      if (rk != null && mounted) await _showRecovery(rk);
      messenger.showSnackBar(const SnackBar(
          content: Text('Your data is now end-to-end encrypted.')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Encryption failed: $e')));
    } finally {
      if (mounted) setState(() => _encrypting = false);
    }
  }

  Future<String?> _promptPassword() {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Confirm your password'),
        content: TextField(
          controller: ctrl,
          obscureText: true,
          decoration: const InputDecoration(
              labelText: 'Password',
              helperText: 'Used to derive your encryption key'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(d), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(d, ctrl.text),
              child: const Text('Encrypt')),
        ],
      ),
    );
  }

  Future<void> _showRecovery(String key) {
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
                'This is the only way to recover your data if you forget your '
                'password. Store it safely — it can\'t be shown again.',
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 12),
              SelectableText(key,
                  style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 15,
                      fontWeight: FontWeight.w700)),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () =>
                      Clipboard.setData(ClipboardData(text: key)),
                  icon: const Icon(Icons.copy, size: 16),
                  label: const Text('Copy'),
                ),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: saved,
                onChanged: (v) => setLocal(() => saved = v ?? false),
                title: const Text("I've saved it", style: TextStyle(fontSize: 13)),
              ),
            ],
          ),
          actions: [
            FilledButton(
                onPressed: saved ? () => Navigator.pop(d) : null,
                child: const Text('Done')),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final blocked = ref.watch(blockedSendersProvider).valueOrNull ?? const <String>{};
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          SwitchListTile(
            secondary: const Icon(Icons.sms),
            title: const Text('Read bank SMS automatically'),
            subtitle: Text(_smsGranted
                ? 'Granted — bank alerts become transactions automatically'
                : 'Denied — tap to request permission'),
            value: _smsGranted,
            onChanged: (v) async {
              if (v) await SmsService.instance.requestPermission();
              await _refresh();
            },
          ),
          ListTile(
            leading: const Icon(Icons.history),
            title: const Text('Backfill last 90 days'),
            subtitle: Text(_busy
                ? 'Scanning your inbox…'
                : 'Scan the inbox now for past bank SMS'),
            trailing: _busy
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.4))
                : const Icon(Icons.chevron_right),
            onTap: _busy ? null : _backfill,
          ),
          if (_busy) const LinearProgressIndicator(minHeight: 2),
          // Background-activity exemption — only relevant once SMS auto-import
          // is on. Lets the broadcast receiver keep firing when the app's closed.
          if (_smsGranted)
            ListTile(
              leading: const Icon(Icons.battery_saver_outlined),
              title: const Text('Allow background activity'),
              subtitle: Text(_bgAllowed
                  ? 'Allowed — AERIS can read bank SMS even when closed'
                  : 'Let AERIS keep reading bank SMS when the app is closed'),
              trailing: _bgAllowed
                  ? const Icon(Icons.check_circle, color: Colors.green)
                  : const Icon(Icons.chevron_right),
              onTap: _allowBackground,
            ),
          if (_smsGranted && !_bgAllowed)
            ListTile(
              dense: true,
              contentPadding: const EdgeInsets.only(left: 72, right: 16),
              title: const Text(
                  'Still missing SMS? Open app settings → set battery to '
                  '"Unrestricted" and enable Auto-launch',
                  style: TextStyle(fontSize: 12)),
              trailing: const Icon(Icons.open_in_new, size: 18),
              onTap: () => openAppSettings(),
            ),
          SwitchListTile(
            secondary: const Icon(Icons.notifications_active_outlined),
            title: const Text('Smart reminders'),
            subtitle: const Text(
                'Weekly summary + bill-due nudges from detected recurring payments'),
            value: _reminders,
            onChanged: _toggleReminders,
          ),
          ListTile(
            leading: const Icon(Icons.grid_on_outlined),
            title: const Text('Export to Excel'),
            subtitle: const Text(
                'Detailed report with charts — summary, categories, monthly trend, merchants'),
            trailing: _exporting
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.4))
                : const Icon(Icons.download_outlined),
            onTap: _exporting ? null : _export,
          ),
          const Divider(),

          // ── Blocked senders ──────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 2),
            child: Text('Blocked senders',
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700)),
          ),
          if (blocked.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 2, 16, 12),
              child: Text(
                'None yet. In “Review SMS imports”, tap “Block sender” on any '
                'junk message and it will never be counted again.',
                style: TextStyle(fontSize: 12),
              ),
            )
          else
            for (final s in blocked)
              ListTile(
                dense: true,
                leading: const Icon(Icons.block, color: Colors.orange),
                title: Text(s),
                trailing: TextButton(
                  child: const Text('Unblock'),
                  onPressed: () async {
                    final uid = ref.read(currentUserIdProvider);
                    if (uid != null) {
                      await ref
                          .read(firestoreServiceProvider)
                          .unblockSender(uid, s);
                    }
                  },
                ),
              ),

          const Divider(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 2),
            child: Text('Security',
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700)),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.fingerprint),
            title: const Text('App lock'),
            subtitle: const Text(
                'Require fingerprint / device PIN when reopening AERIS'),
            value: _appLock,
            onChanged: _toggleAppLock,
          ),
          ListTile(
            leading: const Icon(Icons.enhanced_encryption_outlined),
            title: const Text('Encrypt my existing data'),
            subtitle: const Text(
                'Re-encrypt older transactions, budgets & income on this account'),
            trailing: _encrypting
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.4))
                : const Icon(Icons.chevron_right),
            onTap: _encrypting ? null : _encryptExisting,
          ),
          const ListTile(
            leading: Icon(Icons.lock_outline),
            title: Text('Data stays on your device + your Firebase project'),
            subtitle: Text('End-to-end encrypted — we can\'t read it.'),
          ),
        ],
      ),
    );
  }
}
