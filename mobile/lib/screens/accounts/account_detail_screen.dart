import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/routes.dart';
import '../../core/theme.dart';
import '../../models/transaction.dart';
import '../../providers/accounts_provider.dart';
import '../../providers/privacy_provider.dart';
import '../../providers/transactions_provider.dart';
import '../../utils/formatters.dart';
import '../../widgets/ds.dart';
import '../../widgets/transaction_tile.dart';
import '../transactions/transactions_screen.dart';

/// One bank account: its balance as the bank last reported it, the balance
/// over the last 30 days (from the "Avl Bal" each SMS prints), and its
/// recent transactions.
class AccountDetailScreen extends ConsumerWidget {
  final String accountKey;
  const AccountDetailScreen({super.key, required this.accountKey});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(amountHiddenProvider);
    final tk = context.tk;
    final account = ref
        .watch(accountsProvider)
        .where((a) => a.key == accountKey)
        .firstOrNull;
    final txns = (ref.watch(transactionsStreamProvider).valueOrNull ??
            const <Transaction>[])
        .where((t) => (t.account ?? '').trim() == accountKey)
        .toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

    final title = account?.nickname ?? accountLabel(accountKey);
    final balance = account?.balance;

    return Scaffold(
      appBar: AppBar(
        title: Text(title, style: Ts.title.copyWith(color: tk.t1)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
        children: [
          Text(
              account?.nickname != null
                  ? accountLabel(accountKey)
                  : '${txns.length} transactions',
              style: Ts.bodyS.copyWith(color: tk.t2)),
          const SizedBox(height: 4),
          if (balance != null)
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: MoneyText(balance, style: Ts.display, smallDecimals: true),
            )
          else
            Text('Balance not known yet',
                style: Ts.title.copyWith(color: tk.t2)),
          const SizedBox(height: 4),
          Text(
              account?.bankBalanceAt != null
                  ? 'per bank SMS, ${asOfLabel(account!.bankBalanceAt!)}'
                  : 'Shows once a bank SMS prints the balance',
              style: Ts.label
                  .copyWith(fontWeight: FontWeight.w400, color: tk.t2)),
          const SizedBox(height: 20),
          _BalanceCard(txns: txns),
          const SizedBox(height: 16),
          if (txns.isEmpty)
            const EmptyState(
              icon: Ph.receipt,
              title: 'No transactions yet',
              body: 'Payments on this account will show up here.',
            )
          else ...[
            SectionTitle('Recent',
                action: txns.length > 8 ? 'See all' : null,
                padding: const EdgeInsets.only(left: 4, bottom: 4),
                onAction: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) =>
                            TransactionsScreen(initialAccount: accountKey)))),
            ListGroup(children: [
              for (final t in txns.take(8)) TransactionTile(txn: t),
            ]),
          ],
          const SizedBox(height: 20),
          Center(
            child: TextLink('How this counts in net worth →',
                onTap: () => Navigator.pushNamed(context, AppRoutes.netWorth)),
          ),
        ],
      ),
    );
  }
}

/// "Balance · 30 days": the balance each bank SMS printed, joined into a
/// line. Hidden amounts keep the shape but drop the value labels.
class _BalanceCard extends StatelessWidget {
  final List<Transaction> txns;
  const _BalanceCard({required this.txns});

  @override
  Widget build(BuildContext context) {
    final tk = context.tk;
    final since = DateTime.now().subtract(const Duration(days: 30));
    final points = [
      for (final t in txns.reversed)
        if (t.balance != null && t.timestamp.isAfter(since))
          (t.timestamp, t.balance!),
    ];
    // The biggest credit in the window explains the usual jump ("Salary").
    Transaction? bigIn;
    for (final t in txns) {
      if (!t.isCredit || t.timestamp.isBefore(since)) continue;
      if (bigIn == null || t.amount > bigIn.amount) bigIn = t;
    }

    return AerisCard(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Balance · 30 days', style: Ts.rowTitle.copyWith(color: tk.t1)),
        const SizedBox(height: 12),
        if (points.length < 2)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Text(
                'The line appears once two or more bank SMS print a balance.',
                style: Ts.bodyS.copyWith(color: tk.t2)),
          )
        else ...[
          SizedBox(
            height: 110,
            width: double.infinity,
            child: CustomPaint(
                painter: _LinePainter(points, tk.acc, tk.accSoft)),
          ),
          const SizedBox(height: 8),
          DefaultTextStyle.merge(
            style: TextStyle(fontSize: 11, color: tk.t2),
            child: Row(children: [
              Text(shortDay(points.first.$1)),
              const Spacer(),
              if (bigIn != null)
                Flexible(
                  child: Text(
                      '${bigIn.merchant ?? 'Money in'} ${shortDay(bigIn.timestamp)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ),
              const Spacer(),
              const Text('Today'),
            ]),
          ),
        ],
      ]),
    );
  }
}

class _LinePainter extends CustomPainter {
  final List<(DateTime, double)> points;
  final Color line, fill;
  _LinePainter(this.points, this.line, this.fill);

  @override
  void paint(Canvas canvas, Size size) {
    final t0 = points.first.$1.millisecondsSinceEpoch.toDouble();
    final t1 = math.max(
        DateTime.now().millisecondsSinceEpoch.toDouble(), t0 + 1);
    var lo = points.map((p) => p.$2).reduce(math.min);
    var hi = points.map((p) => p.$2).reduce(math.max);
    if (hi - lo < 1) hi = lo + 1;
    lo -= (hi - lo) * 0.08;
    Offset at((DateTime, double) p) => Offset(
          (p.$1.millisecondsSinceEpoch - t0) / (t1 - t0) * (size.width - 4),
          size.height - (p.$2 - lo) / (hi - lo) * (size.height - 6),
        );
    // Balances change in steps: hold each one until the next.
    final path = Path()..moveTo(at(points.first).dx, at(points.first).dy);
    for (var i = 1; i < points.length; i++) {
      final p = at(points[i]);
      path.lineTo(p.dx, at(points[i - 1]).dy);
      path.lineTo(p.dx, p.dy);
    }
    final end = Offset(size.width - 4, at(points.last).dy);
    path.lineTo(end.dx, end.dy);
    final area = Path.from(path)
      ..lineTo(end.dx, size.height)
      ..lineTo(at(points.first).dx, size.height)
      ..close();
    canvas.drawPath(area, Paint()..color = fill);
    canvas.drawPath(
        path,
        Paint()
          ..color = line
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeJoin = StrokeJoin.round);
  }

  @override
  bool shouldRepaint(_LinePainter o) => o.points != points || o.line != line;
}
