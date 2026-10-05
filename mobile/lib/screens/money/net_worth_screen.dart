import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:syncfusion_flutter_charts/charts.dart';

import '../../core/routes.dart';
import '../../core/theme.dart';
import '../../providers/money_providers.dart';
import '../../providers/privacy_provider.dart';
import '../../utils/formatters.dart';

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
    final muted = AerisColors.muted(context);
    final accent = AerisColors.accent(context);

    final first = trend.isEmpty ? 0.0 : trend.first.$2;
    final last = trend.isEmpty ? 0.0 : trend.last.$2;
    final change = last - first;

    return Scaffold(
      appBar: AppBar(title: const Text('Net worth')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          // ── The number ──
          Container(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
            decoration: BoxDecoration(
              gradient: AerisColors.inkGradient,
              borderRadius: BorderRadius.circular(26),
              border:
                  Border.all(color: AerisColors.arc.withValues(alpha: 0.22)),
            ),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('NET WORTH',
                  style: hudLabel(context,
                      color: const Color(0xB3EAF2F7))),
              const SizedBox(height: 8),
              Text(formatRupees(w.total),
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 40,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -1.2)),
              const SizedBox(height: 6),
              if (trend.length > 1)
                Text(
                    '${change >= 0 ? '▲' : '▼'} ${formatRupees(change.abs())} cash in 12 months',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: change >= 0
                            ? AerisColors.mint
                            : const Color(0xFFFF8A98))),
              if (projection != null) ...[
                const SizedBox(height: 10),
                Text(
                  'At ${formatRupees(projection.perMonth, compact: true)}/month '
                  'you\'ll have ${formatRupees(projection.value, compact: true)} '
                  'by ${_months[projection.by.month]} ${projection.by.year}',
                  style: const TextStyle(
                      color: Color(0xB3EAF2F7),
                      fontSize: 13,
                      fontWeight: FontWeight.w600),
                ),
              ],
            ]),
          ),
          const SizedBox(height: 18),

          // ── What it's made of ──
          const SectionLabel('Made of'),
          AerisCard(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(children: [
              _Row(
                icon: Icons.account_balance_outlined,
                label: 'Bank & cash',
                sub: w.cashExact
                    ? 'From your account balances'
                    : 'Estimated from your activity',
                value: w.cash,
                onTap: () => Navigator.pushNamed(context, AppRoutes.accounts),
              ),
              const Divider(height: 1, indent: 62),
              _Row(
                icon: Icons.flag_outlined,
                label: 'Saved in goals',
                sub: 'Money set aside for goals',
                value: w.goals,
                onTap: () => Navigator.pushNamed(context, AppRoutes.goals),
              ),
              const Divider(height: 1, indent: 62),
              _Row(
                icon: Icons.call_received_rounded,
                label: 'Owed to you',
                sub: 'Money friends will pay back',
                value: w.owedToYou,
                onTap: () => Navigator.pushNamed(context, AppRoutes.loans),
              ),
              const Divider(height: 1, indent: 62),
              _Row(
                icon: Icons.call_made_rounded,
                label: 'You owe',
                sub: 'Borrowed, still to repay',
                value: -w.youOwe,
                onTap: () => Navigator.pushNamed(context, AppRoutes.loans),
              ),
            ]),
          ),
          const SizedBox(height: 18),

          // ── Trend ──
          if (trend.length > 1) ...[
            const SectionLabel('Bank & cash over 12 months'),
            AerisCard(
              padding: const EdgeInsets.fromLTRB(8, 14, 14, 8),
              child: SizedBox(
                height: 200,
                child: SfCartesianChart(
                  plotAreaBorderWidth: 0,
                  margin: EdgeInsets.zero,
                  primaryXAxis: CategoryAxis(
                    majorGridLines: const MajorGridLines(width: 0),
                    axisLine: const AxisLine(width: 0),
                    labelStyle: TextStyle(fontSize: 10, color: muted),
                    interval: 2,
                  ),
                  primaryYAxis: NumericAxis(
                    isVisible: !hidden,
                    majorGridLines: MajorGridLines(
                        width: 0.6, color: AerisColors.line(context)),
                    axisLine: const AxisLine(width: 0),
                    labelStyle: TextStyle(fontSize: 10, color: muted),
                    numberFormat: null,
                    axisLabelFormatter: (a) => ChartAxisLabel(
                        formatRupees(a.value, compact: true),
                        TextStyle(fontSize: 10, color: muted)),
                  ),
                  trackballBehavior: TrackballBehavior(
                    enable: !hidden,
                    activationMode: ActivationMode.singleTap,
                    tooltipSettings: const InteractiveTooltip(format: 'point.y'),
                  ),
                  series: <CartesianSeries<(DateTime, double), String>>[
                    AreaSeries<(DateTime, double), String>(
                      dataSource: trend,
                      xValueMapper: (p, _) => _months[p.$1.month],
                      yValueMapper: (p, _) => p.$2,
                      borderColor: accent,
                      borderWidth: 2.5,
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          accent.withValues(alpha: 0.35),
                          accent.withValues(alpha: 0.0),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
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
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
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
          const SizedBox(width: 12),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w600)),
              Text(sub,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 12, color: AerisColors.muted(context))),
            ]),
          ),
          const SizedBox(width: 8),
          Text(
            '${value < 0 ? '−' : ''}${formatRupees(value.abs())}',
            style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: value < 0
                    ? AerisColors.danger(context)
                    : Theme.of(context).colorScheme.onSurface),
          ),
        ]),
      ),
    );
  }
}
