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
import '../../providers/money_providers.dart';
import '../../utils/formatters.dart';
import '../../utils/motion.dart';
import '../../widgets/mascot/aeris_mascot.dart';
import '../gamification/future_self_screen.dart';

part 'analytics_charts.dart';
part 'analytics_ai.dart';
// ─── Shell ─────────────────────────────────────────────────────────────────

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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Insights',
                      style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5)),
                  const SizedBox(height: 10),
                  _SegPill(
                      value: _tab, onChange: (i) => setState(() => _tab = i)),
                ],
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
    );
  }
}

// ─── Segmented pill ────────────────────────────────────────────────────────

class _SegPill extends StatelessWidget {
  final int value;
  final ValueChanged<int> onChange;
  const _SegPill({required this.value, required this.onChange});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: 42,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _pill(context, 0, Icons.bar_chart_rounded, 'Charts'),
        _pill(context, 1, Icons.psychology_outlined, 'AI'),
        _pill(context, 2, Icons.savings_outlined, 'Future'),
      ]),
    );
  }

  Widget _pill(BuildContext context, int idx, IconData icon, String label) {
    final active = value == idx;
    final scheme = Theme.of(context).colorScheme;
    final fg = active ? scheme.onSurface : scheme.onSurfaceVariant;
    return Expanded(
      child: Semantics(
        button: true,
        selected: active,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => onChange(idx),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            alignment: Alignment.center,
            decoration: active
                ? AerisColors.cardDecoration(context, radius: 11)
                : const BoxDecoration(),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon,
                    size: 16, color: active ? AerisColors.accent(context) : fg),
                const SizedBox(width: 5),
                Text(label,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                        color: fg)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
