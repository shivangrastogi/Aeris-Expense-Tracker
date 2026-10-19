import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/theme.dart';
import '../../models/category.dart';
import '../../models/custom_category.dart';
import '../../providers/auth_provider.dart';
import '../../providers/prefs_data_provider.dart';
import '../../providers/transactions_provider.dart';
import '../../services/category_rules.dart';
import '../../services/sms_templates.dart';
import '../../widgets/aeris_toast.dart';

/// Categories & learning: your own categories, the built-in ones, and what
/// AERIS has learned from your corrections (and a way to undo it).
class CategoriesScreen extends ConsumerStatefulWidget {
  const CategoriesScreen({super.key});

  @override
  ConsumerState<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends ConsumerState<CategoriesScreen> {
  late Future<Map<String, String>> _rules = CategoryRules.instance.all();

  void _toast(String m) =>
      ScaffoldMessenger.of(context).showToast(SnackBar(content: Text(m)));

  Future<void> _edit([ExpenseCategory? existing]) async {
    final saved = await showModalBottomSheet<ExpenseCategory>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _CategoryEditor(existing: existing),
    );
    final uid = ref.read(currentUserIdProvider);
    if (saved == null || uid == null) return;
    await ref.read(firestoreServiceProvider).setCustomCategory(uid, saved);
    _toast(existing == null ? '${saved.label} added' : 'Saved');
  }

  Future<void> _delete(ExpenseCategory c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text('Delete ${c.label}?'),
        content: const Text(
            'Transactions in it will show as "Other". You can recategorise '
            'them any time.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(d, false),
              child: const Text('Cancel')),
          FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: AerisColors.danger(context),
                  foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(d, true),
              child: const Text('Delete')),
        ],
      ),
    );
    final uid = ref.read(currentUserIdProvider);
    if (ok != true || uid == null) return;
    await ref.read(firestoreServiceProvider).deleteCustomCategory(uid, c.id);
    _toast('${c.label} deleted');
  }

  Future<void> _forgetRule(String merchant) async {
    await CategoryRules.instance.forget(merchant);
    setState(() => _rules = CategoryRules.instance.all());
    _toast('Forgot the rule for $merchant');
  }

  Future<void> _resetFormats() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Reset learned SMS formats?'),
        content: const Text(
            'AERIS forgets the amount / type fixes you taught it for bank '
            'message formats. Your transactions don\'t change.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(d, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(d, true),
              child: const Text('Reset')),
        ],
      ),
    );
    if (ok != true) return;
    await SmsTemplates.instance.clear();
    _toast('Learned SMS formats reset');
  }

  @override
  Widget build(BuildContext context) {
    final custom = ref.watch(customCategoriesProvider).valueOrNull ?? const [];
    final muted = AerisColors.muted(context);

    Widget catTile(ExpenseCategory c, {bool editable = false}) => ListTile(
          leading: CircleAvatar(
            radius: 18,
            backgroundColor: c.color.withValues(alpha: 0.16),
            child: Icon(c.icon, color: c.color, size: 20),
          ),
          title: Text(c.label),
          trailing: editable
              ? IconButton(
                  tooltip: 'Delete ${c.label}',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _delete(c))
              : null,
          onTap: editable ? () => _edit(c) : null,
        );

    return Scaffold(
      appBar: AppBar(title: const Text('Categories & learning')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
        children: [
          const SectionLabel('Your categories'),
          AerisCard(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(children: [
              for (final c in custom) catTile(c, editable: true),
              ListTile(
                leading: const Icon(Icons.add_rounded),
                title: const Text('Add a category'),
                subtitle: custom.isEmpty
                    ? const Text('e.g. Pets, Gym, Kids, Gifts')
                    : null,
                onTap: () => _edit(),
              ),
            ]),
          ),
          const SizedBox(height: 20),
          const SectionLabel('Learned from you'),
          FutureBuilder<Map<String, String>>(
            future: _rules,
            builder: (context, snap) {
              final rules = snap.data ?? const {};
              return AerisCard(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(children: [
                  if (rules.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                          'When you change a merchant\'s category, AERIS '
                          'remembers it here for next time.',
                          style: TextStyle(color: muted)),
                    ),
                  for (final e in rules.entries)
                    ListTile(
                      leading: Icon(Categories.byId(e.value).icon,
                          color: Categories.byId(e.value).color),
                      title: Text(e.key),
                      subtitle: Text('→ ${Categories.byId(e.value).label}'),
                      trailing: IconButton(
                          tooltip: 'Forget',
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () => _forgetRule(e.key)),
                    ),
                  ListTile(
                    leading: const Icon(Icons.restart_alt_rounded),
                    title: const Text('Reset learned SMS formats'),
                    subtitle: const Text(
                        'Amount / type fixes taught for bank messages'),
                    onTap: _resetFormats,
                  ),
                ]),
              );
            },
          ),
          const SizedBox(height: 20),
          const SectionLabel('Built in'),
          AerisCard(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(children: [
              for (final c in Categories.builtIn) catTile(c),
            ]),
          ),
        ],
      ),
    );
  }
}

class _CategoryEditor extends StatefulWidget {
  final ExpenseCategory? existing;
  const _CategoryEditor({this.existing});

  @override
  State<_CategoryEditor> createState() => _CategoryEditorState();
}

class _CategoryEditorState extends State<_CategoryEditor> {
  late final _name = TextEditingController(text: widget.existing?.label ?? '');
  late IconData _icon = widget.existing?.icon ?? CustomCategories.icons[1];
  late Color _color = widget.existing?.color ?? CustomCategories.colors[0];

  @override
  void initState() {
    super.initState();
    _name.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final name = _name.text.trim();
    final taken = Categories.all.any((c) =>
        c.id != widget.existing?.id &&
        c.label.toLowerCase() == name.toLowerCase());
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(widget.existing == null ? 'New category' : 'Edit category',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            TextField(
              controller: _name,
              autofocus: widget.existing == null,
              textCapitalization: TextCapitalization.words,
              maxLength: 24,
              decoration: InputDecoration(
                hintText: 'Name (e.g. Pets)',
                errorText: taken ? 'You already have a category called that' : null,
                prefixIcon: Icon(_icon, color: _color),
              ),
            ),
            const SizedBox(height: 8),
            const Text('Icon', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final i in CustomCategories.icons)
                InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => setState(() => _icon = i),
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: i == _icon ? _color.withValues(alpha: 0.16) : null,
                      border: Border.all(
                          color: i == _icon ? _color : AerisColors.line(context)),
                    ),
                    child: Icon(i, color: i == _icon ? _color : null),
                  ),
                ),
            ]),
            const SizedBox(height: 14),
            const Text('Colour', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Wrap(spacing: 10, runSpacing: 10, children: [
              for (final c in CustomCategories.colors)
                GestureDetector(
                  onTap: () => setState(() => _color = c),
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: c,
                      shape: BoxShape.circle,
                      border: c == _color
                          ? Border.all(
                              color: Theme.of(context).colorScheme.onSurface,
                              width: 2.5)
                          : null,
                    ),
                  ),
                ),
            ]),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: name.isEmpty || taken
                    ? null
                    : () => Navigator.pop(
                        context,
                        ExpenseCategory(
                          id: widget.existing?.id ?? 'c_${const Uuid().v4()}',
                          label: name,
                          icon: _icon,
                          color: _color,
                        )),
                child: const Text('Save'),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
