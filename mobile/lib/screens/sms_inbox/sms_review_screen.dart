import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/routes.dart';
import '../../core/theme.dart';
import '../../models/category.dart';
import '../../models/transaction.dart';
import '../../providers/auth_provider.dart';
import '../../providers/gamification_provider.dart';
import '../../providers/transactions_provider.dart';
import '../../utils/motion.dart';
import '../../utils/formatters.dart';
import '../../widgets/text_input_dialog.dart';

class SmsReviewScreen extends ConsumerStatefulWidget {
  const SmsReviewScreen({super.key});

  @override
  ConsumerState<SmsReviewScreen> createState() => _SmsReviewScreenState();
}

class _SmsReviewScreenState extends ConsumerState<SmsReviewScreen> {
  final Set<String> _selected = {};
  bool _selectMode = false;
  final Map<String, String> _catOverrides = {};
  final Map<String, String?> _merchantOverrides = {};

  // One-at-a-time review deck (default) vs the full list. Rows handled in the
  // deck are hidden immediately via [_gone], so the next card shows without
  // waiting for the Firestore stream to catch up.
  bool _deck = true;
  final Set<String> _gone = {};

  // ── Selection helpers ──────────────────────────────────────

  void _enterSelectMode(String id) {
    setState(() {
      _selectMode = true;
      _selected.add(id);
    });
  }

  void _exitSelectMode() {
    setState(() {
      _selectMode = false;
      _selected.clear();
    });
  }

  void _toggleSelect(String id) {
    setState(() {
      if (_selected.contains(id)) {
        _selected.remove(id);
        if (_selected.isEmpty) _selectMode = false;
      } else {
        _selected.add(id);
      }
    });
  }

  void _selectAll(List<Transaction> pending) {
    setState(() => _selected.addAll(pending.map((t) => t.id)));
  }

  // ── Effective field helpers ────────────────────────────────

  String _catFor(Transaction t) => _catOverrides[t.id] ?? t.categoryId;
  String? _merchantFor(Transaction t) => _merchantOverrides.containsKey(t.id)
      ? _merchantOverrides[t.id]
      : t.merchant;

  // ── Accept / ignore ────────────────────────────────────────

  Future<void> _acceptOne(BuildContext context, Transaction txn) async {
    final uid = ref.read(currentUserIdProvider);
    if (uid == null) return;
    final messenger = ScaffoldMessenger.of(context);
    await ref.read(firestoreServiceProvider).updateTransaction(
          uid,
          txn.copyWith(
            categoryId: _catFor(txn),
            merchant: _merchantFor(txn),
            reviewed: true,
          ),
        );
    final awarded =
        ref.read(gamificationProvider.notifier).rewardCategorization(txn.id);
    if (awarded > 0) {
      messenger.showSnackBar(SnackBar(
        content: Text('+$awarded Aura for categorising 🎉'),
        duration: const Duration(seconds: 2),
      ));
    }
  }

