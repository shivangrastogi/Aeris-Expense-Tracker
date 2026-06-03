import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/analytics_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/gamification_provider.dart';
import '../../utils/formatters.dart';
import '../../widgets/aeris_avatar.dart';

class FutureSelfScreen extends ConsumerStatefulWidget {
  const FutureSelfScreen({super.key});
  @override
  ConsumerState<FutureSelfScreen> createState() => _FutureSelfScreenState();
}

class _FutureSelfScreenState extends ConsumerState<FutureSelfScreen> {
  double? _savings;

  @override
  void initState() {
    super.initState();
    final profile = ref.read(userProfileProvider).asData?.value;
    final analytics = ref.read(analyticsProvider).valueOrNull;
    final income = profile?.monthlyIncome ?? 0;
    final spend = analytics?.monthExpense ?? 0;
    final guess = income > 0 ? (income - spend) : (analytics?.monthNet ?? 0);
    _savings = guess.clamp(0, 1000000).toDouble();
    if (_savings == 0) _savings = 5000;
  }

  // Future value of a monthly contribution P over `years` at annual rate r.
  double _fv(double p, double r, int years) {
    final n = years * 12;
    final i = r / 12;
    if (i == 0) return p * n;
    return p * ((math.pow(1 + i, n) - 1) / i);
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(avatarStatusProvider);
    final p = _savings ?? 5000;
    return Scaffold(
      appBar: AppBar(title: const Text('Future Self')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: [
          Center(
            child: AerisAvatar(
                skin: status.skin,
                stage: 5, // your future self — fully evolved
                mood: AvatarMood.excited,
                size: 150),
          ),
          Center(
            child: Text('Future you, if you keep it up',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('You save ${formatRupees(p)} / month',
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  Slider(
                    value: p.clamp(0, 200000).toDouble(),
                    min: 0, max: 200000, divisions: 200,
                    label: formatRupees(p, compact: true),
                    onChanged: (v) => setState(() => _savings = v),
                  ),
                  Text('Drag to explore different saving rates.',
                      style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          for (final y in const [1, 5, 10])
            _HorizonCard(
              years: y,
              saved: _fv(p, 0, y),
              invested: _fv(p, 0.08, y),
            ),
          const SizedBox(height: 12),
          Text(
            'Saved = cash set aside (0% growth). Invested = the same amount in '
            'something earning ~8%/yr. Not financial advice — just the maths of '
            'consistency.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _HorizonCard extends StatelessWidget {
  final int years;
  final double saved, invested;
  const _HorizonCard(
      {required this.years, required this.saved, required this.invested});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: scheme.primary.withValues(alpha: 0.15),
              child: Text('${years}y',
                  style: TextStyle(
                      fontWeight: FontWeight.w800, color: scheme.primary)),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Just saving: ${formatRupees(saved, compact: true)}',
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  Text('Invested @8%: ${formatRupees(invested, compact: true)}',
                      style: const TextStyle(
                          color: Color(0xFF22C55E),
                          fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
