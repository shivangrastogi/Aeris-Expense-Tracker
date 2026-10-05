import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The saved theme, read in main() before the first frame (no dark→light
/// flash on start-up for people who picked Light or System).
ThemeMode kInitialThemeMode = ThemeMode.dark;

final themeModeProvider =
    StateNotifierProvider<ThemeModeNotifier, ThemeMode>(_create);

ThemeModeNotifier _create(Ref _) => ThemeModeNotifier();

class ThemeModeNotifier extends StateNotifier<ThemeMode> {
  ThemeModeNotifier() : super(kInitialThemeMode) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getString('theme_mode') ?? 'dark';
    if (mounted) state = ThemeModeNotifier.parseThemeMode(v);
  }

  Future<void> setMode(ThemeMode mode) async {
    state = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('theme_mode', _serialize(mode));
  }

  static ThemeMode parseThemeMode(String v) => switch (v) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };

  static String _serialize(ThemeMode m) => switch (m) {
        ThemeMode.light => 'light',
        ThemeMode.dark => 'dark',
        _ => 'system',
      };
}