  Future<void> _acceptBulk(BuildContext context, List<Transaction> txns) async {
    final uid = ref.read(currentUserIdProvider);
    if (uid == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final fs = ref.read(firestoreServiceProvider);
    final notifier = ref.read(gamificationProvider.notifier);
    int totalAura = 0;
    for (final t in txns) {
      await fs.updateTransaction(
        uid,
        t.copyWith(
          categoryId: _catFor(t),
          merchant: _merchantFor(t),
          reviewed: true,
        ),
      );
      totalAura += notifier.rewardCategorization(t.id);
    }
    _exitSelectMode();
    final n = txns.length;
    messenger.showSnackBar(SnackBar(
      content: Text(
        totalAura > 0
            ? 'Added $n transaction${n == 1 ? '' : 's'} · +$totalAura Aura 🎉'
            : 'Added $n transaction${n == 1 ? '' : 's'}',
      ),
      duration: const Duration(seconds: 3),
    ));
  }

  Future<void> _ignoreOne(BuildContext context, Transaction txn) async {
    final uid = ref.read(currentUserIdProvider);
    if (uid == null) return;
    await ref.read(firestoreServiceProvider).deleteTransaction(uid, txn.id);
  }

  Future<void> _ignoreBulk(BuildContext context, List<Transaction> txns) async {
    final uid = ref.read(currentUserIdProvider);
    if (uid == null) return;
    final fs = ref.read(firestoreServiceProvider);
    for (final t in txns) {
      await fs.deleteTransaction(uid, t.id);
    }
    _exitSelectMode();
    final n = txns.length;
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Removed $n transaction${n == 1 ? '' : 's'}'),
        duration: const Duration(seconds: 2),
      ));
    }
  }

  // ── Review deck actions ────────────────────────────────────

  /// Add [txn] under [catId] and move to the next card.
  Future<void> _deckAccept(
      BuildContext context, Transaction txn, String catId) async {
    HapticFeedback.selectionClick();
    setState(() {
      _catOverrides[txn.id] = catId;
      _gone.add(txn.id);
    });
    await _acceptOne(context, txn);
  }

  /// Ignore (delete) [txn], with an UNDO that puts it back in the deck.
  Future<void> _deckIgnore(BuildContext context, Transaction txn) async {
    final uid = ref.read(currentUserIdProvider);
    if (uid == null) return;
    final fs = ref.read(firestoreServiceProvider);
    final messenger = ScaffoldMessenger.of(context);
    HapticFeedback.selectionClick();
    setState(() => _gone.add(txn.id));
    await fs.deleteTransaction(uid, txn.id);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(
      content: const Text('Ignored'),
      duration: const Duration(seconds: 4),
      action: SnackBarAction(
        label: 'UNDO',
        onPressed: () async {
          await fs.addTransaction(uid, txn);
          if (mounted) setState(() => _gone.remove(txn.id));
        },
      ),
    ));
  }

  /// Category chips for the deck: the parsed guess first, then the categories
  /// this user files money under most often (same direction).
  List<String> _suggestedCategories(List<Transaction> all, Transaction txn) {
    final counts = <String, int>{};
    for (final t in all) {
      if (t.direction == txn.direction &&
          (t.reviewed || t.source != TxnSource.sms)) {
        counts[t.categoryId] = (counts[t.categoryId] ?? 0) + 1;
      }
    }
    final byUse = counts.keys.toList()
      ..sort((a, b) => counts[b]!.compareTo(counts[a]!));
    final ids = <String>[_catFor(txn), ...byUse];
    for (final c in Categories.all) {
      ids.add(c.id); // pad with defaults for new users
    }
    return ids.toSet().take(6).toList();
  }

  // ── Edit sheets ────────────────────────────────────────────

  void _showCategoryPicker(Transaction txn) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CategoryPickerSheet(
        current: _catFor(txn),
        onPick: (catId) {
          setState(() => _catOverrides[txn.id] = catId);
          Navigator.pop(context);
        },
      ),
    );
  }

  /// Open the SAME full editor the Activity list uses (amount, category,
  /// merchant, date, note, delete), pre-filled with this row's parsed values
  /// plus any inline overrides the user already tapped in. Saving there marks
  /// the transaction reviewed, so it lands in the ledger just like accepting it.
  void _openFullEdit(Transaction txn) {
    Navigator.pushNamed(
      context,
      AppRoutes.txnDetail,
      arguments: txn.copyWith(
        categoryId: _catFor(txn),
        merchant: _merchantFor(txn),
      ),
    );
  }

  Future<void> _showMerchantEditor(Transaction txn) async {
    // promptText() owns the controller, so it survives the dialog's exit
    // animation (disposing it inline used to crash with "used after disposed").
    final result = await promptText(
      context,
      title: 'Edit merchant',
      initial: _merchantFor(txn) ?? '',
      hint: 'Merchant name',
      capitalization: TextCapitalization.words,
    );
    if (result != null) {
      setState(
          () => _merchantOverrides[txn.id] = result.isEmpty ? null : result);
    }
  }

  // ── Build ──────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final txnsAsync = ref.watch(transactionsStreamProvider);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;
    final cardBg = dark ? const Color(0xFF122120) : Colors.white;

    return Scaffold(
      body: SafeArea(
        child: txnsAsync.when(
          loading: () => const _Skeleton(),
          error: (e, _) => Center(child: Text('$e')),
          data: (list) {
            final pending = list
                .where((t) =>
                    t.source == TxnSource.sms &&
                    !t.reviewed &&
                    !_gone.contains(t.id))
                .toList();
            final deck = _deck && !_selectMode;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Header ──────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: _selectMode
                            ? _exitSelectMode
                            : () => Navigator.pop(context),
                        icon: Icon(_selectMode
                            ? Icons.close_rounded
                            : Icons.arrow_back_rounded),
                        style: IconButton.styleFrom(
                          backgroundColor:
                              scheme.onSurface.withValues(alpha: 0.07),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.all(8),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _selectMode
                                  ? '${_selected.length} selected'
                                  : 'Review SMS imports',
                              style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.4),
                            ),
                            Text(
                              pending.isEmpty
                                  ? 'All clear'
                                  : '${pending.length} pending',
                              style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: pending.isEmpty
                                      ? AerisColors.moneyIn(context)
                                      : AerisColors.warning),
                            ),
                          ],
                        ),
                      ),
                      if (pending.isNotEmpty && !_selectMode) ...[
                        IconButton(
                          onPressed: () => setState(() => _deck = !_deck),
                          icon: Icon(
                              _deck
                                  ? Icons.view_list_rounded
                                  : Icons.style_rounded,
                              size: 22),
                          tooltip: _deck ? 'Show as list' : 'Review one by one',
                          style: IconButton.styleFrom(
                            backgroundColor:
                                scheme.onSurface.withValues(alpha: 0.07),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                            padding: const EdgeInsets.all(8),
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      if (pending.isNotEmpty && !deck)
                        _selectMode
                            ? TextButton(
                                onPressed: () =>
                                    _selected.length == pending.length
                                        ? setState(() => _selected.clear())
                                        : _selectAll(pending),
                                child: Text(
                                  _selected.length == pending.length
                                      ? 'Deselect all'
                                      : 'Select all',
                                  style: TextStyle(
                                    color: AerisColors.ink(context),
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                  ),
                                ),
                              )
                            : IconButton(
                                onPressed: () =>
                                    _enterSelectMode(pending.first.id),
                                icon: const Icon(Icons.checklist_rounded,
                                    size: 22),
                                tooltip: 'Multi-select',
                                style: IconButton.styleFrom(
                                  backgroundColor:
                                      scheme.onSurface.withValues(alpha: 0.07),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12)),
                                  padding: const EdgeInsets.all(8),
                                ),
                              ),
                    ],
                  ),
                ),

                // ── List ─────────────────────────────────────────
                Expanded(
                  child: pending.isEmpty
                      ? _emptyState(context)
                      : deck
                          ? _ReviewDeck(
                              txn: pending.first,
                              remaining: pending.length,
                              categoryId: _catFor(pending.first),
                              merchant: _merchantFor(pending.first),
                              suggestions:
                                  _suggestedCategories(list, pending.first),
                              cardBg: cardBg,
                              onAccept: (catId) =>
                                  _deckAccept(context, pending.first, catId),
                              onIgnore: () =>
                                  _deckIgnore(context, pending.first),
                              onEdit: () => _openFullEdit(pending.first),
                              onMerchantTap: () =>
                                  _showMerchantEditor(pending.first),
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                              itemCount: pending.length,
                              itemBuilder: (ctx, i) {
                                final txn = pending[i];
                                // No per-item entrance animation here: in a
                                // ListView.builder items rebuild as they recycle
                                // during a scroll, and a staggered/delayed fade
                                // restarts each time — so fast scrolling left rows
                                // blank until their delay elapsed. Render instantly.
                                return _SmsCard(
                                  key: ValueKey(txn.id),
                                  txn: txn,
                                  cardBg: cardBg,
                                  scheme: scheme,
                                  selectMode: _selectMode,
                                  selected: _selected.contains(txn.id),
                                  catOverride: _catOverrides[txn.id],
                                  merchantOverride:
                                      _merchantOverrides.containsKey(txn.id)
                                          ? _merchantOverrides[txn.id]
                                          : txn.merchant,
                                  onLongPress: () => _enterSelectMode(txn.id),
                                  onTap: _selectMode
                                      ? () => _toggleSelect(txn.id)
                                      : null,
                                  onAccept: () => _acceptOne(context, txn),
                                  onIgnore: () => _ignoreOne(context, txn),
                                  onEdit: () => _openFullEdit(txn),
                                  onCategoryTap: () => _showCategoryPicker(txn),
                                  onMerchantTap: () => _showMerchantEditor(txn),
                                );
                              },
                            ),
                ),

                // ── Bulk action bar ───────────────────────────────
                if (pending.isNotEmpty && !deck)
                  _BulkActionBar(
                    selectMode: _selectMode,
                    hasSelection: _selected.isNotEmpty,
                    onAddSelected: _selected.isEmpty
                        ? null
                        : () => _acceptBulk(
                            context,
                            pending
                                .where((t) => _selected.contains(t.id))
                                .toList()),
                    onAddAll: () => _acceptBulk(context, pending),
                    onIgnoreSelected: _selected.isEmpty
                        ? null
                        : () => _ignoreBulk(
                            context,
                            pending
                                .where((t) => _selected.contains(t.id))
                                .toList()),
                    onIgnoreAll: () => _ignoreBulk(context, pending),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _emptyState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.mark_email_read_rounded,
                size: 52, color: AerisColors.seed.withValues(alpha: 0.5)),
            const SizedBox(height: 14),
            const Text('All clear',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(
              'Auto-imported SMS transactions land here so you can '
              'verify or correct them before they\'re finalised.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 13,
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.5)),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Bulk action bar ───────────────────────────────────────────────────────────

