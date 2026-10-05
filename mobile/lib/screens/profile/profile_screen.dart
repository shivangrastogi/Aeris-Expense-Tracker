import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/routes.dart';
import '../../core/theme.dart';
import '../../models/user_profile.dart';
import '../../providers/auth_provider.dart';
import '../../providers/gamification_provider.dart';
import '../../providers/transactions_provider.dart';
import '../../providers/village_provider.dart';
import '../../services/sync_outbox.dart';
import '../../utils/formatters.dart';

/// The "Me" tab: who you are, then everything else grouped by what it's for —
/// Money (the things you manage), Tools (ways data gets in) and You (the fun
/// stuff). One tidy list instead of a grid of equal-looking tiles.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(userProfileProvider).asData?.value;
    final g = ref.watch(gamificationProvider);
    final pendingCount =
        (ref.watch(transactionsStreamProvider).valueOrNull ?? const [])
            .where((t) => t.needsReview)
            .length;

    void go(String route) => Navigator.pushNamed(context, route);

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(2, 10, 0, 16),
              child: Row(children: [
                const Expanded(
                  child: Text('Me',
                      style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.6)),
                ),
                IconButton(
                  tooltip: 'Settings',
                  onPressed: () => go(AppRoutes.settings),
                  icon: const Icon(Icons.settings_outlined),
                ),
              ]),
            ),
            _ProfileCard(profile: profile, g: g),
            if (pendingCount > 0) ...[
              const SizedBox(height: 12),
              _ReviewBanner(
                  count: pendingCount, onTap: () => go(AppRoutes.smsReview)),
            ],
            const SizedBox(height: 22),
            const SectionLabel('Money'),
            _Group(rows: [
              _Row(
                icon: Icons.stacked_line_chart_rounded,
                title: 'Net worth',
                subtitle: 'Everything you own minus what you owe',
                onTap: () => go(AppRoutes.netWorth),
              ),
              _Row(
                icon: Icons.account_balance_outlined,
                title: 'Accounts',
                subtitle: 'Balances by bank, card and wallet',
                onTap: () => go(AppRoutes.accounts),
              ),
              _Row(
                icon: Icons.savings_outlined,
                title: 'Budgets',
                subtitle: 'Monthly limits by category',
                onTap: () => go(AppRoutes.budgets),
              ),
              _Row(
                icon: Icons.flag_outlined,
                title: 'Goals',
                subtitle: 'What you\'re saving for',
                onTap: () => go(AppRoutes.goals),
              ),
              _Row(
                icon: Icons.calendar_month_outlined,
                title: 'Bill calendar',
                subtitle: 'What\'s due and when — reminded a day before',
                onTap: () => go(AppRoutes.bills),
              ),
              _Row(
                icon: Icons.autorenew_rounded,
                title: 'Subscriptions',
                subtitle: 'Bills and renewals',
                onTap: () => go(AppRoutes.subscriptions),
              ),
              _Row(
                icon: Icons.handshake_outlined,
                title: 'Lent & borrowed',
                subtitle: 'Money between you and friends',
                onTap: () => go(AppRoutes.loans),
              ),
            ]),
            const SizedBox(height: 22),
            const SectionLabel('Tools'),
            _Group(rows: [
              _Row(
                icon: Icons.upload_file_outlined,
                title: 'Import bank statement',
                subtitle: 'PDF, CSV or Excel from any bank',
                onTap: () => go(AppRoutes.importStatement),
              ),
              _Row(
                icon: Icons.sms_outlined,
                title: 'Review imports',
                subtitle: pendingCount > 0
                    ? '$pendingCount waiting for a look'
                    : 'All caught up',
                badge: pendingCount > 0 ? '$pendingCount' : null,
                onTap: () => go(AppRoutes.smsReview),
              ),
              _Row(
                icon: Icons.widgets_outlined,
                title: 'Home-screen widgets',
                subtitle: 'Budget and quick-add on your launcher',
                onTap: () => go(AppRoutes.widgets),
              ),
            ]),
            const SizedBox(height: 22),
            const SectionLabel('You'),
            _Group(rows: [
              _Row(
                icon: Icons.grading_rounded,
                title: 'Report card',
                subtitle: 'Your monthly grade — share it',
                onTap: () => go(AppRoutes.reportCard),
              ),
              _Row(
                icon: Icons.auto_awesome_outlined,
                title: 'Monthly Wrapped',
                subtitle: 'Your month in money, as a story',
                onTap: () => go(AppRoutes.wrapped),
              ),
              _Row(
                icon: Icons.emoji_events_outlined,
                title: 'Aeris World',
                subtitle: 'Streaks, challenges and rewards',
                onTap: () => go(AppRoutes.aerisWorld),
              ),
            ]),
            const SizedBox(height: 22),
            _Group(rows: [
              _Row(
                icon: Icons.settings_outlined,
                title: 'Settings',
                subtitle: 'Theme, privacy, backup and export',
                onTap: () => go(AppRoutes.settings),
              ),
            ]),
            const SizedBox(height: 22),
            OutlinedButton.icon(
              onPressed: () => _signOut(context, ref),
              icon: const Icon(Icons.logout_rounded, size: 19),
              label: const Text('Sign out'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AerisColors.danger(context),
                side: BorderSide(
                    color: AerisColors.danger(context).withValues(alpha: 0.35)),
                minimumSize: const Size.fromHeight(50),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 18),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.lock_outline_rounded,
                      size: 13, color: AerisColors.muted(context)),
                  const SizedBox(width: 5),
                  Text('Your data is end-to-end encrypted',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: AerisColors.muted(context))),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Profile card ──────────────────────────────────────────────
