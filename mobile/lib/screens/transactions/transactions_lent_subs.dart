part of 'transactions_screen.dart';

// Lent and Subscriptions sub-tabs of Activity.

// ── Lent sub-tab ──────────────────────────────────────────────
class _LentTab extends ConsumerWidget {
  const _LentTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loansAsync = ref.watch(loansStreamProvider);
    final totals = ref.watch(loanTotalsProvider);
    final tk = context.tk;

    return Stack(children: [
      loansAsync.when(
        loading: () => const Center(child: RisingLoader(width: 32)),
        error: (e, _) => ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Banner2(
                tone: Tone.bad,
                icon: PhFill.cloudX,
                title: "Couldn't load what you've lent",
                body: '$e'),
          ],
        ),
        data: (loans) {
          final pending = loans.where((l) => !l.isSettled).toList();
          final settled = loans.where((l) => l.isSettled).toList();

          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 110),
            children: [
              // ── Owed to you | You owe ──────────────────────────
              Container(
                padding: const EdgeInsets.all(16),
                decoration: AerisColors.cardDecoration(context),
                child: IntrinsicHeight(
                  child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: _LentSummary(
                              label: 'Owed to you',
                              amount: totals.owedToYou,
                              color: tk.ok),
                        ),
                        Container(width: 1, color: tk.hair),
                        const SizedBox(width: 14),
                        Expanded(
                          child: _LentSummary(
                              label: 'You owe', amount: totals.youOwe),
                        ),
                      ]),
                ),
              ),
              if (loans.isEmpty)
                EmptyState(
                  icon: Ph.handCoins,
                  title: 'Nothing tracked yet',
                  body: 'Gave money to a friend? Add it here and mark it '
                      'when you get it back.',
                  cta: 'Add',
                  onCta: () => showAddLoanSheet(context, ref),
                )
              else ...[
                const Padding(
                  padding: EdgeInsets.fromLTRB(4, 18, 4, 8),
                  child: Overline('Pending'),
                ),
                if (pending.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: AerisColors.cardDecoration(context),
                    child: Row(children: [
                      Icon(PhFill.checkCircle, size: 22, color: tk.ok),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text("Nothing pending. Everyone's square.",
                            style: TextStyle(fontSize: 14, color: tk.t2)),
                      ),
                    ]),
                  ),
                for (final l in pending)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _LentPendingCard(
                      loan: l,
                      onTap: () => _detailSheet(context, ref, l),
                      onSettle: () => _settle(context, ref, l),
                    ),
                  ),
                if (settled.isNotEmpty) ...[
                  const Padding(
                    padding: EdgeInsets.fromLTRB(4, 12, 4, 8),
                    child: Overline('Settled'),
                  ),
                  ListGroup(children: [
                    for (final l in settled)
                      _LentSettledRow(
                          loan: l, onTap: () => _detailSheet(context, ref, l)),
                  ]),
                ],
              ],
            ],
          );
        },
      ),
      // ── Add ─────────────────────────────────────────────────
      Positioned(
        right: 20,
        bottom: 20,
        child: Material(
          color: tk.acc,
          elevation: 0,
          borderRadius: BorderRadius.circular(18),
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () => showAddLoanSheet(context, ref),
            child: Container(
              height: 56,
              padding: const EdgeInsets.fromLTRB(16, 0, 20, 0),
              decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: tk.shadowRaised),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(PhBold.plus, size: 20, color: tk.onAcc),
                const SizedBox(width: 8),
                Text('Add',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: tk.onAcc)),
              ]),
            ),
          ),
        ),
      ),
    ]);
  }

  Future<void> _settle(BuildContext context, WidgetRef ref, Loan l) async {
    final uid = ref.read(currentUserIdProvider);
    if (uid == null) return;
    await ref
        .read(firestoreServiceProvider)
        .setLoan(uid, l.copyWith(paid: l.amount, settledAt: DateTime.now()));
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showToast(SnackBar(content: Text('${l.person} marked settled')));
    }
  }

  void _detailSheet(BuildContext context, WidgetRef ref, Loan l) {
    showDsSheet<void>(
      context,
      title: l.person,
      subtitle: '${l.borrowed ? 'You borrowed' : 'You lent'} '
          '${formatRupees(l.amount)}'
          '${l.note.isNotEmpty ? ' · ${l.note}' : ''}',
      builder: (ctx) {
        final tk = ctx.tk;
        Future<void> save(Loan updated) async {
          Navigator.pop(ctx);
          final uid = ref.read(currentUserIdProvider);
          if (uid == null) return;
          await ref.read(firestoreServiceProvider).setLoan(uid, updated);
        }

        return Column(mainAxisSize: MainAxisSize.min, children: [
          if (!l.isSettled && l.paid > 0)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Expanded(
                      child: Text(
                          '${formatRupees(l.paid)} of ${formatRupees(l.amount)} back',
                          style: Ts.label.copyWith(color: tk.t2)),
                    ),
                    Text('${(l.paid / l.amount * 100).round()}%',
                        style: Ts.label.copyWith(
                            fontWeight: FontWeight.w700, color: tk.t1)),
                  ]),
                  const SizedBox(height: 6),
                  RisingProgress(value: l.paid / l.amount),
                ],
              ),
            ),
          ListGroup(inset: 64, children: [
            if (!l.isSettled) ...[
              SettingsRow(
                icon: Ph.check,
                iconColor: tk.ok,
                title: l.borrowed ? 'Mark as paid back' : 'Mark as received',
                onTap: () =>
                    save(l.copyWith(paid: l.amount, settledAt: DateTime.now())),
              ),
              SettingsRow(
                icon: Ph.coins,
                iconColor: tk.acc,
                title: 'Record partial repayment',
                onTap: () {
                  Navigator.pop(ctx);
                  _recordPartial(context, ref, l);
                },
              ),
            ] else
              SettingsRow(
                icon: Ph.arrowCounterClockwise,
                iconColor: tk.warn,
                title: 'Mark as pending',
                onTap: () => save(l.copyWith(paid: 0, settledAt: null)),
              ),
            SettingsRow(
              icon: Ph.trash,
              iconColor: tk.bad,
              title: 'Delete',
              titleColor: tk.bad,
              onTap: () async {
                Navigator.pop(ctx);
                final uid = ref.read(currentUserIdProvider);
                if (uid == null) return;
                await ref.read(firestoreServiceProvider).deleteLoan(uid, l.id);
              },
            ),
          ]),
        ]);
      },
    );
  }

  void _recordPartial(BuildContext context, WidgetRef ref, Loan l) {
    final ctrl = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Record repayment'),
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

/// One side of the Lent summary: overline + 26/700 figure.
class _LentSummary extends StatelessWidget {
  final String label;
  final double amount;
  final Color? color;
  const _LentSummary({required this.label, required this.amount, this.color});

  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Overline(label),
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: MoneyText(amount,
              color: color,
              style: const TextStyle(
                  fontSize: 26, height: 32 / 26, fontWeight: FontWeight.w700)),
        ),
      ]);
}

