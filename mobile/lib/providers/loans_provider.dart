import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/loan.dart';
import 'auth_provider.dart';
import 'transactions_provider.dart';

final loansStreamProvider = StreamProvider<List<Loan>>((ref) {
  final uid = ref.watch(currentUserIdProvider);
  if (uid == null) return const Stream.empty();
  return ref.read(firestoreServiceProvider).watchLoans(uid);
});

/// Headline numbers for the Lent tab: what's still out with friends and
/// what you still owe back.
typedef LoanTotals = ({double owedToYou, double youOwe, int pendingCount});

final loanTotalsProvider = Provider<LoanTotals>((ref) {
  final loans = ref.watch(loansStreamProvider).valueOrNull ?? const <Loan>[];
  double owedToYou = 0, youOwe = 0;
  int pending = 0;
  for (final l in loans) {
    if (l.isSettled) continue;
    pending++;
    if (l.borrowed) {
      youOwe += l.amount;
    } else {
      owedToYou += l.amount;
    }
  }
  return (owedToYou: owedToYou, youOwe: youOwe, pendingCount: pending);
});