class _ProfileCard extends StatelessWidget {
  final UserProfile? profile;
  final GamificationState g;
  const _ProfileCard({required this.profile, required this.g});

  @override
  Widget build(BuildContext context) {
    final name = (profile?.displayName ?? '').trim();
    final email = profile?.email ?? '';
    final initials = _initials(name.isNotEmpty ? name : email);
    final muted = AerisColors.muted(context);
    final accent = AerisColors.accent(context);

    final bytes = profile?.photoBytes;
    final url = profile?.photoUrl;
    ImageProvider? img;
    if (bytes != null && bytes.isNotEmpty) {
      img = MemoryImage(bytes);
    } else if (url != null && url.isNotEmpty) {
      img = NetworkImage(url);
    }

    return AerisCard(
      padding: const EdgeInsets.all(16),
      onTap: () => Navigator.pushNamed(context, AppRoutes.editProfile),
      child: Row(children: [
        Container(
          width: 60,
          height: 60,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: img == null ? AerisColors.accentSoft(context) : null,
            image: img == null
                ? null
                : DecorationImage(image: img, fit: BoxFit.cover),
          ),
          child: img == null
              ? Text(initials,
                  style: TextStyle(
                      fontSize: 21, fontWeight: FontWeight.w800, color: accent))
              : null,
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(name.isEmpty ? 'Add your name' : name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3)),
              if (email.isNotEmpty)
                Text(email,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                        color: muted)),
              const SizedBox(height: 8),
              Wrap(spacing: 6, runSpacing: 6, children: [
                GestureDetector(
                  onTap: () =>
                      Navigator.pushNamed(context, AppRoutes.aerisWorld),
                  child: _Pill(
                    icon: Icons.bolt_rounded,
                    label: 'Level ${g.level} · ${_fmtAura(g.available)} Aura',
                  ),
                ),
                if (profile != null && profile!.monthlyIncome > 0)
                  _Pill(
                      label:
                          '${formatRupees(profile!.monthlyIncome, compact: true)}/mo'),
              ]),
            ],
          ),
        ),
        Icon(Icons.chevron_right_rounded, color: muted),
      ]),
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

  static String _fmtAura(int v) {
    if (v >= 100000) return '${(v / 100000).toStringAsFixed(1)}L';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}K';
    return '$v';
  }
}

class _Pill extends StatelessWidget {
  final IconData? icon;
  final String label;
  const _Pill({required this.label, this.icon});

  @override
  Widget build(BuildContext context) {
    final accent = AerisColors.accent(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: AerisColors.accentSoft(context),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[
          Icon(icon, size: 13, color: accent),
          const SizedBox(width: 3),
        ],
        Text(label,
            style: TextStyle(
                fontSize: 11.5, fontWeight: FontWeight.w700, color: accent)),
      ]),
    );
  }
}

/// "N imports to review" — the one actionable thing on this tab, so it gets
/// its own banner above the lists when there's something to do.
class _ReviewBanner extends StatelessWidget {
  final int count;
  final VoidCallback onTap;
  const _ReviewBanner({required this.count, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return AerisCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      color: dark ? const Color(0xFF2A2212) : const Color(0xFFFFF8EB),
      onTap: onTap,
      child: Row(children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: AerisColors.warning.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.sms_outlined,
              size: 19, color: AerisColors.warning),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            '$count import${count == 1 ? '' : 's'} to review',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
        ),
        const Text('Review',
            style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w800,
                color: AerisColors.warning)),
        const Icon(Icons.chevron_right_rounded, color: AerisColors.warning),
      ]),
    );
  }
}

// ── Grouped list ──────────────────────────────────────────────
class _Group extends StatelessWidget {
  final List<_Row> rows;
  const _Group({required this.rows});

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: AerisColors.cardDecoration(context),
      child: Column(children: [
        for (var i = 0; i < rows.length; i++) ...[
          rows[i],
          if (i < rows.length - 1)
            const Divider(height: 1, indent: 64, endIndent: 16),
        ],
      ]),
    );
  }
}

class _Row extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String? badge;
  final VoidCallback onTap;

  const _Row({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    final muted = AerisColors.muted(context);
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
          child: Row(children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AerisColors.accentSoft(context),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(icon, size: 19, color: AerisColors.accent(context)),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 1),
                  Text(subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                          color: muted)),
                ],
              ),
            ),
            if (badge != null)
              Container(
                margin: const EdgeInsets.only(left: 8),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AerisColors.warning,
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(badge!,
                    style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        color: Colors.white)),
              ),
            Icon(Icons.chevron_right_rounded, color: muted),
          ]),
        ),
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
  // The village lives in memory too; drop it so the next account doesn't
  // see this one's town.
  ref.invalidate(villageProvider);
}
