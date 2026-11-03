import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../models/town_catalog.dart';
import '../../providers/gamification_provider.dart';
import '../../providers/village_provider.dart';
import '../../widgets/aeris_toast.dart';
import '../../widgets/town_painter.dart';
import '../../widgets/ds.dart';

/// Aeris Town — a night city that grows with your money habits.
/// Rules live in models/town_catalog.dart; state in providers/village_provider.
class VillageScreen extends ConsumerStatefulWidget {
  const VillageScreen({super.key});
  @override
  ConsumerState<VillageScreen> createState() => _VillageScreenState();
}

class _VillageScreenState extends ConsumerState<VillageScreen> {
  static const _canvas = Size(760, 560);
  final _viewer = TransformationController();
  String? _sel;
  String? _placing;
  int _now = DateTime.now().millisecondsSinceEpoch;
  late final Timer _tick;

  Iso get _iso => Iso(Offset(_canvas.width / 2, 140), 92);

  /// The viewport the world was last laid out for (re-centre when it changes).
  Size? _viewport;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      ref.read(villageProvider.notifier).tick();
      setState(() => _now = DateTime.now().millisecondsSinceEpoch);
    });
  }

  /// Zoom at which the whole 7×7 grid fits the screen width (small margin).
  /// It's also the minimum zoom.
  double _fitScale(Size viewport) => math.min(
      1.0, viewport.width * 0.94 / (TownCatalog.gridSize * _iso.tw));

  /// The pannable world: the town canvas, grown to cover the viewport at the
  /// minimum zoom. InteractiveViewer requires the viewport to stay inside the
  /// content's bounds; when the content was smaller than the screen it "fixed"
  /// that on the first drag by jumping the whole town off to one side. With a
  /// world at least screen-sized, the fitted town stays put and a zoomed-in
  /// town pans smoothly within it.
  Size _worldSize(Size viewport) {
    final fit = _fitScale(viewport);
    return Size(math.max(_canvas.width, viewport.width / fit),
        math.max(_canvas.height, viewport.height / fit));
  }

  void _centre(Size viewport) {
    final scale = _fitScale(viewport);
    final world = _worldSize(viewport);
    final dx = (viewport.width - world.width * scale) / 2;
    final dy = (viewport.height - world.height * scale) / 2;
    _viewer.value = Matrix4.identity()
      ..translateByDouble(dx, dy, 0, 1)
      ..scaleByDouble(scale, scale, 1, 1);
  }

  @override
  void dispose() {
    _tick.cancel();
    _viewer.dispose();
    super.dispose();
  }

  void _toast(String msg) => ScaffoldMessenger.of(context)
      .showToast(SnackBar(content: Text(msg), duration: const Duration(milliseconds: 1600)));

  void _tap(TapUpDetails d) {
    final cell = _iso.hit(d.localPosition, TownCatalog.gridSize);
    final v = ref.read(villageProvider);
    if (_placing != null) {
      if (cell == null) return;
      final err = ref.read(villageProvider.notifier).place(_placing!, cell.$1, cell.$2);
      if (err != null) return _toast(err);
      HapticFeedback.mediumImpact();
      _toast('${TownCatalog.byId(_placing!).name} under construction');
      setState(() => _placing = null);
      return;
    }
    String? hit;
    if (cell != null) {
      for (final e in v.buildings.entries) {
        if (e.value.col == cell.$1 && e.value.row == cell.$2) hit = e.key;
      }
    }
    setState(() => _sel = hit);
  }

  @override
  Widget build(BuildContext context) {
    final v = ref.watch(villageProvider);
    final g = ref.watch(gamificationProvider);
    final weather = ref.watch(townWeatherProvider);
    final stored = v.totalStored(_now);
    final mult = weatherMultiplier(weather) * (1 + v.beauty);

    Set<(int, int)> placeable = const {};
    if (_placing != null) {
      final taken = {for (final b in v.buildings.values) (b.col, b.row)};
      placeable = {
        for (var c = 0; c < TownCatalog.gridSize; c++)
          for (var r = 0; r < TownCatalog.gridSize; r++)
            if (!taken.contains((c, r))) (c, r)
      };
    }

    return Scaffold(
      backgroundColor: TownPalette.skyTop,
      body: Stack(children: [
        Positioned.fill(child: _Sky(weather: weather)),
        Positioned.fill(
          child: LayoutBuilder(builder: (context, box) {
            final viewport = box.biggest;
            if (viewport != _viewport) {
              _viewport = viewport;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) _centre(viewport);
              });
            }
            final world = _worldSize(viewport);
            return InteractiveViewer(
              transformationController: _viewer,
              constrained: false,
              minScale: _fitScale(viewport),
              maxScale: 2.2,
              child: SizedBox.fromSize(
                size: world,
                child: Center(
                  child: GestureDetector(
                    onTapUp: _tap,
                    child: CustomPaint(
                      size: _canvas,
                      painter: TownPainter(
                        village: v,
                        iso: _iso,
                        now: _now,
                        selected: _sel,
                        placeable: placeable,
                        glow: weather == TownWeather.storm ? 0.45 : 1,
                      ),
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
        _hud(v, g),
        if (_placing != null) _placingBanner(),
        Positioned(
          left: 14,
          right: 14,
          bottom: 16,
          child: SafeArea(
            top: false,
            child: _sel != null && v.buildings[_sel] != null
                ? _BuildingPanel(
                    id: _sel!,
                    now: _now,
                    mult: mult,
                    onClose: () => setState(() => _sel = null),
                    toast: _toast,
                  )
                : _placing == null
                    ? _bottomBar(stored, mult, v)
                    : const SizedBox.shrink(),
          ),
        ),
      ]),
    );
  }

  Widget _hud(VillageState v, GamificationState g) {
    final weather = ref.watch(townWeatherProvider);
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Column(children: [
            Row(children: [
              _chipBtn(Ph.arrowLeft, 'Back', () => Navigator.pop(context)),
              const SizedBox(width: 8),
              _chip(Row(mainAxisSize: MainAxisSize.min, children: [
                const Text('Aeris Town', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5, color: Colors.white)),
                const SizedBox(width: 6),
                Text('Lv ${v.townLevel}',
                    style: const TextStyle(fontSize: 12, color: AerisColors.arc, fontWeight: FontWeight.w700)),
              ])),
              const Spacer(),
              _chipBtn(Ph.question, 'How it works', _howItWorks),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              _stat(Ph.lightning, AerisColors.amber, _fmt(g.available), 'Aura'),
              const SizedBox(width: 6),
              _stat(Ph.diamond, AerisColors.arc, '${g.gems}', 'Gems'),
              const SizedBox(width: 6),
              _stat(Ph.hardHat, v.freeBuilders(_now) > 0 ? AerisColors.mint : AerisColors.coral,
                  '${v.freeBuilders(_now)}/${v.builders}', 'Builders'),
            ]),
            const SizedBox(height: 8),
            _WeatherBanner(weather: weather, beauty: v.beauty),
          ]),
        ),
      ),
    );
  }

  Widget _bottomBar(int stored, double mult, VillageState v) {
    final gain = (stored * mult).round();
    return Row(children: [
      Expanded(
        child: FilledButton.icon(
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(54),
            backgroundColor: gain > 0 ? AerisColors.amber : AerisColors.cardDark,
            foregroundColor: gain > 0 ? const Color(0xFF2A1A00) : AerisColors.mutedDark,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
          onPressed: gain > 0
              ? () {
                  final got = ref.read(villageProvider.notifier).collectAll();
                  HapticFeedback.mediumImpact();
                  _toast('+$got Aura collected');
                }
              : null,
          icon: const Icon(Ph.lightning),
          label: Text(gain > 0
              ? 'Collect $gain Aura'
              : v.dailyIncome() > 0
                  ? 'Town makes ${(v.dailyIncome() * mult).round()} Aura/day'
                  : 'Build a producer to earn Aura'),
        ),
      ),
      const SizedBox(width: 10),
      FilledButton.icon(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 54),
          backgroundColor: AerisColors.arc,
          foregroundColor: AerisColors.bgDark,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        onPressed: _openShop,
        icon: const Icon(Ph.buildings),
        label: const Text('Build'),
      ),
    ]);
  }

  Widget _placingBanner() {
    final def = TownCatalog.byId(_placing!);
    return Positioned(
      left: 14,
      right: 14,
      bottom: 24,
      child: SafeArea(
        top: false,
        child: _glass(
          padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
          child: Row(children: [
            BuildingIcon(def, size: 44),
            const SizedBox(width: 8),
            Expanded(
              child: Text('Tap a glowing tile to place the ${def.name}',
                  style: const TextStyle(color: Colors.white, fontSize: 13.5)),
            ),
            TextButton(onPressed: () => setState(() => _placing = null), child: const Text('Cancel')),
          ]),
        ),
      ),
    );
  }

  Future<void> _openShop() async {
    final type = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AerisColors.cardDark,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => const _ShopSheet(),
    );
    if (type != null && mounted) {
      setState(() {
        _placing = type;
        _sel = null;
      });
    }
  }

  void _howItWorks() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AerisColors.cardDark,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => const Padding(
        padding: EdgeInsets.fromLTRB(22, 18, 22, 28),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('How Aeris Town works',
              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
          SizedBox(height: 14),
          _Rule(Ph.lightning, 'Aura comes from real habits',
              'Daily check-ins, no-spend days, months under budget, finished goals and won challenges. Your level only grows from these.'),
          _Rule(Ph.house, 'Producers make Aura every day',
              'Each holds up to one day of Aura. Visit daily and collect.'),
          _Rule(Ph.sun, 'The town weathers your spending',
              'Checked in today: collections ×1.5. Over this month\'s budget: storm, collections halved.'),
          _Rule(Ph.tree, 'Decorations pay off',
              'Each tree, fountain or statue adds +5% to everything you collect (max +50%).'),
          _Rule(Ph.diamond, 'Gems are rare',
              'Earned at 7/30/100-day streaks, months under budget, goals and challenges. Spend them to finish construction now.'),
        ]),
      ),
    );
  }

  // ── small pieces ───────────────────────────────────────────────────
  static String _fmt(int v) =>
      v.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');

  Widget _glass({required Widget child, EdgeInsets padding = const EdgeInsets.all(10)}) => Container(
        padding: padding,
        decoration: BoxDecoration(
          color: AerisColors.cardDark.withValues(alpha: 0.88),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AerisColors.lineDark),
        ),
        child: child,
      );

  Widget _chip(Widget child) => _glass(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9), child: child);

  Widget _chipBtn(IconData icon, String tip, VoidCallback onTap) => Tooltip(
        message: tip,
        child: Material(
          color: AerisColors.cardDark.withValues(alpha: 0.88),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12), side: const BorderSide(color: AerisColors.lineDark)),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onTap,
            child: SizedBox(width: 44, height: 40, child: Icon(icon, size: 20, color: Colors.white)),
          ),
        ),
      );

  Widget _stat(IconData icon, Color color, String value, String label) => Expanded(
        child: _glass(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 8),
            Flexible(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13.5)),
                Text(label, style: const TextStyle(color: AerisColors.mutedDark, fontSize: 10.5)),
              ]),
            ),
          ]),
        ),
      );
}

