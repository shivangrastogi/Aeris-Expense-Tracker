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
import '../../providers/privacy_provider.dart';
import '../../widgets/ds.dart';
import '../../widgets/income_text.dart';
import '../../providers/income_lock_provider.dart';

/// The "Me" tab: who you are, then everything else grouped by what it's for —
/// Money (the things you manage), Tools (ways data gets in) and You (the fun
/// stuff). One tidy list instead of a grid of equal-looking tiles.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(amountHiddenProvider); // the header's "Hidden" badge
    final tk = context.tk;
    final profile = ref.watch(userProfileProvider).asData?.value;
    final g = ref.watch(gamificationProvider);
    final pendingCount =
        (ref.watch(transactionsStreamProvider).valueOrNull ?? const [])
            .where((t) => t.needsReview)
            .length;

    // On tablets the page opens in the right-hand pane (see [MeTab]).
    void go(String route) {
      final pane = _MePane.maybeOf(context);
      pane != null ? pane(route) : Navigator.pushNamed(context, route);
    }

    Widget group(String head, List<Widget> rows) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (head.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                child: Overline(head),
              ),
            ListGroup(inset: 64, children: rows),
          ],
        );

    return Scaffold(
      body: SafeArea(
        bottom: false,
        // Large "Me" → slim bar once the page scrolls.
        child: CollapseOnScroll(
          builder: (context, collapsed) => Column(children: [
            CollapsingHeader(
              title: 'Me',
              collapsed: collapsed,
              actions: [
                IconButton(
                  tooltip: 'Settings',
                  onPressed: () => go(AppRoutes.settings),
                  icon: const Icon(Ph.gearSix, size: 22),
                ),
              ],
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
                children: [
                  _ProfileCard(profile: profile, g: g),
                  if (pendingCount > 0) ...[
                    const SizedBox(height: 18),
                    _ReviewBanner(
                        count: pendingCount,
                        onTap: () => go(AppRoutes.smsReview)),
                  ],
                  const SizedBox(height: 18),
                  group('Money', [
                    SettingsRow(
                        icon: Ph.scales,
                        title: 'Net worth',
                        onTap: () => go(AppRoutes.netWorth)),
                    SettingsRow(
                        icon: Ph.bank,
                        title: 'Accounts',
                        onTap: () => go(AppRoutes.accounts)),
                    SettingsRow(
                        icon: Ph.target,
                        title: 'Budgets',
                        onTap: () => go(AppRoutes.budgets)),
                    SettingsRow(
                        icon: Ph.flagBanner,
                        title: 'Goals',
                        onTap: () => go(AppRoutes.goals)),
                    SettingsRow(
                        icon: Ph.calendarDots,
                        title: 'Bills and subscriptions',
                        onTap: () => go(AppRoutes.bills)),
                    SettingsRow(
                        icon: Ph.usersThree,
                        title: 'People',
                        onTap: () => go(AppRoutes.people)),
                  ]),
                  const SizedBox(height: 18),
                  group('Tools', [
                    SettingsRow(
                        icon: Ph.fileArrowUp,
                        title: 'Import bank statement',
                        onTap: () => go(AppRoutes.importStatement)),
                    SettingsRow(
                      icon: Ph.eye,
                      title: 'Review imports',
                      sub: pendingCount > 0 ? null : 'All caught up',
                      trailing: pendingCount > 0
                          ? Row(mainAxisSize: MainAxisSize.min, children: [
                              _CountBadge(pendingCount),
                              const SizedBox(width: 8),
                              Icon(Ph.caretRight, size: 16, color: tk.t3),
                            ])
                          : null,
                      onTap: () => go(AppRoutes.smsReview),
                    ),
                    SettingsRow(
                        icon: Ph.squaresFour,
                        title: 'Home-screen widgets',
                        onTap: () => go(AppRoutes.widgets)),
                  ]),
                  const SizedBox(height: 18),
                  group('You', [
                    SettingsRow(
                        icon: Ph.exam,
                        title: 'Report card',
                        onTap: () => go(AppRoutes.reportCard)),
                    SettingsRow(
                        icon: Ph.play,
                        title: 'Monthly Wrapped',
                        onTap: () => go(AppRoutes.wrapped)),
                    SettingsRow(
                        icon: Ph.globeHemisphereEast,
                        title: 'Aeris World',
                        sub: 'Your town grows as you save',
                        onTap: () => go(AppRoutes.aerisWorld)),
                  ]),
                  const SizedBox(height: 18),
                  group('', [
                    SettingsRow(
                        icon: Ph.gearSix,
                        title: 'Settings',
                        onTap: () => go(AppRoutes.settings)),
                  ]),
                  const SizedBox(height: 18),
                  OutlinedButton(
                    onPressed: () => confirmSignOut(context, ref),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: tk.bad,
                      side: BorderSide(color: tk.hair2, width: 1.5),
                      minimumSize: const Size.fromHeight(52),
                    ),
                    child: const Text('Sign out'),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Ph.lockSimple, size: 13, color: tk.t2),
                        const SizedBox(width: 5),
                        Text('Your data is end-to-end encrypted',
                            style: Ts.label.copyWith(
                                fontWeight: FontWeight.w400, color: tk.t2)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class _CountBadge extends StatelessWidget {
  final int count;
  const _CountBadge(this.count);

  @override
  Widget build(BuildContext context) {
    final tk = context.tk;
    return Container(
      constraints: const BoxConstraints(minWidth: 22),
      height: 22,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      alignment: Alignment.center,
      decoration:
          BoxDecoration(color: tk.acc, borderRadius: BorderRadius.circular(11)),
      child: Text('$count',
          style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w800, color: tk.onAcc)),
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
    final tk = context.tk;
    final name = (profile?.displayName ?? '').trim();
    final email = profile?.email ?? '';
    final initials = _initials(name.isNotEmpty ? name : email);

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
        if (img != null)
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              image: DecorationImage(image: img, fit: BoxFit.cover),
            ),
          )
        else
          InitialAvatar('',
              initials: initials, size: 56, color: const Color(0xFF8A7ED3)),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(name.isEmpty ? 'Add your name' : name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Ts.title.copyWith(color: tk.t1)),
              if (email.isNotEmpty)
                Text(email,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Ts.bodyS.copyWith(color: tk.t2)),
              const SizedBox(height: 8),
              Wrap(spacing: 6, runSpacing: 6, children: [
                GestureDetector(
                  onTap: () =>
                      Navigator.pushNamed(context, AppRoutes.aerisWorld),
                  child: StatusPill(
                    'Level ${g.level} · ${_fmtAura(g.available)} Aura',
                    icon: Ph.trendUp,
                    tone: Tone.accent,
                  ),
                ),
                if (profile != null && profile!.monthlyIncome > 0)
                  // Monthly income: behind the salary lock (tap to unlock).
                  Consumer(builder: (context, ref, _) {
                    final masked = ref.watch(incomeLockProvider).masked;
                    final pill = StatusPill(
                        '${formatIncome(profile!.monthlyIncome, compact: true)}/mo',
                        icon: masked ? PhFill.lockSimple : null);
                    return masked
                        ? GestureDetector(
                            onTap: () => unlockIncome(context, ref),
                            child: pill)
                        : pill;
                  }),
              ]),
            ],
          ),
        ),
        Icon(Ph.caretRight, size: 16, color: tk.t3),
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

/// "N imports to review" — the one actionable thing on this tab, so it gets
/// its own banner above the lists when there's something to do.
class _ReviewBanner extends StatelessWidget {
  final int count;
  final VoidCallback onTap;
  const _ReviewBanner({required this.count, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final tk = context.tk;
    return Material(
      color: tk.accSoft,
      borderRadius: BorderRadius.circular(Rad.button),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Rad.button),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
          child: Row(children: [
            Icon(PhFill.eye, size: 20, color: tk.acc),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '$count import${count == 1 ? '' : 's'} to review',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Ts.rowTitle.copyWith(color: tk.t1),
              ),
            ),
            FilledButton(
              onPressed: onTap,
              style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 40),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12))),
              child: const Text('Review'),
            ),
          ]),
        ),
      ),
    );
  }
}

