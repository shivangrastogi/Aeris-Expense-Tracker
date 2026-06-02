import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/theme.dart';
import '../../services/sms_service.dart';
import '../../widgets/mascot/aeris_mascot.dart';

/// One-time welcome tour shown on first launch (gated by shared_preferences
/// `onboarded`). Introduces the app, Aeris, SMS auto-import, and budgets.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  static Future<bool> isDone() async =>
      (await SharedPreferences.getInstance()).getBool('onboarded') ?? false;

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _ctrl = PageController();
  int _page = 0;

  late final List<_Slide> _slides = [
    const _Slide(
      emoji: '👋',
      title: 'Welcome to AERIS',
      body: 'Your private, automatic expense tracker. Everything is '
          'end-to-end encrypted — only you can read your data.',
    ),
    _Slide(
      custom: const AerisMascot(mood: MascotMood.happy, size: 96),
      title: 'Meet Aeris',
      body: 'Tap Aeris (top-right on Home) anytime to ask things like '
          '“how much did I spend on food this month?”',
    ),
    _Slide(
      emoji: '✉️',
      title: 'Auto-read bank SMS',
      body: 'AERIS turns your bank & UPI alerts into transactions '
          'automatically — no manual entry. You can review everything.',
      action: 'Enable SMS auto-import',
      onAction: (ref) => SmsService.instance.requestPermission(),
    ),
    const _Slide(
      emoji: '🎯',
      title: 'Set a budget & goals',
      body: 'Cap your spending per category and save toward goals — Aeris '
          'tracks your pace and celebrates your wins.',
    ),
  ];

  Future<void> _finish() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarded', true);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final last = _page == _slides.length - 1;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(onPressed: _finish, child: const Text('Skip')),
            ),
            Expanded(
              child: PageView.builder(
                controller: _ctrl,
                onPageChanged: (i) => setState(() => _page = i),
                itemCount: _slides.length,
                itemBuilder: (_, i) => _slideView(_slides[i]),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < _slides.length; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: _page == i ? 18 : 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: _page == i
                          ? AerisColors.seed
                          : scheme.onSurfaceVariant.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    if (last) {
                      _finish();
                    } else {
                      _ctrl.nextPage(
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeInOut);
                    }
                  },
                  child: Text(last ? 'Get started' : 'Next'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _slideView(_Slide s) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          s.custom ?? Text(s.emoji ?? '', style: const TextStyle(fontSize: 72)),
          const SizedBox(height: 28),
          Text(s.title,
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          Text(s.body,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 14,
                  height: 1.4,
                  color: Theme.of(context).colorScheme.onSurfaceVariant)),
          if (s.action != null) ...[
            const SizedBox(height: 20),
            FilledButton.tonal(
              onPressed: () async {
                await s.onAction?.call(ref);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Done!')));
                }
              },
              child: Text(s.action!),
            ),
          ],
        ],
      ),
    );
  }
}

class _Slide {
  final String? emoji;
  final Widget? custom;
  final String title;
  final String body;
  final String? action;
  final Future<void> Function(WidgetRef ref)? onAction;
  const _Slide({
    this.emoji,
    this.custom,
    required this.title,
    required this.body,
    this.action,
    this.onAction,
  });
}