class _Rule extends StatelessWidget {
  final IconData icon;
  final String title, body;
  const _Rule(this.icon, this.title, this.body);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 20, color: AerisColors.arc),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)),
              const SizedBox(height: 2),
              Text(body, style: const TextStyle(color: AerisColors.mutedDark, fontSize: 12.5, height: 1.4)),
            ]),
          ),
        ]),
      );
}

class _WeatherBanner extends StatelessWidget {
  final TownWeather weather;
  final double beauty;
  const _WeatherBanner({required this.weather, required this.beauty});

  @override
  Widget build(BuildContext context) {
    final (icon, color, text) = switch (weather) {
      TownWeather.bright => (Ph.sun, AerisColors.mint, 'Checked in today · collections ×1.5'),
      TownWeather.storm => (Ph.cloudLightning, AerisColors.coral, 'Over budget this month · collections halved'),
      TownWeather.clear => (Ph.moonStars, AerisColors.mutedDark, 'Check in today to boost collections ×1.5'),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: TextStyle(color: color, fontSize: 12.5))),
        if (beauty > 0)
          Text('+${(beauty * 100).round()}% decor',
              style: const TextStyle(color: AerisColors.arc, fontSize: 11.5, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

/// Night sky with stars; rain when the month is over budget.
class _Sky extends StatelessWidget {
  final TownWeather weather;
  const _Sky({required this.weather});
  @override
  Widget build(BuildContext context) => CustomPaint(painter: _SkyPainter(weather));
}

class _SkyPainter extends CustomPainter {
  final TownWeather weather;
  _SkyPainter(this.weather);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
        Offset.zero & size,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [TownPalette.skyTop, TownPalette.skyBottom],
          ).createShader(Offset.zero & size));
    final rnd = math.Random(7);
    if (weather != TownWeather.storm) {
      final star = Paint()..color = Colors.white.withValues(alpha: 0.5);
      for (var i = 0; i < 60; i++) {
        canvas.drawCircle(Offset(rnd.nextDouble() * size.width, rnd.nextDouble() * size.height * 0.45),
            rnd.nextDouble() * 1.1 + 0.2, star);
      }
      // Moon.
      canvas.drawCircle(Offset(size.width * 0.84, size.height * 0.27), 14,
          Paint()..color = const Color(0xFFEAF2F7).withValues(alpha: 0.9));
    } else {
      final rain = Paint()
        ..color = const Color(0xFF7C8AA0).withValues(alpha: 0.35)
        ..strokeWidth = 1;
      for (var i = 0; i < 90; i++) {
        final x = rnd.nextDouble() * size.width, y = rnd.nextDouble() * size.height;
        canvas.drawLine(Offset(x, y), Offset(x - 4, y + 12), rain);
      }
    }
  }

