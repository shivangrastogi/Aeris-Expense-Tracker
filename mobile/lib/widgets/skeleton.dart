import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

/// A single shimmering placeholder block.
///
/// Compose these to mirror the *shape* of the real content while it loads, so
/// data arriving doesn't shift the layout (the jank you get when a centred
/// spinner is suddenly replaced by a full screen of cards).
class SkeletonBox extends StatelessWidget {
  final double? width;
  final double height;
  final double radius;
  final EdgeInsetsGeometry margin;

  const SkeletonBox({
    super.key,
    this.width,
    this.height = 14,
    this.radius = 8,
    this.margin = EdgeInsets.zero,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: width,
      height: height,
      margin: margin,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(radius),
      ),
    )
        .animate(onPlay: (c) => c.repeat())
        .shimmer(duration: 1100.ms, color: scheme.surface.withValues(alpha: 0.55));
  }
}

/// A round shimmering placeholder (avatars, icons).
class SkeletonCircle extends StatelessWidget {
  final double size;
  const SkeletonCircle({super.key, this.size = 40});
  @override
  Widget build(BuildContext context) =>
      SkeletonBox(width: size, height: size, radius: size / 2);
}

/// A single text-line placeholder.
class SkeletonLine extends StatelessWidget {
  final double width;
  final double height;
  const SkeletonLine({super.key, this.width = 120, this.height = 12});
  @override
  Widget build(BuildContext context) =>
      SkeletonBox(width: width, height: height, radius: 6);
}

/// A card-shaped row: leading circle + two stacked lines + a progress bar.
/// Mirrors the budget / list-tile layout.
class SkeletonListTile extends StatelessWidget {
  final bool showBar;
  const SkeletonListTile({super.key, this.showBar = true});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            const SkeletonCircle(size: 40),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SkeletonLine(width: 120, height: 13),
                  const SizedBox(height: 8),
                  const SkeletonLine(width: 180, height: 11),
                  if (showBar) ...[
                    const SizedBox(height: 10),
                    SkeletonBox(width: double.infinity, height: 6, radius: 3),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            const Icon(Icons.chevron_right, color: Colors.transparent),
          ],
        ),
      ),
    );
  }
}

/// A ChartCard-shaped placeholder: a title line + a tall block for the chart.
class SkeletonChartCard extends StatelessWidget {
  final double height;
  const SkeletonChartCard({super.key, this.height = 220});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SkeletonLine(width: 160, height: 15),
            const SizedBox(height: 6),
            const SkeletonLine(width: 110, height: 11),
            const SizedBox(height: 16),
            SkeletonBox(width: double.infinity, height: height, radius: 14),
          ],
        ),
      ),
    );
  }
}

// ── Screen-level skeletons ────────────────────────────────────────────

/// Hero + budget cards on the dashboard.
class DashboardCardsSkeleton extends StatelessWidget {
  const DashboardCardsSkeleton({super.key});
  @override
  Widget build(BuildContext context) {
    return Column(
      children: const [
        SkeletonBox(width: double.infinity, height: 178, radius: 22),
        SizedBox(height: 14),
        SkeletonBox(width: double.infinity, height: 132, radius: 20),
      ],
    );
  }
}

/// Budgets screen: a column of budget rows.
class BudgetListSkeleton extends StatelessWidget {
  const BudgetListSkeleton({super.key});
  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 80),
      children: [
        for (var i = 0; i < 7; i++) const SkeletonListTile(),
      ],
    );
  }
}

/// Analytics screen: range chip + a stack of chart cards.
class AnalyticsSkeleton extends StatelessWidget {
  const AnalyticsSkeleton({super.key});
  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 28),
      children: const [
        Align(
          alignment: Alignment.centerRight,
          child: SkeletonBox(width: 150, height: 34, radius: 18),
        ),
        SizedBox(height: 12),
        SkeletonChartCard(height: 260),
        SizedBox(height: 14),
        SkeletonChartCard(height: 220),
        SizedBox(height: 14),
        SkeletonChartCard(height: 240),
      ],
    );
  }
}

/// Goals screen: streak card + badge row + goal cards.
class GoalsSkeleton extends StatelessWidget {
  const GoalsSkeleton({super.key});
  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 100),
      children: [
        const SkeletonBox(width: double.infinity, height: 120, radius: 20),
        const SizedBox(height: 16),
        Row(
          children: const [
            SkeletonCircle(size: 52),
            SizedBox(width: 14),
            SkeletonCircle(size: 52),
            SizedBox(width: 14),
            SkeletonCircle(size: 52),
            SizedBox(width: 14),
            SkeletonCircle(size: 52),
          ],
        ),
        const SizedBox(height: 20),
        const SkeletonLine(width: 160, height: 16),
        const SizedBox(height: 14),
        const SkeletonBox(width: double.infinity, height: 96, radius: 18),
        const SizedBox(height: 12),
        const SkeletonBox(width: double.infinity, height: 96, radius: 18),
      ],
    );
  }
}

/// Insights screen: mascot card + hero prediction + section cards.
class InsightsSkeleton extends StatelessWidget {
  const InsightsSkeleton({super.key});
  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 32),
      children: const [
        SkeletonBox(width: double.infinity, height: 110, radius: 20),
        SizedBox(height: 14),
        SkeletonBox(width: double.infinity, height: 140, radius: 20),
        SizedBox(height: 18),
        SkeletonLine(width: 150, height: 15),
        SizedBox(height: 12),
        SkeletonBox(width: double.infinity, height: 84, radius: 16),
        SizedBox(height: 12),
        SkeletonBox(width: double.infinity, height: 84, radius: 16),
      ],
    );
  }
}
