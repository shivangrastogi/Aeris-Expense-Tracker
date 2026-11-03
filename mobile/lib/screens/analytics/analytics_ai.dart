part of 'analytics_screen.dart';

// ═══════════════════════════════════════════════════════════════════════════
// TIPS TAB
// "Aeris says" (the tab's one hero-gradient card), Ask Aeris, the month-end
// prediction, budget projections, ways to save and anything unusual.
// ═══════════════════════════════════════════════════════════════════════════

class _AITab extends ConsumerStatefulWidget {
  const _AITab();
  @override
  ConsumerState<_AITab> createState() => _AITabState();
}

class _AITabState extends ConsumerState<_AITab> {
  int _insightIdx = 0;

  /// Lines for "Aeris says" — all computed from the user's own data.
  static List<String> _lines(InsightsBundle b) => [
        for (final p in b.budgetProjections.where((p) => p.alreadyOver).take(2))
          '${Categories.byId(p.categoryId).label} is over its '
              '${formatRupees(p.cap)} budget this month.',
        for (final p in b.budgetProjections
            .where((p) => !p.alreadyOver && p.daysUntilExceed != null)
            .take(2))
          'At this pace ${Categories.byId(p.categoryId).label} goes over '
              'budget in ${p.daysUntilExceed} days.',
        for (final r in b.recommendations.take(3)) '${r.title} — ${r.body}',
        for (final a in b.anomalies.take(2))
          'Unusual: ${formatRupees(a.amount)}'
              '${a.merchant == null ? '' : ' at ${a.merchant}'} — ${a.reason}',
      ];

  @override
  Widget build(BuildContext context) {
    ref.watch(amountHiddenProvider); // rebuild instantly on mask toggle
    final b = ref.watch(insightsProvider);
    return b.when(
      skipLoadingOnReload: true,
      loading: () => const Center(child: RisingLoader(width: 28)),
      error: (e, _) => Padding(
        padding: const EdgeInsets.all(20),
        child: Banner2(
            tone: Tone.bad,
            icon: PhFill.cloudX,
            title: "Couldn't load tips",
            body: '$e'),
      ),
      data: (bundle) {
        final lines = _lines(bundle);
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 120),
          children: [
            _AerisSaysCard(
              lines: lines,
              insightIdx: lines.isEmpty ? 0 : _insightIdx % lines.length,
              onTap: () => setState(() => _insightIdx++),
            ).animate().fadeIn(duration: Mo.standard),
            const SizedBox(height: 12),
            TonalButton('Ask Aeris a question',
                icon: Ph.sparkle,
                onPressed: () =>
                    Navigator.pushNamed(context, AppRoutes.assistant)),
            const SizedBox(height: 16),
            const _WeeklyRecapCard(),
            _PredictionCard(estimate: bundle.monthEstimate),
            if (bundle.budgetProjections.isNotEmpty) ...[
              const SizedBox(height: 16),
              _BudgetProjectionsCard(projections: bundle.budgetProjections),
            ],
            const SizedBox(height: 16),
            const Padding(
              padding: EdgeInsets.fromLTRB(4, 0, 4, 8),
              child: Overline('Ways to save'),
            ),
            if (bundle.recommendations.isEmpty)
              const _EmptyCard('Nothing to flag yet — keep using the app!'),
            for (final r in bundle.recommendations.take(4))
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _RecoCard(r: r),
              ),
            const SizedBox(height: 8),
            const Padding(
              padding: EdgeInsets.fromLTRB(4, 0, 4, 8),
              child: Overline('Unusual activity'),
            ),
            if (bundle.anomalies.isEmpty)
              const _EmptyCard('Nothing unusual in recent activity.'),
            for (final a in bundle.anomalies.take(3))
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Banner2(
                  tone: Tone.warn,
                  icon: PhFill.warningCircle,
                  title:
                      'Unusual: ${a.merchant ?? 'transaction'} ${formatRupees(a.amount, compact: true)}',
                  body: a.reason,
                ),
              ),
          ],
        );
      },
    );
  }
}

