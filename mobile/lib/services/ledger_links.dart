import '../models/transaction.dart';

/// Relationships between auto-imported transactions — pure logic, no I/O, so
/// it runs the same at import time, in the one-time history repair and in
/// tests.
///
///  * [duplicateOf] — the same payment reported twice: the bank's SMS and the
///    UPI app's SMS/notification, or two alerts from one bank.
///  * [transferPartner] — money moved between two of YOUR accounts. One leg
///    is a debit, the other a credit; together they are neither spend nor
///    income.
///  * [refundedPurchase] — the purchase a refund gives money back for.
class LedgerLinks {
  LedgerLinks._();

  static const _dupWindow = Duration(minutes: 10);
  static const _weakTransferWindow = Duration(minutes: 30);
  static const _strongTransferWindow = Duration(days: 3);
  static const _refundWindow = Duration(days: 90);

  static bool _auto(Transaction t) => t.source == TxnSource.sms;

  static bool _sameAmount(Transaction a, Transaction b) =>
      (a.amount - b.amount).abs() < 0.01;

  static Duration _gap(Transaction a, Transaction b) =>
      a.timestamp.difference(b.timestamp).abs();

  /// Reference digits, or null when there are too few to be an id.
  static String? _ref(Transaction t) {
    final d = (t.reference ?? '').replaceAll(RegExp(r'\D'), '');
    return d.length >= 6 ? d : null;
  }

  static bool _sameRef(String a, String b) {
    if (a == b) return true;
    // One side may print a shortened id ("…12345678").
    final (short, long) = a.length <= b.length ? (a, b) : (b, a);
    return short.length >= 6 && long.endsWith(short);
  }

  /// Account fragments match when one ends with the other ("268" vs
  /// "XXXX0268" printed by a different bank as "0268").
  static bool _sameAccount(String a, String b) {
    final (short, long) = a.length <= b.length ? (a, b) : (b, a);
    return short.length >= 3 && long.endsWith(short);
  }

  /// The already-saved transaction that [t] reports again, or null.
  ///
  /// Matching references settle it either way. Without references, the same
  /// amount and direction within 10 minutes from a DIFFERENT sender (bank vs
  /// UPI app) on a compatible account is the same payment; from the same
  /// sender it is not — two ₹20 chais are two payments.
  static Transaction? duplicateOf(Transaction t, Iterable<Transaction> saved) {
    if (!_auto(t)) return null;
    final ref = _ref(t);
    for (final s in saved) {
      if (s.id == t.id || !_auto(s)) continue;
      if (s.direction != t.direction || !_sameAmount(s, t)) continue;
      final sRef = _ref(s);
      if (ref != null && sRef != null) {
        if (_sameRef(ref, sRef) && _gap(s, t) <= const Duration(days: 2)) {
          return s;
        }
        continue;
      }
      if (_gap(s, t) > _dupWindow) continue;
      if (s.smsSender == t.smsSender) continue;
      final a = s.account, b = t.account;
      if (a != null && b != null && !_sameAccount(a, b)) continue;
      return s;
    }
    return null;
  }

  /// "A/c ••5174" — a payee that is an account, as the parser names it.
  static final _acctPayee = RegExp(r'^A/c ••(\d{3,6})$');

  static bool _isAccountOrNone(Transaction t) =>
      t.merchant == null || _acctPayee.hasMatch(t.merchant!);

  /// The other leg of a transfer between your own accounts, or null.
  ///
  /// Strong evidence: one leg names the other's account as its counterparty
  /// ("…; A/C XXXX5174 credited" and a credit alert on your ••5174) — matched
  /// up to 3 days apart. Weak evidence: same amount, opposite directions, on
  /// two different accounts of yours within 30 minutes, and neither side
  /// names a person or shop.
  static Transaction? transferPartner(
      Transaction t, Iterable<Transaction> saved) {
    if (!_auto(t) || t.selfTransfer || t.account == null || t.isRefund) {
      return null;
    }
    Transaction? weak;
    for (final s in saved) {
      if (s.id == t.id || !_auto(s) || s.selfTransfer || s.isRefund) continue;
      if (s.direction == t.direction || !_sameAmount(s, t)) continue;
      final sa = s.account;
      if (sa == null || _sameAccount(sa, t.account!)) continue;
      final gap = _gap(s, t);
      if (gap <= _strongTransferWindow &&
          (_names(t.merchant, sa) || _names(s.merchant, t.account!))) {
        return s;
      }
      if (weak == null &&
          gap <= _weakTransferWindow &&
          _isAccountOrNone(s) &&
          _isAccountOrNone(t)) {
        weak = s;
      }
    }
    return weak;
  }

