import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/theme.dart';
import '../../widgets/brand_mark.dart';
import '../../widgets/ds.dart';

/// App version — keep in step with `version:` in pubspec.yaml.
const kAppVersion = '1.0.0';

/// About AERIS: version, privacy policy, feedback.
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final tk = context.tk;
    return Scaffold(
      appBar: AppBar(title: const Text('About')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          Center(
            child: Column(children: [
              const AerisBrandMark(size: 84),
              const SizedBox(height: 12),
              Text('AERIS Expense', style: Ts.headline.copyWith(color: tk.t1)),
              Text('Version $kAppVersion', style: Ts.bodyS.copyWith(color: tk.t2)),
              const SizedBox(height: 6),
              Text('Private, automatic money tracking',
                  style: Ts.body.copyWith(color: tk.t2)),
            ]),
          ),
          const SizedBox(height: 24),
          ListGroup(inset: 64, children: [
              SettingsRow(
                icon: Ph.lockKey,
                title: 'Privacy policy',
                sub: 'What AERIS reads, stores and never does',
                onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const PrivacyPolicyScreen())),
              ),
              SettingsRow(
                icon: Ph.chatCenteredText,
                title: 'Send feedback',
                sub: 'Report a problem or suggest something',
                onTap: () => Share.share(
                    'AERIS Expense v$kAppVersion feedback:\n\n',
                    subject: 'AERIS Expense feedback'),
              ),
          ]),
        ],
      ),
    );
  }
}

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  static const _sections = <(String, String)>[
    (
      'In short',
      'AERIS is built so that only you can read your financial data. It is '
          'parsed on your phone and end-to-end encrypted before it is synced. '
          'We do not sell, rent or share your data, and we show no ads.'
    ),
    (
      'What the app reads',
      'With your permission, AERIS reads SMS messages from banks, cards and '
          'payment apps to detect transactions, and — if you turn it on — '
          'payment notifications from UPI apps (Google Pay, PhonePe, Paytm and '
          'similar). Only messages that look like transactions are kept; '
          'personal messages are ignored. All of this happens on your device.'
    ),
    (
      'What is stored',
      'Your transactions, budgets, goals, shared bills, receipts and '
          'settings are encrypted on your phone with a key only you hold, '
          'then stored in your account (Google Firebase) so they sync between '
          'your devices. The service stores only encrypted data it cannot '
          'read, plus your email address and basic account metadata needed '
          'to sign you in.'
    ),
    (
      'Your keys',
      'Your encryption key is protected by your password and by a recovery '
          'key that only you see. We cannot reset it or read your data. If '
          'you lose both your password and your recovery key, the data '
          'cannot be recovered.'
    ),
    (
      'Permissions',
      'SMS: to detect bank transactions. Notification access (optional): to '
          'detect UPI-app payments. Notifications: for reminders you turn '
          'on. Camera (optional): to scan receipts. Microphone (optional): '
          'for voice entry. You can withdraw any permission in Android '
          'settings at any time.'
    ),
    (
      'Your choices',
      'Export everything to Excel or an encrypted backup at any time '
          '(Settings). Delete your account and all of its data permanently '
          'from Settings → Account & security → Delete account.'
    ),
    (
      'Crash reports',
      'If the app crashes, an anonymous technical report (no transaction '
          'data) may be sent to help fix the problem.'
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final muted = AerisColors.muted(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Privacy policy')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          for (final (title, body) in _sections) ...[
            Text(title, style: Ts.title.copyWith(color: context.tk.t1)),
            const SizedBox(height: 6),
            Text(body, style: TextStyle(height: 1.5, color: muted)),
            const SizedBox(height: 18),
          ],
        ],
      ),
    );
  }
}
