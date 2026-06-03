import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';

import '../../models/category.dart';
import '../../models/transaction.dart';
import '../../providers/auth_provider.dart';
import '../../providers/transactions_provider.dart';
import '../../services/statement_import_service.dart';
import '../../utils/formatters.dart';

class StatementImportScreen extends ConsumerStatefulWidget {
  const StatementImportScreen({super.key});
  @override
  ConsumerState<StatementImportScreen> createState() => _State();
}

enum _Stage { idle, parsing, password, review, importing }

class _State extends ConsumerState<StatementImportScreen> {
  _Stage _stage = _Stage.idle;
  String? _error;

  // Picked file (kept so we can retry with a PDF password without re-picking).
  Uint8List? _bytes;
  String _ext = '';
  String _name = '';
  final _password = TextEditingController();

  ParsedStatement? _parsed;
  int _done = 0, _total = 0;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    setState(() => _error = null);
    try {
      final res = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'csv', 'xlsx', 'xls', 'txt'],
        withData: true,
      );
      if (res == null || res.files.isEmpty) return;
      final f = res.files.first;
      if (f.bytes == null) {
        setState(() => _error = 'Could not read that file.');
        return;
      }
      _bytes = f.bytes;
      _ext = (f.extension ?? '').toLowerCase();
      _name = f.name;
      await _parse();
    } catch (e) {
      setState(() => _error = '$e');
    }
  }

  Future<void> _parse({String? password}) async {
    if (_bytes == null) return;
    setState(() {
      _stage = _Stage.parsing;
      _error = null;
    });
    try {
      final parsed = await StatementImportService.instance.parseBytes(
        _bytes!,
        _ext,
        fileName: _name,
        pdfPassword: password,
      );
      _parsed = parsed;
      _markDuplicates();
      if (!mounted) return;
      if (parsed.txns.isEmpty) {
        setState(() {
          _stage = _Stage.idle;
          _error = 'No transactions could be read from this file. '
              '${parsed.isTabular ? 'Try mapping the columns manually.' : 'The PDF layout may not be supported — try a CSV/Excel export.'}';
        });
      } else {
        setState(() => _stage = _Stage.review);
      }
    } on StatementException catch (e) {
      if (!mounted) return;
      if (e.needsPassword) {
        setState(() => _stage = _Stage.password);
      } else {
        setState(() {
          _stage = _Stage.idle;
          _error = e.message;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _stage = _Stage.idle;
        _error = '$e';
      });
    }
  }

  void _markDuplicates() {
    final existing = ref.read(transactionsStreamProvider).asData?.value ?? [];
    for (final c in _parsed!.txns) {
      final dup = existing.any((t) =>
          t.direction == c.direction &&
          (t.amount - c.amount).abs() < 0.5 &&
          t.timestamp.year == c.date.year &&
          t.timestamp.month == c.date.month &&
          t.timestamp.day == c.date.day);
      c.duplicate = dup;
      if (dup) c.selected = false;
    }
  }

  Future<void> _import() async {
    final uid = ref.read(currentUserIdProvider);
    if (uid == null || _parsed == null) return;
    final selected = _parsed!.txns.where((t) => t.selected).toList();
    if (selected.isEmpty) return;
    setState(() {
      _stage = _Stage.importing;
      _done = 0;
      _total = selected.length;
    });
    try {
      final saved = await StatementImportService.instance.importSelected(
        uid,
        selected,
        onProgress: (d, t) {
          if (mounted) setState(() { _done = d; _total = t; });
        },
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Imported $saved transaction${saved == 1 ? '' : 's'}.')),
      );
      Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() { _stage = _Stage.review; _error = '$e'; });
    }
  }

  // ── Column mapping (tabular files) ──
  void _openMapping() {
    final p = _parsed!;
    final header = p.table.isNotEmpty ? p.table[p.headerRow] : <String>[];
    var map = p.map;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          Widget picker(String label, ColumnRole role, int current) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(children: [
                SizedBox(width: 110, child: Text(label)),
                Expanded(
                  child: DropdownButton<int>(
                    isExpanded: true,
                    value: current,
                    items: [
                      const DropdownMenuItem(value: -1, child: Text('(none)')),
                      for (var i = 0; i < header.length; i++)
                        DropdownMenuItem(
                          value: i,
                          child: Text(
                            header[i].trim().isEmpty ? 'Column ${i + 1}' : header[i].trim(),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (v) => setSheet(() => map = map.withRole(role, v ?? -1)),
                  ),
                ),
              ]),
            );
          }

          return Padding(
            padding: EdgeInsets.fromLTRB(
                20, 4, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('Map columns',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
              const SizedBox(height: 4),
              const Text('Tell AERIS which column is which. Use Debit/Credit '
                  'for separate columns, or Amount (+ Type) for a single column.',
                  style: TextStyle(fontSize: 12), textAlign: TextAlign.center),
              const SizedBox(height: 10),
              picker('Date', ColumnRole.date, map.dateCol),
              picker('Description', ColumnRole.description, map.descCol),
              picker('Debit', ColumnRole.debit, map.debitCol),
              picker('Credit', ColumnRole.credit, map.creditCol),
              picker('Amount', ColumnRole.amount, map.amountCol),
              picker('Type (Dr/Cr)', ColumnRole.type, map.typeCol),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: map.hasAmountSource
                      ? () {
                          final txns = StatementImportService.instance
                              .applyMapping(p.table, p.headerRow, map);
                          setState(() {
                            _parsed = ParsedStatement(
                              isTabular: true,
                              table: p.table,
                              headerRow: p.headerRow,
                              map: map,
                              txns: txns,
                              fileName: p.fileName,
                            );
                            _markDuplicates();
                          });
                          Navigator.pop(ctx);
                        }
                      : null,
                  child: const Text('Apply mapping'),
                ),
              ),
              if (!map.hasAmountSource)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text('Pick at least a Debit/Credit or Amount column.',
                      style: TextStyle(color: Colors.orange, fontSize: 12)),
                ),
            ]),
          );
        },
      ),
    );
  }

  // ── Per-row edit ──
  void _editRow(StatementTxn t) {
    final amount = TextEditingController(text: t.amount.toStringAsFixed(2));
    final desc = TextEditingController(text: t.description);
    var dir = t.direction;
    var cat = t.categoryId;
    var date = t.date;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('Edit transaction'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              SegmentedButton<TxnDirection>(
                segments: const [
                  ButtonSegment(value: TxnDirection.debit, label: Text('Expense')),
                  ButtonSegment(value: TxnDirection.credit, label: Text('Income')),
                ],
                selected: {dir},
                onSelectionChanged: (s) => setD(() => dir = s.first),
              ),
              const SizedBox(height: 10),
              TextField(controller: amount, keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Amount (₹)')),
              const SizedBox(height: 10),
              TextField(controller: desc,
                  decoration: const InputDecoration(labelText: 'Description')),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: cat,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Category'),
                items: [
                  for (final c in Categories.all)
                    DropdownMenuItem(value: c.id, child: Text(c.label)),
                ],
                onChanged: (v) => setD(() => cat = v ?? cat),
              ),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: Text('Date: ${DateFormat('d MMM yyyy').format(date)}')),
                TextButton(
                  onPressed: () async {
                    final d = await showDatePicker(
                      context: ctx,
                      initialDate: date,
                      firstDate: DateTime(2015),
                      lastDate: DateTime.now(),
                    );
                    if (d != null) setD(() => date = d);
                  },
                  child: const Text('Change'),
                ),
              ]),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                setState(() {
                  t.amount = double.tryParse(amount.text) ?? t.amount;
                  t.description = desc.text.trim();
                  t.direction = dir;
                  t.categoryId = cat;
                  t.date = date;
                  t.hasDate = true;
                });
                Navigator.pop(ctx);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Import statement'),
        actions: [
          if (_stage == _Stage.review && (_parsed?.isTabular ?? false))
            IconButton(
              tooltip: 'Map columns',
              icon: const Icon(Icons.view_column_outlined),
              onPressed: _openMapping,
            ),
        ],
      ),
      body: switch (_stage) {
        _Stage.idle => _idle(),
        _Stage.parsing => const Center(child: CircularProgressIndicator()),
        _Stage.password => _passwordView(),
        _Stage.review => _review(),
        _Stage.importing => _importingView(),
      },
      bottomNavigationBar: _stage == _Stage.review ? _bottomBar() : null,
    );
  }

  Widget _idle() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.upload_file,
              size: 64, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 16),
          const Text('Import from a bank statement',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
              textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text(
            'Pick a statement file from any bank. AERIS reads PDF, CSV and Excel '
            '(.xlsx), figures out the columns, and lets you review everything '
            'before saving. Works with BOB, SBI, HDFC, ICICI and more.',
            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 22),
          FilledButton.icon(
            onPressed: _pick,
            icon: const Icon(Icons.folder_open),
            label: const Text('Choose file'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 18),
            Text(_error!,
                style: const TextStyle(color: Colors.red),
                textAlign: TextAlign.center),
          ],
        ]),
      ),
    );
  }

  Widget _passwordView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.lock_outline, size: 56),
          const SizedBox(height: 12),
          const Text('This PDF is password-protected',
              style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text('Bank PDFs are often locked with your account number, DOB or PAN.',
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center),
          const SizedBox(height: 16),
          TextField(
            controller: _password,
            obscureText: true,
            decoration: const InputDecoration(
                labelText: 'PDF password', border: OutlineInputBorder()),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!, style: const TextStyle(color: Colors.red)),
          ],
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => _parse(password: _password.text),
            child: const Text('Unlock & read'),
          ),
        ]),
      ),
    );
  }

  Widget _review() {
    final txns = _parsed!.txns;
    final selectedCount = txns.where((t) => t.selected).length;
    final dupCount = txns.where((t) => t.duplicate).length;
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_parsed!.fileName,
                style: const TextStyle(fontWeight: FontWeight.w700),
                overflow: TextOverflow.ellipsis),
            const SizedBox(height: 2),
            Text('${txns.length} found · $selectedCount selected'
                '${dupCount > 0 ? ' · $dupCount possible duplicate${dupCount == 1 ? '' : 's'} skipped' : ''}',
                style: const TextStyle(fontSize: 12)),
            if (_parsed!.isTabular)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('Columns look wrong? Tap the ⬚ icon to re-map.',
                    style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 12)),
              ),
          ]),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: txns.length,
            itemBuilder: (_, i) => _row(txns[i]),
          ),
        ),
      ],
    );
  }

  Widget _row(StatementTxn t) {
    final cat = Categories.byId(t.categoryId);
    final isCredit = t.direction == TxnDirection.credit;
    return Opacity(
      opacity: t.selected ? 1 : 0.5,
      child: ListTile(
        leading: Checkbox(
          value: t.selected,
          onChanged: (v) => setState(() => t.selected = v ?? false),
        ),
        title: Text(t.description.isEmpty ? '(no description)' : t.description,
            maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Row(children: [
          Text(t.hasDate ? DateFormat('d MMM yyyy').format(t.date) : 'No date',
              style: const TextStyle(fontSize: 12)),
          const Text('  ·  ', style: TextStyle(fontSize: 12)),
          Flexible(
            child: Text(cat.label,
                style: TextStyle(fontSize: 12, color: cat.color),
                overflow: TextOverflow.ellipsis),
          ),
          if (t.duplicate)
            const Padding(
              padding: EdgeInsets.only(left: 6),
              child: Text('• maybe dup',
                  style: TextStyle(fontSize: 11, color: Colors.orange)),
            ),
        ]),
        trailing: Text(
          '${isCredit ? '+' : '-'}${formatRupees(t.amount)}',
          style: TextStyle(
              fontWeight: FontWeight.w700,
              color: isCredit ? Colors.green : Theme.of(context).colorScheme.onSurface),
        ),
        onTap: () => _editRow(t),
      ),
    );
  }

  Widget _importingView() {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        CircularProgressIndicator(value: _total == 0 ? null : _done / _total),
        const SizedBox(height: 16),
        Text('Saving $_done / $_total…'),
      ]),
    );
  }

  Widget _bottomBar() {
    final count = _parsed!.txns.where((t) => t.selected).length;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: FilledButton.icon(
          onPressed: count == 0 ? null : _import,
          icon: const Icon(Icons.download_done),
          label: Text(count == 0
              ? 'Select transactions to import'
              : 'Import $count transaction${count == 1 ? '' : 's'}'),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
        ),
      ),
    );
  }
}
