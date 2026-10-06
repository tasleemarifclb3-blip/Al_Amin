import 'simple_radio.dart';
import '../domain/format.dart';

import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';

import '../database/app_database.dart';
import '../database/accounting_service.dart';
import '../database/workflow_service.dart';
import 'edit_transaction_page.dart';
import 'qarza_hassanah_page.dart';
import 'receipt_actions.dart';
import 'security.dart';
import 'available_balance_card.dart';

class QarzaBorrowerLedgerPage extends StatefulWidget {
  final AppDatabase database;
  final String borrowerName;

  const QarzaBorrowerLedgerPage({
    super.key,
    required this.database,
    required this.borrowerName,
  });

  @override
  State<QarzaBorrowerLedgerPage> createState() => _QarzaBorrowerLedgerPageState();
}

class _QarzaBorrowerLedgerPageState extends State<QarzaBorrowerLedgerPage> {
  late Future<List<FundAdjustment>> _future;

  @override
  void initState() {
    super.initState();
    _future = _rows();
  }

  Future<List<FundAdjustment>> _rows() {
    return (widget.database.select(widget.database.fundAdjustments)
          ..where((a) => a.partyName.equals(widget.borrowerName) &
              (a.adjustmentType.equals('QARZA_DISBURSEMENT') |
                  a.adjustmentType.equals('QARZA_RECOVERY')))
          ..orderBy([
            (a) => OrderingTerm(expression: a.transactionDate, mode: OrderingMode.asc),
            (a) => OrderingTerm(expression: a.id, mode: OrderingMode.asc),
          ]))
        .get();
  }

  Future<double> _waived() => WorkflowService.waivedForBorrower(widget.database, widget.borrowerName);

  double _balanceAfter(List<FundAdjustment> rows, int index) {
    var balance = 0.0;
    for (var i = 0; i <= index; i++) {
      final row = rows[i];
      balance += row.adjustmentType == 'QARZA_DISBURSEMENT' ? row.amount : -row.amount;
    }
    return balance < 0 ? 0 : balance;
  }

  Future<FundAdjustment?> _latestIssue(List<FundAdjustment> rows) async {
    for (final row in rows.reversed) {
      if (row.adjustmentType == 'QARZA_DISBURSEMENT') return row;
    }
    return null;
  }

