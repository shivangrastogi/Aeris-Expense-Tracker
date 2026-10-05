import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/theme.dart';
import '../../models/currency.dart';
import '../../providers/auth_provider.dart';
import '../../providers/budgets_provider.dart';
import '../../providers/currency_provider.dart';
import '../../providers/theme_provider.dart';
import '../../providers/transactions_provider.dart';
import '../../services/app_lock_service.dart';
import '../../services/backup_service.dart';
import '../../services/export_service.dart';
import '../../services/notification_service.dart';
import '../../services/prediction_service.dart';
import '../../services/sms_import_service.dart';
import '../../services/sms_service.dart';
import '../../widgets/text_input_dialog.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});
  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _smsGranted = false;
  bool _busy = false;
  bool _reminders = false;
  bool _exporting = false;
  bool _appLock = false;
  bool _bgAllowed = false;

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

  Future<void> _toggleSms(bool v) async {
    final messenger = ScaffoldMessenger.of(context);
    if (!v) {
      await openAppSettings();
      await _refresh();
      return;
    }
    final granted = await SmsService.instance.requestPermission();
    if (granted) {
      await _wireLiveSms();
      messenger.showSnackBar(const SnackBar(
          content: Text(
              'SMS auto-import is on — new bank alerts become transactions. '
              'Use "Backfill" below to import past messages.')));
    } else {
      final status = await Permission.sms.status;
      if (status.isPermanentlyDenied || status.isRestricted) {
        messenger.showSnackBar(const SnackBar(
            duration: Duration(seconds: 8),
            content: Text(
                'Android restricts SMS for sideloaded apps. Tap the ⋮ menu → '
                '"Allow restricted settings" → Permissions → SMS → Allow.')));
        await openAppSettings();
      } else {
        messenger.showSnackBar(
            const SnackBar(content: Text('SMS permission was not granted.')));
      }
    }
    await _refresh();
  }

  Future<void> _wireLiveSms() async {
    final uid = ref.read(currentUserIdProvider);
    if (uid == null) return;
    await SmsService.instance.startLiveListening(onTxn: (p) async {
      final blocked = ref.read(blockedSendersProvider).valueOrNull ?? const {};
      await SmsImportService.instance.persistOne(uid, p, blocked);
    });
  }

  Future<void> _allowBackground() async {
    final messenger = ScaffoldMessenger.of(context);
    final status = await Permission.ignoreBatteryOptimizations.request();
    if (mounted) setState(() => _bgAllowed = status.isGranted);
    if (!status.isGranted) {
      messenger.showSnackBar(const SnackBar(
        content:
            Text('On Realme/Xiaomi also turn on "Auto-launch" / set battery to '
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
                'No biometric or device PIN set up. Add one in phone settings first.')));
        return;
      }
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
        messenger.showSnackBar(
            const SnackBar(content: Text('Notification permission denied.')));
        return;
      }
      await NotificationService.instance.scheduleWeeklySummary();
      await NotificationService.instance.scheduleDailyCheckin();
      final txns = ref.read(transactionsStreamProvider).valueOrNull ?? const [];
      final recurring = PredictionService.instance.detectRecurring(txns);
      for (var i = 0; i < recurring.length; i++) {
        await NotificationService.instance.scheduleBillReminder(
            i,
            recurring[i].merchant,
            recurring[i].approxAmount,
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
    final messenger = ScaffoldMessenger.of(context);
    if (!await SmsService.instance.hasPermission()) {
      messenger.showSnackBar(const SnackBar(
          content: Text(
              'SMS permission is off — enable "Read bank SMS automatically" above first.')));
      return;
    }
    setState(() => _busy = true);
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
          content: Text(n > 0
              ? 'Imported $n transactions from the last 90 days.'
              : 'No new transactions found — last 90 days already imported.')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Backfill failed: $e')));
    } finally {
      progress.state = null;
      if (mounted) setState(() => _busy = false);
    }
  }

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

  Future<void> _backup() async {
    final messenger = ScaffoldMessenger.of(context);
    final pass = await _promptPassphrase(
        'Set a backup passphrase',
        'You\'ll need this exact passphrase to restore. It can\'t be recovered.',
        'Back up');
    if (pass == null) return;
    if (pass.length < 4) {
      messenger.showSnackBar(const SnackBar(
          content: Text('Use a passphrase of at least 4 characters.')));
      return;
    }
    final uid = ref.read(currentUserIdProvider);
    if (uid == null) return;
    messenger.showSnackBar(
        const SnackBar(content: Text('Preparing encrypted backup…')));
    try {
      await BackupService.instance.exportBackup(uid, pass);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Backup failed: $e')));
    }
  }

  Future<void> _restore() async {
    final messenger = ScaffoldMessenger.of(context);
    final pass = await _promptPassphrase('Enter the backup passphrase',
        'The passphrase you set when you created the backup.', 'Restore');
    if (pass == null || pass.isEmpty) return;
    final uid = ref.read(currentUserIdProvider);
    if (uid == null) return;
    try {
      final n = await BackupService.instance.restoreBackup(uid, pass);
      if (n < 0) return;
      messenger.showSnackBar(SnackBar(
          content: Text('Backup restored · $n transaction${n == 1 ? '' : 's'}.')));
    } catch (e) {
      messenger.showSnackBar(const SnackBar(
          content: Text('Restore failed — wrong passphrase or invalid file.')));
    }
  }

  // Shared leak-proof dialog. Passphrases are NOT trimmed (a leading/trailing
  // space could be a deliberate part of the secret).
  Future<String?> _promptPassphrase(
          String title, String helper, String action) =>
      promptText(
        context,
        title: title,
        helper: helper,
        confirmLabel: action,
        obscure: true,
        trim: false,
      );

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeProvider);
    final currency = ref.watch(currencyProvider);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;
    final cardBg = dark ? const Color(0xFF122120) : Colors.white;
    final divColor = scheme.onSurface.withValues(alpha: 0.07);
    final blocked =
        ref.watch(blockedSendersProvider).valueOrNull ?? const <String>{};

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          // ── Appearance ──────────────────────────────────────────────────────
          _group(context, 'Appearance', cardBg, divColor, [
            _ThemePicker(
              current: themeMode,
              onChanged: (m) => ref.read(themeModeProvider.notifier).setMode(m),
            ),
            _divider(divColor),
            _chevronRow(
              Icons.currency_rupee,
              'Currency',
              '${currency.name} '
                  '(${currency.symbol.trim().isEmpty ? currency.code : currency.symbol.trim()})',
              scheme,
              () => _showCurrencySheet(context),
            ),
          ]),

          // ── SMS auto-import ─────────────────────────────────────────────────
          _group(context, 'SMS auto-import', cardBg, divColor, [
            _toggleRow(
              Icons.sms_outlined,
              'Read bank SMS automatically',
              'Parsed on-device, encrypted',
              _smsGranted,
              _toggleSms,
              scheme,
            ),
            _divider(divColor),
            _chevronRow(
              Icons.history,
              'Backfill last 90 days',
              _busy ? 'Scanning inbox…' : 'Re-scan inbox → import',
              scheme,
              _busy ? null : _backfill,
              trailing: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : null,
            ),
            if (_smsGranted) ...[
              _divider(divColor),
              _chevronRow(
                Icons.battery_saver_outlined,
                'Allow background activity',
                _bgAllowed
                    ? 'Allowed — reads SMS when app is closed'
                    : 'Keep SMS receiver alive when closed',
                scheme,
                _allowBackground,
                trailing: _bgAllowed
                    ? Icon(Icons.check_circle_rounded,
                        color: AerisColors.moneyIn(context), size: 20)
                    : null,
              ),
            ],
          ]),

          // ── Notifications ───────────────────────────────────────────────────
          _group(context, 'Notifications', cardBg, divColor, [
            _toggleRow(
              Icons.notifications_outlined,
              'Smart reminders',
              'Summaries, bills, check-ins, alerts',
              _reminders,
              _toggleReminders,
              scheme,
            ),
          ]),

          // ── Security & data ─────────────────────────────────────────────────
          _group(context, 'Security & data', cardBg, divColor, [
            _toggleRow(
              Icons.fingerprint,
              'App lock',
              'Biometric / PIN over the app',
              _appLock,
              _toggleAppLock,
              scheme,
            ),
            _divider(divColor),
            _chevronRow(
              Icons.enhanced_encryption_outlined,
              'Encrypted backup',
              'Passphrase-protected export',
              scheme,
              _backup,
            ),
            _divider(divColor),
            _chevronRow(
              Icons.restore_page_outlined,
              'Restore from backup',
              'Import from an AERIS backup file',
              scheme,
              _restore,
            ),
            if (blocked.isNotEmpty) ...[
              _divider(divColor),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                child: Text('Blocked senders',
                    style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        color: scheme.onSurface.withValues(alpha: 0.45))),
              ),
              for (final s in blocked) ...[
                _divider(divColor),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: Row(children: [
                    const Icon(Icons.block, color: Colors.orange, size: 18),
                    const SizedBox(width: 12),
                    Expanded(
                        child: Text(s,
                            style: const TextStyle(
                                fontSize: 13.5, fontWeight: FontWeight.w600))),
                    TextButton(
                      onPressed: () async {
                        final uid = ref.read(currentUserIdProvider);
                        if (uid != null) {
                          await ref
                              .read(firestoreServiceProvider)
                              .unblockSender(uid, s);
                        }
                      },
                      child: const Text('Unblock'),
                    ),
                  ]),
                ),
              ],
            ],
          ]),

          // ── Export ──────────────────────────────────────────────────────────
          _group(context, 'Export', cardBg, divColor, [
            _chevronRow(
              Icons.table_view_outlined,
              'Export to Excel',
              'Styled .xlsx — summary, categories, trend, merchants',
              scheme,
              _exporting ? null : _export,
              trailing: _exporting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.ios_share_rounded, size: 18),
            ),
          ]),
        ],
      ),
    );
  }

  // ── Group container ──────────────────────────────────────────────────────────

  Widget _group(BuildContext context, String title, Color cardBg,
      Color divColor, List<Widget> children) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
            child: Text(title.toUpperCase(),
                style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.06,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.48))),
          ),
          Container(
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: divColor),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 8,
                    offset: const Offset(0, 2)),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Column(children: children),
            ),
          ),
        ],
      ),
    );
  }

  Widget _divider(Color c) => Container(
      height: 1, color: c, margin: const EdgeInsets.symmetric(horizontal: 14));

  Widget _toggleRow(
    IconData icon,
    String label,
    String sub,
    bool value,
    Future<void> Function(bool) onChanged,
    ColorScheme scheme,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      child: Row(
        children: [
          Icon(icon, size: 21, color: scheme.onSurface.withValues(alpha: 0.6)),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w700)),
                Text(sub,
                    style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurface.withValues(alpha: 0.5))),
              ],
            ),
          ),
          _Toggle(on: value, onChanged: onChanged),
        ],
      ),
    );
  }

  Widget _chevronRow(
    IconData icon,
    String label,
    String sub,
    ColorScheme scheme,
    VoidCallback? onTap, {
    Widget? trailing,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        child: Row(
          children: [
            Icon(icon,
                size: 21, color: scheme.onSurface.withValues(alpha: 0.6)),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w700)),
                  Text(sub,
                      style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: scheme.onSurface.withValues(alpha: 0.5))),
                ],
              ),
            ),
            trailing ??
                Icon(Icons.chevron_right_rounded,
                    size: 18, color: scheme.onSurface.withValues(alpha: 0.35)),
          ],
        ),
      ),
    );
  }

  void _showCurrencySheet(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final bg = dark ? const Color(0xFF122120) : Colors.white;
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      backgroundColor: bg,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) {
        final scheme = Theme.of(ctx).colorScheme;
        final selected = ref.read(currencyProvider).code;
        return SafeArea(
          top: false,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 16),
            shrinkWrap: true,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
                child: Text(
                  'Amounts are stored once and shown in your chosen '
                  'currency. Indian grouping (lakh/crore) is used for ₹.',
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurface.withValues(alpha: 0.6)),
                ),
              ),
              for (final c in Currencies.all)
                InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () {
                    ref.read(currencyProvider.notifier).setCurrency(c.code);
                    Navigator.pop(ctx);
                  },
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 2),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 13),
                    decoration: BoxDecoration(
                      color: c.code == selected
                          ? AerisColors.seed.withValues(alpha: 0.12)
                          : null,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Text(c.flag, style: const TextStyle(fontSize: 24)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(c.name,
                                  style: const TextStyle(
                                      fontSize: 14.5,
                                      fontWeight: FontWeight.w800)),
                              Text(
                                '${c.code} · '
                                '${c.symbol.trim().isEmpty ? c.code : c.symbol.trim()}',
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: scheme.onSurface
                                        .withValues(alpha: 0.5)),
                              ),
                            ],
                          ),
                        ),
                        if (c.code == selected)
                          const Icon(Icons.check_circle_rounded,
                              color: AerisColors.seed, size: 22),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

