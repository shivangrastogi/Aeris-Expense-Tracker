import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/category.dart';
import 'auth_provider.dart';
import 'transactions_provider.dart';

/// The user's own categories, live from their account.
final customCategoriesProvider = StreamProvider<List<ExpenseCategory>>((ref) {
  final uid = ref.watch(currentUserIdProvider);
  if (uid == null) return Stream.value(const <ExpenseCategory>[]);
  return ref.read(firestoreServiceProvider).watchCustomCategories(uid);
});

/// Nicknames for accounts ("4521" → "HDFC salary"), live.
final accountNamesProvider = StreamProvider<Map<String, String>>((ref) {
  final uid = ref.watch(currentUserIdProvider);
  if (uid == null) return Stream.value(const <String, String>{});
  return ref.read(firestoreServiceProvider).watchAccountNames(uid);
});
