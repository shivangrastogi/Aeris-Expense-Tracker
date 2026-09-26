import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/subscription.dart';
import 'auth_provider.dart';
import 'transactions_provider.dart';

/// User-managed recurring subscriptions (Netflix, rent, …), encrypted + synced.
final subscriptionsStreamProvider = StreamProvider<List<Subscription>>((ref) {
  final uid = ref.watch(currentUserIdProvider);
  if (uid == null) return const Stream.empty();
  return ref.read(firestoreServiceProvider).watchSubscriptions(uid);
});

/// Headline totals for the Subs tab.
typedef SubTotals = ({double monthly, double yearly, int count});

final subscriptionTotalsProvider = Provider<SubTotals>((ref) {
  final subs = ref.watch(subscriptionsStreamProvider).valueOrNull ??
      const <Subscription>[];
  final monthly = subs.fold<double>(0, (s, x) => s + x.amount);
  return (monthly: monthly, yearly: monthly * 12, count: subs.length);
});