// ─── Aeris says: the hero card ─────────────────────────────────────────────

class _AerisSaysCard extends StatelessWidget {
  final List<String> lines;
  final int insightIdx;
  final VoidCallback onTap;
  const _AerisSaysCard(
      {required this.lines, required this.insightIdx, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final tk = context.tk;
    final text = lines.isEmpty
        ? 'Nothing stands out yet. After a few weeks of transactions, AERIS '
            'spots patterns here.'
        : lines[insightIdx];
    return Semantics(
      button: lines.length > 1,
      label: 'Aeris says: $text',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: lines.length > 1 ? onTap : null,
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: LinearGradient(
              begin: const Alignment(-0.85, -1),
              end: const Alignment(0.85, 1),
              colors: [tk.heroA, tk.heroB],
            ),
            boxShadow: tk.shadow,
          ),
          child: DefaultTextStyle.merge(
            style: TextStyle(color: tk.onHero),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  CustomPaint(
                      size: const Size(22, 22), painter: _MarkPainter(tk.onHero)),
                  const SizedBox(width: 8),
                  Overline('Aeris says', color: tk.onHero),
                ]),
                const SizedBox(height: 12),
                ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 52),
                  child: AnimatedSwitcher(
                    duration: Mo.standard,
                    child: Text(
                      text,
                      key: ValueKey(insightIdx),
                      style: TextStyle(
                          fontSize: 20,
                          height: 26 / 20,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.2,
                          color: tk.onHero),
                    ),
                  ),
                ),
                if (lines.length > 1) ...[
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(
                      child: Text(
                          '${insightIdx + 1} of ${lines.length} · tap for next',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: tk.onHero)),
                    ),
                    for (var i = 0; i < math.min(lines.length, 6); i++)
                      AnimatedContainer(
                        duration: Mo.standard,
                        margin: const EdgeInsets.only(left: 4),
                        width: i == insightIdx % 6 ? 16 : 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: tk.onHero.withValues(
                              alpha: i == insightIdx % 6 ? 1 : 0.35),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                  ]),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The AERIS mark: an "A" whose crossbar rises to a dot.
class _MarkPainter extends CustomPainter {
  final Color color;
  _MarkPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 40;
    final p = Paint()
      ..color = color
      ..strokeWidth = 3.4 * s
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
    canvas.drawCircle(
        Offset(28.6 * s, 17.8 * s), 2.6 * s, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_MarkPainter o) => o.color != color;
}

// ─── Predicted month-end spend ─────────────────────────────────────────────

class _PredictionCard extends StatelessWidget {
  final Prediction estimate;
  const _PredictionCard({required this.estimate});

  @override
  Widget build(BuildContext context) {
    final tk = context.tk;
    final hasRange = estimate.high > estimate.low && estimate.low > 0;
    return AerisCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Overline('Predicted month-end spend'),
        const SizedBox(height: 10),
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.end,
          spacing: 10,
          children: [
            MoneyText(estimate.estimate, style: Ts.amountL),
            if (hasRange)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                    'likely ${formatRupees(estimate.low, compact: true)}–'
                    '${formatRupees(estimate.high, compact: true)}',
                    style: TextStyle(fontSize: 13, color: tk.t2)),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Row(children: [
          Icon(Ph.trendUp, size: 16, color: tk.acc),
          const SizedBox(width: 8),
          Expanded(
            child: Text(estimate.basis,
                style: Ts.bodyS.copyWith(color: tk.t2)),
          ),
        ]),
      ]),
    );
  }
}

// ─── Budget projections card ───────────────────────────────────────────────

