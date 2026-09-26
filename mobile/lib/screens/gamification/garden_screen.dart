import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../models/town.dart';
import '../../providers/gamification_provider.dart';
import '../../providers/goals_provider.dart';
import '../../utils/formatters.dart';

const _cols = 8;
const _rows = 11;
const _tileCount = _cols * _rows;

/// Aeris Town: an 8x11 plot grid the user builds up with the Aura they earn
/// by saving, beating budgets and winning challenges. Each plot holds a
/// [TownElement] that can be upgraded through its emoji evolution chain.
class GardenScreen extends ConsumerStatefulWidget {
  const GardenScreen({super.key});
  @override
  ConsumerState<GardenScreen> createState() => _GardenScreenState();
}

class _GardenScreenState extends ConsumerState<GardenScreen> {
  String _category = TownElements.categories.first;
  String _selectedElement =
      TownElements.inCategory(TownElements.categories.first).first.id;
  int? _selectedTile;

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _tapTile(int idx) {
    final g = ref.read(gamificationProvider);
    if (g.town.containsKey(idx)) {
      setState(() => _selectedTile = _selectedTile == idx ? null : idx);
      return;
    }
    final el = TownElements.byId(_selectedElement);
    final goals = ref.read(goalsStreamProvider).valueOrNull ?? const [];
    final totalSaved = goals.fold<double>(0, (s, x) => s + x.saved);
    if (el.lock != null && totalSaved < el.lock!) {
      _toast(
          '${el.name} unlocks once you\'ve saved ${formatRupees(el.lock!.toDouble(), compact: true)}');
      return;
    }
    final ok =
        ref.read(gamificationProvider.notifier).placeTile(idx, el.id, el.base);
    if (!ok) _toast('Need ${el.base} Aura to place ${el.name}');
  }

  @override
  Widget build(BuildContext context) {
    final g = ref.watch(gamificationProvider);
    final ctrl = ref.read(gamificationProvider.notifier);
    final goals = ref.watch(goalsStreamProvider).valueOrNull ?? const [];
    final totalSaved = goals.fold<double>(0, (s, x) => s + x.saved);
    final theme = GardenThemes.byId(g.gardenTheme);
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = dark ? const Color(0xFF122120) : Colors.white;
    final divColor = scheme.onSurface.withValues(alpha: 0.08);

    final placedCount = g.town.length;
    final totalLevels = g.town.values.fold<int>(0, (s, t) => s + t.lvl + 1);
    final townLevel = (totalLevels / 6).floor() + 1;

    final selCell = _selectedTile != null ? g.town[_selectedTile!] : null;
    final selElement = selCell != null ? TownElements.byId(selCell.type) : null;

    return Scaffold(
      appBar: AppBar(title: const Text('Aeris Town')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
        children: [
          Row(
            children: [
              Expanded(
                  child: _StatCard(
                      label: 'Town',
                      value: 'Lv $townLevel',
                      cardBg: cardBg,
                      divColor: divColor)),
              const SizedBox(width: 10),
              Expanded(
                  child: _StatCard(
                      label: 'Plots',
                      value: '$placedCount/$_tileCount',
                      cardBg: cardBg,
                      divColor: divColor)),
              const SizedBox(width: 10),
              Expanded(
                  child: _StatCard(
                      label: 'Aura',
                      value: '${g.available}',
                      cardBg: cardBg,
                      divColor: divColor,
                      icon: Icons.bolt_rounded,
                      iconColor: AerisColors.warning)),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 36,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: GardenThemes.all.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final t = GardenThemes.all[i];
                final active = t.id == g.gardenTheme;
                return GestureDetector(
                  onTap: () => ctrl.setGardenTheme(t.id),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: active ? AerisColors.seed : cardBg,
                      borderRadius: BorderRadius.circular(99),
                      border: Border.all(
                          color: active ? AerisColors.seed : divColor),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      t.label,
                      style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: active
                              ? Colors.white
                              : scheme.onSurface.withValues(alpha: 0.7)),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          _TownGrid(
            town: g.town,
            theme: theme,
            selected: _selectedTile,
            onTap: _tapTile,
          ),
          const SizedBox(height: 6),
          Text(
            'Tap an empty plot to build · tap a plot you own to upgrade or remove',
            style: TextStyle(
                fontSize: 11.5,
                color: scheme.onSurface.withValues(alpha: 0.45)),
          ),
          const SizedBox(height: 14),
          if (selCell != null && selElement != null)
            _UpgradePanel(
              element: selElement,
              cell: selCell,
              available: g.available,
              cardBg: cardBg,
              divColor: divColor,
              onUpgrade: () {
                final cost = TownElements.upgradeCost(selElement, selCell.lvl);
                if (!ctrl.upgradeTile(_selectedTile!, cost)) {
                  _toast('Need $cost Aura to upgrade');
                }
              },
              onDelete: () {
                ctrl.clearTile(_selectedTile!);
                setState(() => _selectedTile = null);
              },
            )
          else
            _BuildPalette(
              category: _category,
              selectedId: _selectedElement,
              totalSaved: totalSaved,
              cardBg: cardBg,
              divColor: divColor,
              onCategory: (c) => setState(() {
                _category = c;
                _selectedElement = TownElements.inCategory(c).first.id;
              }),
              onSelect: (id) => setState(() => _selectedElement = id),
            ),
        ],
      ),
    );
  }
}

// ── Status chip ───────────────────────────────────────────────────────────

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final Color cardBg;
  final Color divColor;
  final IconData? icon;
  final Color? iconColor;

  const _StatCard({
    required this.label,
    required this.value,
    required this.cardBg,
    required this.divColor,
    this.icon,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: divColor),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null)
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Icon(icon, size: 14, color: iconColor),
                ),
              Text(value,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 2),
          Text(label,
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurface.withValues(alpha: 0.5))),
        ],
      ),
    );
  }
}

