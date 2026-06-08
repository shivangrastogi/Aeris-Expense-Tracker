import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/insights_provider.dart';
import '../../providers/mascot_provider.dart';
import 'aeris_mascot.dart';

/// Aeris + a speech bubble. Tap anywhere on the card (or the mascot) and Aeris
/// reacts and tells you the next insight — making it feel alive.
class MascotCard extends ConsumerStatefulWidget {
  final double mascotSize;
  const MascotCard({super.key, this.mascotSize = 84});

  @override
  ConsumerState<MascotCard> createState() => _MascotCardState();
}

class _MascotCardState extends ConsumerState<MascotCard> {
  int _idx = 0;
  int _react = 0;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(mascotProvider);
    final recs =
        ref.watch(insightsProvider).asData?.value?.recommendations ?? const [];
    final scheme = Theme.of(context).colorScheme;

    // The pool of things Aeris can say: the live mood line, each
    // recommendation, then a couple of friendly tips so a tap always does
    // something.
    final lines = <String>[
      state.line,
      for (final r in recs) '${r.title} — ${r.body}',
      'Tip: tap me for your next insight.',
      'You can switch the time period from the chip up top.',
      'Spotted junk? Block that sender from “Review SMS”.',
    ];
    final line = lines[_idx % lines.length];

    void tap() => setState(() {
          _idx++;
          _react++;
        });

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: tap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 12, 14, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              AerisMascot(
                  mood: state.mood, size: widget.mascotSize, reactKey: _react),
              const SizedBox(width: 8),
              Expanded(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(4),
                      topRight: Radius.circular(16),
                      bottomLeft: Radius.circular(16),
                      bottomRight: Radius.circular(16),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Text('Aeris',
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: scheme.primary)),
                          const Spacer(),
                          Icon(Icons.touch_app_outlined,
                              size: 13, color: scheme.onSurfaceVariant),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(line,
                              style:
                                  const TextStyle(fontSize: 13, height: 1.35))
                          .animate(key: ValueKey(line))
                          .fadeIn(duration: 280.ms)
                          .slideX(begin: 0.05, end: 0),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
