import 'package:flutter/material.dart';

import 'category.dart';

/// User-made categories ("Pets", "Gym", "Kids"). Stored as indexes into these
/// fixed icon / colour sets, so they stay JSON-safe and the icons survive
/// tree-shaking.
class CustomCategories {
  CustomCategories._();

  static const icons = <IconData>[
    Icons.label_outline_rounded,
    Icons.pets_rounded,
    Icons.child_care_rounded,
    Icons.fitness_center_rounded,
    Icons.local_cafe_rounded,
    Icons.card_giftcard_rounded,
    Icons.volunteer_activism_outlined,
    Icons.local_laundry_service_outlined,
    Icons.build_outlined,
    Icons.devices_other_rounded,
    Icons.sports_esports_outlined,
    Icons.flight_takeoff_rounded,
    Icons.local_bar_outlined,
    Icons.medication_outlined,
    Icons.checkroom_rounded,
    Icons.wifi_rounded,
    Icons.savings_outlined,
    Icons.work_outline_rounded,
    Icons.directions_bike_rounded,
    Icons.local_florist_outlined,
  ];

  /// The validated muted chart palette plus four quieter tones.
  static const colors = <Color>[
    Color(0xFF5F8CCB), Color(0xFFC97A52), Color(0xFF2FA287), Color(0xFFB0902F),
    Color(0xFFC9789A), Color(0xFF5F9A4C), Color(0xFF8A7ED3), Color(0xFFC96A66),
    Color(0xFF7D8796), Color(0xFF4E97A8), Color(0xFF8E8F45), Color(0xFFA176B0),
  ];

  static ExpenseCategory fromMap(String id, Map<String, dynamic> m) {
    final i = (m['icon'] as num?)?.toInt() ?? 0;
    final c = (m['color'] as num?)?.toInt() ?? 0;
    return ExpenseCategory(
      id: id,
      label: (m['label'] as String?) ?? 'Category',
      icon: icons[i.clamp(0, icons.length - 1)],
      color: colors[c.clamp(0, colors.length - 1)],
    );
  }

  static Map<String, dynamic> toMap(ExpenseCategory c) => {
        'label': c.label,
        'icon': icons.indexOf(c.icon).clamp(0, icons.length - 1),
        'color': colors.indexOf(c.color).clamp(0, colors.length - 1),
      };
}
