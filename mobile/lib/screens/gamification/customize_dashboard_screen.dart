import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/gamification_provider.dart';

/// Card ids that the Home screen honours for show/hide (see the
/// `kHomeCard*` constants in home_screen.dart).
const dashboardCards = <(String, String)>[
  ('momentum', 'Momentum — savings, streak, goal'),
  ('balances', 'Bank balances & card bills'),
  ('categories', 'Top spending categories'),
  ('forecast', 'Month-end forecast'),
  ('checkin', 'Daily check-in reminder'),
];

// Calm alternatives to the default steel blue: teal, indigo, sage, plum,
// slate, terracotta. accentFor() tones each for light / dark.
const _accents = <int>[
  0xFF2F8F80, 0xFF5C6BC0, 0xFF5E8F4E,
  0xFF8E6C9E, 0xFF64748B, 0xFFB8704A,
];

class CustomizeDashboardScreen extends ConsumerWidget {
  const CustomizeDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final g = ref.watch(gamificationProvider);
    final ctrl = ref.read(gamificationProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('Customize dashboard')),
      body: ListView(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 14, 16, 4),
            child: Text('Show on Home',
                style: TextStyle(fontWeight: FontWeight.w800)),
          ),
          for (final (id, label) in dashboardCards)
            SwitchListTile(
              title: Text(label),
              value: !g.hiddenCards.contains(id),
              onChanged: (v) => ctrl.setCardHidden(id, !v),
            ),
          const Divider(),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Text('Accent colour',
                style: TextStyle(fontWeight: FontWeight.w800)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _Swatch(
                  color: Theme.of(context).colorScheme.onSurface,
                  selected: g.accent == null,
                  label: 'Default',
                  onTap: () => ctrl.setAccent(null),
                ),
                for (final a in _accents)
                  _Swatch(
                    color: Color(a),
                    selected: g.accent == a,
                    onTap: () => ctrl.setAccent(a),
                  ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Accent recolours buttons, highlights and progress '
                'across the app instantly.',
                style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  final Color color;
  final bool selected;
  final String? label;
  final VoidCallback onTap;
  const _Swatch(
      {required this.color, required this.selected, this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: label == null ? color : Colors.transparent,
              shape: BoxShape.circle,
              border: Border.all(
                  color: selected ? color : Colors.grey.withValues(alpha: 0.4),
                  width: selected ? 3 : 1.5),
            ),
            child: label != null
                ? Icon(Icons.format_color_reset,
                    color: Theme.of(context).colorScheme.onSurface)
                : selected
                    ? const Icon(Icons.check, color: Colors.white)
                    : null,
          ),
          if (label != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(label!, style: const TextStyle(fontSize: 10)),
            ),
        ],
      ),
    );
  }
}
