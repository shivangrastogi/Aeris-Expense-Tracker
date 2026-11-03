import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme.dart';
import '../providers/analytics_provider.dart';
import 'ds.dart';

/// A compact period picker that drives [analyticsRangeProvider] for both the
/// Home and Analytics dashboards. Offers presets + a custom date range.
class RangeSelector extends ConsumerWidget {
  const RangeSelector({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tk = context.tk;
    final range = ref.watch(analyticsRangeProvider);
    return Semantics(
      button: true,
      label: 'Change period, currently ${range.label}',
      excludeSemantics: true,
      child: InkWell(
        onTap: () => _choose(context, ref),
        borderRadius: BorderRadius.circular(Rad.chip),
        child: Container(
          height: 36,
          padding: const EdgeInsets.fromLTRB(10, 0, 10, 0),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Rad.chip),
            border: Border.all(color: tk.hair2),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Ph.calendarBlank, size: 16, color: tk.t2),
            const SizedBox(width: 6),
            Text(range.label,
                style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600, color: tk.t1)),
            const SizedBox(width: 4),
            Icon(PhBold.caretDown, size: 12, color: tk.t2),
          ]),
        ),
      ),
    );
  }

  Future<void> _choose(BuildContext context, WidgetRef ref) async {
    final notifier = ref.read(analyticsRangeProvider.notifier);
    final current = ref.read(analyticsRangeProvider).label;
    await showDsSheet<void>(
      context,
      title: 'Show data for',
      builder: (sheet) {
        final tk = sheet.tk;
        return ListGroup(inset: 16, children: [
          for (final opt in <(String, AnalyticsRange Function())>[
            ('This month', AnalyticsRange.thisMonth),
            ('Last 7 days', () => AnalyticsRange.lastDays(7, 'Last 7 days')),
            ('Last 30 days', () => AnalyticsRange.lastDays(30, 'Last 30 days')),
            ('Last 90 days', () => AnalyticsRange.lastDays(90, 'Last 90 days')),
            ('This year', AnalyticsRange.thisYear),
          ])
            DsRow(
              minHeight: 52,
              title: opt.$1,
              trailing: opt.$1 == current
                  ? Icon(PhBold.check, size: 18, color: tk.acc)
                  : null,
              onTap: () {
                notifier.state = opt.$2();
                Navigator.pop(sheet);
              },
            ),
          DsRow(
            minHeight: 52,
            leading: Icon(Ph.calendarBlank, size: 20, color: tk.t2),
            title: 'Custom range…',
            onTap: () async {
              Navigator.pop(sheet);
              final now = DateTime.now();
              final picked = await showDateRangePicker(
                context: context,
                firstDate: DateTime(now.year - 5),
                lastDate: now,
              );
              if (picked != null) {
                notifier.state = AnalyticsRange.custom(picked);
              }
            },
          ),
        ]);
      },
    );
  }
}
