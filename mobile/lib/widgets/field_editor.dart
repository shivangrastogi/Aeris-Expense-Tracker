import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/category.dart';
import '../utils/amount_input_formatter.dart';
import '../utils/formatters.dart';

/// Small bottom sheets that edit **one** field of an existing entry
/// (transaction, lent/borrowed entry…). Tapping "Note" shows just a note box,
/// tapping the amount shows just an amount box — never the whole add form.
///
/// Each returns the new value, or null if the sheet was dismissed.

/// Edits a single line / paragraph of text. Returns the trimmed text (empty
/// string when the user cleared it), or null if cancelled.
Future<String?> editTextField(
  BuildContext context, {
  required String title,
  required String initial,
  String? label,
  String? hint,
  IconData icon = Icons.edit_outlined,
  int maxLength = 200,
  bool multiline = false,
  bool required = false,
  TextCapitalization capitalization = TextCapitalization.sentences,
}) {
  return _showEditorSheet<String>(
    context,
    title: title,
    builder: (ctx, submit) => _TextEditor(
      initial: initial,
      label: label ?? title,
      hint: hint,
      icon: icon,
      maxLength: maxLength,
      multiline: multiline,
      required: required,
      capitalization: capitalization,
      onSubmit: submit,
    ),
  );
}

/// Edits an amount. [initialInr] and the result are in INR (what's stored);
/// the user types in the display currency. Supports "120+45" style math.
Future<double?> editAmountField(
  BuildContext context, {
  required String title,
  required double initialInr,
}) {
  return _showEditorSheet<double>(
    context,
    title: title,
    builder: (ctx, submit) =>
        _AmountEditor(initialInr: initialInr, onSubmit: submit),
  );
}

/// Picks a category from a compact grid. Returns the category id.
Future<String?> editCategoryField(
  BuildContext context, {
  required String selected,
}) {
  return showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (s) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _SheetTitle('Category'),
            const SizedBox(height: 12),
            Flexible(
              child: GridView.count(
                shrinkWrap: true,
                crossAxisCount: 4,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 1.05,
                children: [
                  for (final c in Categories.all)
                    _CategoryCell(
                      category: c,
                      selected: c.id == selected,
                      onTap: () => Navigator.pop(s, c.id),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Picks a date, then a time, capped at "now". Returns null if cancelled.
Future<DateTime?> editDateTimeField(
  BuildContext context, {
  required DateTime initial,
}) async {
  final now = DateTime.now();
  final day = await showDatePicker(
    context: context,
    initialDate: initial.isAfter(now) ? now : initial,
    firstDate: DateTime(2015),
    lastDate: now,
  );
  if (day == null || !context.mounted) return null;
  final time = await showTimePicker(
      context: context, initialTime: TimeOfDay.fromDateTime(initial));
  final t = time ?? TimeOfDay.fromDateTime(initial);
  final picked = DateTime(day.year, day.month, day.day, t.hour, t.minute);
  return picked.isAfter(now) ? now : picked;
}

// ── Internals ─────────────────────────────────────────────────

Future<T?> _showEditorSheet<T>(
  BuildContext context, {
  required String title,
  required Widget Function(BuildContext, ValueChanged<T>) builder,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.fromLTRB(
          20, 0, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SheetTitle(title),
            const SizedBox(height: 14),
            builder(ctx, (v) => Navigator.pop(ctx, v)),
          ],
        ),
      ),
    ),
  );
}

class _SheetTitle extends StatelessWidget {
  final String text;
  const _SheetTitle(this.text);

  @override
  Widget build(BuildContext context) => Text(text,
      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800));
}

class _SaveButton extends StatelessWidget {
  final VoidCallback onPressed;
  const _SaveButton({required this.onPressed});

  @override
  Widget build(BuildContext context) => FilledButton(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(50),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        onPressed: onPressed,
        child: const Text('Save',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      );
}

class _TextEditor extends StatefulWidget {
  final String initial;
  final String label;
  final String? hint;
  final IconData icon;
  final int maxLength;
  final bool multiline;
  final bool required;
  final TextCapitalization capitalization;
  final ValueChanged<String> onSubmit;

  const _TextEditor({
    required this.initial,
    required this.label,
    required this.hint,
    required this.icon,
    required this.maxLength,
    required this.multiline,
    required this.required,
    required this.capitalization,
    required this.onSubmit,
  });

  @override
  State<_TextEditor> createState() => _TextEditorState();
}

class _TextEditorState extends State<_TextEditor> {
  late final _ctrl = TextEditingController(text: widget.initial)
    ..selection = TextSelection.collapsed(offset: widget.initial.length);
  bool _error = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() {
    final v = _ctrl.text.trim();
    if (widget.required && v.isEmpty) {
      setState(() => _error = true);
      HapticFeedback.heavyImpact();
      return;
    }
    widget.onSubmit(v);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _ctrl,
          autofocus: true,
          maxLength: widget.maxLength,
          minLines: 1,
          maxLines: widget.multiline ? 4 : 1,
          textCapitalization: widget.capitalization,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _submit(),
          onChanged: (_) {
            if (_error) setState(() => _error = false);
          },
          decoration: InputDecoration(
            labelText: widget.label,
            hintText: widget.hint,
            prefixIcon: Icon(widget.icon),
            counterText: '',
            errorText: _error ? "This can't be empty" : null,
          ),
        ),
        const SizedBox(height: 16),
        _SaveButton(onPressed: _submit),
      ],
    );
  }
}