  @override
  bool shouldRepaint(_SkyPainter o) => o.weather != weather;
}

class _BuildingPanel extends ConsumerWidget {
  final String id;
  final int now;
  final double mult;
  final VoidCallback onClose;
  final void Function(String) toast;
  const _BuildingPanel({required this.id, required this.now, required this.mult, required this.onClose, required this.toast});

  static String _left(int ms) {
    final m = (ms / 60000).ceil();
    if (m >= 60) return '${m ~/ 60}h ${m % 60}m';
    return '${m}m';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final v = ref.watch(villageProvider);
    final g = ref.watch(gamificationProvider);
    final b = v.buildings[id]!;
    final def = b.def;
    final notifier = ref.read(villageProvider.notifier);
    final busy = b.busy(now);
    final maxed = b.lvl + 1 >= def.maxLevel;
    final cost = def.upgradeCost(b.lvl);
    final stored = (v.stored(id, now) * mult).round();

    String info;
    if (busy) {
      info = 'Building… ${_left(b.endMs - now)} left';
    } else if (def.produces) {
      info = 'Makes ${(def.dailyYield(b.lvl) * mult).round()} Aura/day · holds one day';
    } else if (def.role == TownRole.decoration) {
      info = '+5% to everything you collect';
    } else {
      info = def.desc;
    }

    Widget primary;
    if (busy) {
      final gems = VillageNotifier.rushCost(b.endMs - now);
      primary = FilledButton.icon(
        style: FilledButton.styleFrom(backgroundColor: AerisColors.arc, foregroundColor: AerisColors.bgDark),
        onPressed: () {
          final err = notifier.rush(id);
          toast(err ?? 'Finished with $gems gems');
        },
        icon: const Icon(Ph.diamond, size: 18),
        label: Text('Finish now · $gems'),
      );
    } else if (stored > 0) {
      primary = FilledButton.icon(
        style: FilledButton.styleFrom(backgroundColor: AerisColors.amber, foregroundColor: const Color(0xFF2A1A00)),
        onPressed: () => toast('+${notifier.collect(id)} Aura'),
        icon: const Icon(Ph.lightning, size: 18),
        label: Text('Collect $stored'),
      );
    } else if (!maxed) {
      final afford = g.available >= cost;
      primary = FilledButton.icon(
        style: FilledButton.styleFrom(
            backgroundColor: afford ? AerisColors.arc : AerisColors.lineDark,
            foregroundColor: afford ? AerisColors.bgDark : AerisColors.mutedDark),
        onPressed: () {
          final err = notifier.upgrade(id);
          toast(err ?? 'Upgrading to level ${b.lvl + 2}');
        },
        icon: const Icon(Ph.arrowFatUp, size: 18),
        label: Text('Upgrade · $cost'),
      );
    } else {
      primary = const FilledButton(onPressed: null, child: Text('Max level'));
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AerisColors.cardDark,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AerisColors.lineDark),
        boxShadow: const [BoxShadow(blurRadius: 24, color: Colors.black54)],
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          Container(
            decoration: BoxDecoration(color: AerisColors.bgDark, borderRadius: BorderRadius.circular(14)),
            child: BuildingIcon(def, lvl: b.lvl, size: 60),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${def.name} · Lv ${b.lvl + 1}${maxed ? ' (max)' : ''}',
                  style: const TextStyle(color: Colors.white, fontSize: 15.5, fontWeight: FontWeight.w700)),
              const SizedBox(height: 3),
              Text(info, style: const TextStyle(color: AerisColors.mutedDark, fontSize: 12.5)),
            ]),
          ),
          IconButton(
            tooltip: 'Close',
            onPressed: onClose,
            icon: const Icon(Ph.x, color: AerisColors.mutedDark),
          ),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          if (id != 'th')
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                  foregroundColor: AerisColors.mutedDark,
                  side: const BorderSide(color: AerisColors.lineDark),
                  minimumSize: const Size(48, 46)),
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (c) => AlertDialog(
                    title: Text('Remove the ${def.name}?'),
                    content: Text('You get ${def.baseCost ~/ 2} Aura back (half its price).'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Keep')),
                      TextButton(
                          onPressed: () => Navigator.pop(c, true),
                          child: const Text('Remove', style: TextStyle(color: AerisColors.coral))),
                    ],
                  ),
                );
                if (ok == true) {
                  notifier.demolish(id);
                  onClose();
                  toast('${def.name} removed');
                }
              },
              child: const Icon(Ph.trash, size: 20),
            ),
          if (id != 'th') const SizedBox(width: 10),
          Expanded(child: SizedBox(height: 46, child: primary)),
        ]),
      ]),
    );
  }
}

