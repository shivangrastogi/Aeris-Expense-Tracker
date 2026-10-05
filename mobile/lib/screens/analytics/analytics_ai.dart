part of 'analytics_screen.dart';

// ═══════════════════════════════════════════════════════════════════════════
// AI TAB
// ═══════════════════════════════════════════════════════════════════════════

class _AITab extends ConsumerStatefulWidget {
  const _AITab();
  @override
  ConsumerState<_AITab> createState() => _AITabState();
}

class _AITabState extends ConsumerState<_AITab> {
  int _insightIdx = 0;
  int _reactKey = 0;

  static const _insights = [
    'Your food spend is tracking 18% below last month — nice work 🎉',
    'You\'ve had some great no-spend days this month!',
    'Review any unused subscriptions to save more each month.',
  ];

  @override
  Widget build(BuildContext context) {
    ref.watch(amountHiddenProvider); // rebuild instantly on mask toggle
    final b = ref.watch(insightsProvider);
    return b.when(
      skipLoadingOnReload: true,
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('$e')),
      data: (bundle) => ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
        children: [
          const _WeeklyRecapCard(),
          _AerisSaysCard(
            insightIdx: _insightIdx,
            reactKey: _reactKey,
            onTap: () => setState(() {
              _insightIdx = (_insightIdx + 1) % _insights.length;
              _reactKey++;
            }),
          ).animate().fadeIn(duration: 280.ms),
          const SizedBox(height: 12),
          _PredictionBanner(estimate: bundle.monthEstimate)
              .animate()
              .fadeIn(duration: 280.ms, delay: 60.ms),
          const SizedBox(height: 20),
          if (bundle.budgetProjections.isNotEmpty) ...[
            const _SectionHead('Budget projections'),
            _BudgetProjectionsCard(projections: bundle.budgetProjections)
                .animate()
                .fadeIn(duration: 280.ms, delay: 100.ms),
            const SizedBox(height: 20),
          ],
          const _SectionHead('Recommendations'),
          if (bundle.recommendations.isEmpty)
            _EmptyCard('Nothing to flag yet — keep using the app!'),
          for (final r in bundle.recommendations.take(4))
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _RecoCard(r: r)
                  .animate()
                  .fadeIn(duration: 280.ms, delay: 140.ms),
            ),
          const SizedBox(height: 10),
          const _SectionHead('Anomalies'),
          if (bundle.anomalies.isEmpty)
            _EmptyCard('Nothing anomalous in recent activity.'),
          for (final a in bundle.anomalies.take(3))
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _AnomalyCard(a: a)
                  .animate()
                  .fadeIn(duration: 280.ms, delay: 180.ms),
            ),
          const SizedBox(height: 10),
          _AskAerisBtn().animate().fadeIn(duration: 280.ms, delay: 220.ms),
        ],
      ),
    );
  }
}

// ─── Aeris says card ───────────────────────────────────────────────────────

class _AerisSaysCard extends StatelessWidget {
  final int insightIdx, reactKey;
  final VoidCallback onTap;
  const _AerisSaysCard(
      {required this.insightIdx, required this.reactKey, required this.onTap});