class _AmountEditor extends StatefulWidget {
  final double initialInr;
  final ValueChanged<double> onSubmit;
  const _AmountEditor({required this.initialInr, required this.onSubmit});

  @override
  State<_AmountEditor> createState() => _AmountEditorState();
}

class _AmountEditorState extends State<_AmountEditor> {
  late final String _initialText;
  late final TextEditingController _ctrl;
  bool _error = false;

  static String _plain(double v) =>
      v % 1 == 0 ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

  @override
  void initState() {
    super.initState();
    _initialText = _plain(widget.initialInr / kCurrency.rate);
    _ctrl = TextEditingController(text: _initialText)
      ..selection =
          TextSelection(baseOffset: 0, extentOffset: _initialText.length);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() {
    // Unchanged text keeps the exact stored value (no currency drift).
    if (_ctrl.text == _initialText) {
      widget.onSubmit(widget.initialInr);
      return;
    }
    final v = evalAmount(_ctrl.text);
    if (v == null) {
      setState(() => _error = true);
      HapticFeedback.heavyImpact();
      return;
    }
    widget.onSubmit((v * kCurrency.rate * 100).roundToDouble() / 100);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _ctrl,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: const [AmountInputFormatter(allowMath: true)],
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _submit(),
          onChanged: (_) {
            if (_error) setState(() => _error = false);
          },
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
          decoration: InputDecoration(
            labelText: 'Amount',
            prefixText: '${kCurrency.symbol.trim()} ',
            errorText: _error ? 'Enter an amount greater than 0' : null,
          ),
        ),
        const SizedBox(height: 16),
        _SaveButton(onPressed: _submit),
      ],
    );
  }
}

class _CategoryCell extends StatelessWidget {
  final ExpenseCategory category;
  final bool selected;
  final VoidCallback onTap;
  const _CategoryCell({
    required this.category,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final c = category.color;
    final label = category.label.split(RegExp(r' [&/] ')).first;
    return Material(
      color:
          selected ? c.withValues(alpha: 0.16) : scheme.surfaceContainerLowest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: selected ? c : scheme.outlineVariant.withValues(alpha: 0.5),
          width: selected ? 1.6 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(category.icon, size: 22, color: c),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                    color:
                        selected ? scheme.onSurface : scheme.onSurfaceVariant,
                  )),
            ),
          ],
        ),
      ),
    );
  }
}