class _BulkActionBar extends StatelessWidget {
  final bool selectMode;
  final bool hasSelection;
  final VoidCallback? onAddSelected;
  final VoidCallback onAddAll;
  final VoidCallback? onIgnoreSelected;
  final VoidCallback onIgnoreAll;

  const _BulkActionBar({
    required this.selectMode,
    required this.hasSelection,
    required this.onAddSelected,
    required this.onAddAll,
    required this.onIgnoreSelected,
    required this.onIgnoreAll,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(
          top: BorderSide(color: scheme.onSurface.withValues(alpha: 0.08)),
        ),
      ),
      child: selectMode
          ? Row(
              children: [
                Expanded(
                  child: _BulkBtn(
                    label: 'Ignore sel.',
                    icon: Icons.delete_outline_rounded,
                    color: AerisColors.moneyOut(context),
                    onTap: onIgnoreSelected,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: _BulkBtn(
                    label: 'Add selected',
                    icon: Icons.check_circle_outline_rounded,
                    color: AerisColors.seed,
                    filled: true,
                    onTap: onAddSelected,
                  ),
                ),
              ],
            )
          : Row(
              children: [
                Expanded(
                  child: _BulkBtn(
                    label: 'Delete all',
                    icon: Icons.delete_sweep_rounded,
                    color: AerisColors.moneyOut(context),
                    onTap: onIgnoreAll,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: _BulkBtn(
                    label: 'Add all',
                    icon: Icons.playlist_add_check_rounded,
                    color: AerisColors.seed,
                    filled: true,
                    onTap: onAddAll,
                  ),
                ),
              ],
            ),
    );
  }
}

class _BulkBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final bool filled;
  final VoidCallback? onTap;

