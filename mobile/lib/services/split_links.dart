import '../models/split.dart';
import '../models/transaction.dart';

/// Shared-bill logic — pure, no I/O, so import, the UI and tests all use the
/// same rules.
///
///  * [shareOut] — divide a bill among a group by weight (equal by default).
///  * [autoGroupFor] — the group a payment auto-splits into (its payee is on
///    the group's list, e.g. the landlord's UPI ID).
///  * [paybackTarget] — which open share an incoming payment pays back.
///  * [owedToYou] — what each person still owes across all bills.
class SplitLinks {
  SplitLinks._();

  static const _before = Duration(days: 60); // payback after the bill
  static const _after = Duration(days: 15); // …or paid ahead of it

  static double _round2(double v) => (v * 100).roundToDouble() / 100;

  /// [amount] divided among the group's members and the user by weight.
  /// The user's share absorbs rounding, so the shares never exceed the bill.
  static SplitInfo shareOut(SplitGroup g, double amount,
      {Iterable<SplitMember>? only}) {
    final members = (only ?? g.members).toList();
    final total = members.fold<double>(g.myWeight, (s, m) => s + m.weight);
    return SplitInfo(groupId: g.id, shares: [
      for (final m in members)
        SplitShare(name: m.name, amount: _round2(amount * m.weight / total)),
    ]);
  }

  /// Payee keys a payment is known by: its UPI ID and payee name, lower-case.
  static Set<String> payeeKeys(Transaction t) => {
        if (t.upiVpa != null && t.upiVpa!.isNotEmpty) t.upiVpa!.toLowerCase(),
        if (t.merchant != null && t.merchant!.trim().isNotEmpty)
          t.merchant!.trim().toLowerCase(),
      };

  /// The group [debit] splits into automatically, or null.
  static SplitGroup? autoGroupFor(Transaction debit, Iterable<SplitGroup> groups) {
    if (!debit.isDebit || debit.split != null || debit.selfTransfer) return null;
    final keys = payeeKeys(debit);
    if (keys.isEmpty) return null;
    for (final g in groups) {
      if (g.autoPayees.any(keys.contains)) return g;
    }
    return null;
  }

  static Set<String> _words(String? s) => (s ?? '')
      .toLowerCase()
      .split(RegExp(r'[^a-z0-9]+'))
      .where((w) => w.length >= 3)
      .toSet();

  /// Does [credit] come from the person called [name]? Their UPI ID / payer
  /// name shares a word with the name, or is one of their learned handles.
  static bool _fromPerson(Transaction credit, String name, SplitMember? member) {
    final keys = payeeKeys(credit);
    if (member != null && member.handles.any(keys.contains)) return true;
    final nameWords = _words(name);
    if (nameWords.isEmpty) return false;
    final vpaUser = credit.upiVpa?.split('@').first;
    final payer = {..._words(credit.merchant), ..._words(vpaUser)};
    if (payer.intersection(nameWords).isNotEmpty) return true;
    // "rahulsharma99@ybl" contains "rahul".
    return vpaUser != null &&
        nameWords.any((w) => vpaUser.toLowerCase().contains(w));
  }

  /// A payer the bank SMS couldn't name ("A/c ••5174", or nothing).
  static bool _anonymous(Transaction t) =>
      t.upiVpa == null &&
      (t.merchant == null || t.merchant!.startsWith('A/c ••'));

  /// The open share [credit] pays back: `(bill, share index)`, or null.
  ///
  /// A payment from someone named on a share (by name, UPI ID or a handle
  /// learned from an earlier payback) for no more than what they still owe
  /// settles it — the exact amount first, then the most recent bill. A
  /// payment whose payer the SMS doesn't name only settles a share it
  /// matches to the rupee, and only when exactly one share does.
  static (Transaction, int)? paybackTarget(Transaction credit,
      Iterable<Transaction> saved, Iterable<SplitGroup> groups) {
    if (!credit.isCredit ||
        credit.isRefund ||
        credit.selfTransfer ||
        credit.isSettlement) {
      return null;
    }
    final byId = {for (final g in groups) g.id: g};
    final named = <(Transaction, int)>[];
    final exactAnon = <(Transaction, int)>[];
    for (final bill in saved) {
      final split = bill.split;
      if (split == null || bill.id == credit.id || !bill.isDebit) continue;
      if (credit.timestamp.isBefore(bill.timestamp.subtract(_after)) ||
          credit.timestamp.isAfter(bill.timestamp.add(_before))) {
        continue;
      }
      final group = byId[split.groupId];
      for (var i = 0; i < split.shares.length; i++) {
        final s = split.shares[i];
        if (s.settled || credit.amount > s.outstanding + 0.5) continue;
        final member = group?.members
            .where((m) => m.name.toLowerCase() == s.name.toLowerCase())
            .firstOrNull;
        if (_fromPerson(credit, s.name, member)) {
          named.add((bill, i));
        } else if (_anonymous(credit) &&
            (s.outstanding - credit.amount).abs() < 0.5) {
          exactAnon.add((bill, i));
        }
      }
    }
    if (named.isNotEmpty) {
      named.sort((a, b) {
        final ea = (a.$1.split!.shares[a.$2].outstanding - credit.amount).abs() < 0.5;
        final eb = (b.$1.split!.shares[b.$2].outstanding - credit.amount).abs() < 0.5;
        if (ea != eb) return ea ? -1 : 1;
        return b.$1.timestamp.compareTo(a.$1.timestamp);
      });
      return named.first;
    }
    return exactAnon.length == 1 ? exactAnon.single : null;
  }

  /// [bill] with [amount] more received on share [i].
  static Transaction receive(Transaction bill, int i, double amount) {
    final s = bill.split!.shares[i];
    return bill.copyWith(
        split: bill.split!.withShare(i, s.copyWith(received: s.received + amount)));
  }

  /// [credit] marked as paying back share [i] of [bill]; it takes the bill's
  /// category so lists read "Rent · from Rahul".
  static Transaction markPayback(Transaction credit, Transaction bill, int i) =>
      credit.copyWith(
        settles: bill.id,
        settlesMember: bill.split!.shares[i].name,
        categoryId: bill.categoryId,
      );

  /// [g] having learned that [member] pays from [credit]'s UPI ID / name.
  static SplitGroup learnHandle(SplitGroup g, String member, Transaction credit) {
    final keys = payeeKeys(credit)..removeWhere((k) => k.startsWith('a/c ••'));
    if (keys.isEmpty) return g;
    var changed = false;
    final members = [
      for (final m in g.members)
        if (m.name.toLowerCase() == member.toLowerCase() &&
            !keys.every(m.handles.contains))
          () {
            changed = true;
            return m.copyWith(handles: {...m.handles, ...keys}.toList());
          }()
        else
          m
    ];
    return changed ? g.copyWith(members: members) : g;
  }

  /// What each person still owes the user, across every split bill.
  static Map<String, double> owedToYou(Iterable<Transaction> txns) {
    final out = <String, double>{};
    for (final t in txns) {
      for (final s in t.split?.shares ?? const <SplitShare>[]) {
        if (s.outstanding >= 0.5) out[s.name] = (out[s.name] ?? 0) + s.outstanding;
      }
    }
    return out;
  }
}
