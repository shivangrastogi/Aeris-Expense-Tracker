import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:syncfusion_flutter_charts/charts.dart';

import '../../core/routes.dart';
import '../../core/theme.dart';
import '../../providers/money_providers.dart';
import '../../providers/privacy_provider.dart';
import '../../utils/formatters.dart';
import '../../widgets/ds.dart';

/// Everything you own minus everything you owe, as one number — with what it's
/// made of and how your cash has moved over the last year.
class NetWorthScreen extends ConsumerWidget {
  const NetWorthScreen({super.key});

  static const _months = [
    '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct',
    'Nov', 'Dec'
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hidden = ref.watch(amountHiddenProvider);
    final w = ref.watch(netWorthProvider);
    final trend = ref.watch(netWorthTrendProvider);
    final projection = ref.watch(projectionProvider);
    final tk = context.tk;

    final first = trend.isEmpty ? 0.0 : trend.first.$2;
    final last = trend.isEmpty ? 0.0 : trend.last.$2;
    final change = last - first;

    return Scaffold(
      appBar: AppBar(title: const Text('Net worth')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
        children: [
          // ── The number: the screen's one hero card ──
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              gradient: LinearGradient(
                begin: const Alignment(-0.85, -1),
                end: const Alignment(0.85, 1),
                colors: [tk.heroA, tk.heroB],
              ),
              boxShadow: tk.shadow,
            ),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Overline('Net worth', color: tk.onHero),
              const SizedBox(height: 8),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: MoneyText(w.total,
                    style: Ts.display,
                    color: tk.onHero,
                    credit: w.total < 0 ? false : null),
              ),
              if (trend.length > 1) ...[
                const SizedBox(height: 10),
                Container(
                  height: 28,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                      color: tk.surface,
                      borderRadius: BorderRadius.circular(14)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(change >= 0 ? PhBold.trendUp : PhBold.trendDown,
                        size: 14, color: change >= 0 ? tk.ok : tk.bad),
                    const SizedBox(width: 6),
                    Text(
                        '${change >= 0 ? '+' : kMinus}${formatRupees(change.abs(), compact: true)} cash in 12 months',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: tk.t1)),
                  ]),
                ),
              ],
              if (projection != null) ...[
                const SizedBox(height: 10),
                Text(
                  'At ${formatRupees(projection.perMonth, compact: true)}/month '
                  'you\'ll have ${formatRupees(projection.value, compact: true)} '
                  'by ${_months[projection.by.month]} ${projection.by.year}',
                  style: TextStyle(
                      color: tk.onHero,
                      fontSize: 13,
                      height: 18 / 13,
                      fontWeight: FontWeight.w600),
                ),
              ],
            ]),
          ),
          const SizedBox(height: 24),

          // ── What it's made of ──
          const Padding(
            padding: EdgeInsets.fromLTRB(4, 0, 4, 8),
            child: Overline('Made of'),
          ),
          ListGroup(children: [
            _Row(
              icon: Ph.bank,
              label: 'Bank & cash',
              sub: w.cashExact
                  ? 'From your account balances'
                  : 'Estimated from your activity',
              value: w.cash,
              onTap: () => Navigator.pushNamed(context, AppRoutes.accounts),
            ),
            _Row(
              icon: Ph.flagPennant,
              label: 'Saved in goals',
              sub: 'Money set aside for goals',
              value: w.goals,
              onTap: () => Navigator.pushNamed(context, AppRoutes.goals),
            ),
            _Row(
              icon: Ph.arrowDownLeft,
              label: 'Owed to you',
              sub: 'Money friends will pay back',
              value: w.owedToYou,
              onTap: () => Navigator.pushNamed(context, AppRoutes.loans),
            ),
            _Row(
              icon: Ph.arrowUpRight,
              label: 'You owe',
              sub: 'Borrowed, still to repay',
              value: -w.youOwe,
              onTap: () => Navigator.pushNamed(context, AppRoutes.loans),
            ),
          ]),
          const SizedBox(height: 24),

          // ── Trend ──
          if (trend.length > 1)
            Container(
              decoration: AerisColors.cardDecoration(context),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SectionTitle('Bank & cash', note: '12 months'),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 180,
                    child: SfCartesianChart(
                      plotAreaBorderWidth: 0,
                      margin: const EdgeInsets.only(right: 6, top: 6),
                      primaryXAxis: CategoryAxis(
                        majorGridLines: const MajorGridLines(width: 0),
                        majorTickLines: const MajorTickLines(width: 0),
                        axisLine: AxisLine(width: 1, color: tk.hair),
                        labelStyle: TextStyle(fontSize: 11, color: tk.t2),
                        interval: 2,
                      ),
                      primaryYAxis: const NumericAxis(
                        // Minimal axes: no grid, no value labels — the
                        // number above is the label.
                        isVisible: false,
                      ),
                      trackballBehavior: TrackballBehavior(
                        enable: !hidden,
                        activationMode: ActivationMode.singleTap,
                        lineColor: tk.t3,
                        lineDashArray: const [3, 4],
                        builder: (context, details) {
                          final y = details.point?.y?.toDouble() ?? 0;
                          return Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                                color: tk.inv,
                                borderRadius: BorderRadius.circular(8)),
                            child: Text(formatRupees(y, compact: true),
                                style: TextStyle(
                                    color: tk.onInv,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 11)),
                          );
                        },
                      ),
                      series: <CartesianSeries<(DateTime, double), String>>[
                        AreaSeries<(DateTime, double), String>(
                          dataSource: trend,
                          xValueMapper: (p, _) => _months[p.$1.month],
                          yValueMapper: (p, _) => p.$2,
                          borderColor: tk.acc,
                          borderWidth: 2,
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              tk.acc.withValues(alpha: 0.2),
                              tk.acc.withValues(alpha: 0.0),
                            ],
                          ),
                        ),
                        // "Now": the line ends in the dot.
                        ScatterSeries<(DateTime, double), String>(
                          dataSource: [trend.last],
                          xValueMapper: (p, _) => _months[p.$1.month],
                          yValueMapper: (p, _) => p.$2,
                          color: tk.acc,
                          borderColor: tk.surface,
                          borderWidth: 2,
                          markerSettings:
                              const MarkerSettings(width: 9, height: 9),
                          animationDuration: 0,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final IconData icon;
  final String label;
  final String sub;
  final double value;
  final VoidCallback onTap;
  const _Row(
      {required this.icon,
      required this.label,
      required this.sub,
      required this.value,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    final tk = context.tk;
    return DsRow(
      leading: BadgeTile(icon: icon, tint: tk.acc),
      title: label,
      sub: sub,
      onTap: onTap,
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        MoneyText(value,
            credit: value < 0 ? false : null,
            color: value < 0 ? tk.bad : tk.t1),
        const SizedBox(width: 6),
        Icon(Ph.caretRight, size: 16, color: tk.t3),
      ]),
    );
  }
}