  const _BulkBtn({
    required this.label,
    required this.icon,
    required this.color,
    this.filled = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedOpacity(
        opacity: onTap == null ? 0.38 : 1.0,
        duration: const Duration(milliseconds: 150),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: filled ? color : color.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 17, color: filled ? Colors.white : color),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: filled ? Colors.white : color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Individual SMS card ───────────────────────────────────────────────────────

class _SmsCard extends ConsumerWidget {
  final Transaction txn;
  final Color cardBg;
  final ColorScheme scheme;
  final bool selectMode;
  final bool selected;
  final String? catOverride;
  final String? merchantOverride;
  final VoidCallback onLongPress;
  final VoidCallback? onTap;
  final VoidCallback onAccept;
  final VoidCallback onIgnore;
  final VoidCallback onEdit;
  final VoidCallback onCategoryTap;
  final VoidCallback onMerchantTap;

  const _SmsCard({
    super.key,
    required this.txn,
    required this.cardBg,
    required this.scheme,
    required this.selectMode,
    required this.selected,
    required this.catOverride,
    required this.merchantOverride,
    required this.onLongPress,
    required this.onTap,
    required this.onAccept,
    required this.onIgnore,
    required this.onEdit,
    required this.onCategoryTap,
    required this.onMerchantTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cat = Categories.byId(catOverride ?? txn.categoryId);
    final isCredit = txn.isCredit;
    final edited = catOverride != null || merchantOverride != txn.merchant;

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: selected ? AerisColors.seed.withValues(alpha: 0.08) : cardBg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected
                ? AerisColors.seed.withValues(alpha: 0.5)
                : scheme.onSurface.withValues(alpha: 0.08),
            width: selected ? 1.5 : 1,
          ),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: selected ? 0.02 : 0.05),
                blurRadius: 10,
                offset: const Offset(0, 3)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Bank chip + raw SMS ──────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (txn.smsSender != null)
                          Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: AerisColors.seed.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(99),
                            ),
                            child: Text(txn.smsSender!,
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    color: AerisColors.ink(context))),
                          ),
                        if (txn.smsBody != null)
                          Text(
                            txn.smsBody!,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 11.5,
                                height: 1.4,
                                color: scheme.onSurface.withValues(alpha: 0.6)),
                          ),
                      ],
                    ),
                  ),
                  // Checkbox or edit badge
                  const SizedBox(width: 8),
                  if (selectMode)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: selected ? AerisColors.seed : Colors.transparent,
                        border: Border.all(
                          color: selected
                              ? AerisColors.seed
                              : scheme.onSurface.withValues(alpha: 0.3),
                          width: 2,
                        ),
                      ),
                      child: selected
                          ? const Icon(Icons.check_rounded,
                              size: 14, color: Colors.white)
                          : null,
                    )
                  else if (edited)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AerisColors.warning.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Text('Edited',
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: AerisColors.warning)),
                    ),
                ],
              ),
            ),

            // ── Parsed transaction row ───────────────────────────
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 14),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: scheme.onSurface.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  // Category icon (tappable to change)
                  GestureDetector(
                    onTap: selectMode ? null : onCategoryTap,
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: cat.color.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(cat.icon, size: 18, color: cat.color),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Merchant — tappable to edit
                        GestureDetector(
                          onTap: selectMode ? null : onMerchantTap,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Flexible(
                                child: Text(
                                  merchantOverride ?? cat.label,
                                  style: const TextStyle(
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w700),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (!selectMode) ...[
                                const SizedBox(width: 4),
                                Icon(Icons.edit_rounded,
                                    size: 12,
                                    color: scheme.onSurface
                                        .withValues(alpha: 0.3)),
                              ],
                            ],
                          ),
                        ),
                        // Category label — tappable to change
                        GestureDetector(
                          onTap: selectMode ? null : onCategoryTap,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(cat.label,
                                  style: TextStyle(
                                      fontSize: 11.5,
                                      color: catOverride != null
                                          ? cat.color
                                          : scheme.onSurface
                                              .withValues(alpha: 0.5))),
                              if (!selectMode) ...[
                                const SizedBox(width: 3),
                                Icon(Icons.arrow_drop_down_rounded,
                                    size: 14,
                                    color: catOverride != null
                                        ? cat.color
                                        : scheme.onSurface
                                            .withValues(alpha: 0.3)),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '${isCredit ? '+' : '−'} ${formatRupees(txn.amount)}',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: isCredit
                            ? AerisColors.moneyIn(context)
                            : AerisColors.moneyOut(context)),
                  ),
                ],
              ),
            ),

            // ── Action buttons (normal mode only) ────────────────
            if (!selectMode)
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: _ActionBtn(
                        label: 'Ignore',
                        icon: Icons.close_rounded,
                        color: scheme.onSurface.withValues(alpha: 0.4),
                        bgColor: scheme.onSurface.withValues(alpha: 0.07),
                        onTap: onIgnore,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: _ActionBtn(
                        label: 'Add',
                        icon: Icons.add_rounded,
                        color: Colors.white,
                        bgColor: AerisColors.seed,
                        onTap: onAccept,
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Full editor (amount, category, merchant, date, note) —
                    // the same screen the Activity list opens.
                    _SquareIconBtn(
                      icon: Icons.edit_outlined,
                      color: AerisColors.seed,
                      onTap: onEdit,
                    ),
                    if (txn.smsSender != null) ...[
                      const SizedBox(width: 8),
                      _BlockBtn(
                        onTap: () => _block(context, ref),
                      ),
                    ],
                  ],
                ),
              )
            else
              const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  Future<void> _block(BuildContext context, WidgetRef ref) async {
    final sender = txn.smsSender;
    if (sender == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Block this sender?'),
        content: Text('Messages from "$sender" will no longer be imported. '
            'You can undo this in Settings.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(d, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(d, true),
              child: const Text('Block')),
        ],
      ),
    );
    if (confirm != true) return;
    final uid = ref.read(currentUserIdProvider);
    if (uid == null) return;
    final fs = ref.read(firestoreServiceProvider);
    await fs.blockSender(uid, sender);
    await fs.deleteTransaction(uid, txn.id);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Blocked $sender — future messages ignored.')));
  }
}

