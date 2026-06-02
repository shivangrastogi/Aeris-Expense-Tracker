import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/analytics_provider.dart';

/// A compact period picker that drives [analyticsRangeProvider] for both the
/// Home and Analytics dashboards. Offers presets + a custom date range.
class RangeSelector extends ConsumerWidget {
  const RangeSelector({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final range = ref.watch(analyticsRangeProvider);
    return ActionChip(
      avatar: const Icon(Icons.calendar_month, size: 18),
      label: Text(range.label),
      onPressed: () => _choose(context, ref),
    );
  }

  Future<void> _choose(BuildContext context, WidgetRef ref) async {
    final notifier = ref.read(analyticsRangeProvider.notifier);
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
                title: Text('Show data for',
                    style: TextStyle(fontWeight: FontWeight.w700))),
            for (final opt in <(String, AnalyticsRange Function())>[
              ('This month', AnalyticsRange.thisMonth),
              ('Last 7 days', () => AnalyticsRange.lastDays(7, 'Last 7 days')),
              ('Last 30 days', () => AnalyticsRange.lastDays(30, 'Last 30 days')),
              ('Last 90 days', () => AnalyticsRange.lastDays(90, 'Last 90 days')),
              ('This year', AnalyticsRange.thisYear),
            ])
              ListTile(
                title: Text(opt.$1),
                onTap: () {
                  notifier.state = opt.$2();
                  Navigator.pop(sheet);
                },
              ),
            ListTile(
              leading: const Icon(Icons.date_range),
              title: const Text('Custom range…'),
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
          ],
        ),
      ),
    );
  }
}
