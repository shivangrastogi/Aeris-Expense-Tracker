import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import '../../core/routes.dart';
import '../../core/theme.dart';
import '../../models/category.dart';
import '../../models/transaction.dart';
import '../../providers/accounts_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/transactions_provider.dart';
import '../../services/category_rules.dart';
import '../../services/entry_checks.dart';
import '../../services/merchant_directory.dart';
import '../../services/receipt_scanner.dart';
import '../../services/scan_reader.dart';
import '../../utils/formatters.dart';
import '../../widgets/aeris_toast.dart';
import '../../widgets/ds.dart';
import 'scan_fill_screen.dart';

/// Add transactions from photos: payment-app screenshots (PhonePe, Google
/// Pay, Paytm…), shop bills, or a note written on paper ("Name: Ravi /
/// Amt: 500"). Each is read on-device (see [ScanReader]). A complete one is
/// added straight away as an unreviewed entry; one missing its amount, name
/// or paid/received (or only guessing them) opens prefilled for the user to
/// finish. The photo itself isn't kept — a generated SMS-style text is.
class ScreenshotImportScreen extends ConsumerStatefulWidget {
  /// Images to read straight away (shared into the app). Empty opens the
  /// gallery picker.
  final List<String> initialPaths;

  const ScreenshotImportScreen({super.key, this.initialPaths = const []});

  @override
  ConsumerState<ScreenshotImportScreen> createState() => _State();
}

class _State extends ConsumerState<ScreenshotImportScreen> {
  bool _busy = false;
  int _done = 0, _total = 0;

  // Why the last batch added nothing (shown with a way to try again).
  String? _problem;

