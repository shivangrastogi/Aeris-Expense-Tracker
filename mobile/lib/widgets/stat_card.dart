import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../utils/formatters.dart';

/// Small numeric tile used on the dashboard. Optional delta shows
/// green-up / red-down trend.
class StatCard extends StatelessWidget {
  final String label;
  final double amount;
  final String? subtitle;
  final IconData icon;
  final Color? color;
  final double? deltaPct;

  const StatCard({
    super.key,
    required this.label,
    required this.amount,
    required this.icon,
    this.subtitle,
    this.color,
    this.deltaPct,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: c.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: c, size: 18),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(label,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        )),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            formatRupees(amount),
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          if (subtitle != null || deltaPct != null) ...[
            const SizedBox(height: 4),
            Row(children: [
              if (deltaPct != null) ...[
                Icon(
                  deltaPct! >= 0 ? Icons.north_east : Icons.south_east,
                  size: 12,
                  color: deltaPct! >= 0 ? AerisColors.credit : AerisColors.debit,
                ),
                const SizedBox(width: 2),
                Text(
                  '${deltaPct!.abs().toStringAsFixed(1)}%',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color:
                        deltaPct! >= 0 ? AerisColors.credit : AerisColors.debit,
                  ),
                ),
                const SizedBox(width: 6),
              ],
              if (subtitle != null)
                Expanded(
                  child: Text(
                    subtitle!,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
            ]),
          ],
        ],
      ),
    );
  }
}
