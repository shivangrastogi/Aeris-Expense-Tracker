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
import '../../utils/motion.dart';
import '../../widgets/ds.dart';

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
        icon: Ph.chatText,
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
        icon: Ph.warning,
        color: context.tk.warn,
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
        icon: Ph.creditCard,
        color: days <= 1 ? AerisColors.danger(context) : context.tk.warn,
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
          icon: Ph.wallet,
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
        icon: Ph.arrowsSplit,
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
        icon: Ph.flame,
        color: context.tk.warn,
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
    final tk = context.tk;
    final all = _derive();
    final unread = all.where((n) => !_read.contains(_key(n))).length;
    final view = all.where((n) {
      if (_tab == 'all') return true;
      if (_tab == 'unread') return !_read.contains(_key(n));
      return n.type == _tab;
    }).toList();

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Back',
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Ph.arrowLeft),
        ),
        actions: [
          if (unread > 0)
            TextButton(
              onPressed: () => _markRead(all),
              child: const Text('Mark all read'),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Text('Notifications',
                style: Ts.headline
                    .copyWith(fontSize: 28, height: 34 / 28, color: tk.t1)),
          ),
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              children: [
                _tabChip('all', 'All'),
                _tabChip('unread', 'Unread', count: unread),
                _tabChip('budget', 'Money'),
                _tabChip('bill', 'Bills'),
                _tabChip('people', 'People'),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: view.isEmpty
                ? _empty(context)
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                    itemCount: view.length,
                    itemBuilder: (_, i) {
                      final n = view[i];
                      final isUnread = !_read.contains(_key(n));
                      final tile = _tile(context, n, isUnread);
                      if (reduceMotion(context) || i >= 8) return tile;
                      return tile
                          .animate(delay: (i * 20).ms)
                          .fadeIn(duration: 250.ms)
                          .slideY(begin: 0.04, end: 0);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _tabChip(String key, String label, {int count = 0}) {
    final sel = _tab == key;
    void pick() => setState(() => _tab = key);
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Center(
        child: count > 0 && !sel
            ? _CountChip(label: label, count: count, onTap: pick)
            : DsChip(label, selected: sel, onTap: pick),
      ),
    );
  }

  Widget _tile(BuildContext context, _Notif n, bool unread) {
    final tk = context.tk;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AerisCard(
        padding: const EdgeInsets.all(16),
        color: unread ? tk.surface : tk.surface.withValues(alpha: 0.6),
        onTap: () => _open(n),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CatTile(color: n.color, icon: n.icon),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(
                      child: Text(n.title,
                          style: Ts.rowTitle.copyWith(
                              color: unread ? tk.t1 : tk.t2)),
                    ),
                    if (unread)
                      Container(
                        width: 8,
                        height: 8,
                        margin: const EdgeInsets.only(left: 8, top: 7),
                        decoration: BoxDecoration(
                            shape: BoxShape.circle, color: tk.acc),
                      ),
                  ]),
                  const SizedBox(height: 2),
                  Text(n.body, style: Ts.bodyS.copyWith(color: tk.t2)),
                  const SizedBox(height: 10),
                  Row(children: [
                    Text(n.action,
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: tk.acc)),
                    const SizedBox(width: 4),
                    Icon(Ph.arrowRight, size: 14, color: tk.acc),
                  ]),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _empty(BuildContext context) => const Center(
        child: EmptyState(
          icon: Ph.bellSlash,
          title: 'Nothing here',
          body: "You're all caught up.",
        ),
      );
}

/// "Unread 5" — a chip with a small count bubble.
class _CountChip extends StatelessWidget {
  final String label;
  final int count;
  final VoidCallback onTap;
  const _CountChip(
      {required this.label, required this.count, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final tk = context.tk;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Rad.chip),
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(Rad.chip),
          border: Border.all(color: tk.hair2),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(label,
              style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600, color: tk.t1)),
          const SizedBox(width: 6),
          Container(
            height: 18,
            constraints: const BoxConstraints(minWidth: 18),
            padding: const EdgeInsets.symmetric(horizontal: 5),
            alignment: Alignment.center,
            decoration: BoxDecoration(
                color: tk.press, borderRadius: BorderRadius.circular(9)),
            child: Text('$count',
                style: TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w700, color: tk.t2)),
          ),
        ]),
      ),
    );
  }
}
