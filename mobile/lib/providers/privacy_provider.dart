import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/formatters.dart';

/// Whether rupee amounts are hidden across the app (the "eye" privacy toggle).
/// Mirrors the value into the [kAmountsHidden] global that `formatRupees`
/// reads, and persists it so it survives restarts.
final amountHiddenProvider =
    StateNotifierProvider<AmountHiddenController, bool>(
        (ref) => AmountHiddenController());

class AmountHiddenController extends StateNotifier<bool> {
  AmountHiddenController() : super(kAmountsHidden) {
    _load();
  }

  static const _key = 'amounts_hidden';

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    final v = p.getBool(_key) ?? false;
    kAmountsHidden = v;
    state = v;
  }

  Future<void> toggle() async {
    final v = !state;
    kAmountsHidden = v;
    state = v;
    final p = await SharedPreferences.getInstance();
    await p.setBool(_key, v);
  }
}
