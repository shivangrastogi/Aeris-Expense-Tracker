import 'package:flutter/material.dart';

/// A text-input [AlertDialog] that OWNS its [TextEditingController].
///
/// The controller is created and disposed inside the dialog's own [State], so
/// it lives exactly as long as the dialog route and is torn down only once that
/// route is fully removed — after its exit transition. Creating a controller at
/// the call site and disposing it right after `await showDialog` crashes,
/// because the dialog keeps rebuilding its field while animating out (the
/// "TextEditingController used after being disposed" assert, which then cascades
/// into the framework's `_dependents.isEmpty` teardown assert).
///
/// Returns the entered text (trimmed unless [trim] is false), or null if the
/// user cancelled / dismissed the dialog.
Future<String?> promptText(
  BuildContext context, {
  required String title,
  String? initial,
  String? hint,
  String? helper,
  String confirmLabel = 'Save',
  bool obscure = false,
  bool trim = true,
  TextCapitalization capitalization = TextCapitalization.none,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _TextInputDialog(
      title: title,
      initial: initial ?? '',
      hint: hint,
      helper: helper,
      confirmLabel: confirmLabel,
      obscure: obscure,
      trim: trim,
      capitalization: capitalization,
    ),
  );
}

class _TextInputDialog extends StatefulWidget {
  final String title;
  final String initial;
  final String? hint;
  final String? helper;
  final String confirmLabel;
  final bool obscure;
  final bool trim;
  final TextCapitalization capitalization;

  const _TextInputDialog({
    required this.title,
    required this.initial,
    required this.hint,
    required this.helper,
    required this.confirmLabel,
    required this.obscure,
    required this.trim,
    required this.capitalization,
  });

  @override
  State<_TextInputDialog> createState() => _TextInputDialogState();
}

class _TextInputDialogState extends State<_TextInputDialog> {
  late final TextEditingController _ctrl =
      TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() =>
      Navigator.pop(context, widget.trim ? _ctrl.text.trim() : _ctrl.text);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title,
          style: const TextStyle(fontWeight: FontWeight.w700)),
      content: TextField(
        controller: _ctrl,
        autofocus: true,
        obscureText: widget.obscure,
        textCapitalization: widget.capitalization,
        decoration: InputDecoration(
          hintText: widget.hint,
          helperText: widget.helper,
          helperMaxLines: 3,
          border: const OutlineInputBorder(),
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}
