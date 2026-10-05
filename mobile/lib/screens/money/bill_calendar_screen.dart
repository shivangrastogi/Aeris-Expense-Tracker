import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/routes.dart';
import '../../core/theme.dart';
import '../../models/category.dart';
import '../../providers/money_providers.dart';
import '../../providers/privacy_provider.dart';
import '../../services/reminder_scheduler.dart';
import '../../utils/formatters.dart';

/// Month view of every bill — saved subscriptions and monthly payments AERIS
/// spotted in your history — with what's due next. Reminders fire the day
/// before each (Settings → Smart reminders).
class BillCalendarScreen extends ConsumerStatefulWidget {
  const BillCalendarScreen({super.key});

  @override
  ConsumerState<BillCalendarScreen> createState() => _BillCalendarState();
}

class _BillCalendarState extends ConsumerState<BillCalendarScreen> {
  late DateTime _month;
  int? _selectedDay;

  static const _monthNames = [
    '', 'January', 'February', 'March', 'April', 'May', 'June', 'July',
    'August', 'September', 'October', 'November', 'December'
  ];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = DateTime(now.year, now.month);
  }

  void _shift(int by) => setState(() {
        _month = DateTime(_month.year, _month.month + by);
        _selectedDay = null;
      });

  @override
  Widget build(BuildContext context) {
    ref.watch(amountHiddenProvider);
    final bills = ref.watch(billsProvider);
    final now = DateTime.now();
    final lastDay = DateTime(_month.year, _month.month + 1, 0).day;
    // day → bills due that day in the shown month
    final byDay = <int, List<Bill>>{};
    for (final b in bills) {
      byDay.putIfAbsent(b.day.clamp(1, lastDay), () => []).add(b);
    }
    final monthTotal = bills.fold<double>(0, (s, b) => s + b.amount);
    final upcoming = [...bills]
      ..sort((a, b) => a.nextDue(now).compareTo(b.nextDue(now)));
    final shown = _selectedDay == null ? null : byDay[_selectedDay] ?? const [];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Bill calendar'),
        actions: [
          IconButton(
            tooltip: 'Subscriptions',
            icon: const Icon(Icons.edit_calendar_outlined),
            onPressed: () =>
                Navigator.pushNamed(context, AppRoutes.subscriptions),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          AerisCard(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 14),
            child: Column(children: [
              Row(children: [
                IconButton(
                    tooltip: 'Previous month',
                    onPressed: () => _shift(-1),
                    icon: const Icon(Icons.chevron_left_rounded)),
                Expanded(
                  child: Column(children: [
                    Text('${_monthNames[_month.month]} ${_month.year}',
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w800)),
                    Text(
                        '${bills.length} bills · ${formatRupees(monthTotal)} / month',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: AerisColors.muted(context))),
                  ]),
                ),
                IconButton(
                    tooltip: 'Next month',
                    onPressed: () => _shift(1),
                    icon: const Icon(Icons.chevron_right_rounded)),
              ]),
              const SizedBox(height: 8),
              _Grid(
                month: _month,
                byDay: byDay,
                selected: _selectedDay,
                onTap: (d) =>
                    setState(() => _selectedDay = _selectedDay == d ? null : d),
              ),
            ]),
          ),
          const SizedBox(height: 18),
          if (bills.isEmpty)
            AerisCard(
              child: Column(children: [
                Icon(Icons.event_available_outlined,
                    size: 40, color: AerisColors.muted(context)),
                const SizedBox(height: 8),
                const Text('No bills yet',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(
                  'Add subscriptions like rent, Netflix or your phone plan — '
                  'AERIS also spots monthly payments from your history.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 13, color: AerisColors.muted(context)),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () =>
                      Navigator.pushNamed(context, AppRoutes.subscriptions),
                  child: const Text('Add a subscription'),
                ),
              ]),
            )
          else ...[
            SectionLabel(shown != null
                ? 'Due on ${_selectedDay!} ${_monthNames[_month.month].substring(0, 3)}'
                : 'Coming up'),
            AerisCard(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(children: [
                if (shown != null && shown.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text('Nothing due that day.',
                        style: TextStyle(color: AerisColors.muted(context))),
                  ),
                for (final b in shown ?? upcoming) _BillRow(bill: b, now: now),
              ]),
            ),
            const SizedBox(height: 10),
            Row(children: [
              Icon(Icons.notifications_active_outlined,
                  size: 14, color: AerisColors.muted(context)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Reminders arrive the day before each bill when Smart '
                  'reminders are on in Settings.',
                  style: TextStyle(
                      fontSize: 12, color: AerisColors.muted(context)),
                ),
              ),
            ]),
          ],
        ],
      ),
    );
  }
}

