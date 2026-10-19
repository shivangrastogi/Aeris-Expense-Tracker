import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/theme.dart';
import '../../providers/auth_provider.dart';
import '../../providers/setup_provider.dart';
import '../../services/notification_intake.dart';
import '../../services/sms_service.dart';
import '../../utils/amount_input_formatter.dart';
import '../../utils/formatters.dart';

/// One-time setup tour on first launch (gated by the `onboarded` pref).
/// Each step does its job right here and reports what actually happened —
/// a denied permission says so and points to Settings, never "Done!".
/// Anything skipped stays on Home's "Finish setting up" card.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  static Future<bool> isDone() async =>
      (await SharedPreferences.getInstance()).getBool('onboarded') ?? false;

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

enum _Result { none, on, denied }

class _OnboardingScreenState extends ConsumerState<OnboardingScreen>
    with WidgetsBindingObserver {
  final _ctrl = PageController();
  final _income = TextEditingController();
  int _page = 0;
  _Result _sms = _Result.none;
  _Result _notif = _Result.none;
  _Result _reminders = _Result.none;
  bool _busy = false;

  static const _count = 5;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkPermissions();
    final income = ref.read(userProfileProvider).valueOrNull?.monthlyIncome ?? 0;
    if (income > 0) _income.text = inrToDisplayText(income);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ctrl.dispose();
    _income.dispose();
    super.dispose();
  }

  // Notification access is granted in Android settings — re-check on return.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _checkPermissions();
  }

  Future<void> _checkPermissions() async {
    final sms = await SmsService.instance.hasPermission();
    final notif = await NotificationIntake.instance.isEnabled();
    if (!mounted) return;
    setState(() {
      if (sms) _sms = _Result.on;
      if (notif) _notif = _Result.on;
    });
  }

  Future<void> _askSms() async {
    final ok = await SmsService.instance.requestPermission();
    if (mounted) setState(() => _sms = ok ? _Result.on : _Result.denied);
  }

  Future<void> _askReminders() async {
    final ok = await turnOnReminders(ref);
    if (mounted) setState(() => _reminders = ok ? _Result.on : _Result.denied);
  }

  Future<void> _saveIncome() async {
    final v = displayToInr(_income.text);
    final p = ref.read(userProfileProvider).valueOrNull;
    if (v == null || p == null || v == p.monthlyIncome) return;
    await ref.read(authServiceProvider).saveProfile(p.copyWith(monthlyIncome: v));
    ref.invalidate(userProfileProvider);
  }

  Future<void> _next() async {
    if (_page == 3) {
      setState(() => _busy = true);
      try {
        await _saveIncome();
      } catch (_) {/* optional step; Edit profile still has it */}
      if (mounted) setState(() => _busy = false);
    }
    if (_page == _count - 1) return _finish();
    if (!mounted) return;
    FocusScope.of(context).unfocus();
    _ctrl.nextPage(
        duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
  }

  Future<void> _finish() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarded', true);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final last = _page == _count - 1;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                  onPressed: _finish, child: const Text('Skip for now')),
            ),
            Expanded(
              child: PageView(
                controller: _ctrl,
                onPageChanged: (i) => setState(() => _page = i),
                children: [
                  _step(
                    icon: Icons.lock_outline_rounded,
                    title: 'Private by design',
                    body: 'AERIS tracks your money automatically. Everything '
                        'is read on your phone and end-to-end encrypted — '
                        'only you can see it.',
                  ),
                  _step(
                    icon: Icons.sms_outlined,
                    title: 'Read bank SMS',
                    body: 'Bank and card alerts become transactions on their '
                        'own. Personal messages are ignored. You can review '
                        'anything AERIS isn\'t sure about.',
                    action: _sms == _Result.on ? null : 'Allow SMS access',
                    onAction: _askSms,
                    result: _sms,
                    onText: 'SMS reading is on',
                    deniedText: 'Not allowed. You can turn it on later in '
                        'Settings → SMS auto-import.',
                  ),
                  _step(
                    icon: Icons.notifications_active_outlined,
                    title: 'Catch UPI app payments',
                    body: 'Google Pay, PhonePe and Paytm often send no bank '
                        'SMS. Let AERIS read only those apps\' payment '
                        'notifications. Optional.',
                    action: _notif == _Result.on
                        ? null
                        : 'Open notification access',
                    onAction: () => NotificationIntake.instance.openSettings(),
                    result: _notif,
                    onText: 'UPI payments will be caught',
                    deniedText: '',
                  ),
                  _step(
                    icon: Icons.payments_outlined,
                    title: 'Your monthly income',
                    body: 'Used for your savings rate and budget suggestions. '
                        'Optional — stays encrypted.',
                    child: TextField(
                      controller: _income,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: const [AmountInputFormatter()],
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _next(),
                      decoration: InputDecoration(
                        hintText: 'e.g. 85000',
                        prefixText: '${kCurrency.symbol.trim()} ',
                      ),
                    ),
                  ),
                  _step(
                    icon: Icons.alarm_on_outlined,
                    title: 'Stay on top',
                    body: 'Get a heads-up the day before bills and card dues, '
                        'when friends owe you, and a short weekly recap. '
                        'Choose exactly which in Settings.',
                    action:
                        _reminders == _Result.on ? null : 'Turn on reminders',
                    onAction: _askReminders,
                    result: _reminders,
                    onText: 'Reminders are on',
                    deniedText: 'Notifications are off for AERIS. You can '
                        'allow them later in Settings.',
                  ),
                ],
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < _count; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: _page == i ? 18 : 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: _page == i
                          ? AerisColors.accent(context)
                          : scheme.onSurfaceVariant.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _busy ? null : _next,
                  child: Text(last ? 'Get started' : 'Continue'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _step({
    required IconData icon,
    required String title,
    required String body,
    String? action,
    VoidCallback? onAction,
    _Result result = _Result.none,
    String onText = '',
    String deniedText = '',
    Widget? child,
  }) {
    final accent = AerisColors.accent(context);
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: AerisColors.accentSoft(context),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(icon, color: accent, size: 32),
          ),
          const SizedBox(height: 24),
          Text(title,
              style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5)),
          const SizedBox(height: 10),
          Text(body, style: TextStyle(fontSize: 15, height: 1.45, color: muted)),
          if (child != null) ...[const SizedBox(height: 20), child],
          if (result == _Result.on) ...[
            const SizedBox(height: 20),
            Row(children: [
              Icon(Icons.check_circle_rounded,
                  color: AerisColors.moneyIn(context)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(onText,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
            ]),
          ] else if (result == _Result.denied && deniedText.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text(deniedText,
                style: const TextStyle(
                    color: AerisColors.warning, fontWeight: FontWeight.w600)),
          ],
          if (action != null) ...[
            const SizedBox(height: 20),
            OutlinedButton(
              onPressed: () {
                HapticFeedback.selectionClick();
                onAction?.call();
              },
              child: Text(action),
            ),
          ],
        ],
      ),
    );
  }
}