String _shortDay(DateTime d) => '${d.day} ${const [
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
    ][d.month]}';

/// A pending loan: avatar, who + note, amount + direction, "Mark settled".
class _LentPendingCard extends StatelessWidget {
  final Loan loan;
  final VoidCallback onTap;
  final VoidCallback onSettle;
  const _LentPendingCard(
      {required this.loan, required this.onTap, required this.onSettle});

  @override
  Widget build(BuildContext context) {
    final tk = context.tk;
    final l = loan;
    final note = [
      l.borrowed ? 'You borrowed' : 'You lent',
      _shortDay(l.createdAt),
      if (l.note.isNotEmpty) l.note,
    ].join(' · ');
    return Material(
      color: Colors.transparent,
      child: Container(
        decoration: AerisColors.cardDecoration(context),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(Rad.card),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Column(children: [
              Row(children: [
                InitialAvatar(l.person),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(l.person,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Ts.rowTitle.copyWith(color: tk.t1)),
                        Text(note,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Ts.bodyS.copyWith(color: tk.t2)),
                      ]),
                ),
                const SizedBox(width: 12),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  MoneyText(l.outstanding,
                      color: l.borrowed ? tk.t1 : tk.ok,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w700)),
                  Text(l.borrowed ? 'you owe' : 'owes you',
                      style: TextStyle(fontSize: 11, color: tk.t2)),
                ]),
              ]),
              if (l.isPartial) ...[
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(child: RisingProgress(value: l.paid / l.amount)),
                  const SizedBox(width: 8),
                  Text('${(l.paid / l.amount * 100).round()}% back',
                      style: Ts.label.copyWith(color: tk.t2)),
                ]),
              ],
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: onSettle,
                  icon: const Icon(Ph.check, size: 15),
                  label: const Text('Mark settled'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 40),
                    padding: EdgeInsets.zero,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(Rad.chip)),
                    textStyle: const TextStyle(
                        fontFamily: kFontFamily,
                        fontSize: 13,
                        fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// A settled loan row: muted amount and a green check.
class _LentSettledRow extends StatelessWidget {
  final Loan loan;
  final VoidCallback onTap;
  const _LentSettledRow({required this.loan, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final tk = context.tk;
    final l = loan;
    final sub = [
      if (l.note.isNotEmpty) l.note else (l.borrowed ? 'Borrowed' : 'Lent'),
      if (l.settledAt != null) 'settled ${_shortDay(l.settledAt!)}',
    ].join(' · ');
    return DsRow(
      leading: InitialAvatar(l.person),
      title: l.person,
      sub: sub,
      onTap: onTap,
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        MoneyText(l.amount, color: tk.t2),
        const SizedBox(width: 8),
        Icon(PhFill.checkCircle, size: 18, color: tk.ok),
      ]),
    );
  }
}

// Subs sub-tab - managed subscriptions (Activity > Subs)
class _SubsTab extends StatelessWidget {
  const _SubsTab();

  @override
  Widget build(BuildContext context) => const SubscriptionsBody(embed: true);
}
