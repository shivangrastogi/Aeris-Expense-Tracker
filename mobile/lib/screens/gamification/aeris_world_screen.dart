import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/routes.dart';
import '../../core/theme.dart';
import '../../models/avatar_skin.dart';
import '../../providers/gamification_provider.dart';
import '../../providers/village_provider.dart';
import '../../widgets/aeris_avatar.dart';
import 'bosses_screen.dart';
import 'challenges_screen.dart';
import 'customize_dashboard_screen.dart';

class AerisWorldScreen extends ConsumerStatefulWidget {
  const AerisWorldScreen({super.key});
  @override
  ConsumerState<AerisWorldScreen> createState() => _AerisWorldScreenState();
}

class _AerisWorldScreenState extends ConsumerState<AerisWorldScreen> {
  int _section = 0;

  static const _tabs = [
    (Icons.face_retouching_natural_rounded, 'Avatars'),
    (Icons.flag_rounded, 'Quests'),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
        (_) => ref.read(gamificationProvider.notifier).sync());
  }

  @override
  Widget build(BuildContext context) {
    final g = ref.watch(gamificationProvider);
    final status = ref.watch(avatarStatusProvider);
    final progress = (g.earned % auraPerLevel) / auraPerLevel;
    final skin = status.skin;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: Column(
        children: [
          // ── Gradient header ──────────────────────────────────
          _Header(
            g: g,
            status: status,
            progress: progress,
            skin: skin,
            dark: dark,
            scheme: scheme,
            onCustomize: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const CustomizeDashboardScreen())),
          ),

          // ── Village hero (centerpiece, opens the builder) ────
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 2),
            child: _VillageHero(),
          ),

          // ── Section tab strip (full-width segmented pill) ─────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: scheme.onSurface.withValues(alpha: dark ? 0.08 : 0.06),
                borderRadius: BorderRadius.circular(99),
              ),
              child: Row(
                children: [
                  for (var i = 0; i < _tabs.length; i++)
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() => _section = i),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          alignment: Alignment.center,
                          padding: const EdgeInsets.symmetric(vertical: 9),
                          decoration: BoxDecoration(
                            color: _section == i
                                ? AerisColors.seed
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(99),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(_tabs[i].$1,
                                  size: 16,
                                  color: _section == i
                                      ? Colors.white
                                      : scheme.onSurface
                                          .withValues(alpha: 0.6)),
                              const SizedBox(width: 6),
                              Text(_tabs[i].$2,
                                  style: TextStyle(
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w700,
                                      color: _section == i
                                          ? Colors.white
                                          : scheme.onSurface
                                              .withValues(alpha: 0.7))),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),

          // ── Section content ──────────────────────────────────
          Expanded(
            child: IndexedStack(
              index: _section,
              children: const [
                _AvatarSection(),
                _QuestsSection(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Village hero (landscape preview, opens the full-screen builder) ──────────
class _VillageHero extends ConsumerWidget {
  const _VillageHero();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final v = ref.watch(villageProvider);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = dark ? const Color(0xFF122120) : Colors.white;
    return GestureDetector(
      onTap: () => Navigator.pushNamed(context, AppRoutes.village),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.14),
                blurRadius: 16,
                offset: const Offset(0, 8)),
          ],
        ),
        child: Column(
          children: [
            // landscape preview
            SizedBox(
              height: 124,
              child: Stack(
                children: [
                  // sky → grass gradient
                  const Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Color(0xFF86CFE8),
                            Color(0xFFA7E0C8),
                            Color(0xFF8FD06A),
                            Color(0xFF7BC056),
                          ],
                          stops: [0.0, 0.5, 0.5, 1.0],
                        ),
                      ),
                    ),
                  ),
                  // sun
                  const Positioned(
                    top: 10,
                    right: 14,
                    child: Text('☀️', style: TextStyle(fontSize: 22)),
                  ),
                  // buildings
                  const Positioned(
                    bottom: 12,
                    left: 16,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text('🏛️', style: TextStyle(fontSize: 30)),
                        SizedBox(width: 6),
                        Text('🏠', style: TextStyle(fontSize: 24)),
                        SizedBox(width: 6),
                        Text('🏦', style: TextStyle(fontSize: 26)),
                        SizedBox(width: 6),
                        Text('🌳', style: TextStyle(fontSize: 20)),
                        SizedBox(width: 6),
                        Text('⛲', style: TextStyle(fontSize: 22)),
                      ],
                    ),
                  ),
                  // "Full screen" badge
                  Positioned(
                    top: 12,
                    left: 16,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 11, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child:
                          const Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.fullscreen, size: 14, color: Colors.white),
                        SizedBox(width: 4),
                        Text('Full screen',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w800)),
                      ]),
                    ),
                  ),
                ],
              ),
            ),
            // footer row
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Row(children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Your Village',
                          style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.3)),
                      const SizedBox(height: 2),
                      Text('Build & upgrade your base · TH ${v.townLevel}',
                          style: TextStyle(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                              fontSize: 12,
                              fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                  decoration: BoxDecoration(
                      color: AerisColors.seed,
                      borderRadius: BorderRadius.circular(99)),
                  child: const Row(mainAxisSize: MainAxisSize.min, children: [
                    Text('Enter',
                        style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 13.5)),
                    SizedBox(width: 4),
                    Icon(Icons.arrow_forward, size: 16, color: Colors.white),
                  ]),
                ),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Quests = Challenges + Boss battles, merged into one scroll ───────────────