  void _show(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _recover() async {
    final rows = await _rows();
    final grossOutstanding = rows.fold<double>(
      0,
      (sum, row) => sum +
          (row.adjustmentType == 'QARZA_DISBURSEMENT' ? row.amount : -row.amount),
    );
    final waived = await _waived();
    final outstanding = (grossOutstanding - waived).clamp(0, double.infinity).toDouble();
    if (!mounted || outstanding <= .005) return;

    final amountBorrowed = rows
        .where((row) => row.adjustmentType == 'QARZA_DISBURSEMENT')
        .fold<double>(0, (sum, row) => sum + row.amount);
    final returnedBefore = rows
        .where((row) => row.adjustmentType == 'QARZA_RECOVERY')
        .fold<double>(0, (sum, row) => sum + row.amount);
    final issue = await _latestIssue(rows);
    if (issue == null) {
      _show('Original Qarz issue details could not be found.');
      return;
    }

    final amount = TextEditingController();
    final reference = TextEditingController(text: 'N/A');
    String? mode; // Not preselected: the user must choose Cash or Bank Transfer.
    var transactionDate = DateTime.now();

    if (!mounted) return;
    final result = await showDialog<_QarzRecoveryResult>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocalState) {
          final entered = double.tryParse(
                amount.text.replaceAll(',', '').replaceAll('₹', '').trim(),
              ) ??
              0;
          return AlertDialog(
            title: Text('Receive from ${widget.borrowerName}'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Outstanding: ₹${outstanding.asAmount}', style: const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  TextField(
                    controller: amount,
                    autofocus: true,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    onChanged: (_) => setLocalState(() {}),
                    decoration: const InputDecoration(labelText: 'Amount Returned *', prefixText: '₹ ', border: OutlineInputBorder()),
                  ),
                  if (entered > 0) ...[
                    const SizedBox(height: 6),
                    Text('Amount in Words: ${ReceiptActions.amountInWords(entered)}', style: const TextStyle(fontWeight: FontWeight.w600)),
                  ],
                  const SizedBox(height: 10),
                  InkWell(
                    onTap: () async {
                      final today = DateTime.now();
                      final picked = await showDatePicker(
                        context: ctx,
                        initialDate: transactionDate,
                        firstDate: DateTime(1950),
                        lastDate: DateTime(today.year, today.month, today.day),
                      );
                      if (picked == null) return;
                      setLocalState(() => transactionDate = DateTime(
                            picked.year,
                            picked.month,
                            picked.day,
                            transactionDate.hour,
                            transactionDate.minute,
                            transactionDate.second,
                          ));
                    },
                    child: InputDecorator(
                      decoration: const InputDecoration(labelText: 'Transaction Date *', border: OutlineInputBorder()),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [Text(ReceiptActions.formatDate(transactionDate)), const Icon(Icons.calendar_today_outlined)],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(child: SimpleRadioTile<String>(contentPadding: EdgeInsets.zero, title: const Text('Cash'), value: 'Cash', groupValue: mode, onChanged: (v) => v == null ? null : setLocalState(() => mode = v))),
                      Expanded(child: SimpleRadioTile<String>(contentPadding: EdgeInsets.zero, title: const Text('Bank'), value: 'Bank Transfer', groupValue: mode, onChanged: (v) => v == null ? null : setLocalState(() => mode = v))),
                    ],
                  ),
                  TextField(controller: reference, decoration: const InputDecoration(labelText: 'Cheque / Payment Reference *', border: OutlineInputBorder())),
                  const SizedBox(height: 10),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
              FilledButton(
                onPressed: () async {
                  final value = double.tryParse(amount.text.replaceAll(',', '').replaceAll('₹', '').trim()) ?? 0;
                  if (value <= 0 || value > outstanding + .005) {
                    ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Enter an amount not greater than the outstanding Qarz.')));
                    return;
                  }
                  if (mode == null) {
                    ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Select Cash or Bank Transfer.')));
                    return;
                  }
                  if (reference.text.trim().isEmpty) {
                    ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Cheque / Payment Reference is required.')));
                    return;
                  }
                  final documentNumber = await _nextRecoveryNumber();
                  await widget.database.into(widget.database.fundAdjustments).insert(
                    FundAdjustmentsCompanion.insert(
                      transactionDate: Value(transactionDate),
                      adjustmentType: 'QARZA_RECOVERY',
                      amount: value,
                      paymentMode: mode!,
                      chequeNumber: Value(reference.text.trim()),
                      documentNumber: Value(documentNumber),
                      partyName: Value(widget.borrowerName),
                      address: Value(issue.address),
                      aadhaarNumber: Value(issue.aadhaarNumber),
                      phoneNumber: Value(issue.phoneNumber),
                      verification: const Value(''),
                      verifiedBy1: const Value(''),
                      verifiedBy2: const Value(''),
                      verifiedBy3: const Value(''),
                      remarks: const Value(''),
                      username: Value(currentUsername ?? 'Legacy'),
                    ),
                  );
                  if (ctx.mounted) {
                    Navigator.of(ctx).pop(_QarzRecoveryResult(
                      amount: value,
                      documentNumber: documentNumber,
                      paymentMode: mode!,
                      date: transactionDate,
                      reference: reference.text.trim(),
                      verification: '',
                      verifiedBy1: '',
                      verifiedBy2: '',
                      verifiedBy3: '',
                      remarks: '',
                      address: issue.address ?? '',
                      aadhaar: issue.aadhaarNumber ?? '',
                      phone: issue.phoneNumber ?? '',
                      outstandingAfter: outstanding - value,
                      amountBorrowed: amountBorrowed,
                      totalReturnedAfter: returnedBefore + value,
                    ));
                  }
                },
                child: const Text('Receive & Save'),
              ),
            ],
          );
        },
      ),
    );

    for (final controller in [amount, reference]) {
      controller.dispose();
    }
    if (result == null || !mounted) return;

    setState(() {
      _future = _rows();
    });
    final recoveryConditions = await WorkflowService.conditions(widget.database, result.documentNumber);
    if (!mounted) return;
    await ReceiptActions.showActionsDialog(
      context: context,
      documentNumber: result.documentNumber,
      title: 'Qarz Recovery Voucher',
      fileNamePrefix: 'QH-IN',
      shareMessage: 'Al-Amin Baitul Maal - Qarz recovery ${result.documentNumber}\nBorrower: ${widget.borrowerName}\nReturned: INR ${result.amount.asAmount}\nOutstanding: INR ${result.outstandingAfter.asAmount}',
      buildPdf: () async => ReceiptActions.qarzaVoucherDocument(
        documentNumber: result.documentNumber,
        date: result.date,
        party: widget.borrowerName,
        address: result.address,
        aadhaar: result.aadhaar,
        phone: result.phone,
        amount: result.amount,
        chequeNumber: result.reference,
        paymentMode: result.paymentMode,
        operation: 'RECOVERY',
        conditions: recoveryConditions,
        amountBorrowed: result.amountBorrowed,
        totalReturned: result.totalReturnedAfter,
        balanceAfter: result.outstandingAfter,
        verification: result.verification,
        verifiedBy1: result.verifiedBy1,
        verifiedBy2: result.verifiedBy2,
        verifiedBy3: result.verifiedBy3,
        remarks: '${result.remarks}\nOutstanding After Recovery: INR ${result.outstandingAfter.asAmount}',
      ).save(),
    );
  }

  Future<String> _nextRecoveryNumber() async {
    final rows = await widget.database.select(widget.database.fundAdjustments).get();
    var highest = 0;
    for (final row in rows) {
      final number = row.documentNumber;
      if (number == null || !number.startsWith('QH-IN-')) continue;
      final parsed = int.tryParse(number.substring('QH-IN-'.length));
      if (parsed != null && parsed > highest) highest = parsed;
    }
    return 'QH-IN-${(highest + 1).toString().padLeft(6, '0')}';
  }

  Future<void> _waive(double outstanding) async {
    final authorized = await requireSuperuserPassword(
      context,
      title: 'Authorize Qarza Waiver',
      message: 'Enter the superuser password to transfer the remaining Qarza balance to Zakaat expense.',
    );
    if (!authorized || !mounted) return;

    final issueRows = await (widget.database.select(widget.database.fundAdjustments)
          ..where((a) => a.partyName.equals(widget.borrowerName) & a.adjustmentType.equals('QARZA_DISBURSEMENT'))
          ..orderBy([(a) => OrderingTerm(expression: a.transactionDate, mode: OrderingMode.desc), (a) => OrderingTerm(expression: a.id, mode: OrderingMode.desc)]))
        .get();
    if (!mounted) return;
    if (issueRows.isEmpty) {
      _show('Original Qarz issue could not be found.');
      return;
    }
    final issue = issueRows.first;
    final waived = await _waived();
    final allRows = await _rows();
    final amountBorrowed = allRows
        .where((row) => row.adjustmentType == 'QARZA_DISBURSEMENT')
        .fold<double>(0, (sum, row) => sum + row.amount);
    final returnedSoFar = allRows
        .where((row) => row.adjustmentType == 'QARZA_RECOVERY')
        .fold<double>(0, (sum, row) => sum + row.amount);
    if (!mounted) return;
    final zakaatAvailable = await AccountingService.availableZakaat(widget.database);
    if (zakaatAvailable <= .005) {
      _show('There is no available Zakaat balance to waive Qarza against.');
      return;
    }
    final limit = outstanding < zakaatAvailable ? outstanding : zakaatAvailable;
    final waiverNumber = await WorkflowService.nextWaiverNumber(widget.database);
    final amountField = TextEditingController();
    final remarks = TextEditingController();
    final date = DateTime.now();
    double? parseAmount() => double.tryParse(
          amountField.text.replaceAll(',', '').replaceAll('\u20B9', '').trim(),
        );
    if (!mounted) return;
    final waiveAmount = await showDialog<double>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocalState) {
          final typed = parseAmount() ?? 0.0;
          final valid = typed > 0 && typed <= limit + .005;
          final remaining = outstanding - (valid ? typed : 0);
          return AlertDialog(
            title: const Text('Waive Qarza'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Borrower: ${widget.borrowerName}'),
                  const SizedBox(height: 4),
                  Text('Amount borrowed: \u20B9${amountBorrowed.asAmount}'),
                  Text('Returned so far: \u20B9${returnedSoFar.asAmount}'),
                  if (waived > .005) Text('Waived earlier: \u20B9${waived.asAmount}'),
                  Text('Outstanding: \u20B9${outstanding.asAmount}',
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  Text('Available Zakaat Balance: \u20B9${zakaatAvailable.asAmount}',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: zakaatAvailable >= outstanding
                            ? Theme.of(ctx).colorScheme.primary
                            : Theme.of(ctx).colorScheme.error,
                      )),
                  Text('Waiver No.: $waiverNumber'),
                  Text('Original Qarz: ${issue.documentNumber ?? '\u2014'}'),
                  const SizedBox(height: 12),
                  TextField(
                    controller: amountField,
                    autofocus: true,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    onChanged: (_) => setLocalState(() {}),
                    decoration: InputDecoration(
                      labelText: 'Amount to waive *',
                      prefixText: '\u20B9 ',
                      helperText: 'Up to \u20B9${limit.asAmount}',
                      errorText: amountField.text.trim().isNotEmpty && !valid
                          ? 'Enter an amount between 1 and \u20B9${limit.asAmount}'
                          : null,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text('Balance after waiver: \u20B9${remaining.asAmount}',
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 12),
                  const Text('Journal treatment: Debit Zakaat expense; Credit Qarz receivable. The original Donations funding reference is retained as a linked memo and is not double-counted as cash.'),
                  const SizedBox(height: 12),
                  TextField(
                    controller: remarks,
                    maxLines: 3,
                    onChanged: (_) => setLocalState(() {}),
                    decoration: const InputDecoration(labelText: 'Reason / Remarks *', border: OutlineInputBorder()),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
              FilledButton(
                onPressed: valid && remarks.text.trim().isNotEmpty
                    ? () => Navigator.pop(ctx, typed)
                    : null,
                child: const Text('Confirm Waiver'),
              ),
            ],
          );
        },
      ),
    );
    final note = remarks.text.trim();
    remarks.dispose();
    amountField.dispose();
    if (waiveAmount == null || !mounted) return;

    try {
      await WorkflowService.createQarzaWaiver(
        widget.database,
        waiverNumber: waiverNumber,
        date: date,
        borrowerName: widget.borrowerName,
        originalQarzaNumber: issue.documentNumber ?? '\u2014',
        amount: waiveAmount,
        username: currentUsername ?? 'Legacy',
        remarks: note,
      );
      if (!mounted) return;
      setState(() {
        _future = _rows();
      });
      final saved = (await WorkflowService.qarzaWaivers(widget.database))
          .firstWhere((x) => x.waiverNumber == waiverNumber);
      final figures = await WorkflowService.qarzaWaiverFigures(widget.database, saved);
      if (!mounted) return;
      await ReceiptActions.showActionsDialog(
        context: context,
        documentNumber: waiverNumber,
        title: 'Qarza Waiver Voucher',
        fileNamePrefix: 'Qarza-Waiver',
        shareMessage: 'Al-Amin Baitul Maal - Qarza Waiver $waiverNumber',
        buildPdf: () async => (await ReceiptActions.qarzaWaiverVoucherDocument(
          figures: figures,
          waiverNumber: waiverNumber,
          date: date,
          borrowerName: widget.borrowerName,
          originalQarzaNumber: issue.documentNumber ?? '\u2014',
          amount: waiveAmount,
          username: currentUsername ?? 'Legacy',
          remarks: note,
        )).save(),
      );
    } catch (e) {
      _show('Could not save Qarza waiver: $e');
    }
  }

  Future<void> _edit(FundAdjustment row) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => EditTransactionPage(
          database: widget.database,
          source: LedgerSource.fundAdjustment,
          id: row.id,
          title: row.adjustmentType == 'QARZA_DISBURSEMENT' ? 'Qarz Issued' : 'Qarz Recovery',
        ),
      ),
    );
    if (changed == true && mounted) {
      setState(() {
      _future = _rows();
    });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.borrowerName} — Qarz Ledger'),
        actions: [
          IconButton(
            tooltip: 'Qarza Waiver Ledger',
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => QarzaWaiverLedgerPage(database: widget.database))),
            icon: const Icon(Icons.menu_book_outlined),
          ),
          FutureBuilder<List<FundAdjustment>>(
            future: _future,
            builder: (context, snap) {
              final rows = snap.data ?? const <FundAdjustment>[];
              final gross = rows.fold<double>(0, (s, r) => s + (r.adjustmentType == 'QARZA_DISBURSEMENT' ? r.amount : -r.amount));
              return FutureBuilder<double>(
                future: _waived(),
                builder: (context, waiverSnap) {
                  final outstanding = (gross - (waiverSnap.data ?? 0)).clamp(0, double.infinity).toDouble();
                  return IconButton(tooltip: 'Receive Qarz Payment', onPressed: outstanding > .005 ? _recover : null, icon: const Icon(Icons.payments_outlined));
                },
              );
            },
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(12, 6, 12, 8),
        child: FutureBuilder<List<FundAdjustment>>(
          future: _future,
          builder: (context, buttonSnap) {
            final buttonRows = buttonSnap.data ?? const <FundAdjustment>[];
            final gross = buttonRows.fold<double>(0, (sum, row) => sum + (row.adjustmentType == 'QARZA_DISBURSEMENT' ? row.amount : -row.amount));
            return FutureBuilder<double>(
              future: _waived(),
              builder: (context, buttonWaiverSnap) {
                final buttonWaived = buttonWaiverSnap.data ?? 0;
                final buttonOutstanding = (gross - buttonWaived).clamp(0, double.infinity).toDouble();
                return Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: buttonOutstanding > .005 ? _recover : null,
                        icon: const Icon(Icons.payments_outlined),
                        label: const Text('Receive Payment'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: buttonOutstanding > .005 ? () => _waive(buttonOutstanding) : null,
                        icon: const Icon(Icons.assignment_return_outlined),
                        label: const Text('Waive to Zakaat'),
                      ),
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
      body: FutureBuilder<List<FundAdjustment>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
          if (snap.hasError) return Center(child: Padding(padding: const EdgeInsets.all(20), child: Text('Could not load ledger:\n${snap.error}', textAlign: TextAlign.center)));
          final rows = snap.data!;
          final grossOutstanding = rows.fold<double>(0, (s, r) => s + (r.adjustmentType == 'QARZA_DISBURSEMENT' ? r.amount : -r.amount));
          return FutureBuilder<double>(
            future: _waived(),
            builder: (context, waiverSnap) {
              final waived = waiverSnap.data ?? 0;
              final outstanding = (grossOutstanding - waived).clamp(0, double.infinity).toDouble();
              return Column(children: [
                Card(
                  margin: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                  child: ListTile(
                    title: const Text('Current Running Balance', style: TextStyle(fontWeight: FontWeight.bold)),
                    trailing: Text('₹${outstanding.asAmount}', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: outstanding > .005 ? Colors.red.shade700 : Colors.green.shade700)),
                    subtitle: Text('Receivable after payments and Zakaat waivers\nWaived to Zakaat: ₹${waived.asAmount}'),
                  ),
                ),
                const SizedBox(height: 2),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                  child: AvailableBalanceCard(
                    label: 'Available Zakaat Balance for Qarza Waiver',
                    future: AccountingService.availableZakaat(widget.database),
                  ),
                ),
            Expanded(
              child: rows.isEmpty
                  ? const Center(child: Text('No Qarz transactions found.'))
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(8),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: DataTable(
                          columns: const [
                            DataColumn(label: Text('Date')),
                            DataColumn(label: Text('Amount Borrowed')),
                            DataColumn(label: Text('Amount Returned')),
                            DataColumn(label: Text('Cheque / Ref.')),
                            DataColumn(label: Text('Receipt / Form No.')),
                            DataColumn(label: Text('Running Balance')),
                            DataColumn(label: Text('User')),
                            DataColumn(label: Text('Remarks')),
                            DataColumn(label: Text('Edit')),
                          ],
                          rows: [
                            for (var i = 0; i < rows.length; i++)
                              DataRow(cells: [
                                DataCell(Text(ReceiptActions.formatDate(rows[i].transactionDate))),
                                DataCell(Text(rows[i].adjustmentType == 'QARZA_DISBURSEMENT' ? '₹${rows[i].amount.asAmount}' : '—')),
                                DataCell(Text(rows[i].adjustmentType == 'QARZA_RECOVERY' ? '₹${rows[i].amount.asAmount}' : '—')),
                                DataCell(Text(rows[i].chequeNumber?.trim().isNotEmpty == true ? rows[i].chequeNumber! : '—')),
                                DataCell(Text(rows[i].documentNumber ?? '—')),
                                DataCell(Text('₹${_balanceAfter(rows, i).asAmount}')),
                                DataCell(Text(rows[i].username)),
                                DataCell(Text(rows[i].remarks ?? '—')),
                                DataCell(IconButton(tooltip: 'Edit / Delete', icon: const Icon(Icons.edit_outlined), onPressed: () => _edit(rows[i]))),
                              ]),
                          ],
                        ),
                      ),
                    ),
            ),
              ]);
            },
          );
        },
      ),
    );
  }
}

class _QarzRecoveryResult {
  final double amount;
  final String documentNumber;
  final String paymentMode;
  final DateTime date;
  final String reference;
  final String verification;
  final String verifiedBy1;
  final String verifiedBy2;
  final String verifiedBy3;
  final String remarks;
  final String address;
  final String aadhaar;
  final String phone;
  final double outstandingAfter;
  final double amountBorrowed;
  final double totalReturnedAfter;

  _QarzRecoveryResult({
    required this.amount,
    required this.documentNumber,
    required this.paymentMode,
    required this.date,
    required this.reference,
    required this.verification,
    required this.verifiedBy1,
    required this.verifiedBy2,
    required this.verifiedBy3,
    required this.remarks,
    required this.address,
    required this.aadhaar,
    required this.phone,
    required this.outstandingAfter,
    required this.amountBorrowed,
    required this.totalReturnedAfter,
  });
}
