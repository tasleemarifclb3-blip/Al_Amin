
import 'package:drift/drift.dart' hide Column;
import '../domain/word_case.dart';
import '../domain/format.dart';
import 'package:flutter/material.dart';

import '../database/app_database.dart';
import 'app_ui.dart';
import 'brand.dart';
import 'form_layout.dart';
import 'receipt_actions.dart';
import 'security.dart';

class FinancialEntryPage extends StatefulWidget {
  final AppDatabase database;
  final String title;
  final String category;
  final String receiptPrefix;
  final String nameLabel;
  final String typeLabel;

  const FinancialEntryPage({
    super.key,
    required this.database,
    required this.title,
    required this.category,
    required this.receiptPrefix,
    this.nameLabel = 'Donor / Source Name',
    this.typeLabel = 'Donation',
  });

  @override
  State<FinancialEntryPage> createState() => _FinancialEntryPageState();
}

class _FinancialEntryPageState extends State<FinancialEntryPage> {
  /// Pre-filled donor name; the user can change or clear it.
  static const String defaultDonorName = 'Abdullah';
  final _name = TextEditingController(text: defaultDonorName);
  final _nameFocus = FocusNode();
  final _amount = TextEditingController();
  final _remarks = TextEditingController();
  DateTime _date = DateTime.now();
  String? _mode; // Not preselected: the user must choose Cash or Bank Transfer.
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    // Selecting the pre-filled name on focus lets the user simply type over it.
    _nameFocus.addListener(() {
      if (_nameFocus.hasFocus) {
        _name.selection = TextSelection(baseOffset: 0, extentOffset: _name.text.length);
      }
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _nameFocus.dispose();
    _amount.dispose();
    _remarks.dispose();
    super.dispose();
  }

  double _money(String value) =>
      double.tryParse(value.replaceAll(',', '').replaceAll('₹', '').trim()) ?? 0;

  Future<void> _selectDate() async {
    final today = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(1950),
      lastDate: DateTime(today.year, today.month, today.day),
      helpText: 'Select transaction date',
    );
    if (!mounted || picked == null) return;
    setState(() {
      _date = DateTime(picked.year, picked.month, picked.day, today.hour, today.minute, today.second);
    });
  }

  Future<String> _nextReceipt() async {
    final rows = await widget.database.select(widget.database.financialTransactions).get();
    final members = await widget.database.select(widget.database.householdPayments).get();
    final concessions = await widget.database.select(widget.database.householdConcessions).get();
    final prefix = '${widget.receiptPrefix}-';
    var highest = 0;
    for (final value in <String?>[
      ...rows.map((r) => r.receiptNumber),
      ...members.map((r) => r.receiptNumber),
      ...concessions.map((r) => r.receiptNumber),
    ]) {
      if (value == null || !value.startsWith(prefix)) continue;
      final n = int.tryParse(value.substring(prefix.length));
      if (n != null && n > highest) highest = n;
    }
    return '$prefix${(highest + 1).toString().padLeft(6, '0')}';
  }

  Future<Uint8List> _pdf(String receipt, double amount, String name, String remarks) async {
    final isThermal = const {'GD', 'BD', 'ZK', 'SF', 'OI'}.contains(widget.category.toUpperCase());
    if (isThermal) {
      final doc = ReceiptActions.thermalReceiptDocument(
        title: '${widget.title.toUpperCase()} RECEIPT',
        documentNumber: receipt,
        date: _date,
        rows: [
          ReceiptActions.thermalRow('Received from', name.isEmpty ? '—' : name),
          ReceiptActions.thermalRow('On account of', widget.typeLabel),
          ReceiptActions.thermalRow('Payment Mode', _mode ?? ''),
          ReceiptActions.thermalRow('Amount', '\u20B9${amount.asAmount}'),
        ],
        amountWords: ReceiptActions.amountInWords(amount),
        totalSettled: '\u20B9${amount.asAmount}',
        remarks: remarks,
      );
      return doc.save();
    }

    final doc = ReceiptActions.baseDocument(
      title: '${widget.title.toUpperCase()} VOUCHER',
      documentNumber: receipt,
      date: ReceiptActions.formatDate(_date),
      rows: [
        ReceiptActions.pdfRow('Type', widget.typeLabel),
        ReceiptActions.pdfRow('Name / Source', name.isEmpty ? '—' : name),
        ReceiptActions.pdfRow('Payment Mode', _mode ?? ''),
        ReceiptActions.pdfRow('Amount', '\u20B9${amount.asAmount}'),
        ReceiptActions.pdfRow('Amount in Words', ReceiptActions.amountInWords(amount)),
      ],
      remarks: remarks,
      leftSignature: 'Prepared By: __________________',
      rightSignature: 'Authorized By: __________________',
    );
    return doc.save();
  }

