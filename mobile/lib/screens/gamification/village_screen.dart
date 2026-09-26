import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/gamification_provider.dart';
import '../../providers/village_provider.dart';

// ── Building catalog (ported from flow-village.jsx BLD) ──────────────────────
class _Bld {
  final String name;
  final List<String> emoji; // per level; max level = length-1
  final int base; // Aura place cost
  final Color color;
  final String desc;
  final int sec; // base build seconds
  final int yields; // Aura per collect cycle (0 = none)
  final bool placeable;
  final int? lock; // requires this town-hall level

  const _Bld({
    required this.name,
    required this.emoji,
    required this.base,
    required this.color,
    required this.desc,
    required this.sec,
    this.yields = 0,
    this.placeable = true,
    this.lock,
  });
}

const _bld = <String, _Bld>{
  'townhall': _Bld(
      name: 'Town Hall',
      emoji: ['🏯', '🏯', '🏛️', '🏛️', '🏰', '🏰'],
      base: 0,
      color: Color(0xFFF59E0B),
      desc: 'Heart of your village. Higher level unlocks more buildings.',
      sec: 18,
      placeable: false),
  'house': _Bld(
      name: 'House',
      emoji: ['⛺', '🛖', '🏠', '🏡', '🏘️', '🏰'],
      base: 60,
      color: Color(0xFF10B981),
      desc: 'Generates Aura over time.',
      sec: 8,
      yields: 12),
  'vault': _Bld(
      name: 'Savings Vault',
      emoji: ['🪙', '💰', '🏦', '🏦', '🏦', '🏦'],
      base: 120,
      color: Color(0xFFEAB308),
      desc: 'Stores your savings. Higher level holds more.',
      sec: 12,
      yields: 20),
  'farm': _Bld(
      name: 'Aura Farm',
      emoji: ['🌱', '🌾', '🌽', '🚜', '🚜'],
      base: 40,
      color: Color(0xFF65A30D),
      desc: 'Grows Aura from daily check-ins.',
      sec: 6,
      yields: 8),
  'market': _Bld(
      name: 'Market',
      emoji: ['🛒', '🏪', '🏬', '🏤', '🏤'],
      base: 100,
      color: Color(0xFF3B82F6),
      desc: 'Trade resources & claim rewards.',
      sec: 10,
      yields: 16),
  'fountain': _Bld(
      name: 'Fountain',
      emoji: ['💧', '⛲', '🌊', '🗽'],
      base: 80,
      color: Color(0xFF06B6D4),
      desc: 'Decoration. Boosts village happiness.',
      sec: 9),
  'tree': _Bld(
      name: 'Tree',
      emoji: ['🌱', '🌳', '🌲', '🎄'],
      base: 20,
      color: Color(0xFF16A34A),
      desc: 'Greenery for your base.',
      sec: 4),
  'tower': _Bld(
      name: 'Watch Tower',
      emoji: ['🗼', '🗼', '🏯', '🏯'],
      base: 200,
      color: Color(0xFF8B5CF6),
      desc: 'Guards against overspending raids.',
      sec: 14,
      lock: 3),
  'statue': _Bld(
      name: 'Statue',
      emoji: ['🗿', '🗽', '🏛️'],
      base: 300,
      color: Color(0xFF94A3B8),
      desc: 'A monument to your discipline.',
      sec: 16,
      lock: 4),
};

const _placeable = [
  'house',
  'vault',
  'farm',
  'market',
  'fountain',
  'tree',
  'tower',
  'statue'
];
const _grid = 7;
const _tw = 60.0;
const _th = 30.0;

int _upCost(String type, int lvl) =>
    ((_bld[type]!.base == 0 ? 60 : _bld[type]!.base) * (lvl + 1) * 1.5).round();
int _upTimeMs(String type, int lvl) => _bld[type]!.sec * 1000 * (lvl + 1);
int _rushGems(int msLeft) => math.max(1, (msLeft / 1000 / 6).ceil());

String _countdown(int ms) {
  final s = math.max(0, (ms / 1000).ceil());
  if (s >= 60) return '${s ~/ 60}m ${s % 60}s';
  return '${s}s';
}

