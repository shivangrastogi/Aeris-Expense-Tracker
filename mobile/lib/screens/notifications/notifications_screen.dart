import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/routes.dart';
import '../../core/theme.dart';
import '../../models/category.dart';
import '../../providers/accounts_provider.dart';
import '../../providers/gamification_provider.dart';
import '../../providers/insights_provider.dart';
import '../../providers/money_providers.dart';
import '../../providers/transactions_provider.dart';
import '../../utils/formatters.dart';

/// A notification derived from real app state (no fake data): pending SMS to
/// review, budgets at risk, streak reminders.
class _Notif {
  final String id;
  final IconData icon;
  final Color color;
  final String title;
  final String body;
  final String action;
  final String? route;
  final String type; // 'bill' | 'budget' | 'reward' | 'sms' | 'insight'

  const _Notif({
    required this.id,
    required this.icon,
    required this.color,
    required this.title,
    required this.body,
    required this.action,
    required this.route,
    required this.type,
  });
}

class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  /// Read alerts, remembered across visits. Keyed by id + title, so an alert
  /// whose content changes (a new amount, a new count) is unread again.
  final Set<String> _read = {};
  static const _readKey = 'notif_read';
  String _tab = 'all'; // all | unread | budget | bill | people

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      if (mounted) {
        setState(() => _read.addAll(p.getStringList(_readKey) ?? const []));
      }
    });
  }

  static String _key(_Notif n) => '${n.id}|${n.title}';

  Future<void> _markRead(Iterable<_Notif> ns) async {
    setState(() => _read.addAll(ns.map(_key)));
    final list = _read.toList();
    await (await SharedPreferences.getInstance()).setStringList(
        _readKey, list.length > 150 ? list.sublist(list.length - 150) : list);
  }

  List<_Notif> _derive() {
    final out = <_Notif>[];

    // 1 · Pending SMS imports to review.
    final txns = ref.watch(transactionsStreamProvider).valueOrNull ?? const [];
    final pending =
        txns.where((t) => t.needsReview).length;
    if (pending > 0) {
      out.add(_Notif(
        id: 'sms',
        icon: Icons.sms_outlined,
        color: AerisColors.accent(context),
        title: '$pending new transaction${pending == 1 ? '' : 's'} to review',
        body: 'Verify or correct the transactions AERIS auto-imported.',
        action: 'Review imports',
        route: AppRoutes.smsReview,
        type: 'sms',
      ));
    }

    // 2 · Budgets at risk / over.
    final insights = ref.watch(insightsProvider).valueOrNull;
    final risky = (insights?.budgetProjections ?? [])
        .where((p) =>
            p.alreadyOver || (p.willExceed && (p.daysUntilExceed ?? 99) <= 7))
        .take(3);
    for (final p in risky) {
      final label = Categories.byId(p.categoryId).label;
      out.add(_Notif(
        id: 'budget_${p.categoryId}',
        icon: Icons.warning_amber_rounded,
        color: AerisColors.warning,
        title:
            p.alreadyOver ? '$label budget exceeded' : '$label budget at risk',
        body: p.alreadyOver
            ? "You've gone over your $label cap this month."
            : 'On track to exceed in ${p.daysUntilExceed ?? 0} days.',
        action: 'See budget',
        route: AppRoutes.budgets,
        type: 'budget',
      ));
    }

    // 2b · Credit-card bills due within 5 days.
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    for (final d in ref.watch(cardDuesProvider).valueOrNull ?? const []) {
      final days = DateTime(d.dueDate.year, d.dueDate.month, d.dueDate.day)
          .difference(today)
          .inDays;
      if (days > 5) continue;
      out.add(_Notif(
        id: 'card_${d.key}',
        icon: Icons.credit_card_outlined,
        color: days <= 1 ? AerisColors.danger(context) : AerisColors.warning,
        title: days < 0
            ? '${d.label} bill is overdue'
            : days == 0
                ? '${d.label} bill is due today'
                : '${d.label} bill due in $days day${days == 1 ? '' : 's'}',
        body: '${formatRupees(d.total, decimals: true)} due'
            '${d.minimum == null ? '' : ' · minimum ${formatRupees(d.minimum!)}'}.',
        action: 'See bills',
        route: AppRoutes.bills,
        type: 'bill',
      ));
    }

    // 2c · Accounts below the low-balance alert.
    final limit = ref.watch(lowBalanceLimitProvider);
    if (limit > 0) {
      for (final a in ref.watch(accountsProvider)) {
        final bal = a.bankBalance;
        if (bal == null || bal >= limit) continue;
        out.add(_Notif(
          id: 'lowbal_${a.key}',
          icon: Icons.account_balance_wallet_outlined,
          color: AerisColors.danger(context),
          title: 'Low balance on ${a.label}',
          body: '${formatRupees(bal, decimals: true)} left, as of '
              '${asOfLabel(a.bankBalanceAt!)}.',
          action: 'See accounts',
          route: AppRoutes.accounts,
          type: 'budget',
        ));
      }
    }

    // 2d · Friends who haven't paid their share for 5+ days.
    final waiting = <String, double>{};
    for (final t in txns) {
      final split = t.split;
      if (split == null || now.difference(t.timestamp).inDays < 5) continue;
      for (final s in split.shares) {
        if (!s.settled) waiting[s.name] = (waiting[s.name] ?? 0) + s.outstanding;
      }
    }
    if (waiting.isNotEmpty) {
      final total = waiting.values.fold<double>(0, (s, v) => s + v);
      out.add(_Notif(
        id: 'owed',
        icon: Icons.call_split_rounded,
        color: AerisColors.accent(context),
        title: '${formatRupees(total)} owed to you',
        body: '${waiting.entries.take(3).map((e) => '${e.key} '
            '${formatRupees(e.value)}').join(', ')} — send a friendly reminder.',
        action: 'Open People',
        route: AppRoutes.people,
        type: 'people',
      ));
    }

    // 3 · Streak reminder / celebration. Use the live streak so a lapsed
    // streak doesn't keep nagging with a stale day count.
    final streak = ref.watch(gamificationProvider.select((g) => g.liveStreak));
    final checkedIn = ref.read(gamificationProvider.notifier).checkedInToday;
    if (streak > 0) {
      out.add(_Notif(
        id: 'streak',
        icon: Icons.local_fire_department,
        color: AerisColors.amber,
        title: checkedIn
            ? '$streak-day streak going strong'
            : 'Keep your $streak-day streak',
        body: checkedIn
            ? 'Nice work — see you tomorrow to keep it lit.'
            : 'Check in today to claim your Aura.',
        action: 'Open Aeris World',
        route: AppRoutes.aerisWorld,
        type: 'reward',
      ));
    }

    return out;
  }

  void _open(_Notif n) {
    _markRead([n]);
    if (n.route != null) Navigator.pushNamed(context, n.route!);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final all = _derive();
    final unread = all.where((n) => !_read.contains(_key(n))).length;
    final view = all.where((n) {
      if (_tab == 'all') return true;
      if (_tab == 'unread') return !_read.contains(_key(n));
      return n.type == _tab;
    }).toList();

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back_rounded),
                    style: IconButton.styleFrom(
                      backgroundColor: scheme.onSurface.withValues(alpha: 0.07),
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
                        const Text('Notifications',
                            style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.4)),
                        Text(
                          unread > 0 ? '$unread unread' : 'All caught up',
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  if (unread > 0)
                    TextButton(
                      onPressed: () =>
                          _markRead(all),
                      child: Text('Mark all read',
                          style: TextStyle(
                              color: AerisColors.ink(context),
                              fontWeight: FontWeight.w800,
                              fontSize: 12.5)),
                    ),
                ],
              ),
            ),
            // Tabs
            SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  _tabChip('all', 'All'),
                  _tabChip('unread', 'Unread'),
                  _tabChip('budget', 'Money'),
                  _tabChip('bill', 'Bills'),
                  _tabChip('people', 'People'),
                ],
              ),
            ),
            const SizedBox(height: 8),
            // List
            Expanded(
              child: view.isEmpty
                  ? _empty(context)
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 30),
                      itemCount: view.length,
                      itemBuilder: (_, i) {
                        final n = view[i];
                        final isUnread = !_read.contains(_key(n));
                        return _tile(context, n, isUnread, dark)
                            .animate(delay: (i * 40).ms)
                            .fadeIn(duration: 250.ms)
                            .slideY(begin: 0.05, end: 0);
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tabChip(String key, String label) {
    final sel = _tab == key;
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: () => setState(() => _tab = key),
        child: Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: sel
                ? AerisColors.accent(context)
                : scheme.onSurface.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(99),
          ),
          child: Text(label,
              style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: sel ? AerisColors.onAccent(context) : scheme.onSurfaceVariant)),
        ),
      ),
    );
  }

  Widget _tile(BuildContext context, _Notif n, bool unread, bool dark) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        onTap: () => _open(n),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: unread
                ? (dark ? AerisColors.cardDark : Colors.white)
                : scheme.onSurface.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: scheme.onSurface.withValues(alpha: 0.08)),
            boxShadow: unread
                ? [
                    BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 10,
                        offset: const Offset(0, 3))
                  ]
                : null,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: n.color.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(n.icon, size: 23, color: n.color),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Expanded(
                        child: Text(n.title,
                            style: const TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w800)),
                      ),
                      if (unread)
                        Container(
                          width: 8,
                          height: 8,
                          margin: const EdgeInsets.only(left: 6, top: 4),
                          decoration: BoxDecoration(
                              shape: BoxShape.circle, color: AerisColors.accent(context)),
                        ),
                    ]),
                    const SizedBox(height: 2),
                    Text(n.body,
                        style: TextStyle(
                            fontSize: 12.5,
                            height: 1.4,
                            color: scheme.onSurfaceVariant)),
                    const SizedBox(height: 8),
                    Text('${n.action} →',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: n.color)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _empty(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 68,
            height: 68,
            decoration: BoxDecoration(
                color: scheme.onSurface.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(22)),
            child: Icon(Icons.notifications_off_outlined,
                size: 32, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 14),
          const Text('Nothing here',
              style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800)),
          const SizedBox(height: 5),
          Text("You're all caught up.",
              style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}