class _ShopSheet extends ConsumerWidget {
  const _ShopSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final v = ref.watch(villageProvider);
    final g = ref.watch(gamificationProvider);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(color: AerisColors.lineDark, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 14),
          Row(children: [
            const Text('Build', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
            const Spacer(),
            const Icon(Ph.lightning, size: 16, color: AerisColors.amber),
            const SizedBox(width: 4),
            Text('${g.available} Aura', style: const TextStyle(color: AerisColors.amber, fontWeight: FontWeight.w600)),
          ]),
          const SizedBox(height: 12),
          Flexible(
            child: GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 0.78,
              children: [
                for (final def in TownCatalog.shop)
                  _ShopTile(
                    def: def,
                    locked: v.townLevel < def.unlockHall,
                    full: v.count(def.id) >= TownCatalog.limit(def.id, v.townLevel),
                    afford: g.available >= def.baseCost,
                    count: v.count(def.id),
                    limit: TownCatalog.limit(def.id, v.townLevel),
                  ),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}

class _ShopTile extends StatelessWidget {
  final TownBuilding def;
  final bool locked, full, afford;
  final int count, limit;
  const _ShopTile(
      {required this.def, required this.locked, required this.full, required this.afford, required this.count, required this.limit});

  @override
  Widget build(BuildContext context) {
    final enabled = !locked && !full;
    final sub = locked
        ? 'Town Hall ${def.unlockHall}'
        : full
            ? 'Built $count/$limit'
            : def.produces
                ? '${def.perDay} Aura/day'
                : def.role == TownRole.decoration
                    ? '+5% production'
                    : '+1 builder';
    return Material(
      color: AerisColors.bgDark,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16), side: const BorderSide(color: AerisColors.lineDark)),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: enabled ? () => Navigator.pop(context, def.id) : null,
        child: Opacity(
          opacity: enabled ? 1 : 0.45,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(children: [
              Expanded(child: BuildingIcon(def, size: 72)),
              Text(def.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w600)),
              Text(sub, maxLines: 1, style: const TextStyle(color: AerisColors.mutedDark, fontSize: 10.5)),
              const SizedBox(height: 4),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(locked ? Ph.lock : Ph.lightning,
                    size: 13, color: afford ? AerisColors.amber : AerisColors.coral),
                const SizedBox(width: 2),
                Text('${def.baseCost}',
                    style: TextStyle(
                        color: afford ? AerisColors.amber : AerisColors.coral, fontSize: 12, fontWeight: FontWeight.w700)),
              ]),
            ]),
          ),
        ),
      ),
    );
  }
}
