import '../../widgets/sms_disclosure.dart';
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
import '../../widgets/ds.dart';
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
        _autoConfirm = prefs.getBool(SmsImportService.autoConfirmKey) ?? true;
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
        initial:
            _backfillPresets.contains(_backfillDays) ? null : '$_backfillDays',
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
    final granted = await requestSmsWithDisclosure(context);
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
    // Play restricts the direct "ignore battery optimisation" prompt, so open
    // the app's settings page and let the user choose "Unrestricted".
    messenger.showToast(const SnackBar(
      duration: Duration(seconds: 6),
      content: Text('Open Battery → set to "Unrestricted". On Realme/Xiaomi '
          'also turn on "Auto-launch".'),
    ));
    await openAppSettings();
    final granted = await Permission.ignoreBatteryOptimizations.isGranted;
    if (mounted) setState(() => _bgAllowed = granted);
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

  static const _kindIcons = <String, IconData>{
    'notif_daily': Ph.moon,
    'notif_recap': Ph.calendar,
    'notif_bills': Ph.creditCard,
    'notif_shares': Ph.handCoins,
    'notif_report': Ph.exam,
  };

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeProvider);
    final currency = ref.watch(currencyProvider);
    final low = ref.watch(lowBalanceLimitProvider);
    final blocked =
        ref.watch(blockedSendersProvider).valueOrNull ?? const <String>{};
    final kindsOn =
        ReminderScheduler.kinds.where((k) => _kindOn[k.$1] ?? true).length;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
        children: [
          _group('Account', [
            SettingsRow(
              icon: Ph.shieldCheck,
              title: 'Account and security',
              sub: 'Password, recovery key, delete account',
              onTap: () => Navigator.pushNamed(context, AppRoutes.account),
            ),
          ]),
          _group('Appearance', [
            _ThemePicker(
              current: themeMode,
              onChanged: (m) => ref.read(themeModeProvider.notifier).setMode(m),
            ),
            SettingsRow(
              icon: Ph.currencyInr,
              title: 'Currency',
              trailing: _value(
                  '${currency.symbol.trim().isEmpty ? currency.code : currency.symbol.trim()} ${currency.name}'),
              onTap: () => _showCurrencySheet(context),
            ),
            SettingsRow(
              icon: Ph.layout,
              title: 'Customize Home',
              onTap: () =>
                  Navigator.pushNamed(context, AppRoutes.customizeHome),
            ),
            SettingsRow(
              icon: Ph.tag,
              title: 'Categories and learning',
              onTap: () => Navigator.pushNamed(context, AppRoutes.categories),
            ),
          ]),
          _group('SMS auto-import', [
            SettingsRow(
              icon: Ph.chatText,
              title: 'Read bank SMS automatically',
              sub: 'Parsed on this phone, encrypted',
              trailing: _switch(_smsGranted, _toggleSms),
              onTap: () => _toggleSms(!_smsGranted),
            ),
            SettingsRow(
              icon: Ph.checkCircle,
              title: 'Auto-confirm confident imports',
              sub: 'Only doubtful ones wait in Review',
              trailing: _switch(_autoConfirm, _setAutoConfirm),
              onTap: () => _setAutoConfirm(!_autoConfirm),
            ),
            SettingsRow(
              icon: Ph.clockCounterClockwise,
              title: 'Backfill range',
              trailing: _value(_rangeLabel(_backfillDays)),
              onTap: _busy ? null : _pickBackfillRange,
            ),
            _ActionRow(
              icon: Ph.arrowsClockwise,
              title: 'Backfill last ${_rangeLabel(_backfillDays)}',
              sub: _busy ? 'Scanning your inbox…' : 'Re-scan inbox and import',
              action: 'Re-scan',
              actionIcon: PhBold.arrowRight,
              busy: _busy,
              onTap: _busy ? null : _backfill,
            ),
            SettingsRow(
              icon: Ph.bellRinging,
              title: 'Read UPI app notifications',
              sub: _notifAccess
                  ? 'On · catches Google Pay, PhonePe and Paytm'
                  : 'For payments that send no bank SMS',
              trailing: _switch(_notifAccess, (_) => _toggleNotifAccess()),
              onTap: _toggleNotifAccess,
            ),
            SettingsRow(
              icon: Ph.warningCircle,
              title: 'Low-balance alert',
              trailing: _value(low == 0 ? 'Off' : formatRupees(low)),
              onTap: _pickLowBalance,
            ),
            if (_smsGranted)
              SettingsRow(
                icon: Ph.batteryCharging,
                title: 'Allow background activity',
                sub: 'Needed to import new SMS while closed',
                trailing: _switch(_bgAllowed, (_) => _allowBackground()),
                onTap: _bgAllowed ? null : _allowBackground,
              ),
          ]),
          _group('Notifications', [
            SettingsRow(
              icon: Ph.bell,
              title: 'Smart reminders',
              sub: _reminders ? '$kindsOn kinds on' : 'All reminders off',
              trailing: _switch(_reminders, _toggleReminders),
              onTap: () => _toggleReminders(!_reminders),
            ),
            if (_reminders)
              for (final (key, title, hint) in ReminderScheduler.kinds)
                Padding(
                  padding: const EdgeInsets.only(left: 28),
                  child: SettingsRow(
                    icon: _kindIcons[key] ?? Ph.bell,
                    title: title,
                    sub: hint,
                    trailing:
                        _switch(_kindOn[key] ?? true, (v) => _setKind(key, v)),
                    onTap: () => _setKind(key, !(_kindOn[key] ?? true)),
                  ),
                ),
          ]),
          _group('Security and data', [
            SettingsRow(
              icon: Ph.fingerprint,
              title: 'App lock',
              sub: 'Fingerprint or PIN',
              trailing: _switch(_appLock, _toggleAppLock),
              onTap: () => _toggleAppLock(!_appLock),
            ),
            SettingsRow(
              icon: Ph.eyeSlash,
              title: 'Hide in recent apps',
              sub: 'Blurs AERIS in the app switcher',
              trailing: _switch(ref.watch(recentsPrivacyProvider),
                  (v) => ref.read(recentsPrivacyProvider.notifier).set(v)),
              onTap: () => ref
                  .read(recentsPrivacyProvider.notifier)
                  .set(!ref.read(recentsPrivacyProvider)),
            ),
            SettingsRow(
              icon: Ph.cloudCheck,
              title: 'Encrypted backup',
              sub: 'Passphrase-protected export',
              onTap: _backup,
            ),
            SettingsRow(
              icon: Ph.cloudArrowDown,
              title: 'Restore from backup',
              onTap: _restore,
            ),
            SettingsRow(
              icon: Ph.prohibit,
              title: 'Blocked senders',
              trailing: _value('${blocked.length}'),
              onTap: () => _showBlockedSheet(context),
            ),
          ]),
          _group('Export', [
            _ActionRow(
              icon: Ph.fileXls,
              title: 'Export to Excel',
              sub: _exporting
                  ? 'Preparing file…'
                  : 'All transactions, budgets and goals',
              action: 'Share',
              actionIcon: PhBold.shareNetwork,
              busy: _exporting,
              onTap: _exporting ? null : _export,
            ),
          ]),
          _group('About', [
            SettingsRow(
              icon: Ph.info,
              title: 'About AERIS',
              sub: 'Version $kAppVersion',
              onTap: () => Navigator.pushNamed(context, AppRoutes.about),
            ),
            SettingsRow(
              icon: Ph.lockKey,
              title: 'Privacy policy',
              onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const PrivacyPolicyScreen())),
            ),
          ]),
        ],
      ),
    );
  }

  // ── Building blocks ─────────────────────────────────────────────────────────

  Widget _group(String title, List<Widget> rows) => Padding(
        padding: const EdgeInsets.only(bottom: 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
              child: Overline(title),
            ),
            ListGroup(inset: 64, children: rows),
          ],
        ),
      );

  /// A trailing value + chevron ("90 days ›").
  Widget _value(String v) {
    final tk = context.tk;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 140),
        child: Text(v,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontSize: 14, fontWeight: FontWeight.w600, color: tk.t2)),
      ),
      const SizedBox(width: 6),
      Icon(Ph.caretRight, size: 16, color: tk.t3),
    ]);
  }

  Widget _switch(bool v, Future<void> Function(bool) onChanged) => Switch(
        value: v,
        onChanged: (x) => onChanged(x),
      );

  /// A radio-list sheet ("Backfill range", "Low-balance alert").
  Future<T?> _pickFrom<T>(
      String title, List<(T, String, String?)> opts, bool Function(T) isOn) {
    return showDsSheet<T>(
      context,
      title: title,
      builder: (ctx) {
        final tk = ctx.tk;
        return ListGroup(inset: 16, children: [
          for (final (v, label, sub) in opts)
            DsRow(
              minHeight: 52,
              title: label,
              sub: sub,
              trailing: Container(
                width: 22,
                height: 22,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border:
                      Border.all(color: isOn(v) ? tk.acc : tk.hair2, width: 2),
                ),
                child: isOn(v)
                    ? Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                            shape: BoxShape.circle, color: tk.acc))
                    : null,
              ),
              onTap: () => Navigator.pop(ctx, v),
            ),
        ]);
      },
    );
  }

  Future<void> _pickBackfillRange() async {
    final isPreset = _backfillPresets.contains(_backfillDays);
    final picked = await _pickFrom<int>(
        'Backfill range',
        [
          for (final d in _backfillPresets)
            (d, _rangeLabel(d), d == 90 ? 'Recommended' : null),
          (
            _customRange,
            'Custom…',
            isPreset ? null : _rangeLabel(_backfillDays)
          ),
        ],
        (v) => v == _customRange ? !isPreset : v == _backfillDays);
    if (!mounted) return;
    await _setBackfillRange(picked);
  }

  Future<void> _pickLowBalance() async {
    final cur = ref.read(lowBalanceLimitProvider);
    final picked = await _pickFrom<int>(
        'Low-balance alert',
        [
          for (final r in _lowBalancePresets)
            (r, r == 0 ? 'Off' : formatRupees(r), null),
        ],
        (v) => v == cur);
    if (!mounted) return;
    await _setLowBalance(picked);
  }

  void _showBlockedSheet(BuildContext context) {
    showDsSheet<void>(
      context,
      title: 'Blocked senders',
      builder: (ctx) => Consumer(builder: (ctx, ref2, _) {
        final tk = ctx.tk;
        final list =
            (ref2.watch(blockedSendersProvider).valueOrNull ?? const <String>{})
                .toList();
        if (list.isEmpty) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
                'No blocked senders. Block one from any imported '
                'transaction to stop its SMS being read.',
                style: Ts.bodyS.copyWith(color: tk.t2)),
          );
        }
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text('SMS from these senders is ignored.',
                  style: Ts.bodyS.copyWith(color: tk.t2)),
            ),
            Flexible(
              child: SingleChildScrollView(
                child: ListGroup(inset: 64, children: [
                  for (final s in list)
                    SettingsRow(
                      icon: Ph.prohibit,
                      title: s,
                      trailing: TextButton(
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
                    ),
                ]),
              ),
            ),
          ],
        );
      }),
    );
  }

  void _showCurrencySheet(BuildContext context) {
    final selected = ref.read(currencyProvider).code;
    showDsSheet<void>(
      context,
      title: 'Currency',
      subtitle: 'Amounts are stored once and shown in your chosen currency. '
          'Indian grouping (lakh/crore) is used for ₹.',
      scrollControlled: true,
      builder: (ctx) {
        final tk = ctx.tk;
        return SingleChildScrollView(
          child: ListGroup(inset: 64, children: [
            for (final c in Currencies.all)
              DsRow(
                minHeight: 56,
                leading: SizedBox(
                    width: 40,
                    child: Center(
                        child: Text(c.flag,
                            style: const TextStyle(fontSize: 24)))),
                title: c.name,
                sub: '${c.code} · '
                    '${c.symbol.trim().isEmpty ? c.code : c.symbol.trim()}',
                trailing: c.code == selected
                    ? Icon(PhFill.checkCircle, color: tk.acc, size: 22)
                    : null,
                onTap: () {
                  ref.read(currencyProvider.notifier).setCurrency(c.code);
                  Navigator.pop(ctx);
                },
              ),
          ]),
        );
      },
    );
  }
}

