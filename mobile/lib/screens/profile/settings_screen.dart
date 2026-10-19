import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/routes.dart';
import '../../core/theme.dart';
import '../../models/currency.dart';
import '../../providers/auth_provider.dart';
import '../../providers/budgets_provider.dart';
import '../../providers/currency_provider.dart';
import '../../providers/money_providers.dart';
import '../../providers/setup_provider.dart';
import '../../providers/theme_provider.dart';
import '../../providers/transactions_provider.dart';
import '../../services/app_lock_service.dart';
import '../../services/backup_service.dart';
import '../../services/export_service.dart';
import '../../services/notification_intake.dart';
import '../../services/reminder_scheduler.dart';
import '../../services/sms_import_service.dart';
import '../../services/sms_service.dart';
import '../../utils/formatters.dart';
import '../../widgets/text_input_dialog.dart';
import '../../widgets/aeris_toast.dart';
import '../../widgets/privacy_shield.dart';
import 'about_screen.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});
  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen>
    with WidgetsBindingObserver {
  bool _smsGranted = false;
  bool _notifAccess = false;
  bool _autoConfirm = true;
  final _kindOn = <String, bool>{};

  static const _lowBalancePresets = [0, 500, 1000, 2000, 5000, 10000];
  bool _busy = false;
  bool _reminders = false;
  bool _exporting = false;
  bool _appLock = false;
  bool _bgAllowed = false;
  int _backfillDays = 90;

  /// How far back "Backfill" scans the inbox. Custom values are kept too.
  static const _backfillKey = 'backfill_days';
  static const _backfillPresets = [7, 30, 90, 180, 365];
  static const _backfillMax = 1825; // 5 years
  static const _customRange = -1;

  static String _rangeLabel(int days) => days % 365 == 0
      ? '${days ~/ 365} year${days == 365 ? '' : 's'}'
      : '$days day${days == 1 ? '' : 's'}';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Back from Android settings (notification access, battery) → re-read.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _toggleNotifAccess() async {
    if (!_notifAccess) {
      ScaffoldMessenger.of(context).showToast(const SnackBar(
          content: Text('Turn on "AERIS payment capture" on the next screen. '
              'Only Google Pay, PhonePe, Paytm and other UPI apps are read.')));
    }
    await NotificationIntake.instance.openSettings();
  }

  Future<void> _setAutoConfirm(bool v) async {
    await (await SharedPreferences.getInstance())
        .setBool(SmsImportService.autoConfirmKey, v);
    if (!mounted) return;
    setState(() => _autoConfirm = v);
    ScaffoldMessenger.of(context).showToast(SnackBar(
        content: Text(v
            ? 'Confident imports are confirmed automatically.'
            : 'Every import will wait in Review.')));
  }

  /// Turn one kind of reminder on/off and re-plan the schedule.
  Future<void> _setKind(String key, bool v) async {
    await (await SharedPreferences.getInstance()).setBool(key, v);
    if (!mounted) return;
    setState(() => _kindOn[key] = v);
    await ReminderScheduler.refresh(
      txns: ref.read(transactionsStreamProvider).valueOrNull ?? const [],
      budgets: ref.read(budgetsStreamProvider).valueOrNull ?? const [],
      bills: ref.read(billsProvider),
    );
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showToast(const SnackBar(content: Text('Saved')));
    }
  }

  Future<void> _setLowBalance(int? rupees) async {
    if (rupees == null) return;
    await ref.read(lowBalanceLimitProvider.notifier).set(rupees);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showToast(SnackBar(
        content: Text(rupees == 0
            ? 'Low-balance alert off.'
            : 'You\'ll be alerted when a bank SMS shows less than '
                '${formatRupees(rupees)}.')));
  }

  Future<void> _refresh() async {
    final notif = await NotificationIntake.instance.isEnabled();
    final g = await SmsService.instance.hasPermission();
    final prefs = await SharedPreferences.getInstance();
    final lock = await AppLockService.instance.isEnabled();
    final bg = await Permission.ignoreBatteryOptimizations.isGranted;
    if (mounted) {
      setState(() {
        _smsGranted = g;
        _notifAccess = notif;
        _autoConfirm =
            prefs.getBool(SmsImportService.autoConfirmKey) ?? true;
        for (final (key, _, _) in ReminderScheduler.kinds) {
          _kindOn[key] = prefs.getBool(key) ?? true;
        }
        _reminders = prefs.getBool('reminders_on') ?? false;
        _appLock = lock;
        _bgAllowed = bg;
        _backfillDays = prefs.getInt(_backfillKey) ?? 90;
      });
    }
  }

  Future<void> _setBackfillRange(int? picked) async {
    if (picked == null) return;
    var days = picked;
    if (picked == _customRange) {
      final raw = await promptText(
        context,
        title: 'Custom range',
        initial: _backfillPresets.contains(_backfillDays)
            ? null
            : '$_backfillDays',
        hint: 'Number of days, e.g. 45',
        helper: 'Backfill imports bank SMS from this many days back '
            '(1–$_backfillMax).',
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      );
      if (raw == null || !mounted) return;
      final n = int.tryParse(raw);
      if (n == null || n < 1 || n > _backfillMax) {
        ScaffoldMessenger.of(context).showToast(const SnackBar(
            content: Text('Enter a number of days from 1 to $_backfillMax.')));
        return;
      }
      days = n;
    }
    if (days == _backfillDays) return;
    await (await SharedPreferences.getInstance()).setInt(_backfillKey, days);
    if (!mounted) return;
    setState(() => _backfillDays = days);
    ScaffoldMessenger.of(context).showToast(SnackBar(
        content: Text('Backfill range set to the last ${_rangeLabel(days)}.')));
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
      messenger.showToast(const SnackBar(
          content: Text(
              'SMS auto-import is on — new bank alerts become transactions. '
              'Use "Backfill" below to import past messages.')));
    } else {
      final status = await Permission.sms.status;
      if (status.isPermanentlyDenied || status.isRestricted) {
        messenger.showToast(const SnackBar(
            duration: Duration(seconds: 8),
            content: Text(
                'Android restricts SMS for sideloaded apps. Tap the ⋮ menu → '
                '"Allow restricted settings" → Permissions → SMS → Allow.')));
        await openAppSettings();
      } else {
        messenger.showToast(
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
      messenger.showToast(const SnackBar(
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
        messenger.showToast(const SnackBar(
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
      if (!await turnOnReminders(ref)) {
        messenger.showToast(
            const SnackBar(content: Text('Notification permission denied.')));
        return;
      }
      final bills = ref.read(billsProvider);
      messenger.showToast(SnackBar(
          content: Text('Reminders on — 9 PM spend check, Sunday recap, '
              '${bills.length} bill reminder${bills.length == 1 ? '' : 's'}.')));
    } else {
      await ReminderScheduler.cancelAll();
    }
    await prefs.setBool('reminders_on', v);
    if (mounted) setState(() => _reminders = v);
  }

  Future<void> _backfill() async {
    final uid = ref.read(currentUserIdProvider);
    if (uid == null) return;
    final messenger = ScaffoldMessenger.of(context);
    if (!await SmsService.instance.hasPermission()) {
      messenger.showToast(const SnackBar(
          content: Text(
              'SMS permission is off — enable "Read bank SMS automatically" above first.')));
      return;
    }
    setState(() => _busy = true);
    final blocked = ref.read(blockedSendersProvider).valueOrNull ?? const {};
    final progress = ref.read(importProgressProvider.notifier);
    final days = _backfillDays;
    final range = _rangeLabel(days);
    try {
      final n = await SmsImportService.instance.backfill(
        uid,
        blocked: blocked,
        days: days,
        onProgress: (d, t) {
          if (mounted) progress.state = d >= t ? null : (done: d, total: t);
        },
      );
      messenger.showToast(SnackBar(
          content: Text(n > 0
              ? 'Imported $n transactions from the last $range.'
              : 'No new transactions found — last $range already imported.')));
    } catch (e) {
      messenger.showToast(SnackBar(content: Text('Backfill failed: $e')));
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
      messenger.showToast(
          const SnackBar(content: Text('No transactions to export yet.')));
      return;
    }
    setState(() => _exporting = true);
    try {
      await ExportService.instance.buildAndShare(txns: txns, budgets: budgets);
    } catch (e) {
      messenger.showToast(SnackBar(content: Text('Export failed: $e')));
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
      messenger.showToast(const SnackBar(
          content: Text('Use a passphrase of at least 4 characters.')));
      return;
    }
    final uid = ref.read(currentUserIdProvider);
    if (uid == null) return;
    messenger.showToast(
        const SnackBar(content: Text('Preparing encrypted backup…')));
    try {
      await BackupService.instance.exportBackup(uid, pass);
    } catch (e) {
      messenger.showToast(SnackBar(content: Text('Backup failed: $e')));
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
      messenger.showToast(SnackBar(
          content: Text('Restored $n transaction${n == 1 ? '' : 's'}.')));
    } catch (e) {
      messenger.showToast(const SnackBar(
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
    final cardBg = dark ? AerisColors.cardDark : Colors.white;
    final divColor = scheme.onSurface.withValues(alpha: 0.07);
    final blocked =
        ref.watch(blockedSendersProvider).valueOrNull ?? const <String>{};

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          // ── Account ─────────────────────────────────────────────────────────
          _group(context, 'Account', cardBg, divColor, [
            _chevronRow(
              Icons.manage_accounts_outlined,
              'Account & security',
              'Password, recovery key, sign out, delete account',
              scheme,
              () => Navigator.pushNamed(context, AppRoutes.account),
            ),
          ]),

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
            _divider(divColor),
            _chevronRow(
              Icons.dashboard_customize_outlined,
              'Customize Home',
              'Choose cards and accent colour',
              scheme,
              () => Navigator.pushNamed(context, AppRoutes.customizeHome),
            ),
            _divider(divColor),
            _chevronRow(
              Icons.category_outlined,
              'Categories & learning',
              'Your own categories, learned rules',
              scheme,
              () => Navigator.pushNamed(context, AppRoutes.categories),
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
            _toggleRow(
              Icons.task_alt_rounded,
              'Auto-confirm confident imports',
              'Only doubtful ones wait in Review',
              _autoConfirm,
              _setAutoConfirm,
              scheme,
            ),
            _divider(divColor),
            _chevronRow(
              Icons.date_range_outlined,
              'Backfill range',
              'How far back to import past SMS',
              scheme,
              null,
              trailing: DropdownButtonHideUnderline(
                child: DropdownButton<int>(
                  value: _backfillPresets.contains(_backfillDays)
                      ? _backfillDays
                      : _customRange,
                  borderRadius: BorderRadius.circular(14),
                  style: TextStyle(
                      fontFamily: kFontFamily,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: scheme.onSurface),
                  onChanged: _busy ? null : _setBackfillRange,
                  items: [
                    for (final d in _backfillPresets)
                      DropdownMenuItem(value: d, child: Text(_rangeLabel(d))),
                    DropdownMenuItem(
                      value: _customRange,
                      child: Text(_backfillPresets.contains(_backfillDays)
                          ? 'Custom…'
                          : 'Custom (${_rangeLabel(_backfillDays)})'),
                    ),
                  ],
                ),
              ),
            ),
            _divider(divColor),
            _chevronRow(
              Icons.history,
              'Backfill last ${_rangeLabel(_backfillDays)}',
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
            _divider(divColor),
            _chevronRow(
              Icons.notifications_active_outlined,
              'Read UPI app notifications',
              _notifAccess
                  ? 'On — catches Google Pay / PhonePe / Paytm payments'
                  : 'For payments that send no bank SMS',
              scheme,
              _toggleNotifAccess,
              trailing: _notifAccess
                  ? Icon(Icons.check_circle_rounded,
                      color: AerisColors.moneyIn(context), size: 20)
                  : null,
            ),
            _divider(divColor),
            _chevronRow(
              Icons.savings_outlined,
              'Low-balance alert',
              'When a bank SMS shows a balance below',
              scheme,
              null,
              trailing: DropdownButtonHideUnderline(
                child: DropdownButton<int>(
                  value: _lowBalancePresets
                          .contains(ref.watch(lowBalanceLimitProvider))
                      ? ref.watch(lowBalanceLimitProvider)
                      : 0,
                  borderRadius: BorderRadius.circular(14),
                  style: TextStyle(
                      fontFamily: kFontFamily,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: scheme.onSurface),
                  onChanged: _setLowBalance,
                  items: [
                    for (final r in _lowBalancePresets)
                      DropdownMenuItem(
                          value: r,
                          child: Text(r == 0 ? 'Off' : formatRupees(r))),
                  ],
                ),
              ),
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
              _reminders
                  ? 'Choose which ones below'
                  : 'Bills, card dues, money owed, weekly recap',
              _reminders,
              _toggleReminders,
              scheme,
            ),
            if (_reminders)
              for (final (key, title, hint) in ReminderScheduler.kinds) ...[
                _divider(divColor),
                _toggleRow(
                  Icons.subdirectory_arrow_right_rounded,
                  title,
                  hint,
                  _kindOn[key] ?? true,
                  (v) => _setKind(key, v),
                  scheme,
                ),
              ],
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
            _toggleRow(
              Icons.visibility_off_outlined,
              'Hide in recent apps',
              'Cover balances when you switch apps',
              ref.watch(recentsPrivacyProvider),
              (v) => ref.read(recentsPrivacyProvider.notifier).set(v),
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
                    const Icon(Icons.block, color: AerisColors.warning, size: 18),
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

          // ── About ───────────────────────────────────────────────────────────
          _group(context, 'About', cardBg, divColor, [
            _chevronRow(
              Icons.info_outline_rounded,
              'About AERIS',
              'Version $kAppVersion · feedback',
              scheme,
              () => Navigator.pushNamed(context, AppRoutes.about),
            ),
            _divider(divColor),
            _chevronRow(
              Icons.privacy_tip_outlined,
              'Privacy policy',
              'What AERIS reads, stores and never does',
              scheme,
              () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const PrivacyPolicyScreen())),
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
    final bg = dark ? AerisColors.cardDark : Colors.white;
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
                          ? AerisColors.accent(context).withValues(alpha: 0.12)
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
                          Icon(Icons.check_circle_rounded,
                              color: AerisColors.accent(context), size: 22),
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
                        color: active ? AerisColors.accent(context) : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: active
                            ? [
                                BoxShadow(
                                    color:
                                        AerisColors.accent(context).withValues(alpha: 0.3),
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
                                  ? AerisColors.onAccent(context)
                                  : scheme.onSurface.withValues(alpha: 0.6)),
                          const SizedBox(width: 5),
                          Text(m.$2,
                              style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: active
                                      ? AerisColors.onAccent(context)
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
              on ? AerisColors.accent(context) : scheme.onSurface.withValues(alpha: 0.2),
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