// ── Category picker bottom sheet ──────────────────────────────────────────────

class _CategoryPickerSheet extends StatelessWidget {
  final String current;
  final ValueChanged<String> onPick;

  const _CategoryPickerSheet({required this.current, required this.onPick});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final sheetBg = dark ? const Color(0xFF0F1A19) : Colors.white;

    return Container(
      constraints:
          BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.65),
      decoration: BoxDecoration(
        color: sheetBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12, bottom: 16),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: scheme.onSurface.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(99),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Text('Change category',
                style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: scheme.onSurface)),
          ),
          Flexible(
            child: GridView.builder(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              shrinkWrap: true,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 0.85,
              ),
              itemCount: Categories.all.length,
              itemBuilder: (_, i) {
                final cat = Categories.all[i];
                final isSel = cat.id == current;
                return GestureDetector(
                  onTap: () => onPick(cat.id),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    decoration: BoxDecoration(
                      color: isSel
                          ? cat.color.withValues(alpha: 0.2)
                          : scheme.onSurface.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(14),
                      border: isSel
                          ? Border.all(color: cat.color, width: 1.5)
                          : null,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(cat.icon,
                            size: 24,
                            color: isSel
                                ? cat.color
                                : scheme.onSurface.withValues(alpha: 0.6)),
                        const SizedBox(height: 6),
                        Text(
                          cat.label,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w600,
                            color: isSel
                                ? cat.color
                                : scheme.onSurface.withValues(alpha: 0.7),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ── Small action button ────────────────────────────────────────────────────────

class _ActionBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final Color bgColor;
  final VoidCallback onTap;

  const _ActionBtn({
    required this.label,
    required this.icon,
    required this.color,
    required this.bgColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 5),
            Text(label,
                style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w700, color: color)),
          ],
        ),
      ),
    );
  }
}

