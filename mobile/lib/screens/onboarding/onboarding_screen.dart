import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/theme.dart';
import '../../providers/auth_provider.dart';
import '../../providers/setup_provider.dart';
import '../../services/notification_intake.dart';
import '../../services/sms_service.dart';
import '../../widgets/sms_disclosure.dart';
import '../../utils/amount_input_formatter.dart';
import '../../utils/formatters.dart';
import '../../widgets/ds.dart';
import '../../providers/income_lock_provider.dart';
import '../../services/app_lock_service.dart';

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
  _Result _privacy = _Result.none;
  bool _hideSalary = true;
  bool _lockApp = true;
  bool _busy = false;

  static const _count = 6;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkPermissions();
    final income =
        ref.read(userProfileProvider).valueOrNull?.monthlyIncome ?? 0;
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
    final ok = await requestSmsWithDisclosure(context);
    if (mounted) setState(() => _sms = ok ? _Result.on : _Result.denied);
  }

  Future<void> _askReminders() async {
    final ok = await turnOnReminders(ref);
    if (mounted) setState(() => _reminders = ok ? _Result.on : _Result.denied);
  }

  // One fingerprint confirms both choices, right here.
  Future<void> _confirmPrivacy() async {
    final lockSvc = AppLockService.instance;
    if (!await lockSvc.isAvailable()) {
      if (mounted) setState(() => _privacy = _Result.denied);
      return;
    }
    if (!await lockSvc.authenticate("Confirm it's you")) return;
    await ref
        .read(incomeLockProvider.notifier)
        .setEnabled(_hideSalary, alreadyVerified: true);
    await lockSvc.setEnabled(_lockApp);
    if (mounted) setState(() => _privacy = _Result.on);
  }

  Future<void> _saveIncome() async {
    final v = displayToInr(_income.text);
    final p = ref.read(userProfileProvider).valueOrNull;
    if (v == null || p == null || v == p.monthlyIncome) return;
    await ref
        .read(authServiceProvider)
        .saveProfile(p.copyWith(monthlyIncome: v));
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
    final tk = context.tk;
    final last = _page == _count - 1;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Fixed header: step progress as rising segments, and Skip.
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 8, 0),
              child: Row(children: [
                SizedBox(
                  width: 128,
                  height: 12,
                  child: CustomPaint(
                    painter: _StepsPainter(_page, _count, tk.acc, tk.track),
                  ),
                ),
                const Spacer(),
                TextButton(
                    onPressed: _finish,
                    style: TextButton.styleFrom(
                        foregroundColor: tk.t2,
                        minimumSize: const Size(48, 48)),
                    child: const Text('Skip for now')),
              ]),
            ),
            Expanded(
              child: PageView(
                controller: _ctrl,
                onPageChanged: (i) => setState(() => _page = i),
                children: [
                  _step(
                    index: 1,
                    icon: Ph.lock,
                    title: 'Private by design',
                    body: 'AERIS tracks your money automatically. Everything '
                        'is read on your phone and end-to-end encrypted — '
                        'only you can see it.',
                  ),
                  _step(
                    index: 2,
                    illustration: const _SmsIllustration(),
                    actionIcon: Ph.chatText,
                    icon: Ph.chatText,
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
                    index: 3,
                    actionIcon: Ph.bellRinging,
                    icon: Ph.bellRinging,
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
                    index: 4,
                    icon: Ph.money,
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
                    index: 5,
                    icon: Ph.lockSimple,
                    title: 'Keep your salary private',
                    body: 'Your salary shows as ₹•••• — even when other '
                        'amounts are visible — until you unlock it with your '
                        'fingerprint. Change it any time in Me → Edit profile.',
                    child: AerisCard(
                      padding: EdgeInsets.zero,
                      child: Column(children: [
                        SettingsRow(
                          icon: Ph.eyeSlash,
                          title: 'Hide my salary',
                          sub: 'Fingerprint to see it',
                          trailing: Switch(
                              value: _hideSalary,
                              onChanged: (v) => setState(() {
                                    _hideSalary = v;
                                    _privacy = _Result.none;
                                  })),
                        ),
                        SettingsRow(
                          icon: Ph.fingerprint,
                          title: 'Lock AERIS with fingerprint',
                          sub: 'When you come back to the app',
                          trailing: Switch(
                              value: _lockApp,
                              onChanged: (v) => setState(() {
                                    _lockApp = v;
                                    _privacy = _Result.none;
                                  })),
                        ),
                      ]),
                    ),
                    actionIcon: Ph.fingerprint,
                    action:
                        _privacy == _Result.on || (!_hideSalary && !_lockApp)
                            ? null
                            : 'Confirm with fingerprint',
                    onAction: _confirmPrivacy,
                    result: _privacy,
                    onText: [
                      if (_hideSalary) 'Salary hidden',
                      if (_lockApp) 'app lock on',
                    ].join(' · '),
                    deniedText: 'No fingerprint or screen lock on this phone. '
                        'Add one in phone settings, then turn on Hide salary '
                        'in Me → Edit profile.',
                  ),
                  _step(
                    index: 6,
                    actionIcon: Ph.alarm,
                    icon: Ph.alarm,
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
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: SizedBox(
                width: double.infinity,
                height: 48,
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
    required int index,
    required IconData icon,
    required String title,
    required String body,
    String? action,
    IconData? actionIcon,
    VoidCallback? onAction,
    _Result result = _Result.none,
    String onText = '',
    String deniedText = '',
    Widget? illustration,
    Widget? child,
  }) {
    final tk = context.tk;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: tk.accSoft,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(icon, color: tk.acc, size: 30),
          ),
          const SizedBox(height: 24),
          Overline('Step $index of $_count'),
          const SizedBox(height: 8),
          Text(title, style: Ts.headline.copyWith(color: tk.t1)),
          const SizedBox(height: 10),
          Text(body, style: Ts.body.copyWith(color: tk.t2)),
          if (illustration != null) ...[
            const SizedBox(height: 24),
            illustration,
          ],
          if (child != null) ...[const SizedBox(height: 24), child],
          if (result == _Result.on) ...[
            const SizedBox(height: 20),
            Row(children: [
              Icon(PhFill.checkCircle, size: 20, color: tk.ok),
              const SizedBox(width: 8),
              Expanded(
                child: Text(onText,
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: tk.t1)),
              ),
            ]),
          ] else if (result == _Result.denied && deniedText.isNotEmpty) ...[
            const SizedBox(height: 20),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(PhFill.warningCircle, size: 18, color: tk.warn),
              const SizedBox(width: 8),
              Expanded(
                child: Text(deniedText,
                    style: TextStyle(
                        fontSize: 13,
                        height: 18 / 13,
                        fontWeight: FontWeight.w600,
                        color: tk.t1)),
              ),
            ]),
          ],
          if (action != null) ...[
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: TonalButton(
                action,
                icon: actionIcon,
                onPressed: () {
                  HapticFeedback.selectionClick();
                  onAction?.call();
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The step progress: one short rising segment per step. Done steps and the
/// current one are accent; the current one ends in the dot.
class _StepsPainter extends CustomPainter {
  final int page, count;
  final Color acc, track;
  _StepsPainter(this.page, this.count, this.acc, this.track);

  @override
  void paint(Canvas canvas, Size size) {
    const gap = 3.0;
    final w = (size.width - gap * (count - 1)) / count;
    final p = Paint()
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < count; i++) {
      final x0 = i * (w + gap) + 1.5;
      final y0 = size.height / 2;
      final a = Offset(x0, y0);
      final b = Offset(x0 + w - 3, y0);
      canvas.drawLine(a, b, p..color = i <= page ? acc : track);
    }
  }

  @override
  bool shouldRepaint(_StepsPainter o) =>
      o.page != page || o.acc != acc || o.track != track;
}

/// Step 2's picture: a bank SMS bubble becoming a transaction.
class _SmsIllustration extends StatelessWidget {
  const _SmsIllustration();

  @override
  Widget build(BuildContext context) {
    final tk = context.tk;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: AerisColors.cardDecoration(context),
      child: Column(children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 300),
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration: BoxDecoration(
              color: tk.sunken,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: tk.hair),
            ),
            child: Text.rich(
              TextSpan(children: [
                TextSpan(
                    text: 'HDFC Bank',
                    style:
                        TextStyle(fontWeight: FontWeight.w700, color: tk.t1)),
                const TextSpan(text: ' · 2:07 PM\n'),
                const TextSpan(
                    text: 'Rs.486.00 debited from a/c **4521 to VPA '
                        'swiggy@icici on 19-10-26. UPI Ref 429417.'),
              ]),
              style: TextStyle(fontSize: 12, height: 1.45, color: tk.t2),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Icon(Ph.arrowDown, size: 16, color: tk.t3),
        ),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Rad.input),
            border: Border.all(color: tk.hair2),
          ),
          alignment: Alignment.center,
          child: Text('Becomes a transaction, automatically',
              style: TextStyle(fontSize: 13, color: tk.t2)),
        ),
      ]),
    );
  }
}
