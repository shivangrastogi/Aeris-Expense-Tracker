part of 'transactions_screen.dart';

// Lent and Subscriptions sub-tabs of Activity.

// ── Lent sub-tab ──────────────────────────────────────────────
class _LentTab extends ConsumerWidget {
  const _LentTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loansAsync = ref.watch(loansStreamProvider);
    final totals = ref.watch(loanTotalsProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return loansAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('$e')),
      data: (loans) {
        final pending = loans.where((l) => !l.isSettled).toList();
        final settled = loans.where((l) => l.isSettled).toList();

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 80),
          children: [
            // Summary cards
            Row(children: [
              Expanded(
                child: _LentSummaryCard(
                  label: 'Owed to you',
                  amount: totals.owedToYou,
                  icon: Icons.check,
                  color: AerisColors.moneyIn(context),
                  isDark: isDark,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _LentSummaryCard(
                  label: 'You owe',
                  amount: totals.youOwe,
                  icon: Icons.north_east,
                  color: AerisColors.moneyOut(context),
                  isDark: isDark,
                ),
              ),
            ]),
            const SizedBox(height: 20),
            if (loans.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 40),
                child: Column(children: [
                  Icon(Icons.handshake_outlined,
                      size: 52,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurfaceVariant
                          .withValues(alpha: 0.4)),
                  const SizedBox(height: 10),
                  const Text('Nothing tracked yet',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text('Gave money to a friend?\nAdd it here via the + button.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 13,
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant)),
                ]),
              ),
            if (pending.isNotEmpty) ...[
              Row(children: [
                Icon(Icons.access_time, size: 16, color: AerisColors.warning),
                const SizedBox(width: 6),
                Text(
                  'Pending ${pending.length}',
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3),
                ),
              ]),
              const SizedBox(height: 10),
              for (final l in pending)
                _LentTile(
                    loan: l,
                    isDark: isDark,
                    onTap: () => _detailSheet(context, ref, l)),
            ],
            if (settled.isNotEmpty) ...[
              const SizedBox(height: 18),
              Row(children: [
                Icon(Icons.check_circle,
                    size: 16, color: AerisColors.moneyIn(context)),
                const SizedBox(width: 6),
                const Text('Settled',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3)),
              ]),
              const SizedBox(height: 10),
              for (final l in settled)
                _LentTile(
                    loan: l,
                    isDark: isDark,
                    onTap: () => _detailSheet(context, ref, l)),
            ],
          ],
        );
      },
    );
  }

  void _detailSheet(BuildContext context, WidgetRef ref, Loan l) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            title: Text(l.person,
                style:
                    const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
            subtitle: Text(
                '${l.borrowed ? 'You borrowed' : 'You lent'} ${formatRupees(l.amount)}'
                '${l.note.isNotEmpty ? ' · ${l.note}' : ''}'),
          ),
          if (!l.isSettled) ...[
            if (l.paid > 0)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Text(
                          '${formatRupees(l.paid)} of ${formatRupees(l.amount)} back',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant)),
                      const Spacer(),
                      Text('${(l.paid / l.amount * 100).round()}%',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: AerisColors.ink(context))),
                    ]),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(99),
                      child: LinearProgressIndicator(
                        value: (l.paid / l.amount).clamp(0.0, 1.0),
                        minHeight: 6,
                        backgroundColor: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest,
                        color: AerisColors.accent(context),
                      ),
                    ),
                  ],
                ),
              ),
            ListTile(
              leading: const CircleAvatar(
                backgroundColor: Color(0x3315A24A),
                child: Icon(Icons.check, color: Color(0xFF15A24A)),
              ),
              title:
                  Text(l.borrowed ? 'Mark as paid back' : 'Mark as received'),
              onTap: () async {
                Navigator.pop(ctx);
                final uid = ref.read(currentUserIdProvider);
                if (uid == null) return;
                await ref.read(firestoreServiceProvider).setLoan(
                    uid, l.copyWith(paid: l.amount, settledAt: DateTime.now()));
              },
            ),
            ListTile(
              leading: CircleAvatar(
                backgroundColor: AerisColors.accentSoft(context),
                child: Icon(Icons.add_card, color: AerisColors.accent(context)),
              ),
              title: const Text('Record partial repayment'),
              onTap: () {
                Navigator.pop(ctx);
                _recordPartial(context, ref, l);
              },
            ),
          ] else
            ListTile(
              leading: const CircleAvatar(
                backgroundColor: Color(0x33F59E0B),
                child: Icon(Icons.undo, color: Color(0xFFF59E0B)),
              ),
              title: const Text('Mark as pending'),
              onTap: () async {
                Navigator.pop(ctx);
                final uid = ref.read(currentUserIdProvider);
                if (uid == null) return;
                await ref
                    .read(firestoreServiceProvider)
                    .setLoan(uid, l.copyWith(paid: 0, settledAt: null));
              },
            ),
          ListTile(
            leading: const CircleAvatar(
              backgroundColor: Color(0x33EF4444),
              child: Icon(Icons.delete_outline, color: Color(0xFFEF4444)),
            ),
            title: const Text('Delete'),
            onTap: () async {
              Navigator.pop(ctx);
              final uid = ref.read(currentUserIdProvider);
              if (uid == null) return;
              await ref.read(firestoreServiceProvider).deleteLoan(uid, l.id);
            },
          ),
        ]),
      ),
    );
  }

  void _recordPartial(BuildContext context, WidgetRef ref, Loan l) {
    final ctrl = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Record repayment',
            style: TextStyle(fontWeight: FontWeight.w800)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Outstanding: ${formatRupees(l.outstanding)}',
                style: TextStyle(
                    fontSize: 13,
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              autofocus: true,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Amount received',
                prefixText: '₹ ',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(d), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              final entered = double.tryParse(ctrl.text.trim()) ?? 0;
              Navigator.pop(d);
              if (entered <= 0) return;
              final uid = ref.read(currentUserIdProvider);
              if (uid == null) return;
              final newPaid = (l.paid + entered).clamp(0.0, l.amount);
              final fully = newPaid >= l.amount;
              await ref.read(firestoreServiceProvider).setLoan(
                    uid,
                    l.copyWith(
                      paid: newPaid,
                      settledAt: fully ? DateTime.now() : null,
                    ),
                  );
              if (context.mounted) {
                ScaffoldMessenger.of(context).showToast(SnackBar(
                    content: Text(fully
                        ? 'Settled in full 🎉'
                        : 'Recorded ${formatRupees(entered)}')));
              }
            },
            child: const Text('Record'),
          ),
        ],
      ),
    );
  }
}