  Future<void> _save() async {
    if (_saving) return;
    final amount = _money(_amount.text);
    if (amount <= 0) {
      _show('Enter an amount greater than zero.');
      return;
    }
    if (_mode == null) {
      _show('Select Cash or Bank Transfer.');
      return;
    }
    setState(() => _saving = true);
    try {
      final receipt = await _nextReceipt();
      final name = _name.text.trim();
      final remarks = _remarks.text.trim();
      await widget.database.into(widget.database.financialTransactions).insert(
            FinancialTransactionsCompanion.insert(
              transactionDate: Value(_date),
              category: widget.category,
              paymentMode: _mode!,
              amount: amount,
              receiptNumber: Value(receipt),
              donorName: Value(name.isEmpty ? null : name),
              remarks: Value(remarks.isEmpty ? null : remarks),
          username: Value(currentUsername ?? 'Legacy'),
            ),
          );
      if (!mounted) return;
      await ReceiptActions.showActionsDialog(
        context: context,
        documentNumber: receipt,
        title: '${widget.title} Receipt Generated',
        fileNamePrefix: widget.receiptPrefix,
        shareMessage: 'Al-Amin Baitul Maal - ${widget.title} Receipt $receipt\nDate: ${ReceiptActions.formatDate(_date)}\nAmount: \u20B9${amount.asAmount}',
        buildPdf: () => _pdf(receipt, amount, name, remarks),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) _show('Could not save ${widget.title}: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _show(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  @override
  Widget build(BuildContext context) {
    final amount = _money(_amount.text);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.pop(context)),
      ),
      body: IslamicBackground(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 28),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Center(child: BrandLogo(size: 48)),
                  const SizedBox(height: 6),
                  Center(
                    child: Text(
                      widget.title,
                      style: const TextStyle(fontSize: 21, fontWeight: FontWeight.bold, color: kBrandGreen),
                    ),
                  ),
                  const SizedBox(height: 14),
                  NumberedSection(
                    number: 1,
                    title: 'Donor Details',
                    children: [
                      LabeledField(
                        label: widget.nameLabel,
                        child: TextField(
                          controller: _name,
                          focusNode: _nameFocus,
                          enabled: !_saving,
                          textCapitalization: TextCapitalization.words,
                          inputFormatters: const [WordCaseFormatter()],
                          decoration: boxedDecoration(),
                        ),
                      ),
                    ],
                  ),
                  NumberedSection(
                    number: 2,
                    title: 'Payment Details',
                    children: [
                      LabeledField(
                        label: 'Transaction Date',
                        required: true,
                        widthFactor: .62,
                        child: InkWell(
                          onTap: _saving ? null : _selectDate,
                          child: InputDecorator(
                            decoration: boxedDecoration(suffixIcon: const Icon(Icons.calendar_today_outlined, size: 20)),
                            child: Text(ReceiptActions.formatDate(_date), style: const TextStyle(fontSize: 16)),
                          ),
                        ),
                      ),
                      LabeledField(
                        label: 'Amount',
                        required: true,
                        child: TextField(
                          controller: _amount,
                          enabled: !_saving,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          onChanged: (_) => setState(() {}),
                          decoration: boxedDecoration(prefixText: '\u20B9 '),
                        ),
                      ),
                      if (amount > 0)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: kBrandGreen.withValues(alpha: .08),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: kBrandGreen.withValues(alpha: .25)),
                            ),
                            child: Text(
                              'Amount in Words: ${ReceiptActions.amountInWords(amount)}',
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                        ),
                      LabeledField(
                        label: 'Payment Mode',
                        required: true,
                        child: BoxedChoice(
                          options: const ['Cash', 'Bank Transfer'],
                          value: _mode,
                          onChanged: _saving ? null : (v) => setState(() => _mode = v),
                        ),
                      ),
                    ],
                  ),
                  NumberedSection(
                    number: 3,
                    title: 'Remarks',
                    children: [
                      LabeledField(
                        label: 'Remarks (Optional)',
                        child: TextField(
                          controller: _remarks,
                          enabled: !_saving,
                          maxLines: 3,
                          decoration: boxedDecoration(),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  SizedBox(
                    height: 50,
                    child: FilledButton.icon(
                      onPressed: _saving ? null : _save,
                      icon: const Icon(Icons.save),
                      label: Text(_saving ? 'Saving...' : 'Save Receipt'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
