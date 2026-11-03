import 'package:uuid/uuid.dart';

import '../models/loan.dart';
import '../models/transaction.dart';
import 'firestore_service.dart';

/// Loans tied to the payments that move them. A linked payment is neither
/// spend nor income: lending ₹5,000 isn't spending it and getting it back
/// isn't earning it. Each repayment, partial or full, adds to the loan's
/// repaid amount, and the loan closes once it's all back.
class LoanService {
  LoanService._();
  static final LoanService instance = LoanService._();

  FirestoreService get _fs => FirestoreService.instance;

  /// [t] is money lent to (debit) or borrowed from (credit) [person]: starts
  /// a loan for its amount. Returns the linked payment.
  Future<Transaction> startLoan(String uid, Transaction t, String person) async {
    final loan = Loan(
      id: const Uuid().v4(),
      person: person,
      amount: t.amount,
      createdAt: t.timestamp,
      borrowed: t.isCredit,
    );
    await _fs.setLoan(uid, loan);
    final linked = t.copyWith(
        settles: '${Transaction.loanStart}${loan.id}',
        settlesMember: person,
        reviewed: true);
    await _fs.updateTransaction(uid, linked);
    return linked;
  }

  /// [t] pays back part or all of [loan]. Returns the linked payment and the
  /// loan as saved.
  Future<(Transaction, Loan)> repay(
      String uid, Transaction t, Loan loan) async {
    final paid = loan.paid + t.amount;
    final full = paid >= loan.amount - 0.005;
    final saved = loan.copyWith(
        paid: full ? loan.amount : paid,
        settledAt: full ? (loan.settledAt ?? t.timestamp) : null);
    await _fs.setLoan(uid, saved);
    final linked = t.copyWith(
        settles: '${Transaction.loanRepay}${loan.id}',
        settlesMember: loan.person,
        reviewed: true);
    await _fs.updateTransaction(uid, linked);
    return (linked, saved);
  }

  /// [t] pays back a loan that isn't recorded yet: records it ([total] lent
  /// or borrowed, before [t]), then counts [t] against it.
  Future<(Transaction, Loan)> repayNew(
      String uid, Transaction t, String person, double total) async {
    final loan = Loan(
      id: const Uuid().v4(),
      person: person,
      amount: total,
      createdAt: t.timestamp,
      // Money in repays money you lent; money out repays money you borrowed.
      borrowed: t.isDebit,
    );
    return repay(uid, t, loan);
  }

  /// [t] has nothing to do with a loan after all: a repayment's amount comes
  /// off the loan again; the loan a payment started is deleted unless some
  /// of it was already paid back. [loan] is null if it's gone already.
  Future<Transaction> unlink(String uid, Transaction t, Loan? loan) async {
    await _revert(uid, t, loan);
    final plain = t.copyWith(clearSettles: true);
    await _fs.updateTransaction(uid, plain);
    return plain;
  }

  /// Undoes what [t] did to [loan]; returns the loan as saved (null if
  /// deleted or untouched).
  Future<Loan?> _revert(String uid, Transaction t, Loan? loan) async {
    if (loan == null) return null;
    if (t.repaysLoan) {
      final paid = loan.paid - t.amount;
      final left = paid < 0 ? 0.0 : paid;
      final saved = loan.copyWith(
          paid: left,
          settledAt: left >= loan.amount - 0.005 ? loan.settledAt : null);
      await _fs.setLoan(uid, saved);
      return saved;
    }
    if (t.startsLoan && loan.paid <= 0) await _fs.deleteLoan(uid, loan.id);
    return null;
  }

  /// Saves [t] (already written by the edit form) with [link], replacing
  /// whatever loan link [before] had. Returns the payment as saved.
  Future<Transaction> relink(String uid, Transaction? before, Transaction t,
      LoanLink link, Iterable<Loan> loans) async {
    Loan? find(String? id) => loans.where((l) => l.id == id).firstOrNull;
    final old = before != null && before.isLoan ? before : null;
    final oldLoan = find(old?.loanId);

    // Still the payment that started the same loan: keep the loan in step.
    if (old != null &&
        old.startsLoan &&
        link is LoanStart &&
        oldLoan != null &&
        oldLoan.borrowed == t.isCredit) {
      final full = oldLoan.paid >= t.amount - 0.005;
      await _fs.setLoan(
          uid,
          oldLoan.copyWith(
              person: link.person,
              amount: t.amount,
              paid: full ? t.amount : oldLoan.paid,
              settledAt: full ? (oldLoan.settledAt ?? DateTime.now()) : null));
      final linked =
          t.copyWith(settles: old.settles, settlesMember: link.person);
      await _fs.updateTransaction(uid, linked);
      return linked;
    }

    var target = link is LoanRepay ? link.loan : null;
    if (old != null) {
      final reverted = await _revert(uid, old, oldLoan);
      // Repaying the same loan again: count from its reverted state.
      if (reverted != null && reverted.id == target?.id) target = reverted;
    }
    final plain = t.copyWith(clearSettles: true);
    switch (link) {
      case LoanNone():
        await _fs.updateTransaction(uid, plain);
        return plain;
      case LoanStart(:final person):
        return startLoan(uid, plain, person);
      case LoanRepay():
        return (await repay(uid, plain, target!)).$1;
      case LoanRepayNew(:final person, :final total):
        return (await repayNew(uid, plain, person, total)).$1;
    }
  }
}

/// What the edit form ties a payment to.
sealed class LoanLink {
  const LoanLink();
}

/// An ordinary payment: no loan.
class LoanNone extends LoanLink {
  const LoanNone();
}

/// Money lent to (out) or borrowed from (in) [person].
class LoanStart extends LoanLink {
  final String person;
  const LoanStart(this.person);
}

/// Pays back part or all of [loan].
class LoanRepay extends LoanLink {
  final Loan loan;
  const LoanRepay(this.loan);
}

/// Pays back a loan of [total] with [person] that isn't recorded yet.
class LoanRepayNew extends LoanLink {
  final String person;
  final double total;
  const LoanRepayNew(this.person, this.total);
}