  static bool _names(String? payee, String account) {
    final m = _acctPayee.firstMatch(payee ?? '');
    return m != null && _sameAccount(m.group(1)!, account);
  }

  static Set<String> _words(String? s) => (s ?? '')
      .toLowerCase()
      .split(RegExp(r'[^a-z0-9]+'))
      .where((w) => w.length >= 3)
      .toSet();

  /// The purchase [refund] gives money back for, or null.
  ///
  /// Same payee (shared name word or same UPI id), bought before the refund
  /// within 90 days, for at least the refunded amount; an exact amount wins,
  /// then the most recent. A refund with no payee only links to a purchase
  /// of exactly that amount, and only if there's just one.
  static Transaction? refundedPurchase(
      Transaction refund, Iterable<Transaction> saved) {
    if (!refund.isRefund) return null;
    final words = _words(refund.merchant);
    final candidates = <Transaction>[];
    for (final s in saved) {
      if (s.id == refund.id || !s.isDebit || s.selfTransfer) continue;
      if (s.timestamp.isAfter(refund.timestamp)) continue;
      if (refund.timestamp.difference(s.timestamp) > _refundWindow) continue;
      if (s.amount + 0.01 < refund.amount) continue;
      final samePayee = (refund.upiVpa != null && refund.upiVpa == s.upiVpa) ||
          words.intersection(_words(s.merchant)).isNotEmpty;
      if (words.isEmpty && refund.upiVpa == null) {
        if (_sameAmount(s, refund)) candidates.add(s);
      } else if (samePayee) {
        candidates.add(s);
      }
    }
    if (candidates.isEmpty) return null;
    if (words.isEmpty && refund.upiVpa == null && candidates.length > 1) {
      return null;
    }
    candidates.sort((a, b) {
      final ea = _sameAmount(a, refund), eb = _sameAmount(b, refund);
      if (ea != eb) return ea ? -1 : 1;
      return b.timestamp.compareTo(a.timestamp);
    });
    return candidates.first;
  }

  /// [kept] with anything [dup] knew that [kept] didn't (payee, UPI id,
  /// reference, balance) — so merging the two loses nothing.
  static Transaction enrich(Transaction kept, Transaction dup) {
    final keptPayeeWeak = _isAccountOrNone(kept);
    return Transaction(
      id: kept.id,
      amount: kept.amount,
      direction: kept.direction,
      timestamp: kept.timestamp,
      categoryId: keptPayeeWeak && !_isAccountOrNone(dup)
          ? dup.categoryId
          : kept.categoryId,
      merchant:
          keptPayeeWeak && dup.merchant != null ? dup.merchant : kept.merchant,
      account: kept.account ?? dup.account,
      note: kept.note ?? dup.note,
      source: kept.source,
      smsBody: kept.smsBody,
      smsSender: kept.smsSender,
      reviewed: kept.reviewed,
      reference: kept.reference ?? dup.reference,
      upiVpa: kept.upiVpa ?? dup.upiVpa,
      hasReceipt: kept.hasReceipt,
      balance: kept.balance ?? dup.balance,
      linkId: kept.linkId,
      selfTransfer: kept.selfTransfer,
      split: kept.split ?? dup.split,
      settles: kept.settles ?? dup.settles,
      settlesMember: kept.settles != null ? kept.settlesMember : dup.settlesMember,
    );
  }

  /// Both legs marked as a transfer between your own accounts.
  static (Transaction, Transaction) pairTransfer(Transaction a, Transaction b) =>
      (
        a.copyWith(selfTransfer: true, linkId: b.id, categoryId: 'transfer'),
        b.copyWith(selfTransfer: true, linkId: a.id, categoryId: 'transfer'),
      );
}
