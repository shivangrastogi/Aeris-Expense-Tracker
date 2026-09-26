import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/routes.dart';
import '../../core/theme.dart';
import '../../models/avatar_skin.dart';
import '../../models/transaction.dart';
import '../../models/user_profile.dart';
import '../../providers/auth_provider.dart';
import '../../providers/gamification_provider.dart';
import '../../providers/transactions_provider.dart';
import '../../services/sync_outbox.dart';
import '../../utils/formatters.dart';
import '../../widgets/aeris_avatar.dart';
import '../../widgets/budget_ring.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(userProfileProvider).asData?.value;
    final g = ref.watch(gamificationProvider);
    final skin = Avatars.byId(g.selected);
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;

    final levelProgress = (g.earned % auraPerLevel) / auraPerLevel;
    final initials = _initials(profile?.displayName ?? profile?.email ?? 'A');

    final pendingCount =
        (ref.watch(transactionsStreamProvider).valueOrNull ?? [])
            .where((t) => t.source == TxnSource.sms && !t.reviewed)
            .length;

    final cardBg = dark ? const Color(0xFF122120) : Colors.white;
    final divColor = scheme.onSurface.withValues(alpha: 0.08);

    return Scaffold(
      backgroundColor: scheme.surface,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 92),
          children: [
            // ── Title ── (top spacing matches the Home header)
            const Padding(
              padding: EdgeInsets.fromLTRB(0, 8, 0, 16),
              child: Text('Me',
                  style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.5)),
            ),

            // ── Profile card ──
            _ProfileCard(
              profile: profile,
              g: g,
              initials: initials,
              levelProgress: levelProgress,
              cardBg: cardBg,
              divColor: divColor,
              scheme: scheme,
            ),

            const SizedBox(height: 14),

            // ── Equipped avatar banner ──
            _AvatarBanner(skin: skin, cardBg: cardBg),

            const SizedBox(height: 16),

            // ── 2 × 4 tile grid ──
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 1.12,
              children: [
                _GridTile(
                  icon: Icons.sports_esports,
                  label: 'Aeris World',
                  sub: 'Garden · challenges · bosses',
                  gradient: AerisColors.heroGradient,
                  cardBg: cardBg,
                  onTap: () =>
                      Navigator.pushNamed(context, AppRoutes.aerisWorld),
                ),
                _GridTile(
                  icon: Icons.celebration,
                  label: 'Wrapped',
                  sub: 'Your month in money',
                  gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFFDB2777), Color(0xFF8B5CF6)]),
                  cardBg: cardBg,
                  onTap: () => Navigator.pushNamed(context, AppRoutes.wrapped),
                ),
                _GridTile(
                  icon: Icons.flag_rounded,
                  label: 'Goals',
                  sub: 'Savings goals',
                  cardBg: cardBg,
                  onTap: () => Navigator.pushNamed(context, AppRoutes.goals),
                ),
                _GridTile(
                  icon: Icons.widgets_rounded,
                  label: 'Widgets',
                  sub: 'Home-screen widgets',
                  cardBg: cardBg,
                  onTap: () => Navigator.pushNamed(context, AppRoutes.widgets),
                ),
                _GridTile(
                  icon: Icons.account_balance_rounded,
                  label: 'Accounts',
                  sub: 'Linked banks',
                  cardBg: cardBg,
                  onTap: () => Navigator.pushNamed(context, AppRoutes.accounts),
                ),
                _GridTile(
                  icon: Icons.upload_file_rounded,
                  label: 'Import statement',
                  sub: 'PDF / CSV',
                  cardBg: cardBg,
                  onTap: () =>
                      Navigator.pushNamed(context, AppRoutes.importStatement),
                ),
                _GridTile(
                  icon: Icons.mark_email_read_rounded,
                  label: 'SMS review',
                  sub: pendingCount > 0 ? '$pendingCount pending' : 'All clear',
                  badge: pendingCount > 0 ? '$pendingCount' : null,
                  cardBg: cardBg,
                  onTap: () =>
                      Navigator.pushNamed(context, AppRoutes.smsReview),
                ),
                _GridTile(
                  icon: Icons.settings_rounded,
                  label: 'Settings',
                  sub: 'Theme · privacy · data',
                  cardBg: cardBg,
                  onTap: () => Navigator.pushNamed(context, AppRoutes.settings),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // ── Sign out ──
            OutlinedButton.icon(
              onPressed: () => _signOut(context, ref),
              icon: const Icon(Icons.logout_rounded, size: 20),
              label: const Text('Sign out'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AerisColors.moneyOut(context),
                side: BorderSide(color: AerisColors.moneyOut(context), width: 1.5),
                padding: const EdgeInsets.symmetric(vertical: 14),
                textStyle: const TextStyle(
                    fontSize: 14.5, fontWeight: FontWeight.w800),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
              ),
            ),

            // ── Footer ──
            Padding(
              padding: const EdgeInsets.only(top: 16, bottom: 2),
              child: Text(
                'AERIS · Flow 2.0 · Member since Jan 2026',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurface.withValues(alpha: 0.38)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2 && parts[1].isNotEmpty) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    if (parts[0].isNotEmpty) return parts[0][0].toUpperCase();
    return 'A';
  }
}

