import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/transaction.dart';
import '../services/firestore_service.dart';
import '../services/quote_service.dart';
import 'auth_provider.dart';

final firestoreServiceProvider =
    Provider<FirestoreService>((_) => FirestoreService.instance);

/// Motivational quotes for the Home carousel (online, offline fallback).
final quoteProvider =
    FutureProvider<List<Quote>>((_) => QuoteService.fetchMany(6));

/// Progress of an in-flight SMS backfill: null = idle, else (done, total).
final importProgressProvider =
    StateProvider<({int done, int total})?>((_) => null);

/// Live stream of all transactions for the signed-in user.
final transactionsStreamProvider = StreamProvider<List<Transaction>>((ref) {
  final uid = ref.watch(currentUserIdProvider);
  if (uid == null) return const Stream.empty();
  return ref.read(firestoreServiceProvider).watchTransactions(uid);
});

/// Most-recent N transactions for the dashboard.
///
/// Derived in-memory from [transactionsStreamProvider] instead of opening a
/// second Firestore listener for overlapping data — the full stream is already
/// ordered newest-first, so we just take the first N.
final recentTransactionsProvider =
    Provider.family<AsyncValue<List<Transaction>>, int>((ref, limit) {
  return ref
      .watch(transactionsStreamProvider)
      .whenData((list) => list.take(limit).toList());
});

/// Senders the user has blocked — their SMS are never imported.
final blockedSendersProvider = StreamProvider<Set<String>>((ref) {
  final uid = ref.watch(currentUserIdProvider);
  if (uid == null) return Stream.value(<String>{});
  return ref.read(firestoreServiceProvider).watchBlockedSenders(uid);
});

/// Manual fetch — used by analytics when we want non-streaming snapshots.
final transactionsSinceProvider =
    FutureProvider.family<List<Transaction>, DateTime>((ref, since) async {
  final uid = ref.watch(currentUserIdProvider);
  if (uid == null) return const [];
  return ref.read(firestoreServiceProvider).fetchTransactions(uid, since: since);
});