class _Grid extends StatelessWidget {
  final DateTime month;
  final Map<int, List<Bill>> byDay;
  final int? selected;
  final ValueChanged<int> onTap;
  const _Grid(
      {required this.month,
      required this.byDay,
      required this.selected,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final lastDay = DateTime(month.year, month.month + 1, 0).day;
    final lead = DateTime(month.year, month.month, 1).weekday - 1; // Mon=0
    final cells = lead + lastDay;
    final rows = (cells / 7).ceil();
    final accent = AerisColors.accent(context);
    final muted = AerisColors.muted(context);

    return Column(children: [
      Row(children: [
        for (final d in const ['M', 'T', 'W', 'T', 'F', 'S', 'S'])
          Expanded(
            child: Center(
              child: Text(d,
                  style: hudLabel(context, size: 10.5)),
            ),
          ),
      ]),
      const SizedBox(height: 6),
      for (var r = 0; r < rows; r++)
        Row(children: [
          for (var c = 0; c < 7; c++)
            Expanded(
              child: Builder(builder: (context) {
                final day = r * 7 + c - lead + 1;
                if (day < 1 || day > lastDay) return const SizedBox(height: 44);
                final due = byDay[day] ?? const [];
                final isToday = now.year == month.year &&
                    now.month == month.month &&
                    now.day == day;
                final isSel = selected == day;
                return Semantics(
                  button: true,
                  label: '$day${due.isEmpty ? '' : ', ${due.length} bill due'}',
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => onTap(day),
                    child: Container(
                      height: 44,
                      margin: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: isSel
                            ? accent
                            : due.isNotEmpty
                                ? AerisColors.accentSoft(context)
                                : null,
                        borderRadius: BorderRadius.circular(12),
                        border: isToday && !isSel
                            ? Border.all(color: accent, width: 1.5)
                            : null,
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text('$day',
                              style: TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: due.isNotEmpty || isToday
                                      ? FontWeight.w800
                                      : FontWeight.w500,
                                  color: isSel
                                      ? AerisColors.onAccent(context)
                                      : due.isEmpty
                                          ? muted
                                          : Theme.of(context)
                                              .colorScheme
                                              .onSurface)),
                          if (due.isNotEmpty)
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                for (final b in due.take(3))
                                  Container(
                                    width: 5,
                                    height: 5,
                                    margin: const EdgeInsets.only(
                                        top: 3, left: 1, right: 1),
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: isSel
                                          ? AerisColors.onAccent(context)
                                          : Categories.byId(b.categoryId).color,
                                    ),
                                  ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ),
        ]),
    ]);
  }
}

class _BillRow extends StatelessWidget {
  final Bill bill;
  final DateTime now;
  const _BillRow({required this.bill, required this.now});

  @override
  Widget build(BuildContext context) {
    final cat = Categories.byId(bill.categoryId);
    final due = bill.nextDue(now);
    final days = DateTime(due.year, due.month, due.day)
        .difference(DateTime(now.year, now.month, now.day))
        .inDays;
    final when = days == 0
        ? 'Due today'
        : days == 1
            ? 'Due tomorrow'
            : 'In $days days · ${due.day}/${due.month}';
    final soon = days <= 1;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: cat.color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(cat.icon, size: 20, color: cat.color),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(bill.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            Text(bill.detected ? '$when · spotted from history' : when,
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: soon ? FontWeight.w700 : FontWeight.w500,
                    color: soon ? AerisColors.warning : AerisColors.muted(context))),
          ]),
        ),
        Text(formatRupees(bill.amount),
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
      ]),
    );
  }
}
