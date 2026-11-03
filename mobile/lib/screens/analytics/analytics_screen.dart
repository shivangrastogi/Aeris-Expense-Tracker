import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:syncfusion_flutter_charts/charts.dart';

import '../../core/routes.dart';
import '../../core/theme.dart';
import '../../models/budget.dart';
import '../../models/category.dart';
import '../../models/insight.dart';
import '../../providers/analytics_provider.dart';
import '../../providers/insights_provider.dart';
import '../../providers/privacy_provider.dart';
import '../../providers/income_lock_provider.dart';
import '../../providers/money_providers.dart';
import '../../utils/formatters.dart';
import '../../utils/motion.dart';
import '../../widgets/income_text.dart';
import '../../widgets/ds.dart';
import '../gamification/future_self_screen.dart';

part 'analytics_charts.dart';
part 'analytics_ai.dart';
// ─── Shell ─────────────────────────────────────────────────────────────────
//
// Insights: large title with the range picker and Ask Aeris, the Charts /
// Tips / Future segmented control, then a row of shortcuts into the money
// tools (budgets, goals, net worth, report card, wrapped).

class AnalyticsScreen extends ConsumerStatefulWidget {
  const AnalyticsScreen({super.key});
  @override
  ConsumerState<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends ConsumerState<AnalyticsScreen> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    ref.watch(amountHiddenProvider);
    return Scaffold(
      body: SafeArea(
        bottom: false,
        // Large title → slim bar once the tab scrolls (reset per tab).
        child: CollapseOnScroll(
          key: ValueKey(_tab),
          builder: (context, collapsed) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              CollapsingHeader(
                title: 'Insights',
                collapsed: collapsed,
                largeSize: 24,
                actions: [
                  const _RangePillBtn(),
                  const SizedBox(width: 8),
                  RoundIconButton(
                    icon: Ph.sparkle,
                    tooltip: 'Ask Aeris',
                    onTap: () =>
                        Navigator.pushNamed(context, AppRoutes.assistant),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: DsSegmented(
                  labels: const ['Charts', 'Tips', 'Future'],
                  index: _tab,
                  height: 44,
                  onChanged: (i) => setState(() => _tab = i),
                ),
              ),
              Expanded(
                child: IndexedStack(
                  index: _tab,
                  children: const [
                    _ChartsTab(),
                    _AITab(),
                    FutureSelfScreen(embed: true),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Shortcuts into the money tools ────────────────────────────────────────

class _Shortcuts extends StatelessWidget {
  const _Shortcuts();

  @override
  Widget build(BuildContext context) {
    final tk = context.tk;
    final items = <(IconData, String, String)>[
      (Ph.target, 'Budgets', AppRoutes.budgets),
      (Ph.flagPennant, 'Goals', AppRoutes.goals),
      (Ph.scales, 'Net worth', AppRoutes.netWorth),
      (Ph.presentationChart, 'Report card', AppRoutes.reportCard),
      (Ph.confetti, 'Wrapped', AppRoutes.wrapped),
    ];
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final (icon, label, route) = items[i];
          return Material(
            color: tk.surface,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(Rad.chip),
                side: tk.isDark ? BorderSide(color: tk.hair) : BorderSide.none),
            child: InkWell(
              borderRadius: BorderRadius.circular(Rad.chip),
              onTap: () => Navigator.pushNamed(context, route),
              child: Container(
                padding: const EdgeInsets.fromLTRB(10, 0, 14, 0),
                decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(Rad.chip),
                    boxShadow: tk.shadow),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(icon, size: 16, color: tk.acc),
                  const SizedBox(width: 6),
                  Text(label,
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: tk.t1)),
                ]),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ─── Shared card shell ─────────────────────────────────────────────────────

/// A design card: radius 20, padding 16, title 18/600 with an optional note.
class _InsightCard extends StatelessWidget {
  final String title;
  final String? note;
  final Widget child;
  static const padding = EdgeInsets.all(16);
  const _InsightCard({
    required this.title,
    required this.child,
    this.note,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: AerisColors.cardDecoration(context),
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                child:
                    Text(title, style: Ts.title.copyWith(color: context.tk.t1)),
              ),
              if (note != null)
                Text(note!,
                    style: TextStyle(fontSize: 12, color: context.tk.t2)),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}
