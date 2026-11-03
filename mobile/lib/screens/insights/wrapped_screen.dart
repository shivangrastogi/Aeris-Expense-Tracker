import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/theme.dart';
import '../../models/category.dart';
import '../../models/transaction.dart';
import '../../providers/auth_provider.dart';
import '../../providers/transactions_provider.dart';
import '../../utils/formatters.dart';
import '../../utils/motion.dart';
import '../../widgets/ds.dart';

/// "Your month in money" — a calm, story-style recap computed entirely
/// on-device from this month's transactions. Tap the right side to go
/// forward, the left side to go back; slides also advance on their own.
class WrappedScreen extends ConsumerStatefulWidget {
  const WrappedScreen({super.key});
  @override
  ConsumerState<WrappedScreen> createState() => _WrappedScreenState();
}

class _WrappedScreenState extends ConsumerState<WrappedScreen> {
  final _controller = PageController();
  int _page = 0;
  int _count = 1;
  Timer? _auto;

  static const _months = [
    '', 'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _auto?.cancel();
    if (!reduceMotion(context)) {
      _auto = Timer.periodic(const Duration(seconds: 6), (_) => _go(1));
    }
  }

  @override
  void dispose() {
    _auto?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _go(int delta) {
    final next = (_page + delta).clamp(0, _count - 1);
    if (next == _page || !_controller.hasClients) return;
    _controller.animateToPage(next,
        duration: reduceMotion(context) ? const Duration(milliseconds: 1) : Mo.enter,
        curve: Mo.curve);
  }

  @override
  Widget build(BuildContext context) {
    final tk = context.tk;
    final txns =
        ref.watch(transactionsStreamProvider).asData?.value ?? const <Transaction>[];
    final profile = ref.watch(userProfileProvider).asData?.value;
    final first = (profile?.displayName ?? '').trim().split(RegExp(r'\s+')).first;
    final now = DateTime.now();
    final stats = _compute(txns, now);
    final monthName = _months[now.month];

    final cards = <Widget>[
      _slide(
        sub: '${first.isEmpty ? 'Your' : '$first, your'} month in money',
        big: '$monthName in money.',
        visual: CustomPaint(
            size: const Size(180, 50), painter: _Spark(tk.acc)),
        caption: 'Tap to begin',
      ),
    ];

    if (stats.txnCount == 0) {
      cards.add(_slide(
        sub: 'Nothing here yet',
        big: 'No activity yet this month.',
        caption: 'Add a few transactions and check back.',
      ));
    } else {
      cards.add(_slide(
        sub: 'This month you spent',
        big: formatRupees(stats.spent),
        caption: 'across ${stats.txnCount} transaction'
            '${stats.txnCount == 1 ? '' : 's'}',
      ));

      if (stats.topCat != null) {
        final c = Categories.byId(stats.topCat!);
        cards.add(_slide(
          visual: CatTile.of(c, size: 64),
          sub: 'Your top category',
          big: '${c.label}.',
          // Refunds lower total spend but not categories, so cap it.
          caption: '${formatRupees(stats.topCatAmount)} · '
              '${(stats.spent <= 0 ? 100 : (stats.topCatAmount / stats.spent * 100).clamp(0, 100)).toStringAsFixed(0)}% of spend',
        ));
      }

      if (stats.topMerchant != null) {
        cards.add(_slide(
          visual: BadgeTile(icon: Ph.storefront, tint: tk.acc, size: 64),
          sub: 'You spent most at',
          big: '${stats.topMerchant!}.',
          caption: formatRupees(stats.topMerchantAmount),
        ));
      }

      if (stats.biggestDay != null) {
        cards.add(_slide(
          visual: BadgeTile(icon: Ph.calendarBlank, tint: tk.warn, size: 64),
          sub: 'Your biggest day',
          big: '${stats.biggestDay!.day} $monthName.',
          caption: '${formatRupees(stats.biggestDayAmount)} in one day',
        ));
      }

      cards.add(_slide(
        sub: 'No-spend days',
        big: '${stats.noSpendDays} day${stats.noSpendDays == 1 ? '' : 's'}.',
        caption: stats.noSpendDays == 0
            ? 'You spent something every day so far.'
            : 'Days you didn\'t spend a rupee.',
      ));

      if (stats.momPct != null) {
        final down = stats.momPct! < 0;
        cards.add(_slide(
          visual: BadgeTile(
              icon: down ? PhBold.trendDown : PhBold.trendUp,
              tint: down ? tk.ok : tk.warn,
              size: 64),
          sub: 'Compared with last month',
          big: '${stats.momPct!.abs().toStringAsFixed(0)}% ${down ? 'less' : 'more'}.',
          caption: down ? 'Nice — spending is down.' : 'Spending crept up.',
        ));
      }

      // Final: net + share
      final saved = stats.income - stats.spent;
      cards.add(_slide(
        sub: saved >= 0 ? 'You saved' : 'You overspent',
        big: formatRupees(saved.abs()),
        bigColor: saved >= 0 ? tk.ok : tk.bad,
        action: FilledButton.icon(
          onPressed: () => _share(stats, monthName),
          icon: const Icon(Ph.shareNetwork, size: 18),
          label: const Text('Share my month'),
        ),
      ));
    }
    _count = cards.length;

    return Scaffold(
      backgroundColor: tk.bg,
      body: DecoratedBox(
        // A quiet accent-tinted ground, never a loud gradient.
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color.lerp(tk.bg, tk.acc, tk.isDark ? 0.14 : 0.16)!,
              Color.lerp(tk.bg, tk.acc, tk.isDark ? 0.03 : 0.06)!,
            ],
          ),
        ),
        child: SafeArea(
          child: Column(children: [
            // Story progress: one segment per slide.
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Row(children: [
                for (var i = 0; i < cards.length; i++)
                  Expanded(
                    child: Container(
                      height: 3,
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      decoration: BoxDecoration(
                        color: i <= _page
                            ? tk.t1
                            : tk.t1.withValues(alpha: 0.22),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 8, 0),
              child: Row(children: [
                CustomPaint(size: const Size(16, 16), painter: _Mark(tk.acc)),
                const SizedBox(width: 8),
                Expanded(child: Overline('$monthName wrapped', color: tk.t1)),
                IconButton(
                  tooltip: 'Close',
                  icon: Icon(Ph.x, color: tk.t1),
                  onPressed: () => Navigator.pop(context),
                ),
              ]),
            ),
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: (d) {
                  final w = MediaQuery.sizeOf(context).width;
                  _go(d.localPosition.dx > w / 3 ? 1 : -1);
                },
                child: PageView(
                  controller: _controller,
                  onPageChanged: (i) => setState(() => _page = i),
                  children: cards,
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _slide({
    required String sub,
    required String big,
    Widget? visual,
    String? caption,
    Color? bigColor,
    Widget? action,
  }) {
    final tk = context.tk;
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 0, 28, 48),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (visual != null) ...[visual, const SizedBox(height: 24)],
          Text(sub,
              style: TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w500, color: tk.t2)),
          const SizedBox(height: 12),
          Text(big,
              style: TextStyle(
                  fontSize: 44,
                  height: 52 / 44,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -1.2,
                  fontFeatures: const [FontFeature.tabularFigures()],
                  color: bigColor ?? tk.t1)),
          if (caption != null) ...[
            const SizedBox(height: 16),
            Text(caption,
                style: TextStyle(fontSize: 14, height: 20 / 14, color: tk.t2)),
          ],
          if (action != null) ...[const SizedBox(height: 28), action],
        ],
      ),
    );
  }

  void _share(_Stats s, String month) {
    final saved = s.income - s.spent;
    final lines = <String>[
      'My $month in money (via AERIS):',
      '• Spent ${formatRupees(s.spent)} across ${s.txnCount} transactions',
      if (s.topCat != null)
        '• Top category: ${Categories.byId(s.topCat!).label} (${formatRupees(s.topCatAmount)})',
      if (s.topMerchant != null)
        '• Most at: ${s.topMerchant} (${formatRupees(s.topMerchantAmount)})',
      '• ${s.noSpendDays} no-spend days',
      '• ${saved >= 0 ? 'Saved' : 'Overspent'} ${formatRupees(saved.abs())}',
    ];
    Share.share(lines.join('\n'));
  }

  _Stats _compute(List<Transaction> txns, DateTime now) {
    double spent = 0, income = 0;
    final byCat = <String, double>{};
    final byMerchant = <String, double>{};
    final byDay = <int, double>{};
    final spendDays = <int>{};
    double lastMonthSpent = 0;
    final lastM = DateTime(now.year, now.month - 1, 1);

    for (final t in txns) {
      if (t.isInternal) continue; // own-account transfer / share payback
      final ts = t.timestamp;
      if (ts.year == lastM.year && ts.month == lastM.month && t.isSpend) {
        lastMonthSpent += t.spendAmount;
      }
      if (ts.year != now.year || ts.month != now.month) continue;
      if (t.isRefund) {
        spent -= t.spendAmount; // money back, not income
        continue;
      }
      if (t.isIncoming) {
        income += t.spendAmount;
        continue;
      }
      spent += t.spendAmount;
      byCat[t.categoryId] = (byCat[t.categoryId] ?? 0) + t.spendAmount;
      final mName = t.merchant?.trim();
      if (mName != null && mName.isNotEmpty) {
        byMerchant[mName] = (byMerchant[mName] ?? 0) + t.spendAmount;
      }
      byDay[ts.day] = (byDay[ts.day] ?? 0) + t.spendAmount;
      spendDays.add(ts.day);
    }
    if (spent < 0) spent = 0;

    String? topCat;
    double topCatAmount = 0;
    byCat.forEach((k, v) {
      if (v > topCatAmount) {
        topCatAmount = v;
        topCat = k;
      }
    });
    String? topMerchant;
    double topMerchantAmount = 0;
    byMerchant.forEach((k, v) {
      if (v > topMerchantAmount) {
        topMerchantAmount = v;
        topMerchant = k;
      }
    });
    int? biggestDay;
    double biggestDayAmount = 0;
    byDay.forEach((k, v) {
      if (v > biggestDayAmount) {
        biggestDayAmount = v;
        biggestDay = k;
      }
    });

    final noSpend = (now.day - spendDays.length).clamp(0, 31);
    final momPct = lastMonthSpent > 0
        ? (spent - lastMonthSpent) / lastMonthSpent * 100
        : null;

    final count = txns
        .where((t) => t.timestamp.year == now.year && t.timestamp.month == now.month)
        .length;

    return _Stats(
      spent: spent,
      income: income,
      txnCount: count,
      topCat: topCat,
      topCatAmount: topCatAmount,
      topMerchant: topMerchant,
      topMerchantAmount: topMerchantAmount,
      biggestDay: biggestDay == null ? null : DateTime(now.year, now.month, biggestDay!),
      biggestDayAmount: biggestDayAmount,
      noSpendDays: noSpend,
      momPct: momPct,
    );
  }
}

class _Stats {
  final double spent;
  final double income;
  final int txnCount;
  final String? topCat;
  final double topCatAmount;
  final String? topMerchant;
  final double topMerchantAmount;
  final DateTime? biggestDay;
  final double biggestDayAmount;
  final int noSpendDays;
  final double? momPct;

  const _Stats({
    required this.spent,
    required this.income,
    required this.txnCount,
    required this.topCat,
    required this.topCatAmount,
    required this.topMerchant,
    required this.topMerchantAmount,
    required this.biggestDay,
    required this.biggestDayAmount,
    required this.noSpendDays,
    required this.momPct,
  });
}

/// The cover's little sparkline: a rising line that ends in a dot.
class _Spark extends CustomPainter {
  final Color color;
  _Spark(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final p = Paint()
      ..color = color
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(
        Path()
          ..moveTo(2, h - 4)
          ..lineTo(w * 0.35, h * 0.45)
          ..lineTo(w * 0.52, h * 0.65)
          ..lineTo(w - 12, h * 0.05 + 6),
        p);
    canvas.drawCircle(Offset(w - 4, 4), 4, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_Spark o) => o.color != color;
}

/// The AERIS mark: an "A" whose crossbar rises to a dot.
class _Mark extends CustomPainter {
  final Color color;
  _Mark(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 40;
    final p = Paint()
      ..color = color
      ..strokeWidth = 4 * s
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(
        Path()
          ..moveTo(9 * s, 32 * s)
          ..lineTo(20 * s, 8 * s)
          ..lineTo(31 * s, 32 * s),
        p);
    canvas.drawLine(Offset(12.6 * s, 25 * s), Offset(24.5 * s, 19.6 * s), p);
    canvas.drawCircle(Offset(28.6 * s, 17.8 * s), 3 * s, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_Mark o) => o.color != color;
}