class _BudgetProjectionsCard extends StatelessWidget {
  final List<BudgetProjection> projections;
  const _BudgetProjectionsCard({required this.projections});

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: AerisColors.cardDecoration(context),
      padding: const EdgeInsets.only(top: 16, bottom: 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SectionTitle('Budget projections',
            padding: EdgeInsets.fromLTRB(16, 0, 16, 8)),
        for (final p in projections) _BpRow(bp: p),
      ]),
    );
  }
}

class _BpRow extends StatelessWidget {
  final BudgetProjection bp;
  const _BpRow({required this.bp});

  @override
  Widget build(BuildContext context) {
    final cat = Categories.byId(bp.categoryId);
    final (Tone tone, IconData icon, String label) = bp.alreadyOver
        ? (Tone.bad, PhFill.warningOctagon, 'Over')
        : bp.willExceed
            ? (Tone.warn, PhFill.warning, 'At risk')
            : (Tone.ok, PhFill.checkCircle, 'On track');
    return DsRow(
      minHeight: 60,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      leading: CatTile.of(cat),
      title: cat.label,
      sub: '${formatRupees(bp.spentSoFar, compact: true)} of '
          '${formatRupees(bp.cap, compact: true)}'
          '${bp.alreadyOver ? '' : ' · ends near ${formatRupees(bp.projectedMonthEnd, compact: true)}'}',
      trailing: StatusPill(label, icon: icon, tone: tone),
    );
  }
}

// ─── Ways to save ──────────────────────────────────────────────────────────

class _RecoCard extends StatelessWidget {
  final Recommendation r;
  const _RecoCard({required this.r});

  @override
  Widget build(BuildContext context) {
    final tk = context.tk;
    final (Color c, IconData fallback) = switch (r.severity) {
      InsightSeverity.warning => (tk.warn, Ph.warning),
      InsightSeverity.info => (tk.acc, Ph.lightbulb),
      InsightSeverity.positive => (tk.ok, Ph.piggyBank),
      InsightSeverity.alert => (tk.bad, Ph.warningOctagon),
    };
    final icon =
        r.categoryId != null ? Categories.byId(r.categoryId!).icon : fallback;
    final saving = r.potentialSaving;

    return AerisCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Row(children: [
        BadgeTile(icon: icon, tint: c),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(r.title,
                  style: TextStyle(
                      fontSize: 15,
                      height: 21 / 15,
                      fontWeight: FontWeight.w600,
                      color: tk.t1)),
              const SizedBox(height: 2),
              Text(r.body,
                  style: TextStyle(fontSize: 12, height: 16 / 12, color: tk.t2)),
            ],
          ),
        ),
        if (saving != null && saving > 0) ...[
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              MoneyText(saving,
                  color: tk.ok,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w700)),
              Text('per month', style: TextStyle(fontSize: 11, color: tk.t2)),
            ],
          ),
        ],
      ]),
    );
  }
}

// ─── Empty state ───────────────────────────────────────────────────────────

class _EmptyCard extends StatelessWidget {
  final String msg;
  const _EmptyCard(this.msg);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: AerisCard(
          padding: const EdgeInsets.all(16),
          child: Text(msg,
              style: TextStyle(fontSize: 13, color: context.tk.t2)),
        ),
      );
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
    final tk = context.tk;
    Widget line(IconData icon, Color color, String label, String text) =>
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            BadgeTile(icon: icon, tint: color, size: 32),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Overline(label),
                    const SizedBox(height: 2),
                    Text(text,
                        style: TextStyle(
                            fontSize: 14,
                            height: 20 / 14,
                            fontWeight: FontWeight.w500,
                            color: tk.t1)),
                  ]),
            ),
          ]),
        );
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: AerisCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SectionTitle('Your week', note: 'last 7 days'),
          line(Ph.arrowsDownUp, tk.acc, 'Biggest change', r.change),
          line(Ph.wrench, tk.warn, 'One habit to fix', r.habit),
          line(Ph.trophy, tk.ok, 'One win', r.win),
        ]),
      ),
    );
  }
}