/// A row with an inline action ("Re-scan →", "Share") that shows the rising
/// loader while it works.
class _ActionRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String sub;
  final String action;
  final IconData actionIcon;
  final bool busy;
  final VoidCallback? onTap;
  const _ActionRow({
    required this.icon,
    required this.title,
    required this.sub,
    required this.action,
    required this.actionIcon,
    required this.busy,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tk = context.tk;
    return SettingsRow(
      icon: icon,
      title: title,
      sub: sub,
      onTap: onTap,
      trailing: busy
          ? const RisingLoader()
          : Row(mainAxisSize: MainAxisSize.min, children: [
              Text(action,
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: tk.acc)),
              const SizedBox(width: 4),
              Icon(actionIcon, size: 14, color: tk.acc),
            ]),
    );
  }
}

// ── Theme picker (segmented control) ─────────────────────────────────────────

class _ThemePicker extends StatelessWidget {
  final ThemeMode current;
  final ValueChanged<ThemeMode> onChanged;

  const _ThemePicker({required this.current, required this.onChanged});

  static const _modes = [ThemeMode.light, ThemeMode.dark, ThemeMode.system];

  @override
  Widget build(BuildContext context) {
    final tk = context.tk;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
              color: tk.press, borderRadius: BorderRadius.circular(10)),
          child: Icon(Ph.circleHalf, size: 18, color: tk.t2),
        ),
        const SizedBox(width: 12),
        Text('Theme', style: Ts.rowTitle.copyWith(color: tk.t1)),
        const SizedBox(width: 12),
        Expanded(
          child: DsSegmented(
            height: 38,
            labels: const ['Light', 'Dark', 'System'],
            index: _modes.indexOf(current).clamp(0, 2),
            onChanged: (i) => onChanged(_modes[i]),
          ),
        ),
      ]),
    );
  }
}