  static const _insights = [
    'Your food spend is tracking 18% below last month — nice work 🎉',
    'You\'ve had some great no-spend days this month!',
    'Review any unused subscriptions to save more each month.',
  ];

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: BoxDecoration(
          color: AerisColors.accent(context).withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: AerisColors.accent(context).withValues(alpha: 0.25)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AerisMascot(
                mood: MascotMood.celebrate, size: 50, reactKey: reactKey),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('AERIS SAYS',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: AerisColors.ink(context),
                          letterSpacing: 0.8)),
                  const SizedBox(height: 4),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: Text(
                      _insights[insightIdx],
                      key: ValueKey(insightIdx),
                      style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          height: 1.45),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Prediction banner ─────────────────────────────────────────────────────

class _PredictionBanner extends StatelessWidget {
  final Prediction estimate;
  const _PredictionBanner({required this.estimate});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      decoration: BoxDecoration(
        gradient: AerisColors.violetGradient,
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [
          BoxShadow(
              color: Color(0x4D6366F1), blurRadius: 24, offset: Offset(0, 8)),
        ],
      ),
      child: Stack(children: [
        Positioned(
          right: -10,
          top: -10,
          child: Opacity(
            opacity: 0.2,
            child: const Icon(Icons.online_prediction,
                size: 110, color: Colors.white),
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Predicted month-end spend',
                style: TextStyle(
                    color: Color(0xD9FFFFFF),
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(formatRupees(estimate.estimate),
                  maxLines: 1,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 36,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5)),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(99),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.trending_down,
                      size: 15, color: Colors.white),
                  const SizedBox(width: 5),
                  Flexible(
                    child: Text(estimate.basis,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w800)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ]),
    );
  }
}

// ─── Section heading ───────────────────────────────────────────────────────

class _SectionHead extends StatelessWidget {
  final String title;
  const _SectionHead(this.title);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10, left: 2),
        child: Text(title,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
      );
}

// ─── Budget projections card ───────────────────────────────────────────────

class _BudgetProjectionsCard extends StatelessWidget {
  final List<BudgetProjection> projections;
  const _BudgetProjectionsCard({required this.projections});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = scheme.brightness == Brightness.dark
        ? AerisColors.cardDark
        : Colors.white;
    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.2)),
      ),
      child: Column(children: [
        for (var i = 0; i < projections.length; i++) ...[
          if (i > 0)
            Divider(
                height: 1,
                thickness: 1,
                color: scheme.outlineVariant.withValues(alpha: 0.2)),
          _BpRow(bp: projections[i], isLast: i == projections.length - 1),
        ],
      ]),
    );
  }
}

class _BpRow extends StatelessWidget {
  final BudgetProjection bp;
  final bool isLast;
  const _BpRow({required this.bp, required this.isLast});

  @override
  Widget build(BuildContext context) {
    final cat = Categories.byId(bp.categoryId);
    final (Color color, IconData icon, String label) = bp.alreadyOver
        ? (AerisColors.danger(context), Icons.error, 'Over budget')
        : bp.willExceed
            ? (AerisColors.warning, Icons.warning, 'At risk')
            : (AerisColors.moneyIn(context), Icons.check_circle, 'On track');
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: EdgeInsets.fromLTRB(12, 12, 12, isLast ? 12 : 10),
      child: Row(children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: cat.color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(cat.icon, color: cat.color, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(cat.label,
                  style: const TextStyle(
                      fontSize: 13.5, fontWeight: FontWeight.w700)),
              Text(
                '${formatRupees(bp.spentSoFar, compact: true)} of ${formatRupees(bp.cap, compact: true)}',
                style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
        Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  fontSize: 11.5, fontWeight: FontWeight.w800, color: color)),
        ]),
      ]),
    );
  }
}

// ─── Recommendation card ───────────────────────────────────────────────────

class _RecoCard extends StatelessWidget {
  final Recommendation r;
  const _RecoCard({required this.r});