// ── Generic square icon button (Edit, etc.) ───────────────────────────────────

class _SquareIconBtn extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _SquareIconBtn({
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, size: 18, color: color),
      ),
    );
  }
}

// ── Block sender mini button ──────────────────────────────────────────────────

class _BlockBtn extends StatelessWidget {
  final VoidCallback onTap;

  const _BlockBtn({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: AerisColors.moneyOut(context).withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(Icons.block_rounded,
            size: 18, color: AerisColors.moneyOut(context)),
      ),
    );
  }
}

// ── Loading skeleton ───────────────────────────────────────────────────────────

class _Skeleton extends StatelessWidget {
  const _Skeleton();
  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context)
        .colorScheme
        .surfaceContainerHighest
        .withValues(alpha: 0.4);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        for (var i = 0; i < 5; i++)
          Container(
            height: 160,
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
                color: base, borderRadius: BorderRadius.circular(20)),
          ).shimmerLoop(context,
              duration: 1200.ms,
              color:
                  Theme.of(context).colorScheme.surface.withValues(alpha: 0.5)),
      ],
    );
  }
}

// ── One-at-a-time review deck ─────────────────────────────────
//
// The top pending SMS as a single card. Tap a category chip to add it under
// that category; swipe right to add as suggested; swipe left to ignore.
class _ReviewDeck extends StatelessWidget {
  final Transaction txn;
  final int remaining;
  final String categoryId;
  final String? merchant;
  final List<String> suggestions;
  final Color cardBg;
  final ValueChanged<String> onAccept;
  final VoidCallback onIgnore;
  final VoidCallback onEdit;
  final VoidCallback onMerchantTap;

