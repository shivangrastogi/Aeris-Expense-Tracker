import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/theme.dart';
import '../../providers/money_providers.dart';
import '../../providers/privacy_provider.dart';
import '../../services/money_insights.dart';
import '../../utils/formatters.dart';
import '../../widgets/aeris_toast.dart';
import '../../widgets/ds.dart';

/// A grade for the month — budget, savings and habits — that can be shared as
/// an image. Early in a month it shows last month's final card; later it
/// shows this month so far.
class ReportCardScreen extends ConsumerStatefulWidget {
  final DateTime? month;
  const ReportCardScreen({super.key, this.month});

  @override
  ConsumerState<ReportCardScreen> createState() => _ReportCardState();
}

class _ReportCardState extends ConsumerState<ReportCardScreen> {
  final _cardKey = GlobalKey();
  late DateTime _month;
  bool _sharing = false;

  static const _names = [
    '', 'January', 'February', 'March', 'April', 'May', 'June', 'July',
    'August', 'September', 'October', 'November', 'December'
  ];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = widget.month ??
        (now.day <= 7
            ? DateTime(now.year, now.month - 1)
            : DateTime(now.year, now.month));
  }

  bool get _isCurrent {
    final now = DateTime.now();
    return _month.year == now.year && _month.month == now.month;
  }

  Future<void> _share(ReportCard c) async {
    setState(() => _sharing = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final boundary = _cardKey.currentContext!.findRenderObject()
          as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 3);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final dir = await getTemporaryDirectory();
      final f = File(
          '${dir.path}/aeris-report-${_month.year}-${_month.month}.png');
      await f.writeAsBytes(bytes!.buffer.asUint8List());
      await Share.shareXFiles([XFile(f.path)],
          text:
              'My ${_names[_month.month]} money report card from AERIS: ${c.grade}');
    } catch (e) {
      messenger.showToast(SnackBar(content: Text('Could not share: $e')));
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(amountHiddenProvider);
    final tk = context.tk;
    final c = ref.watch(reportCardProvider(_month));
    return Scaffold(
      appBar: AppBar(
        title: Text('${_names[_month.month]} report card'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: TonalButton(_sharing ? 'Preparing…' : 'Share',
                icon: Ph.shareNetwork,
                height: 40,
                onPressed: _sharing ? null : () => _share(c)),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
        children: [
          Row(children: [
            IconButton(
              tooltip: 'Previous month',
              onPressed: () => setState(
                  () => _month = DateTime(_month.year, _month.month - 1)),
              icon: const Icon(Ph.caretLeft),
            ),
            Expanded(
              child: Text(
                '${_names[_month.month]} ${_month.year}${c.inProgress ? ' · so far' : ''}',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600, color: tk.t2),
              ),
            ),
            IconButton(
              tooltip: 'Next month',
              onPressed: _isCurrent
                  ? null
                  : () => setState(
                      () => _month = DateTime(_month.year, _month.month + 1)),
              icon: const Icon(Ph.caretRight),
            ),
          ]),
          RepaintBoundary(
            key: _cardKey,
            // The shared image carries the screen's ground behind it.
            child: ColoredBox(
              color: tk.bg,
              child: _Card(card: c, month: _month),
            ),
          ),
          const SizedBox(height: 12),
          if (_wins(c).isNotEmpty) ...[
            _ListCard(
                title: 'What went well',
                icon: PhBold.check,
                color: tk.ok,
                lines: _wins(c)),
            const SizedBox(height: 12),
          ],
          _ListCard(
              title: 'Try next month',
              icon: PhBold.arrowRight,
              color: tk.acc,
              lines: _tips(c)),
        ],
      ),
    );
  }

  /// Only what the month's own numbers support — nothing invented.
  List<String> _wins(ReportCard c) {
    final rate = c.savingsRate;
    return [
      if (rate != null && rate > 0)
        'You kept ${(rate * 100).round()}% of your income',
      if (c.budget > 0 && c.spent <= c.budget)
        'Stayed within your ${formatRupees(c.budget, compact: true)} budget',
      if (c.noSpendDays >= 4) '${c.noSpendDays} no-spend days',
      if (c.trackedDays >= 15) 'Tracked spending on ${c.trackedDays} days',
    ];
  }

  List<String> _tips(ReportCard c) {
    final tips = <String>[];
    if (c.budget <= 0) {
      tips.add('Set a monthly budget — it\'s worth 40 points.');
    } else if (c.budgetScore < 40) {
      tips.add('Stay under 90% of your budget for full budget points.');
    }
    if (c.income <= 0) {
      tips.add('Add your income (Me → profile) so savings can be graded.');
    } else if (c.savingsScore < 40) {
      tips.add('Keep 30% of your income to max out savings points.');
    }
    if (c.noSpendDays < 4) {
      tips.add('Aim for 4 no-spend days in a month.');
    }
    if (c.trackedDays < 15) {
      tips.add('Log spending on at least 15 days — tracking is a habit.');
    }
    if (tips.isEmpty) tips.add('Perfect month. Keep doing exactly this.');
    return tips;
  }
}


