import '../models/split.dart';
import '../models/transaction.dart';
import 'firestore_service.dart';
import 'split_links.dart';

/// Shared-bill actions that write to the ledger. Every edit re-reads the
/// transactions it changes, so a stale copy on screen never overwrites newer
/// data.
class SplitService {
  SplitService._();
  static final SplitService instance = SplitService._();

  FirestoreService get _fs => FirestoreService.instance;

  /// Put [split] on [bill] (or change it), then link any paybacks that
  /// already arrived for it. Returns the saved bill.
  Future<Transaction> applySplit(String uid, Transaction bill, SplitInfo split,
      {List<SplitGroup> groups = const []}) async {
    final current = await _fs.fetchTransaction(uid, bill.id) ?? bill;
    // Keep what was already received from people still on the split.
    final before = {
      for (final s in current.split?.shares ?? const <SplitShare>[])
        s.name.toLowerCase(): s.received
    };
    var saved = current.copyWith(
      reviewed: true,
      split: SplitInfo(groupId: split.groupId, shares: [
        for (final s in split.shares)
          s.copyWith(received: before[s.name.toLowerCase()] ?? s.received),
      ]),
    );
    await _fs.updateTransaction(uid, saved);
    saved = await _matchExisting(uid, saved, groups);
    return saved;
  }

  /// Link already-saved, unlinked incoming payments to [bill]'s open shares.
  Future<Transaction> _matchExisting(
      String uid, Transaction bill, List<SplitGroup> groups) async {
    final recent = await _fs.fetchTransactions(uid,
        since: bill.timestamp.subtract(const Duration(days: 15)));
    var current = bill;
    final credits = recent
        .where((t) => t.isCredit && !t.isSettlement && !t.isRefund)
        .toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    for (final c in credits) {
      final hit = SplitLinks.paybackTarget(c, [current], groups);
      if (hit == null) continue;
      current = SplitLinks.receive(current, hit.$2, c.amount);
      await _fs.updateTransaction(
          uid, SplitLinks.markPayback(c, hit.$1, hit.$2));
    }
    if (!identical(current, bill)) await _fs.updateTransaction(uid, current);
    return current;
  }

  /// No longer a shared bill: clears the split and un-links its paybacks
  /// (they count as ordinary money in again).
  Future<void> removeSplit(String uid, Transaction bill) async {
    final current = await _fs.fetchTransaction(uid, bill.id) ?? bill;
    await _fs.updateTransaction(uid, current.copyWith(clearSplit: true));
    final recent = await _fs.fetchTransactions(uid,
        since: bill.timestamp.subtract(const Duration(days: 15)));
    for (final c in recent.where((t) => t.settles == bill.id)) {
      await _fs.updateTransaction(
          uid, c.copyWith(clearSettles: true, categoryId: 'transfer'));
    }
  }

  /// Share [i] of [bill] paid back outside the bank (cash) — or, with
  /// [received] false, not paid after all.
  Future<Transaction> markReceived(String uid, Transaction bill, int i,
      {bool received = true}) async {
    final current = await _fs.fetchTransaction(uid, bill.id) ?? bill;
    final s = current.split!.shares[i];
    final saved = current.copyWith(
        split: current.split!
            .withShare(i, s.copyWith(received: received ? s.amount : 0)));
    await _fs.updateTransaction(uid, saved);
    return saved;
  }

  /// The user says [credit] is share [i] of [bill] paid back.
  Future<void> linkPayback(String uid, Transaction credit, Transaction bill,
      int i, {SplitGroup? group}) async {
    final b = await _fs.fetchTransaction(uid, bill.id) ?? bill;
    await _fs.updateTransaction(uid, SplitLinks.receive(b, i, credit.amount));
    await _fs.updateTransaction(
        uid, SplitLinks.markPayback(credit, b, i).copyWith(reviewed: true));
    if (group != null) {
      final learned =
          SplitLinks.learnHandle(group, b.split!.shares[i].name, credit);
      if (!identical(learned, group)) await _fs.setSplitGroup(uid, learned);
    }
  }

  /// [credit] isn't a payback after all: give the amount back to the share
  /// it was settling and count the credit as ordinary money in again.
  Future<void> unlinkPayback(String uid, Transaction credit) async {
    final billId = credit.settles;
    if (billId == null) return;
    final bill = await _fs.fetchTransaction(uid, billId);
    final split = bill?.split;
    if (bill != null && split != null) {
      final i = split.shares.indexWhere(
          (s) => s.name.toLowerCase() == (credit.settlesMember ?? '').toLowerCase());
      if (i >= 0) {
        final s = split.shares[i];
        final back = s.received - credit.amount;
        await _fs.updateTransaction(
            uid,
            bill.copyWith(
                split: split.withShare(
                    i, s.copyWith(received: back < 0 ? 0 : back))));
      }
    }
    await _fs.updateTransaction(
        uid, credit.copyWith(clearSettles: true, categoryId: 'transfer'));
  }
}
