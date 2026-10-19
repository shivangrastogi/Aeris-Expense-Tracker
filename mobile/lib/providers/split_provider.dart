import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/split.dart';
import '../models/transaction.dart';
import '../services/split_links.dart';
import 'auth_provider.dart';
import 'transactions_provider.dart';

/// The user's split groups ("Flat", "Goa trip"), live.
final splitGroupsProvider = StreamProvider<List<SplitGroup>>((ref) {
  final uid = ref.watch(currentUserIdProvider);
  if (uid == null) return Stream.value(const <SplitGroup>[]);
  return ref.read(firestoreServiceProvider).watchSplitGroups(uid);
});

/// Person → what they still owe the user across all shared bills.
final owedToYouProvider = Provider<Map<String, double>>((ref) {
  final txns = ref.watch(transactionsStreamProvider).valueOrNull ?? const [];
  return SplitLinks.owedToYou(txns);
});

/// One unpaid share on a shared bill.
typedef OpenShare = ({Transaction bill, int index, SplitShare share});

/// Every share not yet paid back, newest bill first.
final openSharesProvider = Provider<List<OpenShare>>((ref) {
  final txns = ref.watch(transactionsStreamProvider).valueOrNull ?? const [];
  final out = <OpenShare>[];
  for (final t in txns) {
    final split = t.split;
    if (split == null) continue;
    for (var i = 0; i < split.shares.length; i++) {
      if (!split.shares[i].settled) {
        out.add((bill: t, index: i, share: split.shares[i]));
      }
    }
  }
  out.sort((a, b) => b.bill.timestamp.compareTo(a.bill.timestamp));
  return out;
});

/// Shared bills (with a split), newest first.
final sharedBillsProvider = Provider<List<Transaction>>((ref) {
  final txns = ref.watch(transactionsStreamProvider).valueOrNull ?? const [];
  return [for (final t in txns) if (t.split != null) t]
    ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
});