class _QuestsSection extends StatelessWidget {
  const _QuestsSection();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 40),
      children: [
        const Row(children: [
          Icon(Icons.flag_rounded, size: 18, color: AerisColors.seed),
          SizedBox(width: 7),
          Text('Challenges',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        ]),
        const SizedBox(height: 10),
        const ChallengesScreen(embed: true),
        const SizedBox(height: 24),
        Row(children: [
          Icon(Icons.sports_kabaddi_rounded,
              size: 18, color: AerisColors.moneyOut(context)),
          SizedBox(width: 7),
          Text('Boss battles',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        ]),
        const SizedBox(height: 4),
        Text('Each budgeted category is a boss — stay under the cap to win.',
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: scheme.onSurfaceVariant)),
        const SizedBox(height: 10),
        const BossesScreen(embed: true),
      ],
    );
  }
}

// ── Gradient header ───────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  final GamificationState g;
  final AvatarStatus status;
  final double progress;
  final AvatarSkin skin;
  final bool dark;
  final ColorScheme scheme;

  final VoidCallback onCustomize;

  const _Header({
    required this.g,
    required this.status,
    required this.skin,
    required this.progress,
    required this.dark,
    required this.scheme,
    required this.onCustomize,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            skin.aura,
            Color.lerp(skin.aura, skin.accent, 0.6)!,
          ],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
          child: Column(
            children: [
              // Back + title row
              Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back_rounded,
                        color: Colors.white),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.white.withValues(alpha: 0.2),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.all(8),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Text('Aeris World',
                      style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: -0.4)),
                  const Spacer(),
                  IconButton(
                    onPressed: onCustomize,
                    icon: const Icon(Icons.tune_rounded, color: Colors.white),
                    tooltip: 'Customize',
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.white.withValues(alpha: 0.2),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.all(8),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(99)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.bolt,
                          size: 16, color: Color(0xFFFFE0B2)),
                      const SizedBox(width: 4),
                      Text('${g.available}',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w800)),
                    ]),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Avatar + info row
              Row(
                children: [
                  // Avatar
                  SizedBox(
                    width: 90,
                    height: 90,
                    child: AerisAvatar(
                      skin: status.skin,
                      stage: status.stage,
                      mood: status.mood,
                      size: 90,
                    ),
                  ),
                  const SizedBox(width: 16),

                  // Info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'EQUIPPED',
                          style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.6,
                              color: Colors.white70),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          skin.name,
                          style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              letterSpacing: -0.5),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Level ${status.level} · ${stageNames[status.stage]} tier',
                          style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.white70),
                        ),
                        const SizedBox(height: 10),
                        // Level progress bar
                        FractionallySizedBox(
                          widthFactor: 0.9,
                          alignment: Alignment.centerLeft,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(99),
                            child: LinearProgressIndicator(
                              value: progress,
                              minHeight: 7,
                              color: Colors.white,
                              backgroundColor:
                                  Colors.white.withValues(alpha: 0.25),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Avatar section (inline, no separate screen push) ─────────────────────────

class _AvatarSection extends ConsumerWidget {
  const _AvatarSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final g = ref.watch(gamificationProvider);
    final scheme = Theme.of(context).colorScheme;
    final unlockedCount = Avatars.all
        .where((a) => a.cost == 0 || g.unlocked.contains(a.id))
        .length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
      children: [
        // ── header: unlocked count + aura to spend ──
        Row(
          children: [
            Text('$unlockedCount of ${Avatars.all.length} unlocked',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurface.withValues(alpha: 0.6))),
            const Spacer(),
            const Icon(Icons.bolt, size: 15, color: Color(0xFFD97706)),
            const SizedBox(width: 3),
            Text('${g.available} to spend',
                style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFFD97706))),
          ],
        ),
        const SizedBox(height: 12),
        // ── 2-column grid of avatar cards ──
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 0.72,
          ),
          itemCount: Avatars.all.length,
          itemBuilder: (ctx, i) {
            final skin = Avatars.all[i];
            return _AvatarCard(skin: skin, g: g, ref: ref)
                .animate(delay: (i * 30).ms)
                .fadeIn(duration: 250.ms);
          },
        ),
      ],
    );
  }
}

