import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../models/category.dart';
import '../../models/transaction.dart';
import '../../providers/transactions_provider.dart';
import '../../utils/formatters.dart';

/// "Your month in money" — a Spotify-Wrapped-style swipeable recap computed
/// entirely on-device from this month's transactions.
class WrappedScreen extends ConsumerStatefulWidget {
  const WrappedScreen({super.key});
  @override
  ConsumerState<WrappedScreen> createState() => _WrappedScreenState();
}

class _WrappedScreenState extends ConsumerState<WrappedScreen> {
  final _controller = PageController();
  int _page = 0;

  static const _months = [
    '', 'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final txns =
        ref.watch(transactionsStreamProvider).asData?.value ?? const <Transaction>[];
    final now = DateTime.now();
    final stats = _compute(txns, now);
    final monthName = _months[now.month];

    final cards = <Widget>[
      _card(
        const [Color(0xFF0EA5A4), Color(0xFF0F766E)],
        [
          const Text('🗓️', style: TextStyle(fontSize: 52)),
          const SizedBox(height: 18),
          _big('$monthName\nin money'),
          const SizedBox(height: 10),
          _sub('A quick recap of your month. Swipe →'),
        ],
      ),
    ];

    if (stats.txnCount == 0) {
      cards.add(_card(
        const [Color(0xFF334155), Color(0xFF1E293B)],
        [
          const Text('🤷', style: TextStyle(fontSize: 52)),
          const SizedBox(height: 16),
          _big('No activity\nyet this month'),
          const SizedBox(height: 10),
          _sub('Add a few transactions and check back.'),
        ],
      ));
    } else {
      cards.add(_card(
        const [Color(0xFFEF4444), Color(0xFF991B1B)],
        [
          _sub('This month you spent'),
          const SizedBox(height: 10),
          _big(formatRupees(stats.spent)),
          const SizedBox(height: 10),
          _sub('across ${stats.txnCount} transaction'
              '${stats.txnCount == 1 ? '' : 's'}'),
        ],
      ));

      if (stats.topCat != null) {
        final c = Categories.byId(stats.topCat!);
        cards.add(_card(
          [c.color, Color.lerp(c.color, Colors.black, 0.4)!],
          [
            Icon(c.icon, color: Colors.white, size: 52),
            const SizedBox(height: 16),
            _sub('Your top category'),
            const SizedBox(height: 8),
            _big(c.label),
            const SizedBox(height: 8),
            _sub('${formatRupees(stats.topCatAmount)} · '
                '${(stats.topCatAmount / stats.spent * 100).toStringAsFixed(0)}% of spend'),
          ],
        ));
      }

      if (stats.topMerchant != null) {
        cards.add(_card(
          const [Color(0xFF8B5CF6), Color(0xFF6366F1)],
          [
            const Text('🏆', style: TextStyle(fontSize: 52)),
            const SizedBox(height: 16),
            _sub('You spent most at'),
            const SizedBox(height: 8),
            _big(stats.topMerchant!),
            const SizedBox(height: 8),
            _sub(formatRupees(stats.topMerchantAmount)),
          ],
        ));
      }

      if (stats.biggestDay != null) {
        cards.add(_card(
          const [Color(0xFFF59E0B), Color(0xFFB45309)],
          [
            const Text('💥', style: TextStyle(fontSize: 52)),
            const SizedBox(height: 16),
            _sub('Your biggest day'),
            const SizedBox(height: 8),
            _big('${stats.biggestDay!.day} $monthName'),
            const SizedBox(height: 8),
            _sub('${formatRupees(stats.biggestDayAmount)} in one day'),
          ],
        ));
      }

      cards.add(_card(
        const [Color(0xFF22C55E), Color(0xFF15803D)],
        [
          Text('${stats.noSpendDays}', style: const TextStyle(
              color: Colors.white, fontSize: 80, fontWeight: FontWeight.w900)),
          const SizedBox(height: 6),
          _big('no-spend day${stats.noSpendDays == 1 ? '' : 's'}'),
          const SizedBox(height: 10),
          _sub(stats.noSpendDays == 0
              ? 'Spent something every day so far.'
              : 'Days you didn\'t spend a rupee 🎉'),
        ],
      ));

      if (stats.momPct != null) {
        final down = stats.momPct! < 0;
        cards.add(_card(
          down
              ? const [Color(0xFF22C55E), Color(0xFF15803D)]
              : const [Color(0xFFEF4444), Color(0xFF991B1B)],
          [
            Icon(down ? Icons.trending_down : Icons.trending_up,
                color: Colors.white, size: 52),
            const SizedBox(height: 16),
            _sub('vs last month'),
            const SizedBox(height: 8),
            _big('${stats.momPct!.abs().toStringAsFixed(0)}% ${down ? 'less' : 'more'}'),
            const SizedBox(height: 8),
            _sub(down ? 'Nice — spending is down.' : 'Spending crept up.'),
          ],
        ));
      }

      // Final: net + share
      final saved = stats.income - stats.spent;
      cards.add(_card(
        const [Color(0xFF0EA5A4), Color(0xFF0F766E)],
        [
          _sub(saved >= 0 ? 'You saved' : 'You overspent'),
          const SizedBox(height: 10),
          _big(formatRupees(saved.abs())),
          const SizedBox(height: 20),
          FilledButton.icon(
            style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: const Color(0xFF0F766E)),
            onPressed: () => _share(stats, monthName),
            icon: const Icon(Icons.share),
            label: const Text('Share my month'),
          ),
        ],
      ));
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          PageView(
            controller: _controller,
            onPageChanged: (i) => setState(() => _page = i),
            children: cards,
          ),
          // Progress dots
          Positioned(
            top: MediaQuery.of(context).padding.top + 10,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < cards.length; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: i == _page ? 22 : 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: Colors.white
                          .withValues(alpha: i == _page ? 0.95 : 0.4),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
              ],
            ),
          ),
          Positioned(
            top: MediaQuery.of(context).padding.top + 2,
            right: 6,
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white70),
              onPressed: () => Navigator.pop(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _card(List<Color> gradient, List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: gradient,
        ),
      ),
      padding: const EdgeInsets.all(32),
      alignment: Alignment.center,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: children,
      ),
    );
  }

  Widget _big(String s) => Text(
        s,
        textAlign: TextAlign.center,
        style: const TextStyle(
            color: Colors.white,
            fontSize: 34,
            fontWeight: FontWeight.w900,
            height: 1.1),
      );

  Widget _sub(String s) => Text(
        s,
        textAlign: TextAlign.center,
        style: const TextStyle(color: Colors.white70, fontSize: 15),
      );

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
      final ts = t.timestamp;
      if (ts.year == lastM.year && ts.month == lastM.month && t.isDebit) {
        lastMonthSpent += t.amount;
      }
      if (ts.year != now.year || ts.month != now.month) continue;
      if (t.isCredit) {
        income += t.amount;
        continue;
      }
      spent += t.amount;
      byCat[t.categoryId] = (byCat[t.categoryId] ?? 0) + t.amount;
      final mName = t.merchant?.trim();
      if (mName != null && mName.isNotEmpty) {
        byMerchant[mName] = (byMerchant[mName] ?? 0) + t.amount;
      }
      byDay[ts.day] = (byDay[ts.day] ?? 0) + t.amount;
      spendDays.add(ts.day);
    }

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
