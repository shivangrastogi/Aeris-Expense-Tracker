import 'package:flutter/material.dart';

/// Guards a form screen against accidental loss of entered data.
///
/// While [dirty] is true, the system back gesture/button and the AppBar back
/// arrow (both go through `Navigator.maybePop`) are intercepted and the user is
/// asked to confirm before the screen closes. A programmatic
/// `Navigator.pop` (e.g. after a successful save) is never blocked.
class DiscardGuard extends StatelessWidget {
  final bool dirty;
  final Widget child;
  final String title;
  final String message;

  const DiscardGuard({
    super.key,
    required this.dirty,
    required this.child,
    this.title = 'Discard this entry?',
    this.message = "You've entered details that haven't been saved. "
        'If you leave now they will be lost.',
  });

  @override
  Widget build(BuildContext context) {
    return PopScope<Object?>(
      canPop: !dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final discard =
            await confirmDiscard(context, title: title, message: message);
        if (discard && context.mounted) Navigator.of(context).pop();
      },
      child: child,
    );
  }
}

/// Shows the "discard changes?" dialog. Returns true only if the user
/// explicitly chose to discard.
Future<bool> confirmDiscard(
  BuildContext context, {
  String title = 'Discard this entry?',
  String message = "You've entered details that haven't been saved. "
      'If you leave now they will be lost.',
}) async {
  final scheme = Theme.of(context).colorScheme;
  final result = await showDialog<bool>(
    context: context,
    builder: (d) => AlertDialog(
      icon: Icon(Icons.warning_amber_rounded, color: scheme.error),
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(d, false),
          child: const Text('Keep editing'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: scheme.error,
            foregroundColor: scheme.onError,
          ),
          onPressed: () => Navigator.pop(d, true),
          child: const Text('Discard'),
        ),
      ],
    ),
  );
  return result ?? false;
}