// ── 8x11 plot grid ───────────────────────────────────────────────────────────

class _TownGrid extends StatelessWidget {
  final Map<int, TownTile> town;
  final GardenTheme theme;
  final int? selected;
  final ValueChanged<int> onTap;

  const _TownGrid({
    required this.town,
    required this.theme,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 380,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        gradient: theme.skyGradient,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Stack(
        children: [
          const Positioned(
              top: 2,
              right: 10,
              child: Text('☀️', style: TextStyle(fontSize: 22))),
          const Positioned(
            top: 4,
            left: 10,
            child: Opacity(
                opacity: 0.85,
                child: Text('☁️', style: TextStyle(fontSize: 18))),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 26),
            child: GridView.builder(
              itemCount: _tileCount,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: _cols,
                crossAxisSpacing: 3,
                mainAxisSpacing: 3,
                childAspectRatio: 1,
              ),
              itemBuilder: (_, idx) {
                final cell = town[idx];
                final el = cell != null ? TownElements.byId(cell.type) : null;
                final row = idx ~/ _cols;
                final col = idx % _cols;
                final ground = (row + col).isEven ? theme.g1 : theme.g2;
                final isSel = selected == idx;
                return GestureDetector(
                  onTap: () => onTap(idx),
                  child: Container(
                    decoration: BoxDecoration(
                      color: ground,
                      borderRadius: BorderRadius.circular(6),
                      border: isSel
                          ? Border.all(color: Colors.white, width: 2)
                          : Border.all(
                              color: Colors.white.withValues(alpha: 0.15)),
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        if (el != null && cell != null)
                          Text(el.emojiAt(cell.lvl),
                              style: const TextStyle(fontSize: 17)),
                        if (cell != null && cell.lvl > 0)
                          Positioned(
                            top: 1,
                            right: 1,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 3, vertical: 0.5),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.35),
                                borderRadius: BorderRadius.circular(5),
                              ),
                              child: Text('${cell.lvl + 1}',
                                  style: const TextStyle(
                                      fontSize: 8,
                                      fontWeight: FontWeight.w800,
                                      color: Colors.white)),
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

// ── Selected-plot upgrade/delete panel ──────────────────────────────────────

class _UpgradePanel extends StatelessWidget {
  final TownElement element;
  final TownTile cell;
  final int available;
  final Color cardBg;
  final Color divColor;
  final VoidCallback onUpgrade;
  final VoidCallback onDelete;

  const _UpgradePanel({
    required this.element,
    required this.cell,
    required this.available,
    required this.cardBg,
    required this.divColor,
    required this.onUpgrade,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final maxed = cell.lvl >= element.chain.length - 1;
    final cost = maxed ? 0 : TownElements.upgradeCost(element, cell.lvl);
    final canAfford = available >= cost;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: divColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: scheme.onSurface.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(14),
                ),
                alignment: Alignment.center,
                child: Text(element.emojiAt(cell.lvl),
                    style: const TextStyle(fontSize: 28)),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${element.name} · Lv ${cell.lvl + 1}',
                        style: const TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 15)),
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        for (var i = 0; i < element.chain.length; i++)
                          Padding(
                            padding: const EdgeInsets.only(right: 5),
                            child: Opacity(
                              opacity: i <= cell.lvl ? 1 : 0.3,
                              child: Text(element.chain[i],
                                  style: const TextStyle(fontSize: 17)),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              OutlinedButton(
                onPressed: onDelete,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AerisColors.moneyOut(context),
                  side: BorderSide(
                      color: AerisColors.moneyOut(context).withValues(alpha: 0.4)),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: const Icon(Icons.delete_outline_rounded, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: maxed
                    ? Container(
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: scheme.onSurface.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text('Max level',
                            style: TextStyle(
                                fontWeight: FontWeight.w800,
                                color:
                                    scheme.onSurface.withValues(alpha: 0.5))),
                      )
                    : FilledButton(
                        onPressed: canAfford ? onUpgrade : null,
                        style: FilledButton.styleFrom(
                          backgroundColor: AerisColors.seed,
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        child: Text(
                            'Upgrade to ${element.chain[cell.lvl + 1]} · $cost ✦',
                            style:
                                const TextStyle(fontWeight: FontWeight.w800)),
                      ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Build palette (category tabs + element cards + info bar) ───────────────

class _BuildPalette extends StatelessWidget {
  final String category;
  final String selectedId;
  final double totalSaved;
  final Color cardBg;
  final Color divColor;
  final ValueChanged<String> onCategory;
  final ValueChanged<String> onSelect;

  const _BuildPalette({
    required this.category,
    required this.selectedId,
    required this.totalSaved,
    required this.cardBg,
    required this.divColor,
    required this.onCategory,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final selected = TownElements.byId(selectedId);
    final locked = selected.lock != null && totalSaved < selected.lock!;
    final items = TownElements.inCategory(category);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            for (final c in TownElements.categories)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: () => onCategory(c),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: category == c ? AerisColors.seed : cardBg,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: category == c ? AerisColors.seed : divColor),
                      ),
                      child: Text(
                        c,
                        style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: category == c
                                ? Colors.white
                                : scheme.onSurface.withValues(alpha: 0.7)),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 104,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(width: 9),
            itemBuilder: (_, i) {
              final el = items[i];
              final on = el.id == selectedId;
              final lockedEl = el.lock != null && totalSaved < el.lock!;
              return GestureDetector(
                onTap: () => onSelect(el.id),
                child: Container(
                  width: 84,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 11),
                  decoration: BoxDecoration(
                    color:
                        on ? AerisColors.seed.withValues(alpha: 0.12) : cardBg,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                        color: on ? AerisColors.seed : divColor,
                        width: on ? 1.5 : 1),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Opacity(
                        opacity: lockedEl ? 0.4 : 1,
                        child: Text(el.chain.first,
                            style: const TextStyle(fontSize: 26)),
                      ),
                      const SizedBox(height: 4),
                      Text(el.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w700)),
                      Text('${el.chain.length} levels',
                          style: TextStyle(
                              fontSize: 10,
                              color: scheme.onSurface.withValues(alpha: 0.45))),
                      const SizedBox(height: 3),
                      if (lockedEl)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.lock_rounded,
                                size: 10, color: AerisColors.warning),
                            const SizedBox(width: 2),
                            Text(
                                formatRupees(el.lock!.toDouble(),
                                    compact: true),
                                style: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: AerisColors.warning)),
                          ],
                        )
                      else
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.bolt_rounded,
                                size: 11, color: AerisColors.warning),
                            Text('${el.base}',
                                style: const TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w800)),
                          ],
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color:
                locked ? AerisColors.warning.withValues(alpha: 0.08) : cardBg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: locked
                    ? AerisColors.warning.withValues(alpha: 0.3)
                    : divColor),
          ),
          child: Row(
            children: [
              Text(selected.chain.first, style: const TextStyle(fontSize: 26)),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text.rich(
                      TextSpan(children: [
                        TextSpan(
                            text: '${selected.name}  ',
                            style: const TextStyle(
                                fontWeight: FontWeight.w800, fontSize: 13.5)),
                        TextSpan(
                            text:
                                'grows into ${selected.chain.skip(1).join(' ')}',
                            style: TextStyle(
                                fontSize: 12,
                                color:
                                    scheme.onSurface.withValues(alpha: 0.5))),
                      ]),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      locked
                          ? 'Unlocks once you\'ve saved ${formatRupees(selected.lock!.toDouble(), compact: true)}'
                          : 'Tap any empty plot to place · ${selected.base} Aura',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: locked
                              ? AerisColors.warning
                              : scheme.onSurface.withValues(alpha: 0.6)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
