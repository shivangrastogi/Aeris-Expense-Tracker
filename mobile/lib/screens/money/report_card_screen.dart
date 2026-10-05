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
    final c = ref.watch(reportCardProvider(_month));
    return Scaffold(
      appBar: AppBar(title: const Text('Report card')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          Row(children: [
            IconButton(
              tooltip: 'Previous month',
              onPressed: () => setState(
                  () => _month = DateTime(_month.year, _month.month - 1)),
              icon: const Icon(Icons.chevron_left_rounded),
            ),
            Expanded(
              child: Text(
                '${_names[_month.month]} ${_month.year}${c.inProgress ? ' · so far' : ''}',
                textAlign: TextAlign.center,
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
            ),
            IconButton(
              tooltip: 'Next month',
              onPressed: _isCurrent
                  ? null
                  : () => setState(
                      () => _month = DateTime(_month.year, _month.month + 1)),
              icon: const Icon(Icons.chevron_right_rounded),
            ),
          ]),
          const SizedBox(height: 8),
          RepaintBoundary(key: _cardKey, child: _Card(card: c, month: _month)),
          const SizedBox(height: 18),
          const SectionLabel('How to score higher'),
          AerisCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final tip in _tips(c))
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.arrow_right_rounded,
                              color: AerisColors.accent(context)),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(tip,
                                style: const TextStyle(
                                    fontSize: 13.5, height: 1.4)),
                          ),
                        ]),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: _sharing ? null : () => _share(c),
            icon: const Icon(Icons.ios_share_rounded),
            label: Text(_sharing ? 'Preparing…' : 'Share as image'),
          ),
        ],
      ),
    );
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

/// The shareable card itself — self-contained HUD panel.
class _Card extends StatelessWidget {
  final ReportCard card;
  final DateTime month;
  const _Card({required this.card, required this.month});

  Color _gradeColor(String g) => switch (g[0]) {
        'A' => AerisColors.mint,
        'B' => AerisColors.arc,
        'C' => AerisColors.amber,
        _ => AerisColors.coral,
      };

  @override
  Widget build(BuildContext context) {
    final c = card;
    final gc = _gradeColor(c.grade);
    const dim = Color(0xB3EAF2F7);
    final rate = c.savingsRate;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
      decoration: BoxDecoration(
        gradient: AerisColors.inkGradient,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: gc.withValues(alpha: 0.35)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('AERIS · REPORT CARD', style: hudLabel(context, color: dim)),
          const Spacer(),
          Text(
              '${const ['', 'JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', 'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'][month.month]} ${month.year}',
              style: hudLabel(context, color: dim)),
        ]),
        const SizedBox(height: 16),
        Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          Container(
            width: 104,
            height: 104,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: gc, width: 3),
              boxShadow: [
                BoxShadow(color: gc.withValues(alpha: 0.45), blurRadius: 24),
              ],
            ),
            child: Text(c.grade,
                style: TextStyle(
                    color: gc,
                    fontSize: 44,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -1)),
          ),
          const SizedBox(width: 18),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${c.score}/100',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(
                  'Spent ${formatRupees(c.spent, compact: true)}'
                  '${rate == null ? '' : ' · saved ${(rate * 100).round()}%'}',
                  style: const TextStyle(
                      color: dim, fontSize: 13, fontWeight: FontWeight.w600)),
              Text(
                  '${c.noSpendDays} no-spend days · ${c.trackedDays} days tracked',
                  style: const TextStyle(
                      color: dim, fontSize: 13, fontWeight: FontWeight.w600)),
            ]),
          ),
        ]),
        const SizedBox(height: 18),
        _Bar(label: 'BUDGET', score: c.budgetScore, max: 40, color: AerisColors.arc),
        _Bar(label: 'SAVINGS', score: c.savingsScore, max: 40, color: AerisColors.mint),
        _Bar(label: 'HABITS', score: c.habitScore, max: 20, color: AerisColors.violet),
      ]),
    );
  }
}

class _Bar extends StatelessWidget {
  final String label;
  final int score;
  final int max;
  final Color color;
  const _Bar(
      {required this.label,
      required this.score,
      required this.max,
      required this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(children: [
        SizedBox(
            width: 74,
            child: Text(label,
                style: hudLabel(context, color: const Color(0xB3EAF2F7), size: 10))),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: score / max,
              minHeight: 7,
              color: color,
              backgroundColor: Colors.white.withValues(alpha: 0.08),
            ),
          ),
        ),
        SizedBox(
          width: 48,
          child: Text('$score/$max',
              textAlign: TextAlign.end,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700)),
        ),
      ]),
    );
  }
}