/// The shareable card: the grade on a ring, a one-line read of the month and
/// the three scores as rising lines.
class _Card extends StatelessWidget {
  final ReportCard card;
  final DateTime month;
  const _Card({required this.card, required this.month});

  @override
  Widget build(BuildContext context) {
    final tk = context.tk;
    final c = card;
    final rate = c.savingsRate;
    final summary = [
      'Spent ${formatRupees(c.spent, compact: true)}',
      if (rate != null) 'saved ${(rate * 100).round()}% of income',
      '${c.noSpendDays} no-spend days',
    ].join(' · ');
    return Column(children: [
      const SizedBox(height: 8),
      CatRing(
        value: c.score / 100,
        color: tk.acc,
        size: 152,
        stroke: 4,
        center: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(c.grade,
              style: TextStyle(
                  fontSize: 56,
                  height: 1,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -1,
                  color: tk.t1)),
          const SizedBox(height: 6),
          Text('${c.score} / 100',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  fontFeatures: const [FontFeature.tabularFigures()],
                  color: tk.t2)),
        ]),
      ),
      const SizedBox(height: 16),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Text(summary,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 15, height: 22 / 15, color: tk.t2)),
      ),
      const SizedBox(height: 16),
      AerisCard(
        child: Column(children: [
          _Bar(
              label: 'Budget',
              score: c.budgetScore,
              max: 40,
              note: c.budget <= 0
                  ? 'No monthly budget set.'
                  : '${formatRupees(c.spent, compact: true)} of '
                      '${formatRupees(c.budget, compact: true)}.'),
          _Bar(
              label: 'Savings',
              score: c.savingsScore,
              max: 40,
              note: rate == null
                  ? 'Add your income to grade savings.'
                  : 'You kept ${(rate * 100).round()}% of income. The target is 30%.'),
          _Bar(
              label: 'Habits',
              score: c.habitScore,
              max: 20,
              note: '${c.trackedDays} days tracked · ${c.noSpendDays} no-spend days.'),
        ]),
      ),
    ]);
  }
}

class _Bar extends StatelessWidget {
  final String label;
  final int score;
  final int max;
  final String note;
  const _Bar(
      {required this.label,
      required this.score,
      required this.max,
      required this.note});

  @override
  Widget build(BuildContext context) {
    final tk = context.tk;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
              child: Text(label, style: Ts.rowTitle.copyWith(color: tk.t1))),
          Text.rich(
            TextSpan(children: [
              TextSpan(
                  text: '$score',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              TextSpan(text: '/$max', style: TextStyle(color: tk.t2)),
            ]),
            style: TextStyle(
                fontSize: 15,
                fontFeatures: const [FontFeature.tabularFigures()],
                color: tk.t1),
          ),
        ]),
        const SizedBox(height: 6),
        RisingProgress(value: max == 0 ? 0 : score / max, stroke: 3, dot: 4),
        const SizedBox(height: 6),
        Text(note, style: TextStyle(fontSize: 12, color: tk.t2)),
      ]),
    );
  }
}

/// "What went well" / "Try next month": an overline and short lines.
class _ListCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  final List<String> lines;
  const _ListCard(
      {required this.title,
      required this.icon,
      required this.color,
      required this.lines});

  @override
  Widget build(BuildContext context) {
    final tk = context.tk;
    return AerisCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Overline(title),
        const SizedBox(height: 6),
        for (final l in lines)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(icon, size: 16, color: color),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(l,
                    style: TextStyle(
                        fontSize: 15, height: 22 / 15, color: tk.t1)),
              ),
            ]),
          ),
      ]),
    );
  }
}