String _aura(int v) => v.toString().replaceAllMapped(
    RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');

class VillageScreen extends ConsumerStatefulWidget {
  const VillageScreen({super.key});
  @override
  ConsumerState<VillageScreen> createState() => _VillageScreenState();
}

class _VillageScreenState extends ConsumerState<VillageScreen> {
  Offset _pan = Offset.zero;
  String? _sel;
  String? _placing;
  bool _shopOpen = false;
  int _now = DateTime.now().millisecondsSinceEpoch;
  late final Timer _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (!mounted) return;
      _now = DateTime.now().millisecondsSinceEpoch;
      // Finish any elapsed constructions.
      final v = ref.read(villageProvider);
      final notifier = ref.read(villageProvider.notifier);
      for (final e in v.buildings.entries) {
        if (e.value.endMs != 0 && e.value.endMs <= _now) {
          notifier.finishUpgrade(e.key);
        }
      }
      setState(() {});
    });
  }

  @override
  void dispose() {
    _tick.cancel();
    super.dispose();
  }

  Offset _cellXY(int c, int r, Size size) {
    final originX = size.width / 2 + _pan.dx;
    final originY = 168 + _pan.dy;
    return Offset(originX + (c - r) * _tw / 2, originY + (c + r) * _th / 2);
  }

  void _onPanUpdate(DragUpdateDetails d) {
    const clampX = (_grid + _grid) * _tw / 2 / 2; // baseW/2
    const clampY = 150.0;
    setState(() {
      _pan = Offset(
        (_pan.dx + d.delta.dx).clamp(-clampX, clampX),
        (_pan.dy + d.delta.dy).clamp(-clampY, clampY),
      );
    });
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(msg), duration: const Duration(milliseconds: 1400)),
    );
  }

  void _tapCell(int c, int r) {
    final v = ref.read(villageProvider);
    final occupied = {
      for (final b in v.buildings.values) '${b.col},${b.row}': true
    };
    if (_placing != null) {
      if (occupied['$c,$r'] == true) return _toast('Tile occupied');
      if (v.freeBuilders(_now) <= 0) {
        return _toast('No free builders — wait or rush');
      }
      final type = _placing!;
      final cost = _bld[type]!.base;
      final id = 'b${DateTime.now().millisecondsSinceEpoch}';
      final ok = ref
          .read(villageProvider.notifier)
          .place(id, type, c, r, cost, _upTimeMs(type, 0));
      if (!ok) return _toast('Not enough Aura');
      setState(() {
        _placing = null;
        _sel = id;
      });
      _toast('${_bld[type]!.name} under construction');
    } else {
      setState(() => _sel = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final v = ref.watch(villageProvider);
    final aura = ref.watch(gamificationProvider.select((g) => g.available));
    final gems = v.gems;
    final townLvl = v.townLevel;
    final free = v.freeBuilders(_now);

    return Scaffold(
      body: LayoutBuilder(builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        final order = v.buildings.entries.toList()
          ..sort((a, b) =>
              (a.value.col + a.value.row) - (b.value.col + b.value.row));
        final occupied = {
          for (final b in v.buildings.values) '${b.col},${b.row}': true
        };

        return Stack(
          children: [
            // Sky → grass background
            Positioned.fill(
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0xFF7CC9EC),
                      Color(0xFFA6DCC4),
                      Color(0xFF86C84C),
                      Color(0xFF6FAF44),
                    ],
                    stops: [0.0, 0.30, 0.30, 1.0],
                  ),
                ),
              ),
            ),
            const Positioned(
                top: 60,
                left: 26,
                child: Text('☁️', style: TextStyle(fontSize: 26))),
            const Positioned(
                top: 96,
                right: 40,
                child: Text('☁️', style: TextStyle(fontSize: 20))),
            const Positioned(
                top: 56,
                right: 24,
                child: Text('☀️', style: TextStyle(fontSize: 30))),

            // Pannable world
            Positioned.fill(
              child: GestureDetector(
                onPanUpdate: _onPanUpdate,
                behavior: HitTestBehavior.opaque,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // Ground tiles
                    for (int r = 0; r < _grid; r++)
                      for (int c = 0; c < _grid; c++)
                        _tile(c, r, size, occupied),
                    // Buildings
                    for (final e in order) _building(e.key, e.value, size),
                  ],
                ),
              ),
            ),

            // ── HUD ──
            _topBar(townLvl, aura, gems),
            _buildersPill(free, v.builders),
            if (_placing != null) _placingBanner(),
            if (_sel == null && _placing == null) _buildFab(),
            if (_sel != null && v.buildings[_sel] != null)
              _selectedPanel(v, townLvl, free, aura),
            if (_shopOpen) _shopDrawer(townLvl, aura),
          ],
        );
      }),
    );
  }

  // ── Ground tile ──────────────────────────────────────────────
  Widget _tile(int c, int r, Size size, Map<String, bool> occupied) {
    final p = _cellXY(c, r, size);
    final canPlace = _placing != null && occupied['$c,$r'] != true;
    return Positioned(
      left: p.dx - _tw / 2,
      top: p.dy - _th / 2,
      width: _tw,
      height: _th,
      child: GestureDetector(
        onTap: () => _tapCell(c, r),
        behavior: HitTestBehavior.opaque,
        child: CustomPaint(
          painter: _DiamondPainter(
            fill: canPlace
                ? Colors.white.withValues(alpha: 0.6)
                : ((c + r) % 2 == 0
                    ? const Color(0xFF8FD356)
                    : const Color(0xFF84C84A)),
            highlight: canPlace,
          ),
        ),
      ),
    );
  }

  // ── Building ─────────────────────────────────────────────────
  Widget _building(String id, VillageBuilding b, Size size) {
    final p = _cellXY(b.col, b.row, size);
    final def = _bld[b.type]!;
    final lvl = math.min(b.lvl, def.emoji.length - 1);
    final constructing = b.busy(_now);
    final total = _upTimeMs(b.type, b.lvl);
    final prog = constructing ? 1 - (b.endMs - _now) / total : 0.0;
    final isSel = _sel == id;
    final ready = def.yields > 0 &&
        !constructing &&
        (_now - (ref.read(villageProvider).collected[id] ?? 0) > 12000);

    return Positioned(
      left: p.dx - 30,
      top: p.dy - 50,
      width: 60,
      height: 70,
      child: GestureDetector(
        onTap: () => setState(() {
          _sel = id;
          _placing = null;
        }),
        behavior: HitTestBehavior.opaque,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            if (isSel)
              Positioned(
                bottom: 8,
                child: SizedBox(
                  width: _tw - 4,
                  height: _th - 4,
                  child: CustomPaint(
                    painter: _DiamondPainter(
                        fill: Colors.white.withValues(alpha: 0.4),
                        highlight: true),
                  ),
                ),
              ),
            Positioned(
              bottom: 12,
              child: Text(def.emoji[lvl],
                  style: const TextStyle(fontSize: 36, shadows: [
                    Shadow(
                        blurRadius: 3,
                        color: Colors.black38,
                        offset: Offset(0, 4))
                  ])),
            ),
            if (!constructing && b.type != 'townhall')
              Positioned(
                top: 2,
                right: 2,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  decoration: BoxDecoration(
                    color: def.color,
                    borderRadius: BorderRadius.circular(7),
                    border: Border.all(color: Colors.white, width: 1.5),
                  ),
                  child: Text('${b.lvl + 1}',
                      style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: Colors.white)),
                ),
              ),
            if (constructing) ...[
              const Positioned(
                  top: 0,
                  right: 0,
                  child: Text('🔨', style: TextStyle(fontSize: 18))),
              Positioned(
                bottom: 4,
                child: Container(
                  width: 44,
                  height: 6,
                  decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(99)),
                  child: FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: prog.clamp(0.0, 1.0),
                    child: Container(
                      decoration: BoxDecoration(
                          color: const Color(0xFF34D399),
                          borderRadius: BorderRadius.circular(99)),
                    ),
                  ),
                ),
              ),
            ],
            if (ready)
              Positioned(
                top: -6,
                child: GestureDetector(
                  onTap: () {
                    ref
                        .read(villageProvider.notifier)
                        .collect(id, def.yields * (b.lvl + 1));
                    _toast('+${def.yields * (b.lvl + 1)} Aura collected');
                    setState(() {});
                  },
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFCD34D),
                      borderRadius: BorderRadius.circular(99),
                      boxShadow: const [
                        BoxShadow(blurRadius: 6, color: Colors.black38)
                      ],
                    ),
                    child: Text('+${def.yields * (b.lvl + 1)}',
                        style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF78350F))),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ── HUD pieces ───────────────────────────────────────────────
  Widget _topBar(int townLvl, int aura, int gems) {
    return Positioned(
      top: MediaQuery.paddingOf(context).top + 8,
      left: 12,
      right: 12,
      child: Row(children: [
        _hudBtn(Icons.arrow_back, () => Navigator.pop(context)),
        const SizedBox(width: 7),
        _hudChip(
            child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Text('🏰', style: TextStyle(fontSize: 15)),
          const SizedBox(width: 5),
          Text('TH $townLvl',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800)),
        ])),
        const Spacer(),
        _resource(Icons.bolt, const Color(0xFFFCD34D), _aura(aura)),
        const SizedBox(width: 7),
        _resource(Icons.diamond, const Color(0xFF67E8F9), '$gems'),
      ]),
    );
  }

  Widget _hudBtn(IconData icon, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.42),
              borderRadius: BorderRadius.circular(11)),
          child: Icon(icon, size: 21, color: Colors.white),
        ),
      );

  Widget _hudChip({required Widget child}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.42),
            borderRadius: BorderRadius.circular(11)),
        child: child,
      );

  Widget _resource(IconData icon, Color color, String value) => _hudChip(
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 4),
          Text(value,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w800)),
        ]),
      );

  Widget _buildersPill(int free, int total) {
    return Positioned(
      top: MediaQuery.paddingOf(context).top + 54,
      right: 12,
      child: _hudChip(
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.engineering,
              size: 16,
              color:
                  free > 0 ? const Color(0xFF86EFAC) : const Color(0xFFFCA5A5)),
          const SizedBox(width: 5),
          Text('$free/$total free',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800)),
        ]),
      ),
    );
  }

  Widget _placingBanner() {
    return Positioned(
      top: MediaQuery.paddingOf(context).top + 92,
      left: 0,
      right: 0,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
              color: const Color(0xFF0E7A6F),
              borderRadius: BorderRadius.circular(12),
              boxShadow: const [
                BoxShadow(blurRadius: 16, color: Colors.black38)
              ]),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(_bld[_placing]!.emoji[0],
                style: const TextStyle(fontSize: 20)),
            const SizedBox(width: 8),
            const Text('Tap a glowing tile to place',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700)),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => setState(() => _placing = null),
              child: const Icon(Icons.close, size: 16, color: Colors.white),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _buildFab() {
    return Positioned(
      bottom: 20,
      right: 16,
      child: GestureDetector(
        onTap: () => setState(() => _shopOpen = true),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
                colors: [Color(0xFF16A34A), Color(0xFF15803D)]),
            border: Border.all(
                color: Colors.white.withValues(alpha: 0.55), width: 3),
            borderRadius: BorderRadius.circular(18),
            boxShadow: const [BoxShadow(blurRadius: 20, color: Colors.black45)],
          ),
          child: const Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.add_business, size: 23, color: Colors.white),
            SizedBox(width: 7),
            Text('Build',
                style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 14.5)),
          ]),
        ),
      ),
    );
  }

  // ── Selected building panel ──────────────────────────────────
  Widget _selectedPanel(VillageState v, int townLvl, int free, int aura) {
    final id = _sel!;
    final b = v.buildings[id]!;
    final def = _bld[b.type]!;
    final maxLvl = def.emoji.length - 1;
    final busy = b.busy(_now);
    final canUp = !busy && b.lvl < maxLvl;
    final cost = _upCost(b.type, b.lvl);
    final lockNeed = def.lock != null && townLvl < def.lock!;
    final scheme = Theme.of(context).colorScheme;

    Widget action;
    if (busy) {
      final gemCost = _rushGems(b.endMs - _now);
      action = _panelBtn(
        gradient: const [Color(0xFF22D3EE), Color(0xFF0891B2)],
        icon: Icons.hourglass_top,
        label: '${_countdown(b.endMs - _now)} · Rush 💎$gemCost',
        onTap: () {
          if (ref.read(villageProvider.notifier).rush(id, gemCost)) {
            _toast('Rushed with gems! 💎');
          } else {
            _toast('Not enough gems');
          }
          setState(() {});
        },
      );
    } else if (lockNeed) {
      action = Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 13),
          alignment: Alignment.center,
          decoration: BoxDecoration(
              color: AerisWarnTint, borderRadius: BorderRadius.circular(13)),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Icon(Icons.lock, size: 17, color: Color(0xFFE08C00)),
            const SizedBox(width: 6),
            Text('Unlock at Town Hall ${def.lock}',
                style: const TextStyle(
                    color: Color(0xFFE08C00),
                    fontWeight: FontWeight.w800,
                    fontSize: 13)),
          ]),
        ),
      );
    } else if (canUp) {
      final afford = free > 0 && aura >= cost;
      action = _panelBtn(
        solid:
            afford ? const Color(0xFF0EA5A4) : scheme.surfaceContainerHighest,
        textColor: afford ? Colors.white : scheme.onSurfaceVariant,
        icon: Icons.upgrade,
        label: 'Upgrade · $cost Aura · ${def.sec * (b.lvl + 1)}s',
        onTap: () {
          if (free <= 0) return _toast('No free builders');
          if (aura < cost) return _toast('Need ${cost - aura} more Aura');
          ref
              .read(villageProvider.notifier)
              .startUpgrade(id, cost, _upTimeMs(b.type, b.lvl));
          _toast('Upgrading to Lv ${b.lvl + 2}…');
          setState(() {});
        },
      );
    } else {
      action = Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 13),
          alignment: Alignment.center,
          decoration: BoxDecoration(
              color: const Color(0x1422C55E),
              borderRadius: BorderRadius.circular(13)),
          child:
              const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.verified, size: 18, color: Color(0xFF15A24A)),
            SizedBox(width: 6),
            Text('Max level reached',
                style: TextStyle(
                    color: Color(0xFF15A24A),
                    fontWeight: FontWeight.w800,
                    fontSize: 13.5)),
          ]),
        ),
      );
    }

    return Positioned(
      bottom: 16,
      left: 14,
      right: 14,
      child: Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(20),
          border:
              Border.all(color: scheme.outlineVariant.withValues(alpha: 0.4)),
          boxShadow: const [BoxShadow(blurRadius: 24, color: Colors.black38)],
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            Container(
              width: 52,
              height: 52,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                  color: def.color.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(15)),
              child: Text(def.emoji[math.min(b.lvl, maxLvl)],
                  style: const TextStyle(fontSize: 32)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(children: [
                    Flexible(
                      child: Text(def.name,
                          style: const TextStyle(
                              fontSize: 16.5, fontWeight: FontWeight.w800)),
                    ),
                    const SizedBox(width: 7),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                          color: def.color.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(99)),
                      child: Text(
                          'Lv ${b.lvl + 1}${b.lvl >= maxLvl ? ' · MAX' : ''}',
                          style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w800,
                              color: def.color)),
                    ),
                  ]),
                  const SizedBox(height: 2),
                  Text(def.desc,
                      style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: scheme.onSurfaceVariant)),
                ],
              ),
            ),
            GestureDetector(
              onTap: () => setState(() => _sel = null),
              child: Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest,
                    shape: BoxShape.circle),
                child:
                    Icon(Icons.close, size: 18, color: scheme.onSurfaceVariant),
              ),
            ),
          ]),
          const SizedBox(height: 13),
          Row(children: [
            if (def.placeable) ...[
              GestureDetector(
                onTap: () {
                  ref.read(villageProvider.notifier).remove(id);
                  setState(() => _sel = null);
                  _toast('Removed');
                },
                child: Container(
                  padding: const EdgeInsets.all(13),
                  decoration: BoxDecoration(
                    border: Border.all(
                        color: scheme.outlineVariant.withValues(alpha: 0.5)),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(Icons.delete_outline,
                      size: 19, color: scheme.onSurfaceVariant),
                ),
              ),
              const SizedBox(width: 9),
            ],
            action,
          ]),
        ]),
      ),
    );
  }

  Widget _panelBtn({
    List<Color>? gradient,
    Color? solid,
    Color textColor = Colors.white,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 13),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: solid,
            gradient:
                gradient != null ? LinearGradient(colors: gradient) : null,
            borderRadius: BorderRadius.circular(13),
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, size: 18, color: textColor),
            const SizedBox(width: 7),
            Flexible(
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: textColor,
                      fontWeight: FontWeight.w800,
                      fontSize: 13.5)),
            ),
          ]),
        ),
      ),
    );
  }

  // ── Shop drawer ──────────────────────────────────────────────
  Widget _shopDrawer(int townLvl, int aura) {
    final scheme = Theme.of(context).colorScheme;
    return Positioned.fill(
      child: Stack(children: [
        GestureDetector(
          onTap: () => setState(() => _shopOpen = false),
          child: Container(color: Colors.black.withValues(alpha: 0.5)),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.72),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                    color: scheme.outlineVariant,
                    borderRadius: BorderRadius.circular(2)),
              ),
              Row(children: [
                const Text('Build menu',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                const Spacer(),
                Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.bolt, size: 15, color: Color(0xFFE08C00)),
                  const SizedBox(width: 4),
                  Text(_aura(aura),
                      style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFFE08C00))),
                ]),
              ]),
              const SizedBox(height: 12),
              Flexible(
                child: GridView.count(
                  crossAxisCount: 3,
                  shrinkWrap: true,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 0.92,
                  children: [
                    for (final type in _placeable)
                      _shopTile(type, townLvl, aura),
                  ],
                ),
              ),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _shopTile(String type, int townLvl, int aura) {
    final def = _bld[type]!;
    final locked = def.lock != null && townLvl < def.lock!;
    final afford = aura >= def.base;
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: locked
          ? null
          : () {
              setState(() {
                _placing = type;
                _shopOpen = false;
                _sel = null;
              });
              _toast('Tap a tile to place ${def.name}');
            },
      child: Opacity(
        opacity: locked ? 0.55 : 1,
        child: Container(
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(16),
            border:
                Border.all(color: scheme.outlineVariant.withValues(alpha: 0.4)),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(def.emoji[0], style: const TextStyle(fontSize: 34)),
              const SizedBox(height: 5),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(def.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w800)),
              ),
              const SizedBox(height: 3),
              if (locked)
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.lock, size: 11, color: scheme.onSurfaceVariant),
                  const SizedBox(width: 2),
                  Text('TH ${def.lock}',
                      style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w800,
                          color: scheme.onSurfaceVariant)),
                ])
              else
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.bolt,
                      size: 11,
                      color: afford
                          ? const Color(0xFFE08C00)
                          : const Color(0xFFE5484D)),
                  const SizedBox(width: 2),
                  Text('${def.base}',
                      style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          color: afford
                              ? const Color(0xFFE08C00)
                              : const Color(0xFFE5484D))),
                ]),
            ],
          ),
        ),
      ),
    );
  }
}

const AerisWarnTint = Color(0x22E08C00);

// ── Isometric diamond tile painter ───────────────────────────────────────────
class _DiamondPainter extends CustomPainter {
  final Color fill;
  final bool highlight;
  _DiamondPainter({required this.fill, required this.highlight});

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(size.width / 2, 0)
      ..lineTo(size.width, size.height / 2)
      ..lineTo(size.width / 2, size.height)
      ..lineTo(0, size.height / 2)
      ..close();
    canvas.drawPath(path, Paint()..color = fill);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = highlight ? 2 : 1
        ..color = highlight
            ? const Color(0xFF0E7A6F)
            : Colors.white.withValues(alpha: 0.14),
    );
  }

  @override
  bool shouldRepaint(_DiamondPainter old) =>
      old.fill != fill || old.highlight != highlight;
}