  @override
  void initState() {
    super.initState();
    if (widget.initialPaths.isNotEmpty) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _import(widget.initialPaths));
    }
  }

  Future<void> _pick() async {
    List<XFile> picked;
    try {
      // Originals, not downscaled: small text needs every pixel for OCR.
      picked = await ImagePicker().pickMultiImage(limit: 20);
    } catch (_) {
      picked = const [];
    }
    if (!mounted || picked.isEmpty) return;
    await _import([for (final x in picked) x.path]);
  }

  Future<void> _snap() async {
    XFile? shot;
    try {
      shot = await ImagePicker().pickImage(source: ImageSource.camera);
    } catch (_) {}
    if (!mounted || shot == null) return;
    await _import([shot.path]);
  }

  /// Reads every image and saves each payment found. Ones already in AERIS
  /// (or repeated in this batch) are skipped, never added twice.
  Future<void> _import(List<String> paths) async {
    final uid = ref.read(currentUserIdProvider);
    if (uid == null) return;
    setState(() {
      _busy = true;
      _problem = null;
      _done = 0;
      _total = paths.length;
    });
    final fs = ref.read(firestoreServiceProvider);
    final before = ref.read(transactionsStreamProvider).asData?.value ??
        const <Transaction>[];
    final existing = [...before];
    final accounts = {for (final a in ref.read(accountsProvider)) a.key};

    final added = <Transaction>[];
    final toFill = <ScanResult>[];
    final lists = <List<ScanResult>>[];
    var unreadable = 0, duplicates = 0, skipped = 0;
    String? error;

    Future<void> save(ScanResult r, {required bool reviewed}) async {
      if (_isDuplicate(r, existing, before)) {
        duplicates++;
        return;
      }
      try {
        final t = await _toTransaction(r, accounts, reviewed: reviewed);
        await fs.addTransaction(uid, t);
        added.add(t);
        existing.add(t); // so a repeat later in this batch is caught
      } catch (e) {
        error = '$e';
      }
    }

    for (final path in paths) {
      final found = await ReceiptScanner.readAll(path);
      // Read: the text is all that's kept, so drop AERIS's copy of the photo.
      await ReceiptScanner.forget(path);
      if (found.isEmpty) {
        unreadable++;
      } else if (found.length > 1) {
        lists.add(found);
      } else if (found.single.needsInput) {
        toFill.add(found.single);
      } else {
        await save(found.single, reviewed: false); // waits in the review deck
      }
      if (!mounted) return;
      setState(() => _done++);
    }

    // A page listing several entries: separate entries, or one total?
    for (final list in lists) {
      if (!mounted) return;
      final choice = await showScanListChoice(context, list);
      if (choice == null) {
        skipped += list.length;
      } else if (choice.length == 1) {
        toFill.add(choice.single); // one total: still needs a name
      } else {
        for (final r in choice) {
          r.needsInput ? toFill.add(r) : await save(r, reviewed: true);
        }
      }
    }

    // Photos missing something: ask, one at a time, with what was read.
    for (var i = 0; i < toFill.length; i++) {
      if (!mounted) return;
      final filled = await Navigator.of(context).push<ScanResult>(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => ScanFillScreen(
              scan: toFill[i], index: i + 1, count: toFill.length),
        ),
      );
      if (!mounted) return;
      if (filled == null) {
        skipped++;
      } else {
        await save(filled, reviewed: true); // the user just checked it
      }
    }

    if (!mounted) return;
    final notes = [
      if (duplicates > 0) '$duplicates already in AERIS',
      if (skipped > 0) '$skipped skipped',
      if (unreadable > 0) "$unreadable couldn't be read",
    ];
    if (added.isEmpty) {
      setState(() {
        _busy = false;
        _problem = error != null
            ? 'Could not save: $error'
            : unreadable > 0 && ReceiptScanner.modelDownloading
                ? 'The text reader is still downloading (first use only). '
                    'Stay online and try again in a minute.'
                : skipped > 0 && unreadable == 0 && duplicates == 0
                    ? 'Nothing was saved.'
                    : unreadable == 0
                        ? (paths.length == 1
                            ? 'That payment is already in AERIS.'
                            : 'Those payments are already in AERIS.')
                        : duplicates == 0 && skipped == 0
                            ? "Couldn't read any text in "
                                '${paths.length == 1 ? 'that image' : 'those images'}. '
                                'Hold the camera steady over the amount and '
                                'name, in good light.'
                            : 'Nothing new: ${notes.join(', ')}.';
      });
      return;
    }

    HapticFeedback.mediumImpact();
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    final unchecked = added.where((t) => t.needsReview).length;
    nav.pop();
    messenger.hideToast();
    messenger.showToast(SnackBar(
      content: Text([_summary(added), ...notes].join(' · ')),
      action: unchecked == 0
          ? null
          : SnackBarAction(
              label: 'Review',
              onPressed: () => nav.pushNamed(AppRoutes.smsReview),
            ),
    ));
  }

  /// "₹4,750 from Ayush Patel added" for one, "3 added" for many.
  String _summary(List<Transaction> added) {
    if (added.length != 1) return '${added.length} added';
    final t = added.first;
    final amt = formatRupees(t.amount, decimals: t.amount % 1 != 0, raw: true);
    if (t.merchant == null) return '$amt added';
    return '$amt ${t.isCredit ? 'from' : 'to'} ${t.merchant} added';
  }

  /// Already here? The UTR is exact (bank SMS carry the same number);
  /// without one, fall back to same amount + direction around the same time.
  /// A note with no date on it is saved as "now", so re-scanning the same
  /// page tomorrow is caught by matching an earlier scan's amount, direction
  /// and name instead ([before]: what was there before this batch, so two
  /// equal lines on one page both count).
  bool _isDuplicate(
      ScanResult r, List<Transaction> existing, List<Transaction> before) {
    if (r.reference != null &&
        existing.any((t) => t.reference == r.reference)) {
      return true;
    }
    if (r.amount == null || r.direction == null) return false;
    if (r.when == null) {
      final name = r.name?.trim().toLowerCase();
      final since = DateTime.now().subtract(const Duration(days: 2));
      return before.any((t) =>
          t.scanGenerated &&
          t.timestamp.isAfter(since) &&
          t.direction == r.direction &&
          (t.amount - r.amount!).abs() < 0.005 &&
          t.merchant?.trim().toLowerCase() == name);
    }
    return EntryChecks.likelyDuplicate(existing,
            amount: r.amount!,
            direction: r.direction!,
            when: r.when!,
            merchant: r.name,
            window: const Duration(minutes: 30)) !=
        null;
  }

  Future<Transaction> _toTransaction(ScanResult r, Set<String> accounts,
      {required bool reviewed}) async {
    final name = r.name ?? '';
    final dir = r.direction!;
    final when = r.when ?? DateTime.now();
    final learned = await CategoryRules.instance.categoryFor(name);
    // A category written on the paper ("Category: food"), or what the note
    // says it was for — in English, Hinglish ("sabzi") or Hindi ("दवा").
    final written = [r.category, r.note]
        .whereType<String>()
        .map((s) => ScanReader.categoryHint(s) ?? Categories.classify(s))
        .firstWhere((c) => c != 'other', orElse: () => 'other');
    return Transaction(
      id: const Uuid().v4(),
      amount: r.amount!,
      direction: dir,
      timestamp: when,
      merchant: name.isEmpty ? null : name,
      // Tag the account only if it's one the user already tracks.
      account: accounts.contains(r.account) ? r.account : null,
      categoryId: learned ??
          (written != 'other'
              ? written
              : dir == TxnDirection.credit
                  ? 'transfer'
                  : MerchantDirectory.lookup(name)?.categoryId ??
                      MerchantDirectory.lookup(r.upiVpa)?.categoryId ??
                      ScanReader.categoryHint(name) ??
                      Categories.classify(name)),
      note: r.note,
      source: TxnSource.manual,
      // Not the photo: a bank-SMS-style text, signed as generated.
      smsBody: ScanSms.compose(
        amount: r.amount!,
        direction: dir,
        when: when,
        kindLabel: r.kindLabel,
        name: r.name,
        upiVpa: r.upiVpa,
        reference: r.reference,
        account: r.account,
        phone: r.phone,
        note: r.note,
      ),
      smsSender: Transaction.scanSender,
      reviewed: reviewed,
      reference: r.reference,
      upiVpa: r.upiVpa,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: _busy ? _progress() : _idle(),
        ),
      ),
    );
  }

  Widget _progress() => Column(mainAxisSize: MainAxisSize.min, children: [
        CircularProgressIndicator(value: _total == 0 ? null : _done / _total),
        const SizedBox(height: 16),
        Text(_done >= _total
            ? 'Checking…'
            : _total == 1
                ? 'Reading…'
                : 'Reading ${_done + 1} of $_total…'),
      ]);

  Widget _idle() {
    final failed = _problem != null;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(failed ? Ph.imageBroken : Ph.scan,
          size: 60, color: AerisColors.accent(context)),
      const SizedBox(height: 16),
      Text(failed ? 'Nothing added' : 'Scan a payment',
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          textAlign: TextAlign.center),
      const SizedBox(height: 8),
      Text(
        _problem ??
            'A UPI success screen, a shop bill, or a note on paper like '
                '"Name: Ravi · Amount: 500". AERIS reads it on your phone, '
                'fills in what it finds and asks for anything missing.',
        style: TextStyle(color: AerisColors.muted(context)),
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 22),
      FilledButton.icon(
        style: FilledButton.styleFrom(minimumSize: const Size(220, 48)),
        onPressed: _snap,
        icon: const Icon(Ph.camera),
        label: const Text('Take a photo'),
      ),
      const SizedBox(height: 10),
      OutlinedButton.icon(
        style: OutlinedButton.styleFrom(minimumSize: const Size(220, 48)),
        onPressed: _pick,
        icon: const Icon(Ph.images),
        label: Text(failed ? 'Choose others' : 'Choose from gallery'),
      ),
      if (failed)
        TextButton(
          onPressed: () =>
              Navigator.pushReplacementNamed(context, AppRoutes.addTxn),
          child: const Text('Enter it by hand'),
        ),
    ]);
  }
}
