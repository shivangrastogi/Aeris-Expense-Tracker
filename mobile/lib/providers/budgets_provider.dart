import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/budget.dart';
import 'auth_provider.dart';
import 'transactions_provider.dart';

final budgetsStreamProvider = StreamProvider<List<Budget>>((ref) {
  final uid = ref.watch(currentUserIdProvider);
  if (uid == null) return const Stream.empty();
  return ref.read(firestoreServiceProvider).watchBudgets(uid);
});
