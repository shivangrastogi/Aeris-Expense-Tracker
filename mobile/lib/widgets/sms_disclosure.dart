import 'package:flutter/material.dart';

import '../services/sms_service.dart';

/// Google Play "prominent disclosure" for the SMS permission. It MUST be shown
/// (and accepted) before the system SMS dialog appears, so every place that
/// asks for SMS goes through [requestSmsWithDisclosure].
Future<bool> requestSmsWithDisclosure(BuildContext context) async {
  final agreed = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      title: const Text('Allow AERIS to read your SMS?'),
      content: const SingleChildScrollView(
        child: Text(
          'AERIS Expense reads the SMS messages on your phone to find bank, '
          'card and UPI transaction alerts (amount, merchant, date) and add '
          'them to your expense tracker automatically.\n\n'
          '• Only messages that look like transaction alerts are used. '
          'Personal and other messages are ignored and never stored.\n'
          '• Messages are read and processed on your phone. The text of your '
          'SMS is not uploaded or sent to anyone.\n'
          '• The extracted transactions are end-to-end encrypted before they '
          'sync to your account, so only you can read them.\n'
          '• We never sell or share this data, and there are no ads.\n'
          '• This is optional. You can add transactions yourself, and turn '
          'SMS reading off any time in Settings or Android permissions.',
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('No thanks')),
        FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Agree and continue')),
      ],
    ),
  );
  if (agreed != true) return false;
  return SmsService.instance.requestPermission();
}
