import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../providers/gamification_provider.dart';
import '../../widgets/ds.dart';

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

const _cardIcons = <String, IconData>{
  'momentum': Ph.trendUp,
  'balances': Ph.bank,
  'categories': Ph.chartPieSlice,
  'forecast': Ph.chartLineUp,
  'checkin': Ph.flame,
};

class CustomizeDashboardScreen extends ConsumerWidget {
  const CustomizeDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tk = context.tk;
    final g = ref.watch(gamificationProvider);
    final ctrl = ref.read(gamificationProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('Customize Home')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(4, 0, 4, 8),
            child: Overline('Show on Home'),
          ),
          ListGroup(inset: 64, children: [
            for (final (id, label) in dashboardCards)
              SettingsRow(
                icon: _cardIcons[id] ?? Ph.squaresFour,
                iconColor: g.hiddenCards.contains(id) ? null : tk.acc,
                title: label,
                trailing: Switch(
                  value: !g.hiddenCards.contains(id),
                  onChanged: (v) => ctrl.setCardHidden(id, !v),
                ),
                onTap: () =>
                    ctrl.setCardHidden(id, !g.hiddenCards.contains(id)),
              ),
          ]),
          const SizedBox(height: 18),
          const Padding(
            padding: EdgeInsets.fromLTRB(4, 0, 4, 8),
            child: Overline('Accent colour'),
          ),
          AerisCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _Swatch(
                      color: AerisColors.arc,
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
                const SizedBox(height: 12),
                Text(
                    'Accent recolours buttons, highlights and progress '
                    'across the app instantly.',
                    style: Ts.label
                        .copyWith(fontWeight: FontWeight.w400, color: tk.t2)),
              ],
            ),
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
      {required this.color,
      required this.selected,
      this.label,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    final tk = context.tk;
    return Semantics(
      button: true,
      selected: selected,
      label: label ?? 'Accent colour',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            boxShadow: selected
                ? [
                    BoxShadow(color: color, spreadRadius: 4),
                    BoxShadow(color: tk.surface, spreadRadius: 2),
                  ]
                : null,
          ),
          child: selected
              ? const Icon(PhBold.check, size: 16, color: Colors.white)
              : null,
        ),
      ),
    );
  }
}
