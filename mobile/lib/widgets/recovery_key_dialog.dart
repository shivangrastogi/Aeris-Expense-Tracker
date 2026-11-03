import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme.dart';
import 'aeris_toast.dart';
import 'ds.dart';

/// Shows a recovery key once, full screen, with Copy, and won't close until
/// the user confirms they saved it. Used at sign-up and when making a new key
/// in Account & security. The page rises from the bottom like a sheet.
Future<void> showRecoveryKeyDialog(BuildContext context, String key,
    {bool replacing = false}) {
  return Navigator.of(context).push<void>(PageRouteBuilder(
    fullscreenDialog: true,
    transitionDuration: const Duration(milliseconds: 420),
    reverseTransitionDuration: Mo.exit,
    pageBuilder: (_, __, ___) =>
        _RecoveryKeyPage(recoveryKey: key, replacing: replacing),
    transitionsBuilder: (_, a, __, child) => SlideTransition(
      position: Tween(begin: const Offset(0, 1), end: Offset.zero)
          .animate(CurvedAnimation(parent: a, curve: Curves.easeOutBack)),
      child: child,
    ),
  ));
}

class _RecoveryKeyPage extends StatefulWidget {
  final String recoveryKey;
  final bool replacing;
  const _RecoveryKeyPage({required this.recoveryKey, required this.replacing});

  @override
  State<_RecoveryKeyPage> createState() => _RecoveryKeyPageState();
}

class _RecoveryKeyPageState extends State<_RecoveryKeyPage> {
  bool _saved = false;

  @override
  Widget build(BuildContext context) {
    final tk = context.tk;
    final blocks = widget.recoveryKey.split('-');
    return PopScope(
      canPop: _saved,
      child: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 32),
                        Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                              color: tk.accSoft,
                              borderRadius: BorderRadius.circular(18)),
                          child: Icon(Ph.key, size: 30, color: tk.acc),
                        ),
                        const SizedBox(height: 20),
                        Text(
                            widget.replacing
                                ? 'Your new recovery key'
                                : 'Save your recovery key',
                            style: Ts.headline.copyWith(color: tk.t1)),
                        const SizedBox(height: 8),
                        Text(
                          widget.replacing
                              ? 'Your old recovery key no longer works. If you '
                                  'forget your password, this is the only way '
                                  "back in. We can't see it or reset it."
                              : 'Your data is encrypted with a key only you '
                                  'hold. If you forget your password, this is '
                                  "the only way back in. We can't see it or "
                                  'reset it.',
                          style: Ts.body.copyWith(color: tk.t2),
                        ),
                        const SizedBox(height: 20),
                        // The key in monospace chunks, three to a row.
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: tk.sunken,
                            borderRadius: BorderRadius.circular(Rad.card),
                            border: Border.all(color: tk.hair),
                          ),
                          child: LayoutBuilder(builder: (context, c) {
                            final w = (c.maxWidth - 2 * 8) / 3;
                            return Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (final b in blocks)
                                  Container(
                                    width: w,
                                    height: 48,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: tk.raised,
                                      borderRadius:
                                          BorderRadius.circular(Rad.chip),
                                      border: tk.isDark
                                          ? Border.all(color: tk.hair)
                                          : null,
                                      boxShadow: tk.segShadow,
                                    ),
                                    child: Text(b,
                                        style: TextStyle(
                                            fontFamily: 'monospace',
                                            fontSize: 16,
                                            fontWeight: FontWeight.w700,
                                            letterSpacing: 2,
                                            color: tk.t1)),
                                  ),
                              ],
                            );
                          }),
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: TonalButton(
                            'Copy',
                            icon: Ph.copy,
                            onPressed: () {
                              Clipboard.setData(
                                  ClipboardData(text: widget.recoveryKey));
                              ScaffoldMessenger.of(context).showToast(
                                  const SnackBar(
                                      content: Text('Recovery key copied')));
                            },
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Ph.info, size: 15, color: tk.t2),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                "Keep it in a password manager or print it. "
                                "Don't screenshot it into a shared album. You "
                                'can make a new one later in Settings → '
                                'Account & security.',
                                style: Ts.label.copyWith(
                                    fontWeight: FontWeight.w400, color: tk.t2),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                InkWell(
                  onTap: () => setState(() => _saved = !_saved),
                  borderRadius: BorderRadius.circular(Rad.chip),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(children: [
                      Checkbox(
                        value: _saved,
                        onChanged: (v) => setState(() => _saved = v ?? false),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text("I've saved my recovery key",
                            style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w500,
                                color: tk.t1)),
                      ),
                    ]),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: FilledButton(
                    onPressed: _saved ? () => Navigator.pop(context) : null,
                    child: const Text('Continue'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
