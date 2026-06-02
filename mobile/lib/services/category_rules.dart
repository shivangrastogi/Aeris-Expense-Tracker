import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Remembers the user's merchant → category corrections so future SMS from the
/// same merchant auto-tag to the right category. Stored on-device (works in
/// the background isolate too) with an in-memory cache.
class CategoryRules {
  CategoryRules._();
  static final CategoryRules instance = CategoryRules._();

  static const _key = 'category_rules';
  Map<String, String>? _cache;

  String _norm(String m) => m.toLowerCase().trim();

  Future<Map<String, String>> _load() async {
    if (_cache != null) return _cache!;
    final raw = (await SharedPreferences.getInstance()).getString(_key);
    _cache = raw == null
        ? <String, String>{}
        : Map<String, String>.from(jsonDecode(raw) as Map);
    return _cache!;
  }

  /// The learned category for a merchant, or null if none.
  Future<String?> categoryFor(String? merchant) async {
    if (merchant == null || merchant.trim().isEmpty) return null;
    return (await _load())[_norm(merchant)];
  }

  /// Remember that [merchant] should map to [categoryId].
  Future<void> remember(String? merchant, String categoryId) async {
    if (merchant == null || merchant.trim().isEmpty) return;
    final rules = await _load();
    rules[_norm(merchant)] = categoryId;
    await (await SharedPreferences.getInstance()).setString(_key, jsonEncode(rules));
  }
}
