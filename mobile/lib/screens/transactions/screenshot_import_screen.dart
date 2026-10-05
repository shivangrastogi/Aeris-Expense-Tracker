import 'dart:io';
import 'dart:ui' as ui;

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
import '../../services/payment_shot_parser.dart';
import '../../services/receipt_scanner.dart';
import '../../utils/formatters.dart';
import '../../widgets/aeris_toast.dart';
import '../../widgets/receipt_field.dart';

/// Add transactions from payment-app screenshots (PhonePe, Google Pay,
/// Paytm…). Pick one or many: each is read on-device and added straight away,
/// with the screenshot as its receipt, as an unreviewed entry — so the whole
/// batch waits in the review deck to be checked afterwards.
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.initialPaths.isEmpty ? _pick() : _import(widget.initialPaths);
    });
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
    final existing = [
      ...ref.read(transactionsStreamProvider).asData?.value ??
          const <Transaction>[],
    ];
    final accounts = {for (final a in ref.read(accountsProvider)) a.key};

    final added = <Transaction>[];
    var unreadable = 0, duplicates = 0;
    String? error;
    for (final path in paths) {
      final p = await ReceiptScanner.scanPayment(path);
      if (p == null) {
        unreadable++;
      } else if (_isDuplicate(p, existing)) {
        duplicates++;
      } else {
        try {
          final image = await _receiptBytes(path);
          final t = await _toTransaction(p, accounts, hasReceipt: image != null);
          await fs.addTransaction(uid, t);
          if (image != null) await fs.setReceipt(uid, t.id, image);
          added.add(t);
          existing.add(t); // so a repeat later in this batch is caught
        } catch (e) {
          error = '$e';
        }
      }
      if (!mounted) return;
      setState(() => _done++);
    }

    final notes = [
      if (duplicates > 0) '$duplicates already in AERIS',
      if (unreadable > 0) "$unreadable couldn't be read",
    ];
    if (added.isEmpty) {
      setState(() {
        _busy = false;
        _problem = error != null
            ? 'Could not save: $error'
            : unreadable == 0
                ? (paths.length == 1
                    ? 'That payment is already in AERIS.'
                    : 'Those payments are already in AERIS.')
                : duplicates == 0
                    ? "Couldn't find a payment in "
                        '${paths.length == 1 ? 'that image' : 'those images'}. '
                        'Use the success screen from PhonePe, Google Pay or '
                        'Paytm, with the amount and name visible.'
                    : 'Nothing new: ${notes.join(', ')}.';
      });
      return;
    }

    HapticFeedback.mediumImpact();
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    nav.pop();
    messenger.hideToast();
    messenger.showToast(SnackBar(
      content: Text([_summary(added), ...notes].join(' · ')),
      action: SnackBarAction(
        label: 'Review',
        onPressed: () => nav.pushNamed(AppRoutes.smsReview),
      ),
    ));
  }

  /// "₹4,750 from Ayush Patel added" for one, "3 added to review" for many.
  String _summary(List<Transaction> added) {
    if (added.length != 1) return '${added.length} added to review';
    final t = added.first;
    final amt = formatRupees(t.amount, decimals: t.amount % 1 != 0, raw: true);
    if (t.merchant == null) return '$amt added';
    return '$amt ${t.isCredit ? 'from' : 'to'} ${t.merchant} added';
  }

  /// Already here? The UTR is exact (bank SMS carry the same number);
  /// without one, fall back to same amount + direction around the same time.
  bool _isDuplicate(PaymentShot p, List<Transaction> existing) {
    if (p.reference != null &&
        existing.any((t) => t.reference == p.reference)) {
      return true;
    }
    if (p.when == null) return false;
    return EntryChecks.likelyDuplicate(existing,
            amount: p.amount,
            direction: p.direction,
            when: p.when!,
            merchant: p.name,
            window: const Duration(minutes: 30)) !=
        null;
  }

  Future<Transaction> _toTransaction(PaymentShot p, Set<String> accounts,
      {required bool hasReceipt}) async {
    final name = p.name ?? '';
    final learned = await CategoryRules.instance.categoryFor(name);
    return Transaction(
      id: const Uuid().v4(),
      amount: p.amount,
      direction: p.direction,
      timestamp: p.when ?? DateTime.now(),
      merchant: name.isEmpty ? null : name,
      // Tag the account only if it's one the user already tracks.
      account: accounts.contains(p.account) ? p.account : null,
      categoryId: learned ??
          (p.direction == TxnDirection.credit
              ? 'transfer'
              : MerchantDirectory.lookup(name)?.categoryId ??
                  MerchantDirectory.lookup(p.upiVpa)?.categoryId ??
                  Categories.classify(name)),
      source: TxnSource.manual,
      reviewed: false, // waits in the review deck, like an SMS import
      reference: p.reference,
      upiVpa: p.upiVpa,
      hasReceipt: hasReceipt,
    );
  }

  /// The image as stored with the transaction: as-is when small enough, else
  /// scaled down; null if it still won't fit (the entry saves without it).
  Future<Uint8List?> _receiptBytes(String path) async {
    try {
      final raw = await File(path).readAsBytes();
      if (raw.length <= kMaxReceiptBytes) return raw;
      final codec = await ui.instantiateImageCodec(raw, targetHeight: 1400);
      final img = (await codec.getNextFrame()).image;
      final png = await img.toByteData(format: ui.ImageByteFormat.png);
      img.dispose();
      final out = png?.buffer.asUint8List();
      return out == null || out.length > kMaxReceiptBytes ? null : out;
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('From screenshots')),
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
        Text(_total == 1 ? 'Reading…' : 'Reading $_done of $_total…'),
      ]);

  Widget _idle() {
    final failed = _problem != null;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(failed ? Icons.image_not_supported_outlined : Icons.image_search,
          size: 60, color: AerisColors.accent(context)),
      const SizedBox(height: 16),
      Text(failed ? 'Nothing added' : 'Add from payment screenshots',
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          textAlign: TextAlign.center),
      const SizedBox(height: 8),
      Text(
        _problem ??
            'Pick one or many success screens from PhonePe, Google Pay, Paytm '
                'or any UPI app. AERIS reads each one on your phone and adds '
                'them all for you to review.',
        style: TextStyle(color: AerisColors.muted(context)),
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 22),
      FilledButton.icon(
        onPressed: _pick,
        icon: const Icon(Icons.photo_library_outlined),
        label: Text(failed ? 'Choose others' : 'Choose screenshots'),
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