/// "Sign out of AERIS?" — then [signOutWithCheck].
Future<void> confirmSignOut(BuildContext context, WidgetRef ref) async {
  final tk = context.tk;
  final ok = await showDialog<bool>(
    context: context,
    builder: (d) => AlertDialog(
      title: const Text('Sign out of AERIS?'),
      content: const Text(
          'Your encrypted data stays in backup. You\'ll need your password to '
          'unlock it on this or another phone.'),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(d, false),
            child: const Text('Cancel')),
        FilledButton(
          style: FilledButton.styleFrom(
              backgroundColor: tk.bad,
              foregroundColor:
                  tk.isDark ? const Color(0xFF1A0F0E) : Colors.white),
          onPressed: () => Navigator.pop(d, true),
          child: const Text('Sign out'),
        ),
      ],
    ),
  );
  if (ok == true && context.mounted) await signOutWithCheck(context, ref);
}

/// Signs out — but first warns if changes are still waiting to sync, since
/// they'd be rejected by the server once the session is gone.
Future<void> signOutWithCheck(BuildContext context, WidgetRef ref) async {
  final box = SyncOutbox.instance;
  await box.refresh();
  if (box.count > 0 && !await box.syncNow() && context.mounted) {
    final scheme = Theme.of(context).colorScheme;
    final n = box.count;
    final go = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        icon: Icon(Ph.cloudSlash, color: scheme.error),
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

/// The Me tab. On tablets / unfolded foldables it's list–detail: Me on the
/// left, the chosen page (Settings, Accounts, …) in a pane on the right with
/// its own back stack. Phones get the plain [ProfileScreen].
class MeTab extends StatefulWidget {
  const MeTab({super.key});

  @override
  State<MeTab> createState() => _MeTabState();
}

class _MeTabState extends State<MeTab> {
  final _pane = GlobalKey<NavigatorState>();

  void _open(String route) =>
      _pane.currentState?.pushNamedAndRemoveUntil(route, (_) => false);

  @override
  Widget build(BuildContext context) {
    final tk = context.tk;
    return LayoutBuilder(builder: (context, box) {
      if (box.maxWidth < 760) return const ProfileScreen();
      return Row(children: [
        SizedBox(
          width: 400,
          child: _MePane(open: _open, child: const ProfileScreen()),
        ),
        Container(width: 1, color: tk.hair),
        Expanded(
          child: ClipRect(
            child: Navigator(
              key: _pane,
              initialRoute: AppRoutes.settings,
              onGenerateRoute: AppRoutes.onGenerateRoute,
            ),
          ),
        ),
      ]);
    });
  }
}

class _MePane extends InheritedWidget {
  final ValueChanged<String> open;
  const _MePane({required this.open, required super.child});

  static ValueChanged<String>? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_MePane>()?.open;

  @override
  bool updateShouldNotify(_MePane old) => old.open != open;
}