class _LentSummaryCard extends StatelessWidget {
  final String label;
  final double amount;
  final IconData icon;
  final Color color;
  final bool isDark;
  const _LentSummaryCard({
    required this.label,
    required this.amount,
    required this.icon,
    required this.color,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    // Plain card, coloured figure: the colour carries the meaning (green =
    // coming back to you), the surface stays calm.
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: AerisColors.cardDecoration(context, radius: 18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 5),
          Text(label,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AerisColors.muted(context))),
        ]),
        const SizedBox(height: 6),
        Text(formatRupees(amount),
            style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: color,
                letterSpacing: -0.5)),
      ]),
    );
  }
}

class _LentTile extends StatelessWidget {
  final Loan loan;
  final bool isDark;
  final VoidCallback onTap;
  const _LentTile(
      {required this.loan, required this.isDark, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final l = loan;
    final color = l.borrowed
        ? AerisColors.moneyOut(context)
        : AerisColors.moneyIn(context);
    final avatarColor = _colorForName(l.person);
    final initials = l.person.trim().split(' ').take(2).map((w) {
      return w.isEmpty ? '' : w[0].toUpperCase();
    }).join();
    final dateStr = '${l.createdAt.day} ${const [
      '',
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ][l.createdAt.month]}';
    final cardColor = isDark ? AerisColors.cardDark : Colors.white;
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.07);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: borderColor),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.05),
                blurRadius: 8,
                offset: const Offset(0, 3)),
          ],
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Avatar circle
          Container(
            width: 42,
            height: 42,
            decoration:
                BoxDecoration(shape: BoxShape.circle, color: avatarColor),
            child: Center(
              child: Text(
                initials.isEmpty ? '?' : initials,
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 14),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Content
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(l.person,
                  style: const TextStyle(
                      fontSize: 14.5, fontWeight: FontWeight.w800)),
              const SizedBox(height: 2),
              Text(
                '${l.borrowed ? 'You borrowed' : 'You lent'} · $dateStr'
                '${l.note.isNotEmpty ? ' · ${l.note}' : ''}',
                style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w500),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              if (l.isPartial) ...[
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(99),
                      child: LinearProgressIndicator(
                        value: (l.paid / l.amount).clamp(0.0, 1.0),
                        minHeight: 5,
                        backgroundColor: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest,
                        color: AerisColors.accent(context),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text('${(l.paid / l.amount * 100).round()}%',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: AerisColors.ink(context))),
                ]),
              ],
            ]),
          ),
          const SizedBox(width: 12),
          // Amount + badge
          Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  formatRupees(l.amount),
                  style: TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w800,
                      color: l.isSettled
                          ? Theme.of(context).colorScheme.onSurfaceVariant
                          : color),
                ),
                const SizedBox(height: 5),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: l.isSettled
                        ? AerisColors.moneyIn(context).withValues(alpha: 0.15)
                        : const Color(0xFFD97706).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    l.isSettled ? 'Received' : 'Pending',
                    style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        color: l.isSettled
                            ? AerisColors.moneyIn(context)
                            : const Color(0xFFD97706)),
                  ),
                ),
              ]),
        ]),
      ),
    );
  }

  static Color _colorForName(String name) {
    final colors = [
      const Color(0xFF0EA5A4),
      const Color(0xFF8B5CF6),
      const Color(0xFF15A24A),
      const Color(0xFFD97706),
      const Color(0xFFEC4899),
      const Color(0xFF3B82F6),
      const Color(0xFFEF4444),
    ];
    final hash = name.codeUnits.fold(0, (h, c) => (h * 31 + c) & 0x7FFFFFFF);
    return colors[hash % colors.length];
  }
}

// Subs sub-tab - managed subscriptions (Activity > Subs)
class _SubsTab extends StatelessWidget {
  const _SubsTab();

  @override
  Widget build(BuildContext context) => const SubscriptionsBody(embed: true);
}
