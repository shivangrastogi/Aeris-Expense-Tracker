import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'aeris_toast.dart';

/// Shows a recovery key once, with Copy, and won't close until the user
/// confirms they saved it. Used at sign-up and when making a new key in
/// Account & security.
Future<void> showRecoveryKeyDialog(BuildContext context, String key,
    {bool replacing = false}) {
  bool saved = false;
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (d) => StatefulBuilder(
      builder: (d, setLocal) => AlertDialog(
        title: Text(replacing ? 'Your new recovery key' : 'Save your recovery key'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              replacing
                  ? 'Your old recovery key no longer works. If you forget your '
                      'password, this key is the ONLY way to get your data '
                      'back. Store it somewhere safe.'
                  : 'Your data is end-to-end encrypted — not even we can read '
                      'it. If you forget your password, this key is the ONLY '
                      'way to get your transactions back. Store it somewhere '
                      'safe. You can make a new one later in Settings → '
                      'Account & security.',
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .surfaceContainerHighest
                    .withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final block in key.split('-'))
                    Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .surface
                            .withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        block,
                        style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 2),
                      ),
                    ),
                ],
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: key));
                  ScaffoldMessenger.of(context).showToast(
                      const SnackBar(content: Text('Recovery key copied')));
                },
                icon: const Icon(Icons.copy, size: 16),
                label: const Text('Copy'),
              ),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: saved,
              onChanged: (v) => setLocal(() => saved = v ?? false),
              title: const Text("I've saved my recovery key",
                  style: TextStyle(fontSize: 13)),
            ),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: saved ? () => Navigator.pop(d) : null,
            child: const Text('Continue'),
          ),
        ],
      ),
    ),
  );
}