// ── Profile card ─────────────────────────────────────────────────────────────

class _ProfileCard extends StatelessWidget {
  final UserProfile? profile;
  final GamificationState g;
  final String initials;
  final double levelProgress;
  final Color cardBg;
  final Color divColor;
  final ColorScheme scheme;

  const _ProfileCard({
    required this.profile,
    required this.g,
    required this.initials,
    required this.levelProgress,
    required this.cardBg,
    required this.divColor,
    required this.scheme,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: divColor),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 16,
              offset: const Offset(0, 4)),
        ],
      ),
      child: Row(
        children: [
          // Level ring + initials
          GestureDetector(
            onTap: () => Navigator.pushNamed(context, AppRoutes.aerisWorld),
            child: SizedBox(
              width: 74,
              height: 74,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  BudgetRing(
                    progress: levelProgress,
                    size: 74,
                    strokeWidth: 6,
                    color: AerisColors.seed,
                    duration: const Duration(milliseconds: 800),
                  ),
                  Builder(builder: (_) {
                    final bytes = profile?.photoBytes;
                    final url = profile?.photoUrl;
                    ImageProvider? img;
                    if (bytes != null && bytes.isNotEmpty) {
                      img = MemoryImage(bytes);
                    } else if (url != null && url.isNotEmpty) {
                      img = NetworkImage(url);
                    }
                    return Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: img == null ? AerisColors.heroGradient : null,
                        image: img != null
                            ? DecorationImage(image: img, fit: BoxFit.cover)
                            : null,
                      ),
                      alignment: Alignment.center,
                      child: img == null
                          ? Text(initials,
                              style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white))
                          : null,
                    );
                  }),
                  Positioned(
                    bottom: 0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: AerisColors.seed,
                        borderRadius: BorderRadius.circular(99),
                        border: Border.all(color: cardBg, width: 2),
                      ),
                      child: Text('Lv ${g.level}',
                          style: const TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              height: 1.1)),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(width: 16),

          // Identity info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(profile?.displayName ?? 'Unnamed',
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w700)),
                const SizedBox(height: 1),
                Text(profile?.email ?? '',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurface.withValues(alpha: 0.55))),
                const SizedBox(height: 7),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    if (profile != null && profile!.monthlyIncome > 0)
                      _Badge(
                        label: '${formatRupees(profile!.monthlyIncome)}/mo',
                        color: AerisColors.seed,
                      ),
                    _Badge(
                      icon: Icons.bolt,
                      label: _fmtAura(g.available),
                      color: const Color(0xFFD97706),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Pencil edit
          IconButton(
            onPressed: () =>
                Navigator.pushNamed(context, AppRoutes.editProfile),
            icon: Icon(Icons.edit_rounded,
                color: scheme.onSurface.withValues(alpha: 0.55)),
            style: IconButton.styleFrom(
              backgroundColor: scheme.onSurface.withValues(alpha: 0.07),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.all(8),
            ),
          ),
        ],
      ),
    );
  }

  String _fmtAura(int v) {
    if (v >= 100000) return '${(v / 100000).toStringAsFixed(1)}L ✦';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}K ✦';
    return '$v ✦';
  }
}