  @override
  Widget build(BuildContext context) {
    final (Color c, Color tint, IconData fallback) = switch (r.severity) {
      InsightSeverity.warning => (
          AerisColors.warning,
          const Color(0x1AE08C00),
          Icons.restaurant
        ),
      InsightSeverity.info => (
          AerisColors.info,
          const Color(0x1A3B82F6),
          Icons.subscriptions
        ),
      InsightSeverity.positive => (
          AerisColors.moneyIn(context),
          const Color(0x1A15A24A),
          Icons.savings
        ),
      InsightSeverity.alert => (
          AerisColors.danger(context),
          const Color(0x1AE5484D),
          Icons.priority_high
        ),
    };
    final icon =
        r.categoryId != null ? Categories.byId(r.categoryId!).icon : fallback;
    final scheme = Theme.of(context).colorScheme;
    final bg = scheme.brightness == Brightness.dark
        ? AerisColors.cardDark
        : Colors.white;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
                color: tint, borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, size: 22, color: c),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(r.title,
                    style: const TextStyle(
                        fontSize: 13.5, fontWeight: FontWeight.w800)),
                const SizedBox(height: 3),
                Text(r.body,
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        height: 1.45,
                        color: scheme.onSurfaceVariant)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Anomaly card ──────────────────────────────────────────────────────────

class _AnomalyCard extends StatelessWidget {
  final Anomaly a;
  const _AnomalyCard({required this.a});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = scheme.brightness == Brightness.dark
        ? AerisColors.cardDark
        : Colors.white;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.2)),
      ),
      child: Row(children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: AerisColors.danger(context).withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(13),
          ),
          child: Icon(Icons.priority_high,
              size: 24, color: AerisColors.danger(context)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Unusual: ${a.merchant ?? 'transaction'} ${formatRupees(a.amount, compact: true)}',
                style: const TextStyle(
                    fontSize: 13.5, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 2),
              Text(a.reason,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurfaceVariant)),
            ],
          ),
        ),
      ]),
    );
  }
}

// ─── Ask Aeris button ──────────────────────────────────────────────────────

class _AskAerisBtn extends StatelessWidget {
  const _AskAerisBtn();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = scheme.brightness == Brightness.dark
        ? AerisColors.cardDark
        : Colors.white;
    return GestureDetector(
      onTap: () => Navigator.pushNamed(context, AppRoutes.assistant),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(18),
          border:
              Border.all(color: scheme.outlineVariant.withValues(alpha: 0.25)),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.07),
                blurRadius: 12,
                offset: const Offset(0, 4)),
          ],
        ),
        child: Row(children: [
          AerisMascot(mood: MascotMood.happy, size: 40),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Ask Aeris',
                    style:
                        TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800)),
                Text('"How much on food last week?"',
                    style: TextStyle(
                        fontSize: 12, color: scheme.onSurfaceVariant)),
              ],
            ),
          ),
          Icon(Icons.chat_bubble_outline,
              color: AerisColors.accent(context), size: 22),
        ]),
      ),
    );
  }
}

// ─── Empty state ───────────────────────────────────────────────────────────

class _EmptyCard extends StatelessWidget {
  final String msg;
  const _EmptyCard(this.msg);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = scheme.brightness == Brightness.dark
        ? AerisColors.cardDark
        : Colors.white;
    return Container(
      padding: const EdgeInsets.all(14),
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.2)),
      ),
      child: Text(msg,
          style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
    );
  }
}

// ─── Weekly recap ──────────────────────────────────────────────────────────
// Three lines from the last 7 days vs the 7 before: the biggest change, one
// habit to fix, one win. Also sent as the Sunday-evening notification.
class _WeeklyRecapCard extends ConsumerWidget {
  const _WeeklyRecapCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = ref.watch(weeklyRecapProvider);
    if (r == null) return const SizedBox.shrink();
    final accent = AerisColors.accent(context);
    Widget line(IconData icon, Color color, String label, String text) =>
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(icon, size: 16, color: color),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: hudLabel(context, size: 10)),
                    const SizedBox(height: 2),
                    Text(text,
                        style: const TextStyle(
                            fontSize: 13.5,
                            height: 1.35,
                            fontWeight: FontWeight.w600)),
                  ]),
            ),
          ]),
        );
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: AerisCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.auto_awesome_rounded, size: 16, color: accent),
            const SizedBox(width: 6),
            Text('YOUR WEEK', style: hudLabel(context, color: accent)),
            const Spacer(),
            Text('last 7 days',
                style:
                    TextStyle(fontSize: 12, color: AerisColors.muted(context))),
          ]),
          line(Icons.swap_vert_rounded, AerisColors.info, 'BIGGEST CHANGE',
              r.change),
          line(Icons.build_circle_outlined, AerisColors.warning,
              'ONE HABIT TO FIX', r.habit),
          line(Icons.emoji_events_outlined, AerisColors.moneyIn(context),
              'ONE WIN', r.win),
        ]),
      ),
    );
  }
}
