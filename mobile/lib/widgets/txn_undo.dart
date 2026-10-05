import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/transaction.dart';
import '../providers/auth_provider.dart';
import '../providers/transactions_provider.dart';
import 'aeris_toast.dart';

/// Deletes [txns] and offers an UNDO snackbar that restores them exactly
/// (same ids, same data). Receipt photos are only removed once the undo
/// window has passed, so an undo brings those back too.
///
/// Uses the app-wide messenger, so it's safe to call right before popping
/// the current screen — the snackbar stays up on the screen underneath.
Future<void> deleteTransactionsWithUndo(
    BuildContext context, WidgetRef ref, List<Transaction> txns) async {
  final uid = ref.read(currentUserIdProvider);
  if (uid == null || txns.isEmpty) return;
  final fs = ref.read(firestoreServiceProvider);
  final messenger = ScaffoldMessenger.of(context);

  for (final t in txns) {
    await fs.deleteTransaction(uid, t.id);
  }
  HapticFeedback.mediumImpact();

  messenger.hideToast();
  final n = txns.length;
  final controller = messenger.showToast(SnackBar(
    content: Text(n == 1 ? 'Transaction deleted' : '$n transactions deleted'),
    duration: const Duration(seconds: 6),
    behavior: SnackBarBehavior.floating,
    action: SnackBarAction(
      label: 'UNDO',
      onPressed: () async {
        for (final t in txns) {
          await fs.addTransaction(uid, t);
        }
      },
    ),
  ));
  controller.closed.then((reason) async {
    if (reason == SnackBarClosedReason.action) return;
    for (final t in txns.where((t) => t.hasReceipt)) {
      await fs.deleteReceipt(uid, t.id);
    }
  });
}