// ── Theme picker (segmented pill) ─────────────────────────────────────────────

class _ThemePicker extends StatelessWidget {
  final ThemeMode current;
  final ValueChanged<ThemeMode> onChanged;

  const _ThemePicker({required this.current, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    const modes = [
      (ThemeMode.light, 'Light', Icons.light_mode_rounded),
      (ThemeMode.dark, 'Dark', Icons.dark_mode_rounded),
      (ThemeMode.system, 'System', Icons.contrast_rounded),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Theme',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
          const SizedBox(height: 9),
          Container(
            height: 52,
            decoration: BoxDecoration(
              color: scheme.onSurface.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: modes.map((m) {
                final active = current == m.$1;
                return Expanded(
                  child: GestureDetector(
                    onTap: () => onChanged(m.$1),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.all(4),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: active ? AerisColors.seed : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: active
                            ? [
                                BoxShadow(
                                    color:
                                        AerisColors.seed.withValues(alpha: 0.3),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2))
                              ]
                            : null,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(m.$3,
                              size: 15,
                              color: active
                                  ? Colors.white
                                  : scheme.onSurface.withValues(alpha: 0.6)),
                          const SizedBox(width: 5),
                          Text(m.$2,
                              style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: active
                                      ? Colors.white
                                      : scheme.onSurface
                                          .withValues(alpha: 0.7))),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Custom toggle switch ───────────────────────────────────────────────────────

class _Toggle extends StatelessWidget {
  final bool on;
  final Future<void> Function(bool) onChanged;

  const _Toggle({required this.on, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: () => onChanged(!on),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 46,
        height: 28,
        decoration: BoxDecoration(
          color:
              on ? AerisColors.seed : scheme.onSurface.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(99),
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 200),
          alignment: on ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            margin: const EdgeInsets.all(3),
            width: 22,
            height: 22,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                    color: Colors.black26, blurRadius: 4, offset: Offset(0, 1))
              ],
            ),
          ),
        ),
      ),
    );
  }
}