// ── Equipped avatar banner ────────────────────────────────────────────────────

class _AvatarBanner extends StatelessWidget {
  final AvatarSkin skin;
  final Color cardBg;

  const _AvatarBanner({required this.skin, required this.cardBg});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: () => Navigator.pushNamed(context, AppRoutes.aerisWorld),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: skin.aura.withValues(alpha: 0.25)),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              skin.aura.withValues(alpha: 0.15),
              Colors.transparent,
            ],
          ),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 12,
                offset: const Offset(0, 3)),
          ],
        ),
        child: Row(
          children: [
            SizedBox(
              width: 64,
              height: 64,
              child: AerisAvatar(
                skin: skin,
                stage: 1,
                mood: AvatarMood.happy,
                size: 64,
                animate: false,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('YOUR AVATAR',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.05,
                          color: scheme.onSurface.withValues(alpha: 0.5))),
                  const SizedBox(height: 3),
                  Text(skin.name,
                      style: const TextStyle(
                          fontSize: 17, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 3),
                  Text('Tap to change · unlock more →',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AerisColors.ink(context))),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded,
                color: scheme.onSurface.withValues(alpha: 0.3)),
          ],
        ),
      ),
    );
  }
}

// ── Grid tile ─────────────────────────────────────────────────────────────────

class _GridTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String sub;
  final LinearGradient? gradient;
  final String? badge;
  final Color cardBg;
  final VoidCallback onTap;

  const _GridTile({
    required this.icon,
    required this.label,
    required this.sub,
    required this.cardBg,
    required this.onTap,
    this.gradient,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasGrad = gradient != null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: scheme.onSurface.withValues(alpha: 0.08)),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 10,
                offset: const Offset(0, 3)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    gradient: hasGrad ? gradient : null,
                    color: hasGrad
                        ? null
                        : AerisColors.seed.withValues(alpha: 0.12),
                  ),
                  child: Icon(icon,
                      size: 22,
                      color: hasGrad ? Colors.white : AerisColors.seed),
                ),
                if (badge != null)
                  Positioned(
                    right: -4,
                    top: -4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: AerisColors.moneyOut(context),
                        borderRadius: BorderRadius.circular(99),
                        border: Border.all(color: cardBg, width: 1.5),
                      ),
                      child: Text(badge!,
                          style: const TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              height: 1.2)),
                    ),
                  ),
              ],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text(sub,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        height: 1.3,
                        color: scheme.onSurface.withValues(alpha: 0.5))),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Badge chip ────────────────────────────────────────────────────────────────

class _Badge extends StatelessWidget {
  final IconData? icon;
  final String label;
  final Color color;

  const _Badge({required this.label, required this.color, this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 3),
          ],
          Text(label,
              style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w800, color: color)),
        ],
      ),
    );
  }
}

/// Signs out — but first warns if changes are still waiting to sync, since
/// they'd be rejected by the server once the session is gone.
Future<void> _signOut(BuildContext context, WidgetRef ref) async {
  final box = SyncOutbox.instance;
  await box.refresh();
  if (box.count > 0 && !await box.syncNow() && context.mounted) {
    final scheme = Theme.of(context).colorScheme;
    final n = box.count;
    final go = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        icon: Icon(Icons.cloud_off, color: scheme.error),
        title: const Text('Unsynced changes'),
        content: Text(
            '$n ${n == 1 ? 'change hasn\'t' : 'changes haven\'t'} reached the '
            'cloud yet. If you sign out now they will be lost.\n\n'
            'Connect to the internet and wait for them to sync first.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(d, false),
              child: const Text('Stay signed in')),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: scheme.error),
            onPressed: () => Navigator.pop(d, true),
            child: const Text('Sign out anyway'),
          ),
        ],
      ),
    );
    if (go != true) return;
  }
  await ref.read(authServiceProvider).signOut();
}