  const _ReviewDeck({
    required this.txn,
    required this.remaining,
    required this.categoryId,
    required this.merchant,
    required this.suggestions,
    required this.cardBg,
    required this.onAccept,
    required this.onIgnore,
    required this.onEdit,
    required this.onMerchantTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final money = txn.isCredit
        ? AerisColors.moneyIn(context)
        : AerisColors.moneyOut(context);
    final muted = scheme.onSurfaceVariant;

    Widget swipeBg(Color c, IconData icon, String label, Alignment a) =>
        Container(
          alignment: a,
          padding: const EdgeInsets.symmetric(horizontal: 28),
          decoration: BoxDecoration(
              color: c.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(24)),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, color: c, size: 30),
            const SizedBox(height: 4),
            Text(label,
                style: TextStyle(
                    color: c, fontWeight: FontWeight.w800, fontSize: 13)),
          ]),
        );

    final card = Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: scheme.onSurface.withValues(alpha: 0.08)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 16,
              offset: const Offset(0, 6)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(children: [
            if (txn.smsSender != null)
              Text(txn.smsSender!,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: AerisColors.ink(context))),
            const Spacer(),
            Text(relativeDate(txn.timestamp),
                style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w600, color: muted)),
          ]),
          const SizedBox(height: 14),
          Text(
            '${txn.isCredit ? '+' : '−'}${formatRupees(txn.amount, decimals: txn.amount % 1 != 0)}',
            style: TextStyle(
                fontSize: 36,
                fontWeight: FontWeight.w800,
                letterSpacing: -1,
                color: money),
          ),
          const SizedBox(height: 4),
          InkWell(
            onTap: onMerchantTap,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Flexible(
                  child: Text(
                    merchant?.isNotEmpty == true
                        ? merchant!
                        : (txn.isCredit ? 'Add payer' : 'Add merchant'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(width: 6),
                Icon(Icons.edit_outlined, size: 15, color: muted),
              ]),
            ),
          ),
          if (txn.smsBody != null) ...[
            const SizedBox(height: 10),
            Text(txn.smsBody!,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, height: 1.4, color: muted)),
          ],
          const SizedBox(height: 16),
          Text('Add as', style: TextStyle(fontSize: 12.5, color: muted)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final id in suggestions)
                Builder(builder: (context) {
                  final c = Categories.byId(id);
                  final guess = id == categoryId;
                  return ActionChip(
                    avatar: Icon(c.icon, size: 16, color: c.color),
                    label: Text(c.label.split(' ').first),
                    backgroundColor:
                        guess ? c.color.withValues(alpha: 0.16) : null,
                    side: BorderSide(
                        color: guess ? c.color : scheme.outlineVariant),
                    onPressed: () => onAccept(id),
                  );
                }),
            ],
          ),
        ],
      ),
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        Dismissible(
          key: ValueKey('deck-${txn.id}'),
          background: swipeBg(AerisColors.moneyIn(context), Icons.check_rounded,
              'Add', Alignment.centerLeft),
          secondaryBackground: swipeBg(AerisColors.moneyOut(context),
              Icons.close_rounded, 'Ignore', Alignment.centerRight),
          onDismissed: (dir) => dir == DismissDirection.startToEnd
              ? onAccept(categoryId)
              : onIgnore(),
          child: card,
        ),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: onIgnore,
              icon: const Icon(Icons.close_rounded),
              label: const Text('Ignore'),
              style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48)),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: FilledButton.icon(
              onPressed: () => onAccept(categoryId),
              icon: const Icon(Icons.check_rounded),
              label: Text(
                  'Add as ${Categories.byId(categoryId).label.split(' ').first}'),
              style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48)),
            ),
          ),
        ]),
        const SizedBox(height: 6),
        Center(
          child: TextButton(
            onPressed: onEdit,
            child: const Text('Edit all details'),
          ),
        ),
        const SizedBox(height: 4),
        Center(
          child: Text(
            '$remaining left · swipe right to add, left to ignore',
            style: TextStyle(fontSize: 12, color: muted),
          ),
        ),
      ],
    );
  }
}
