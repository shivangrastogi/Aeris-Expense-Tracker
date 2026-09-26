import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/currency.dart';
import '../utils/formatters.dart';

/// The user's selected display currency. Mirrors into the [kCurrency] global
/// that `formatRupees` reads — amounts are stored in INR and converted for
/// display only. Persists the choice so it survives restarts.
final currencyProvider = StateNotifierProvider<CurrencyController, Currency>(
    (ref) => CurrencyController());

class CurrencyController extends StateNotifier<Currency> {
  CurrencyController() : super(kCurrency) {
    _load();
  }

  static const _key = 'currency_code';

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    final code = p.getString(_key);
    if (code != null) {
      final c = Currencies.byCode(code);
      kCurrency = c;
      state = c;
    }
  }

  Future<void> setCurrency(String code) async {
    final c = Currencies.byCode(code);
    kCurrency = c;
    state = c;
    final p = await SharedPreferences.getInstance();
    await p.setString(_key, code);
  }
}