class _AvatarCard extends StatelessWidget {
  final AvatarSkin skin;
  final GamificationState g;
  final WidgetRef ref;
  const _AvatarCard({required this.skin, required this.g, required this.ref});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = dark ? const Color(0xFF122120) : Colors.white;
    final owned = skin.cost == 0 || g.unlocked.contains(skin.id);
    final equipped = g.selected == skin.id;
    final canAfford = g.available >= skin.cost;
    final r = skin.rarity;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color:
                equipped ? r.color : scheme.onSurface.withValues(alpha: 0.08),
            width: equipped ? 2 : 1),
        boxShadow: [
          if (equipped)
            BoxShadow(color: r.color.withValues(alpha: 0.25), blurRadius: 10),
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 8,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        children: [
          // rarity badge + equipped check
          Row(
            children: [
              _RarityBadge(rarity: r),
              const Spacer(),
              if (equipped)
                Container(
                  width: 22,
                  height: 22,
                  decoration:
                      BoxDecoration(color: r.color, shape: BoxShape.circle),
                  child: const Icon(Icons.check, size: 15, color: Colors.white),
                ),
            ],
          ),
          const SizedBox(height: 2),
          // avatar
          Expanded(
            child: Center(
              child: Opacity(
                opacity: owned ? 1 : 0.85,
                child: ColorFiltered(
                  colorFilter: owned
                      ? const ColorFilter.mode(
                          Colors.transparent, BlendMode.dst)
                      : const ColorFilter.matrix(<double>[
                          0.25,
                          0.25,
                          0.25,
                          0,
                          -18,
                          0.25,
                          0.25,
                          0.25,
                          0,
                          -18,
                          0.25,
                          0.25,
                          0.25,
                          0,
                          -18,
                          0,
                          0,
                          0,
                          1,
                          0,
                        ]),
                  child: AerisAvatar(
                    skin: skin,
                    stage: 1,
                    mood: AvatarMood.happy,
                    size: 70,
                    animate: owned,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(skin.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style:
                  const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          SizedBox(
            height: 28,
            child: Text(skin.tagline,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 10.5,
                    height: 1.25,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurface.withValues(alpha: 0.55))),
          ),
          const SizedBox(height: 6),
          _cardButton(context, owned, equipped, canAfford, r),
        ],
      ),
    );
  }

  Widget _cardButton(BuildContext context, bool owned, bool equipped,
      bool canAfford, AvatarRarity r) {
    if (equipped) {
      return Container(
        width: double.infinity,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(
          color: r.color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text('Equipped',
            style: TextStyle(
                fontSize: 12.5, fontWeight: FontWeight.w800, color: r.color)),
      );
    }
    if (owned) {
      return _filledBtn(
        label: const Text('Equip'),
        bg: AerisColors.seed,
        onTap: () => ref.read(gamificationProvider.notifier).select(skin.id),
      );
    }
    // locked
    return _filledBtn(
      bg: canAfford
          ? const Color(0xFFD97706).withValues(alpha: 0.14)
          : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.06),
      fg: canAfford
          ? const Color(0xFFD97706)
          : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4),
      label: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(canAfford ? Icons.bolt : Icons.lock,
            size: 14,
            color: canAfford
                ? const Color(0xFFD97706)
                : Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.4)),
        const SizedBox(width: 3),
        Text('${skin.cost}',
            style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                color: canAfford
                    ? const Color(0xFFD97706)
                    : Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.4))),
      ]),
      onTap: () => canAfford
          ? _confirmUnlock(context)
          : ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('Need ${skin.cost - g.available} more Aura'))),
    );
  }

  Widget _filledBtn(
      {required Widget label,
      required Color bg,
      Color fg = Colors.white,
      required VoidCallback onTap}) {
    return SizedBox(
      width: double.infinity,
      child: TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          backgroundColor: bg,
          foregroundColor: fg,
          padding: const EdgeInsets.symmetric(vertical: 9),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          textStyle:
              const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: label,
      ),
    );
  }

  void _confirmUnlock(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: 100,
                child: Center(
                  child: AerisAvatar(
                      skin: skin,
                      stage: 1,
                      mood: AvatarMood.happy,
                      size: 92,
                      animate: true),
                ),
              ),
              const SizedBox(height: 6),
              Text(skin.name,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(skin.tagline,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
              const SizedBox(height: 14),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                const Icon(Icons.bolt, size: 20, color: Color(0xFFD97706)),
                const SizedBox(width: 4),
                Text('${skin.cost} Aura',
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFFD97706))),
              ]),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(13))),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: FilledButton(
                    onPressed: () {
                      ref.read(gamificationProvider.notifier).unlock(skin);
                      ref.read(gamificationProvider.notifier).select(skin.id);
                      Navigator.pop(ctx);
                    },
                    style: FilledButton.styleFrom(
                        backgroundColor: AerisColors.seed,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(13))),
                    child: const Text('Unlock'),
                  ),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}

/// Small rarity pill shown on the corner of an avatar thumbnail.
class _RarityBadge extends StatelessWidget {
  final AvatarRarity rarity;
  const _RarityBadge({required this.rarity});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
      decoration: BoxDecoration(
        color: rarity.color,
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: Colors.white, width: 1.2),
      ),
      child: Text(
        rarity.label,
        style: const TextStyle(
            fontSize: 8.5,
            fontWeight: FontWeight.w800,
            color: Colors.white,
            letterSpacing: 0.2),
      ),
    );
  }
}
