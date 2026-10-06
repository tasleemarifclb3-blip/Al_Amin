import '../database/chart_data_service.dart';
import 'finance_charts.dart';
import '../domain/format.dart';

import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import '../database/formal_financial_report.dart';

import '../database/app_database.dart';
import 'brand.dart';
import 'receipt_actions.dart';
import 'qarza_borrower_ledger_page.dart';
import 'edit_transaction_page.dart';
import 'security.dart';
import '../database/workflow_service.dart';

enum _ReportView { summary, detailed, charts }

class ReportsPage extends StatefulWidget {
  final AppDatabase database;
  const ReportsPage({super.key, required this.database});

  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage> {
  late DateTime _from;
  late DateTime _to;
  _ReportView _view = _ReportView.summary;
  /// "All Time" is the default period: from the first record to today.
  bool _allTime = true;
  String _scope = 'ALL';
  String _user = 'ALL';
  String _type = 'ALL';
  String _party = '';
  String _statusFilter = 'ALL';
  Future<_ReportData>? _future;
  bool _authorized = false;

  static const List<String> _scopes = <String>[
    'ALL',
    'DONATIONS',
    'ZAKAAT',
    'SADQA_FITR',
    'QARZA',
  ];

  static const List<String> _types = <String>[
    'Monthly Donation',
    'General Donation',
    'Box Collection',
    'Other Income',
    'Zakaat',
    'Sadqa-e-Fitr',
    'Zakaat Expenditure',
    'Qarz Issued',
    'Qarz Recovered',
    'Qarz Waived to Zakaat',
    'Sadqa-e-Fitr Expenditure',
    'Other Expense',
  ];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _from = DateTime(now.year, 1, 1);
    _to = DateTime(now.year, now.month, now.day);
    WidgetsBinding.instance.addPostFrameCallback((_) => _authorize());
  }

  Future<void> _authorize() async {
    final ok = await requireAdminOrSuperuserPassword(
      context,
      title: 'Authorize Reports',
      message: 'Enter the Admin or Superuser Password to access reports.',
    );
    if (!mounted) return;
    if (!ok) {
      Navigator.of(context).pop(false);
      return;
    }
    setState(() {
      _authorized = true;
      _future = _load();
    });
  }

  bool _inRange(DateTime date) {
    final d = DateTime(date.year, date.month, date.day);
    final from = DateTime(_from.year, _from.month, _from.day);
    final to = DateTime(_to.year, _to.month, _to.day);
    return !d.isBefore(from) && !d.isAfter(to);
  }

  bool _userMatches(String username) =>
      _user == 'ALL' || username.trim().toLowerCase() == _user.trim().toLowerCase();

  bool _typeMatches(String type) => _type == 'ALL' || type == _type;

  bool _partyMatches(String party) {
    final query = _party.trim().toLowerCase();
    return query.isEmpty || party.toLowerCase().contains(query);
  }

  bool _scopeMatches(String type) {
    switch (_scope) {
      case 'DONATIONS':
        // Donations is the parent fund. Its child collection accounts are
        // Monthly Donation, General Donation and Box Collection. Qarza is
        // also linked to Donations, so its issue/recovery entries are shown
        // here and separately summarized below.
        return type == 'Monthly Donation' ||
            type == 'General Donation' ||
            type == 'Box Collection' ||
            type == 'Qarz Issued' ||
            type == 'Qarz Recovered';
      case 'ZAKAAT':
        return type == 'Zakaat' || type == 'Zakaat Expenditure' || type == 'Qarz Waived to Zakaat';
      case 'SADQA_FITR':
        return type == 'Sadqa-e-Fitr' || type == 'Sadqa-e-Fitr Expenditure';
      case 'QARZA':
        return type == 'Qarz Issued' || type == 'Qarz Recovered' || type == 'Qarz Waived to Zakaat';
      default:
        return true;
    }
  }

  bool _includeEntry(String type, String username, String party) =>
      _scopeMatches(type) &&
      _userMatches(username) &&
      _typeMatches(type) &&
      _partyMatches(party);

  bool _statusMatches(String status) {
    if (_statusFilter == 'ALL') return true;
    if (_statusFilter == 'APPROVED') return status == 'APPROVED' || status == 'FINAL';
    return status == _statusFilter;
  }

  Future<List<String>> _allUsers() async {
    final users = <String>{...kUserPasswords.keys};
    final payments = await widget.database.select(widget.database.householdPayments).get();
    final financial = await widget.database.select(widget.database.financialTransactions).get();
    final zakaat = await widget.database.select(widget.database.zakaatDisbursements).get();
    final adjustments = await widget.database.select(widget.database.fundAdjustments).get();
    final waivers = await WorkflowService.qarzaWaivers(widget.database);

    users.addAll(payments.map((r) => r.username.trim()).where((v) => v.isNotEmpty));
    users.addAll(financial.map((r) => r.username.trim()).where((v) => v.isNotEmpty));
    users.addAll(zakaat.map((r) => r.username.trim()).where((v) => v.isNotEmpty));
    users.addAll(adjustments.map((r) => r.username.trim()).where((v) => v.isNotEmpty));
    users.addAll(waivers.map((r) => r.username.trim()).where((v) => v.isNotEmpty));

    final result = users.toList();
    result.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return result;
  }

  Future<_ReportData> _load() async {
    if (_allTime) {
      final now = DateTime.now();
      _to = DateTime(now.year, now.month, now.day);
      _from = await _earliestRecordDate(_to);
    }
    final entries = <_ReportEntry>[];
    final deleted = <_DeletedReceipt>[];
    final collections = <String, double>{};
    final expenses = <String, double>{};

    double collected = 0;
    double spent = 0;
    double issued = 0;
    double recovered = 0;
    double waived = 0;
    final nonEffective = await WorkflowService.nonEffectiveKeys(widget.database);

    void addCollection(_ReportEntry entry) {
      if (entry.credit <= 0) return;
      collected += entry.credit;
      collections[entry.type] = (collections[entry.type] ?? 0) + entry.credit;
    }

    void addExpense(_ReportEntry entry) {
      if (entry.debit <= 0) return;
      if (entry.approvalStatus != 'FINAL' && entry.approvalStatus != 'APPROVED') return;
      spent += entry.debit;
      expenses[entry.type] = (expenses[entry.type] ?? 0) + entry.debit;
    }

    final households = await widget.database.select(widget.database.households).get();
    final householdNames = <int, String>{for (final h in households) h.id: h.name};

    // 1. Monthly donations: Collections.
    final payments = await widget.database.select(widget.database.householdPayments).get();
    for (final p in payments) {
      const type = 'Monthly Donation';
      if (!_inRange(p.paymentDate)) continue;
      final party = householdNames[p.householdId] ?? 'Household ${p.householdId}';
      if (!_includeEntry(type, p.username, party)) continue;
      final entry = _ReportEntry(
        p.paymentDate,
        p.amount,
        0,
        p.receiptNumber ?? '—',
        type,
        party,
        p.username,
        source: LedgerSource.memberPayment,
        id: p.id,
      );
      entries.add(entry);
      addCollection(entry);
    }

    // 2. Normal incoming receipts: all collection heads.
    final financial = await widget.database.select(widget.database.financialTransactions).get();
    for (final t in financial) {
      if (!_inRange(t.transactionDate)) continue;
      final category = t.category.toUpperCase();
      final type = switch (category) {
        'GD' || 'GENERAL_DONATION' => 'General Donation',
        'BD' || 'BOX_DONATION' => 'Box Collection',
        'OI' || 'OTHER_INCOME' => 'Other Income',
        'ZK' || 'ZAKAAT' => 'Zakaat',
        'SF' || 'SADQA_FITR' => 'Sadqa-e-Fitr',
        _ => category,
      };
      final party = (t.donorName ?? '').trim();
      if (!_includeEntry(type, t.username, party)) continue;
      final entry = _ReportEntry(
        t.transactionDate,
        t.amount,
        0,
        t.receiptNumber ?? '—',
        type,
        party,
        t.username,
        source: LedgerSource.financial,
        id: t.id,
      );
      entries.add(entry);
      addCollection(entry);
    }

    // 3. Zakaat expenditure: Spent.
    final zakaatRows = await widget.database.select(widget.database.zakaatDisbursements).get();
    for (final d in zakaatRows) {
      final statusInfo = await WorkflowService.approvalInfo(widget.database, sourceTable: 'zakaat_disbursements', transactionId: d.id);
      final approvalStatus = statusInfo['status'] as String? ?? 'FINAL';
      final approvalReason = statusInfo['rejection_reason'] as String? ?? '';
      final approvalRejectedBy = statusInfo['rejected_by'] as String? ?? '';
      const type = 'Zakaat Expenditure';
      if (!_inRange(d.disbursementDate)) continue;
      if (!_includeEntry(type, d.username, d.recipientName)) continue;
      final entry = _ReportEntry(
        d.disbursementDate,
        0,
        d.amount,
        d.voucherNumber ?? '—',
        type,
        d.recipientName,
        d.username,
        approvalStatus: approvalStatus,
        approvalReason: approvalReason,
        approvalRejectedBy: approvalRejectedBy,
        approvalBy: statusInfo['approved_by']?.toString() ?? '',
        source: LedgerSource.zakaat,
        id: d.id,
      );
      entries.add(entry);
      if (approvalStatus == 'FINAL' || approvalStatus == 'APPROVED') addExpense(entry);
    }

    // 4. Fund adjustments: Qarz, Sadqa expenditure, Other expense, and deletion audit.
    final adjustments = await widget.database.select(widget.database.fundAdjustments).get();
    for (final a in adjustments) {
      final approvalInfo = (a.adjustmentType == 'QARZA_DISBURSEMENT' || a.adjustmentType == 'OTHER_EXPENSE' || a.adjustmentType == 'SADQA_EXPENSE')
          ? await WorkflowService.approvalInfo(widget.database, sourceTable: 'fund_adjustments', transactionId: a.id)
          : <String, Object?>{'status': 'FINAL'};
      final approvalStatus = approvalInfo['status'] as String? ?? 'FINAL';
      final approvalReason = approvalInfo['rejection_reason'] as String? ?? '';
      final approvalRejectedBy = approvalInfo['rejected_by'] as String? ?? '';
      if (a.adjustmentType == 'DELETED_RECEIPT') {
        if (_inRange(a.transactionDate)) {
          final originalType = a.partyName?.trim();
          final auditType = (originalType == null || originalType.isEmpty)
              ? 'Deleted Receipt'
              : originalType;
          if (_userMatches(a.username) || _user == 'ALL') {
            deleted.add(_DeletedReceipt(
              date: a.transactionDate,
              receiptNumber: a.documentNumber ?? '—',
              amount: a.amount,
              type: auditType,
              username: a.username,
            ));
          }
        }
        continue;
      }

      if (!_inRange(a.transactionDate)) continue;
      final party = (a.partyName ?? '').trim();

      switch (a.adjustmentType) {
        case 'QARZA_DISBURSEMENT':
          const type = 'Qarz Issued';
          if (!_includeEntry(type, a.username, party)) continue;
          entries.add(_ReportEntry(a.transactionDate, 0, a.amount, a.documentNumber ?? '—', type, party, a.username, approvalStatus: approvalStatus, approvalReason: approvalReason, approvalRejectedBy: approvalRejectedBy, approvalBy: approvalInfo['approved_by']?.toString() ?? '', source: LedgerSource.fundAdjustment, id: a.id));
          if (approvalStatus == 'FINAL' || approvalStatus == 'APPROVED') issued += a.amount;
          break;

        case 'QARZA_RECOVERY':
          const type = 'Qarz Recovered';
          if (!_includeEntry(type, a.username, party)) continue;
          entries.add(_ReportEntry(a.transactionDate, a.amount, 0, a.documentNumber ?? '—', type, party, a.username, approvalStatus: approvalStatus, approvalReason: approvalReason, approvalRejectedBy: approvalRejectedBy, approvalBy: approvalInfo['approved_by']?.toString() ?? '', source: LedgerSource.fundAdjustment, id: a.id));
          if (approvalStatus == 'FINAL' || approvalStatus == 'APPROVED') recovered += a.amount;
          break;

        case 'SADQA_EXPENSE':
          const type = 'Sadqa-e-Fitr Expenditure';
          if (!_includeEntry(type, a.username, party)) continue;
          final entry = _ReportEntry(a.transactionDate, 0, a.amount, a.documentNumber ?? '—', type, party, a.username, approvalStatus: approvalStatus, approvalReason: approvalReason, approvalRejectedBy: approvalRejectedBy, approvalBy: approvalInfo['approved_by']?.toString() ?? '', source: LedgerSource.fundAdjustment, id: a.id);
          entries.add(entry);
          if (approvalStatus == 'FINAL' || approvalStatus == 'APPROVED') addExpense(entry);
          break;

        case 'OTHER_EXPENSE':
          const type = 'Other Expense';
          if (!_includeEntry(type, a.username, party)) continue;
          final entry = _ReportEntry(a.transactionDate, 0, a.amount, a.documentNumber ?? '—', type, party, a.username, approvalStatus: approvalStatus, approvalReason: approvalReason, approvalRejectedBy: approvalRejectedBy, approvalBy: approvalInfo['approved_by']?.toString() ?? '', source: LedgerSource.fundAdjustment, id: a.id);
          entries.add(entry);
          if (approvalStatus == 'FINAL' || approvalStatus == 'APPROVED') addExpense(entry);
          break;

        default:
          // Unknown adjustment types are not silently counted.
          break;
      }
    }

    final waivers = await WorkflowService.qarzaWaivers(widget.database);
    for (final w in waivers) {
      const type = 'Qarz Waived to Zakaat';
      if (!_inRange(w.date)) continue;
      if (!_includeEntry(type, w.username, w.borrowerName)) continue;
      final entry = _ReportEntry(w.date, 0, w.amount, w.waiverNumber, type, w.borrowerName, w.username, source: LedgerSource.qarzaWaiver, id: w.id);
      entries.add(entry);
      waived += w.amount;
      addExpense(entry);
    }

    entries.sort((a, b) {
      final byDate = b.date.compareTo(a.date);
      return byDate != 0 ? byDate : b.reference.compareTo(a.reference);
    });

    // Borrower balances are up to the selected report end date, but are not
    // affected by the report From date. This gives a meaningful outstanding
    // balance for the period ending at the selected To date.
    final reportEnd = DateTime(_to.year, _to.month, _to.day, 23, 59, 59);
    final borrowerMap = <String, _BorrowerSummary>{};
    for (final a in adjustments) {
      if (a.adjustmentType != 'QARZA_DISBURSEMENT' && a.adjustmentType != 'QARZA_RECOVERY') continue;
      if (nonEffective.contains('fund_adjustments:${a.id}')) continue;
      if (a.transactionDate.isAfter(reportEnd)) continue;
      final party = (a.partyName ?? '').trim();
      final type = a.adjustmentType == 'QARZA_DISBURSEMENT' ? 'Qarz Issued' : 'Qarz Recovered';
      if (!_userMatches(a.username) || !_partyMatches(party)) continue;
      if (!_typeMatches(type)) continue;
      if (!_scopeMatches(type)) continue;
      final name = party.isEmpty ? 'Unnamed' : party;
      final summary = borrowerMap.putIfAbsent(name, () => _BorrowerSummary(name));
      if (a.adjustmentType == 'QARZA_DISBURSEMENT') summary.issued += a.amount;
      if (a.adjustmentType == 'QARZA_RECOVERY') summary.recovered += a.amount;
    }
    for (final w in waivers) {
      if (w.date.isAfter(reportEnd)) continue;
      if (!_userMatches(w.username) || !_partyMatches(w.borrowerName)) continue;
      if (!_scopeMatches('Qarz Waived to Zakaat')) continue;
      if (_type != 'ALL' && _type != 'Qarz Waived to Zakaat') continue;
      final name = w.borrowerName.isEmpty ? 'Unnamed' : w.borrowerName;
      final summary = borrowerMap.putIfAbsent(name, () => _BorrowerSummary(name));
      summary.waived += w.amount;
    }

    // Recurring Zakaat beneficiaries: total received up to report end.
    final recurringTotals = <int, _RecurringBeneficiarySummary>{};
    for (final d in zakaatRows) {
      final statusInfo = await WorkflowService.approvalInfo(widget.database, sourceTable: 'zakaat_disbursements', transactionId: d.id);
      final approvalStatus = statusInfo['status'] as String? ?? 'FINAL';
      if (approvalStatus != 'FINAL' && approvalStatus != 'APPROVED') continue;
      if (d.disbursementType != 'RECURRING_MONTHLY' || d.beneficiaryId == null) continue;
      if (d.disbursementDate.isAfter(reportEnd)) continue;
      if (!_userMatches(d.username)) continue;
      final id = d.beneficiaryId!;
      final item = recurringTotals.putIfAbsent(
        id,
        () => _RecurringBeneficiarySummary(id, d.recipientName),
      );
      item.total += d.amount;
    }

    final beneficiaryRows = await widget.database.select(widget.database.zakaatBeneficiaries).get();
    final recurring = <_RecurringBeneficiarySummary>[];
    for (final b in beneficiaryRows) {
      final item = recurringTotals[b.id];
      if (item == null) continue;
      item.name = b.name;
      recurring.add(item);
    }
    recurring.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    final qarzaNet = recovered + waived - issued;
    final openingNet = await WorkflowService.totalOpeningBalance(
      widget.database,
      const ['MONTHLY_DONATION', 'GENERAL_DONATION', 'BOX_COLLECTION', 'OTHER_INCOME', 'OTHER_EXPENSE', 'ZAKAAT'],
    );
    final netAvailable = collected - spent + qarzaNet + openingNet;

    final disapprovedEntries = entries.where((r) => r.approvalStatus == 'REJECTED').toList();

    return _ReportData(
      rows: entries.where((r) => _statusMatches(r.approvalStatus)).toList(),
      collections: collections,
      expenses: expenses,
      borrowers: borrowerMap.values.toList()..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase())),
      recurringBeneficiaries: recurring,
      deletedReceipts: deleted..sort((a, b) => b.date.compareTo(a.date)),
      disapprovedTransactions: disapprovedEntries,
      collectedTotal: collected,
      spentTotal: spent,
      loanIssued: issued,
      loanRecovered: recovered,
      loanWaived: waived,
      qarzaNet: qarzaNet,
      netAvailable: netAvailable,
    );
  }

  Future<void> _showFilters() async {
    final users = await _allUsers();
    if (!mounted) return;

    var scope = _scope;
    var user = _user;
    var type = _type;
    var party = _party;
    var status = _statusFilter;
    final partyController = TextEditingController(text: party);

    try {
      final applied = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (ctx, setLocal) => AlertDialog(
            title: const Text('Filter Reports'),
            content: SingleChildScrollView(
              child: SizedBox(
                width: 430,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: _scopes.contains(scope) ? scope : 'ALL',
                      decoration: const InputDecoration(labelText: 'Ledger / Scope', border: OutlineInputBorder()),
                      items: const [
                        DropdownMenuItem(value: 'ALL', child: Text('All Ledgers')),
                        DropdownMenuItem(value: 'DONATIONS', child: Text('Donations')),
                        DropdownMenuItem(value: 'ZAKAAT', child: Text('Zakaat')),
                        DropdownMenuItem(value: 'SADQA_FITR', child: Text('Sadqa-e-Fitr')),
                        DropdownMenuItem(value: 'QARZA', child: Text('Qarz-e-Hassanah')),
                      ],
                      onChanged: (v) => setLocal(() => scope = v ?? 'ALL'),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      initialValue: users.contains(user) ? user : 'ALL',
                      decoration: const InputDecoration(labelText: 'User', border: OutlineInputBorder()),
                      items: [
                        const DropdownMenuItem(value: 'ALL', child: Text('All Users')),
                        ...users.map((u) => DropdownMenuItem(value: u, child: Text(u))),
                      ],
                      onChanged: (v) => setLocal(() => user = v ?? 'ALL'),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      initialValue: type == 'ALL' || _types.contains(type) ? type : 'ALL',
                      decoration: const InputDecoration(labelText: 'Transaction Type', border: OutlineInputBorder()),
                      items: [
                        const DropdownMenuItem(value: 'ALL', child: Text('All Transaction Types')),
                        ..._types.map((t) => DropdownMenuItem(value: t, child: Text(t))),
                      ],
                      onChanged: (v) => setLocal(() => type = v ?? 'ALL'),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      initialValue: status,
                      decoration: const InputDecoration(labelText: 'Approval Status', border: OutlineInputBorder()),
                      items: const [
                        DropdownMenuItem(value: 'ALL', child: Text('All Statuses')),
                        DropdownMenuItem(value: 'PENDING', child: Text('Pending')),
                        DropdownMenuItem(value: 'APPROVED', child: Text('Approved')),
                        DropdownMenuItem(value: 'REJECTED', child: Text('Disproved')),
                      ],
                      onChanged: (v) => setLocal(() => status = v ?? 'ALL'),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: partyController,
                      decoration: const InputDecoration(
                        labelText: 'Party / Beneficiary / Member',
                        hintText: 'Enter a name or part of a name',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (v) => party = v,
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  scope = 'ALL';
                  user = 'ALL';
                  type = 'ALL';
                  party = '';
                  status = 'ALL';
                  partyController.clear();
                  Navigator.of(dialogContext).pop(true);
                },
                child: const Text('Clear'),
              ),
              TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Cancel')),
              FilledButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: const Text('Apply')),
            ],
          ),
        ),
      );

      if (!mounted || applied != true) return;
      setState(() {
        _scope = scope;
        _user = user;
        _type = type;
        _party = party.trim();
        _statusFilter = status;
        _future = _load();
      });
    } finally {
      partyController.dispose();
    }
  }

  String _date(DateTime date) => ReceiptActions.formatDate(date);

  String _filterLabel() {
    final parts = <String>[];
    if (_scope != 'ALL') {
      parts.add(switch (_scope) {
        'DONATIONS' => 'Donations',
        'ZAKAAT' => 'Zakaat',
        'SADQA_FITR' => 'Sadqa-e-Fitr',
        'QARZA' => 'Qarz-e-Hassanah',
        _ => _scope,
      });
    }
    if (_user != 'ALL') parts.add('User: $_user');
    if (_type != 'ALL') parts.add('Type: $_type');
    if (_party.trim().isNotEmpty) parts.add('Party: ${_party.trim()}');
    return parts.isEmpty ? 'Filter: All Reports' : 'Filter: ${parts.join(' • ')}';
  }

  Future<Uint8List> _reportPdf(_ReportData data) async {
    var running = 0.0;
    final chronological = [...data.rows]..sort((a, b) => a.date.compareTo(b.date));
    final balances = <_ReportEntry, double>{};
    for (final r in chronological) {
      running += r.credit - r.debit;
      balances[r] = running;
    }

    final rows = data.rows
        .map((r) => [
              _date(r.date),
              '₹${(r.credit == 0 ? r.debit : r.credit).asAmount}',
              r.credit == 0 ? 'DEBIT' : 'CREDIT',
              r.reference,
              r.party,
              r.type,
              'INR ${(balances[r] ?? 0).asAmount}',
              r.username,
            ])
        .toList();

    return ReceiptActions.ledgerDocument(
      title: 'Financial Report ${_date(_from)} - ${_date(_to)}',
      rows: rows,
    ).save();
  }

  Future<void> _generateFormalBalanceSheet() async {
    if (!_authorized) return;
    if (_from.isAfter(_to)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('The report start date must be on or before the end date.')),
      );
      return;
    }
    try {
      final bytes = await FormalFinancialReport.build(widget.database, from: _from, to: _to);
      await ReceiptActions.printPdf(
        bytes: bytes,
        fileName: 'AABM-Balance-Sheet-${_from.year}-${_to.year}.pdf',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not generate the balance sheet: $e')),
      );
    }
  }

  Future<void> _print(_ReportData data) async {
    await ReceiptActions.printPdf(
      bytes: await _reportPdf(data),
      fileName: 'Al-Amin-Report.pdf',
    );
  }

  Future<void> _share(_ReportData data) async {
    await ReceiptActions.sharePdf(
      bytes: await _reportPdf(data),
      fileName: 'Al-Amin-Report.pdf',
      message: 'Al-Amin Baitul Maal Financial Report ${_date(_from)} to ${_date(_to)}',
    );
  }

  Future<void> _showReportEntry(_ReportEntry entry) async {
    try {
      Future<Uint8List> buildPdf() async {
        switch (entry.type) {
          case 'Qarz Waived to Zakaat':
            final waiverRows = await WorkflowService.qarzaWaivers(widget.database);
            final w = waiverRows.firstWhere((x) => x.waiverNumber == entry.reference);
            final waiverFigures = await WorkflowService.qarzaWaiverFigures(widget.database, w);
            return (await ReceiptActions.qarzaWaiverVoucherDocument(
              figures: waiverFigures,
              waiverNumber: w.waiverNumber,
              date: w.date,
              borrowerName: w.borrowerName,
              originalQarzaNumber: w.originalQarzaNumber,
              amount: w.amount,
              username: w.username,
              remarks: w.remarks,
            )).save();

          case 'Monthly Donation':
            final rows = await (widget.database.select(widget.database.householdPayments)
                  ..where((p) => p.receiptNumber.equals(entry.reference)))
                .get();
            if (rows.isEmpty) throw StateError('Monthly donation receipt not found.');
            final p = rows.first;
            return ReceiptActions.thermalReceiptDocument(
              title: 'MONTHLY DONATION RECEIPT',
              documentNumber: entry.reference,
              date: p.paymentDate,
              rows: [
                ReceiptActions.thermalRow('Member', entry.party.isEmpty ? '—' : entry.party),
                ReceiptActions.thermalRow('Payment Mode', p.paymentMode),
                ReceiptActions.thermalRow('Amount', 'INR ${p.amount.asAmount}'),
              ],
              amountWords: ReceiptActions.amountInWords(p.amount),
            ).save();

          case 'General Donation':
          case 'Box Collection':
          case 'Zakaat':
          case 'Sadqa-e-Fitr':
            final rows = await (widget.database.select(widget.database.financialTransactions)
                  ..where((t) => t.receiptNumber.equals(entry.reference)))
                .get();
            if (rows.isEmpty) throw StateError('Receipt not found.');
            final t = rows.first;
            return ReceiptActions.thermalReceiptDocument(
              title: '${entry.type.toUpperCase()} RECEIPT',
              documentNumber: entry.reference,
              date: t.transactionDate,
              rows: [
                ReceiptActions.thermalRow('Name', (t.donorName ?? '').trim().isEmpty ? '—' : t.donorName!.trim()),
                ReceiptActions.thermalRow('Payment Mode', t.paymentMode),
                ReceiptActions.thermalRow('Amount', 'INR ${t.amount.asAmount}'),
              ],
              amountWords: ReceiptActions.amountInWords(t.amount),
              remarks: t.remarks,
            ).save();

          case 'Other Income':
            final rows = await (widget.database.select(widget.database.financialTransactions)
                  ..where((t) => t.receiptNumber.equals(entry.reference)))
                .get();
            if (rows.isEmpty) throw StateError('Other Income receipt not found.');
            final t = rows.first;
            return ReceiptActions.thermalReceiptDocument(
              title: 'OTHER INCOME RECEIPT',
              documentNumber: entry.reference,
              date: t.transactionDate,
              rows: [
                ReceiptActions.thermalRow('Received from', (t.donorName ?? '').trim().isEmpty ? '—' : t.donorName!.trim()),
                ReceiptActions.thermalRow('On account of', 'Other Income'),
                ReceiptActions.thermalRow('Payment Mode', t.paymentMode),
                ReceiptActions.thermalRow('Amount', 'INR ${t.amount.asAmount}'),
              ],
              amountWords: ReceiptActions.amountInWords(t.amount),
              totalSettled: 'INR ${t.amount.asAmount}',
              remarks: t.remarks,
            ).save();

          case 'Zakaat Expenditure':
            final rows = await (widget.database.select(widget.database.zakaatDisbursements)
                  ..where((d) => d.voucherNumber.equals(entry.reference)))
                .get();
            if (rows.isEmpty) throw StateError('Zakaat voucher not found.');
            final d = rows.first;
            return ReceiptActions.zakaatVoucherDocument(
              voucherNumber: d.voucherNumber ?? entry.reference,
              date: d.disbursementDate,
              recipientName: d.recipientName,
              address: d.recipientAddress ?? '',
              aadhaar: d.aadhaarNumber ?? '',
              phone: d.phoneNumber ?? '',
              amount: d.amount,
              reason: d.reason ?? '',
              authority: d.issuingAuthorityReport ?? '',
              cheque: d.chequeNumber ?? '',
              paymentMode: d.paymentMode,
              verification: d.verification ?? '',
              verifiedBy1: d.verifiedBy1 ?? '',
              verifiedBy2: d.verifiedBy2 ?? '',
              verifiedBy3: d.verifiedBy3 ?? '',
              remarks: d.remarks ?? '',
              recipientSignature: d.recipientSignature,
              accountantSignature: d.accountantSignature,
              preparedBy: d.username,
            ).save();

          case 'Qarz Issued':
          case 'Qarz Recovered':
            final rows = await (widget.database.select(widget.database.fundAdjustments)
                  ..where((a) => a.documentNumber.equals(entry.reference)))
                .get();
            if (rows.isEmpty) throw StateError('Qarz form not found.');
            final a = rows.first;
            final parentage = await WorkflowService.parentage(widget.database, a.documentNumber ?? entry.reference);
            final conditions = await WorkflowService.conditions(widget.database, a.documentNumber ?? entry.reference);
            final borrowerRows = await (widget.database.select(widget.database.fundAdjustments)
                  ..where((x) => x.partyName.equals(a.partyName ?? '') &
                      (x.adjustmentType.equals('QARZA_DISBURSEMENT') | x.adjustmentType.equals('QARZA_RECOVERY')))
                  ..orderBy([
                    (x) => OrderingTerm(expression: x.transactionDate),
                    (x) => OrderingTerm(expression: x.id),
                  ]))
                .get();
            var borrowedTotal = 0.0;
            var returnedTotal = 0.0;
            var balanceAfterReceipt = 0.0;
            for (final row in borrowerRows) {
              if (row.adjustmentType == 'QARZA_DISBURSEMENT') {
                borrowedTotal += row.amount;
                balanceAfterReceipt += row.amount;
              } else {
                returnedTotal += row.amount;
                balanceAfterReceipt -= row.amount;
              }
              if (row.id == a.id) break;
            }
            if (balanceAfterReceipt < 0) balanceAfterReceipt = 0;
            return ReceiptActions.qarzaVoucherDocument(
              documentNumber: a.documentNumber ?? entry.reference,
              date: a.transactionDate,
              party: a.partyName ?? '',
              parentage: parentage,
              conditions: conditions,
              address: a.address ?? '',
              aadhaar: a.aadhaarNumber ?? '',
              phone: a.phoneNumber ?? '',
              amount: a.amount,
              chequeNumber: a.chequeNumber ?? '',
              paymentMode: a.paymentMode,
              operation: a.adjustmentType == 'QARZA_DISBURSEMENT' ? 'ISSUE' : 'RECOVERY',
              amountBorrowed: borrowedTotal,
              totalReturned: returnedTotal,
              balanceAfter: balanceAfterReceipt,
              verification: a.verification ?? '',
              verifiedBy1: a.verifiedBy1 ?? '',
              verifiedBy2: a.verifiedBy2 ?? '',
              verifiedBy3: a.verifiedBy3 ?? '',
              remarks: a.remarks ?? '',
              recipientSignature: a.recipientSignature,
              accountantSignature: a.accountantSignature,
              preparedBy: a.username,
            ).save();

          case 'Sadqa-e-Fitr Expenditure':
          case 'Other Expense':
            final rows = await (widget.database.select(widget.database.fundAdjustments)
                  ..where((a) => a.documentNumber.equals(entry.reference)))
                .get();
            if (rows.isEmpty) throw StateError('Expense voucher not found.');
            final a = rows.first;
            return ReceiptActions.fundAdjustmentVoucherDocument(
              title: entry.type.toUpperCase(),
              documentNumber: a.documentNumber ?? entry.reference,
              date: a.transactionDate,
              fundLabel: entry.type == 'Sadqa-e-Fitr Expenditure' ? 'Sadqa-e-Fitr' : 'Donations',
              party: a.partyName ?? '',
              address: a.address,
              aadhaar: a.aadhaarNumber,
              phone: a.phoneNumber,
              amount: a.amount,
              chequeNumber: a.chequeNumber,
              paymentMode: a.paymentMode,
              verification: a.verification,
              verifiedBy1: a.verifiedBy1,
              verifiedBy2: a.verifiedBy2,
              verifiedBy3: a.verifiedBy3,
              remarks: a.remarks,
              recipientSignature: a.recipientSignature,
              accountantSignature: a.accountantSignature,
              preparedBy: a.username,
            ).save();

          default:
            return ReceiptActions.baseDocument(
              title: entry.type.toUpperCase(),
              documentNumber: entry.reference,
              date: ReceiptActions.formatDate(entry.date),
              rows: [
                ReceiptActions.pdfRow('Party / Description', entry.party.isEmpty ? '—' : entry.party),
                ReceiptActions.pdfRow('Amount', 'INR ${(entry.credit == 0 ? entry.debit : entry.credit).asAmount}'),
                ReceiptActions.pdfRow('Debit / Credit', entry.credit == 0 ? 'Debit' : 'Credit'),
                ReceiptActions.pdfRow('Username', entry.username),
              ],
            ).save();
        }
      }

      await ReceiptActions.showActionsDialog(
        context: context,
        documentNumber: entry.reference,
        title: '${entry.type} - ${entry.reference}',
        fileNamePrefix: entry.type.replaceAll(' ', '-'),
        shareMessage: 'Al-Amin Baitul Maal - ${entry.type} ${entry.reference}\nParty: ${entry.party}\nAmount: INR ${(entry.credit == 0 ? entry.debit : entry.credit).asAmount}',
        buildPdf: buildPdf,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not open receipt: $e')));
      }
    }
  }

  Future<void> _showBorrowers(List<_BorrowerSummary> borrowers) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Qarz Borrowers'),
        content: SizedBox(
          width: 500,
          child: borrowers.isEmpty
              ? const Text('No Qarza borrowers found for the selected filters.')
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: borrowers.length,
                  itemBuilder: (context, index) {
                    final b = borrowers[index];
                    final owes = (b.issued - b.recovered - b.waived).clamp(0, double.infinity).toDouble();
                    return Card(
                      child: ListTile(
                        title: Text(b.name),
                        subtitle: Text('Issued: ₹${b.issued.asAmount}   Recovered: ₹${b.recovered.asAmount}   Waived: ₹${b.waived.asAmount}'),
                        trailing: Text(
                          'Owes ₹${owes.asAmount}',
                          style: TextStyle(fontWeight: FontWeight.bold, color: owes > .005 ? Colors.red.shade700 : kBrandGreen),
                        ),
                        onTap: () async {
                          Navigator.of(ctx).pop();
                          await Navigator.push(context, MaterialPageRoute(builder: (_) => QarzaBorrowerLedgerPage(database: widget.database, borrowerName: b.name)));
                          if (mounted) {
                            setState(() {
                              _future = _load();
                            });
                          }
                        },
                      ),
                    );
                  },
                ),
        ),
        actions: [TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Close'))],
      ),
    );
  }

  Future<void> _showRecurring(List<_RecurringBeneficiarySummary> beneficiaries) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Recurring Monthly Zakaat Beneficiaries'),
        content: SizedBox(
          width: 500,
          child: beneficiaries.isEmpty
              ? const Text('No recurring monthly Zakaat beneficiaries found.')
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: beneficiaries.length,
                  itemBuilder: (context, index) {
                    final b = beneficiaries[index];
                    return ListTile(
                      leading: const Icon(Icons.person_outline),
                      title: Text(b.name),
                      trailing: Text(
                        '₹${b.total.asAmount}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    );
                  },
                ),
        ),
        actions: [TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Close'))],
      ),
    );
  }

  Future<void> _showDeleted(List<_DeletedReceipt> rows) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Deleted Receipts Ledger'),
        content: SizedBox(
          width: 700,
          child: rows.isEmpty
              ? const Text('No deleted receipts found for the selected period.')
              : SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columns: const [
                      DataColumn(label: Text('Deleted Date')),
                      DataColumn(label: Text('Receipt / Form No.')),
                      DataColumn(label: Text('Amount')),
                      DataColumn(label: Text('Type')),
                      DataColumn(label: Text('Deleted By')),
                    ],
                    rows: rows
                        .map(
                          (r) => DataRow(cells: [
                            DataCell(Text(_date(r.date))),
                            DataCell(Text(r.receiptNumber)),
                            DataCell(Text('₹${r.amount.asAmount}')),
                            DataCell(Text(r.type)),
                            DataCell(Text(r.username)),
                          ]),
                        )
                        .toList(),
                  ),
                ),
        ),
        actions: [TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Close'))],
      ),
    );
  }

  Future<void> _showDisapproved(List<_ReportEntry> rows) async {
    final items = rows.where((r) => r.approvalStatus == 'REJECTED').toList();
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Disproved Transactions'),
        content: SizedBox(
          width: 760,
          child: items.isEmpty
              ? const Text('No disproved transactions found for the selected period and filters.')
              : SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columns: const [
                      DataColumn(label: Text('Date')),
                      DataColumn(label: Text('Reference')),
                      DataColumn(label: Text('Type')),
                      DataColumn(label: Text('Party')),
                      DataColumn(label: Text('Amount')),
                      DataColumn(label: Text('Disproved By')),
                      DataColumn(label: Text('Reason')),
                    ],
                    rows: items.map((r) => DataRow(cells: [
                      DataCell(Text(_date(r.date))),
                      DataCell(Text(r.reference)),
                      DataCell(Text(r.type)),
                      DataCell(Text(r.party.isEmpty ? '—' : r.party)),
                      DataCell(Text('₹${(r.credit == 0 ? r.debit : r.credit).asAmount}')),
                      DataCell(Text(r.approvalRejectedBy.isEmpty ? '—' : r.approvalRejectedBy)),
                      DataCell(SizedBox(width: 280, child: Text(r.approvalReason.isEmpty ? '—' : r.approvalReason))),
                    ])).toList(),
                  ),
                ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
        ],
      ),
    );
  }

  bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

  /// Start of the year of the oldest record, so "All Time" covers everything.
  Future<DateTime> _earliestRecordDate(DateTime today) async {
    try {
      final records = await ChartDataService.load(widget.database);
      DateTime? earliest;
      for (final r in records) {
        if (earliest == null || r.date.isBefore(earliest)) earliest = r.date;
      }
      return DateTime((earliest ?? today).year, 1, 1);
    } catch (_) {
      return DateTime(today.year, 1, 1);
    }
  }

  void _setAllTime() {
    setState(() {
      _allTime = true;
      _future = _load();
    });
  }

  void _setRange(DateTime from, DateTime to) {
    setState(() {
      _allTime = false;
      _from = DateTime(from.year, from.month, from.day);
      _to = DateTime(to.year, to.month, to.day);
      _future = _load();
    });
  }

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final last = DateTime(now.year, now.month, now.day);
    final start = _from.isAfter(last) ? last : _from;
    var end = _to.isAfter(last) ? last : _to;
    if (end.isBefore(start)) end = start;
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(1950),
      lastDate: last,
      initialDateRange: DateTimeRange(start: start, end: end),
      helpText: 'Select report period',
      saveText: 'Apply',
    );
    if (!mounted || picked == null) return;
    _setRange(picked.start, picked.end);
  }

  /// One bordered box showing the report period; tap it to choose a range, or
  /// use a shortcut. The same period applies to every report view.
  Widget _dateRangeBox() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final monthStart = DateTime(today.year, today.month, 1);
    final lastMonthStart = DateTime(today.year, today.month - 1, 1);
    final lastMonthEnd = DateTime(today.year, today.month, 0);
    final yearStart = DateTime(today.year, 1, 1);
    Widget chip(String label, bool selected, VoidCallback onTap) => ChoiceChip(
          label: Text(label, style: const TextStyle(fontSize: 12)),
          visualDensity: VisualDensity.compact,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          selected: selected,
          onSelected: (_) => onTap(),
        );
    bool isRange(DateTime from, DateTime to) => !_allTime && _sameDay(_from, from) && _sameDay(_to, to);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .92),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kBrandGreen.withValues(alpha: .35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: _pickRange,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  const Icon(Icons.date_range, color: kBrandGreen),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Report period', style: TextStyle(fontSize: 11.5, color: Colors.black54)),
                        Text(
                          _allTime ? 'All Time' : '${_date(_from)}  \u2192  ${_date(_to)}',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                        ),
                        if (_allTime)
                          Text(
                            '${_date(_from)}  \u2192  ${_date(_to)}',
                            style: const TextStyle(fontSize: 12, color: Colors.black54),
                          ),
                      ],
                    ),
                  ),
                  const Icon(Icons.arrow_drop_down),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            children: [
              chip('All Time', _allTime, _setAllTime),
              chip('Today', isRange(today, today), () => _setRange(today, today)),
              chip('This Month', isRange(monthStart, today), () => _setRange(monthStart, today)),
              chip('Last Month', isRange(lastMonthStart, lastMonthEnd), () => _setRange(lastMonthStart, lastMonthEnd)),
              chip('This Year', isRange(yearStart, today), () => _setRange(yearStart, today)),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _openEditor(_ReportEntry r, {bool delete = false}) async {
    final source = r.source;
    final id = r.id;
    if (source == null || id == null) return;
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => EditTransactionPage(
          database: widget.database,
          source: source,
          id: id,
          title: r.type,
          deleteOnOpen: delete,
        ),
      ),
    );
    if (changed == true && mounted) {
      setState(() {
        _future = _load();
      });
    }
  }

  String _viewTitle() {
    switch (_view) {
      case _ReportView.summary:
        return 'Reports';
      case _ReportView.detailed:
        return 'Detailed Transactions';
      case _ReportView.charts:
        return 'Income & Expense Charts';
    }
  }

  Widget _reportsDrawer() {
    return Drawer(
      child: SafeArea(
        child: FutureBuilder<_ReportData>(
          future: _future,
          builder: (context, snap) {
            final data = snap.data;
            Widget item(IconData icon, String label, VoidCallback? onTap, {bool selected = false, int? count}) {
              return ListTile(
                dense: true,
                selected: selected,
                selectedColor: kBrandGreen,
                selectedTileColor: kBrandGreen.withValues(alpha: .10),
                leading: Icon(icon, color: onTap == null ? Colors.black26 : kBrandGreen),
                title: Text(label),
                trailing: count == null
                    ? null
                    : Text('$count', style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.black54)),
                onTap: onTap == null
                    ? null
                    : () {
                        Navigator.of(context).pop();
                        onTap();
                      },
              );
            }

            return ListView(
              padding: EdgeInsets.zero,
              children: [
                Container(
                  padding: const EdgeInsets.fromLTRB(20, 20, 16, 14),
                  color: kBrandGreen,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Reports', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 4),
                      Text(_allTime ? 'All Time' : '${_date(_from)}  \u2192  ${_date(_to)}', style: const TextStyle(color: Colors.white70)),
                    ],
                  ),
                ),
                item(
                  Icons.table_rows_outlined,
                  'Detailed Transactions',
                  () => setState(() => _view = _ReportView.detailed),
                  selected: _view == _ReportView.detailed,
                  count: data?.rows.length,
                ),
                item(Icons.account_balance_outlined, 'Generate Formal Balance Sheet', _generateFormalBalanceSheet),
                item(
                  Icons.bar_chart_rounded,
                  'Income & Expense Charts',
                  () => setState(() => _view = _ReportView.charts),
                  selected: _view == _ReportView.charts,
                ),
                const Divider(),
                item(Icons.people_alt_outlined, 'Qarz Borrowers',
                    data == null ? null : () => _showBorrowers(data.borrowers), count: data?.borrowers.length),
                item(Icons.calendar_month_outlined, 'Recurring Monthly Zakaat',
                    data == null ? null : () => _showRecurring(data.recurringBeneficiaries),
                    count: data?.recurringBeneficiaries.length),
                item(Icons.delete_sweep_outlined, 'Deleted Receipts Ledger',
                    data == null ? null : () => _showDeleted(data.deletedReceipts), count: data?.deletedReceipts.length),
                item(Icons.block_outlined, 'Disproved Transactions',
                    data == null ? null : () => _showDisapproved(data.disapprovedTransactions),
                    count: data?.disapprovedTransactions.length),
                const Divider(),
                item(Icons.filter_alt_outlined, 'Filters', _showFilters),
                item(
                  Icons.dashboard_outlined,
                  'Summary',
                  () => setState(() => _view = _ReportView.summary),
                  selected: _view == _ReportView.summary,
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _statusCell(_ReportEntry r) {
    final IconData icon;
    final Color color;
    final String label;
    if (r.approvalStatus == 'REJECTED') {
      icon = Icons.cancel_outlined;
      color = Colors.red.shade700;
      label = 'Disproved';
    } else if (r.approvalStatus == 'PENDING') {
      icon = Icons.schedule;
      color = Colors.orange.shade800;
      label = 'Pending';
    } else {
      icon = Icons.check_circle_outline;
      color = Colors.green.shade700;
      label = 'Approved';
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 12.5, color: color, fontWeight: FontWeight.w600)),
      ],
    );
  }

  /// Compact table: every column is only as wide as its own text (long names
  /// wrap), so more of the row is visible on a phone.
  Widget _detailedTable(_ReportData data) {
    if (data.rows.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(18),
          child: Text('No transactions found for the selected period and filters.'),
        ),
      );
    }
    const cell = TextStyle(fontSize: 12.5);
    Widget wrapped(String text, {double max = 170, TextStyle style = cell}) => ConstrainedBox(
          constraints: BoxConstraints(maxWidth: max),
          child: Text(text, style: style, softWrap: true),
        );
    final rows = <DataRow>[];
    for (var i = 0; i < data.rows.length; i++) {
      final r = data.rows[i];
      final rejectedRow = r.approvalStatus == 'REJECTED';
      final pendingRow = r.approvalStatus == 'PENDING';
      final shade = rejectedRow
          ? const Color(0xFFFFCDD2)
          : pendingRow
              ? const Color(0xFFFFF3B0)
              : (i.isEven ? Colors.white : const Color(0xFFF4F8F6));
      final isCredit = r.credit != 0;
      final amount = isCredit ? r.credit : r.debit;
      final canEdit = r.source != null && r.id != null;
      rows.add(
        DataRow(
          color: WidgetStatePropertyAll(shade),
          cells: [
            DataCell(Text(_date(r.date), style: cell)),
            DataCell(
              Text(
                r.reference,
                style: const TextStyle(
                  fontSize: 12.5,
                  color: Colors.blue,
                  decoration: TextDecoration.underline,
                ),
              ),
              onTap: r.reference == '\u2014' ? null : () => _showReportEntry(r),
            ),
            DataCell(wrapped(r.party.isEmpty ? '\u2014' : r.party)),
            DataCell(
              Tooltip(
                message: r.approvalReason.isEmpty ? '' : 'Disproof reason: ${r.approvalReason}',
                child: wrapped(r.type, max: 150),
              ),
            ),
            DataCell(
              Text(
                '\u20B9${amount.asAmount}',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: isCredit ? Colors.green.shade800 : Colors.red.shade700,
                ),
              ),
            ),
            DataCell(
              Text(
                isCredit ? 'Credit' : 'Debit',
                style: TextStyle(
                  fontSize: 12.5,
                  color: isCredit ? Colors.green.shade700 : Colors.red.shade700,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            DataCell(_statusCell(r)),
            DataCell(Text(r.username, style: cell)),
            DataCell(Text(r.approvalBy.isEmpty ? '\u2014' : r.approvalBy, style: cell)),
            DataCell(
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Modify transaction',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.edit_outlined, size: 20),
                    onPressed: canEdit ? () => _openEditor(r) : null,
                  ),
                  IconButton(
                    tooltip: 'Delete transaction',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.delete_outline, size: 20, color: Colors.red),
                    onPressed: canEdit ? () => _openEditor(r, delete: true) : null,
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }
    return Card(
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: constraints.maxWidth),
            child: DataTable(
              columnSpacing: 16,
              horizontalMargin: 10,
              headingRowHeight: 42,
              dataRowMinHeight: 40,
              dataRowMaxHeight: 64,
              headingTextStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5, color: kBrandGreen),
              columns: const [
                DataColumn(label: Text('Date')),
                DataColumn(label: Text('Reference')),
                DataColumn(label: Text('Party')),
                DataColumn(label: Text('Type')),
                DataColumn(label: Text('Amount')),
                DataColumn(label: Text('Dr/Cr')),
                DataColumn(label: Text('Approval')),
                DataColumn(label: Text('User')),
                DataColumn(label: Text('Approved By')),
                DataColumn(label: Text('Actions')),
              ],
              rows: rows,
            ),
          ),
        ),
      ),
    );
  }

  Widget _reportBody(_ReportData data) {
    final children = <Widget>[];
    if (_view == _ReportView.summary) {
      children.add(const BrandTitle());
      children.add(const SizedBox(height: 12));
    }
    children.add(_dateRangeBox());
    children.add(const SizedBox(height: 10));
    children.add(
      OutlinedButton.icon(
        onPressed: _showFilters,
        icon: const Icon(Icons.filter_alt_outlined),
        label: Text(_filterLabel(), maxLines: 2, overflow: TextOverflow.ellipsis),
        style: OutlinedButton.styleFrom(alignment: Alignment.centerLeft),
      ),
    );
    children.add(const SizedBox(height: 16));
    switch (_view) {
      case _ReportView.summary:
        children.add(_summaryCards(data));
        children.add(const SizedBox(height: 12));
        children.add(_qarzaSummary(data));
        children.add(const SizedBox(height: 12));
        children.add(_netAvailableCard(data));
        children.add(const SizedBox(height: 14));
        children.add(
          const Text(
            'Open the menu (\u2630, top left) for Detailed Transactions, the Formal Balance Sheet, charts, Qarz borrowers and more.',
            style: TextStyle(fontSize: 12.5, color: Colors.black54),
          ),
        );
        break;
      case _ReportView.detailed:
        children.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              '${data.rows.length} transaction(s). Scroll sideways for more columns.',
              style: const TextStyle(fontSize: 12.5, color: Colors.black54),
            ),
          ),
        );
        children.add(_detailedTable(data));
        break;
      case _ReportView.charts:
        children.add(
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text(
              'Last 12 months up to the report end date. Approved transactions only.',
              style: TextStyle(fontSize: 12.5, color: Colors.black54),
            ),
          ),
        );
        children.add(FinanceChartsLoader(key: ObjectKey(data), database: widget.database, to: _to));
        break;
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_authorized) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      drawer: _reportsDrawer(),
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leadingWidth: 104,
        leading: Row(
          children: [
            IconButton(
              tooltip: 'Back',
              icon: const Icon(Icons.arrow_back),
              onPressed: () => Navigator.of(context).maybePop(),
            ),
            Builder(
              builder: (ctx) => IconButton(
                tooltip: 'Reports menu',
                icon: const Icon(Icons.menu_rounded),
                onPressed: () => Scaffold.of(ctx).openDrawer(),
              ),
            ),
          ],
        ),
        title: Text(_viewTitle(), maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          FutureBuilder<_ReportData>(
            future: _future,
            builder: (context, snap) => snap.hasData
                ? Row(
                    children: [
                      IconButton(tooltip: 'Print / Save PDF', onPressed: () => _print(snap.data!), icon: const Icon(Icons.print)),
                      IconButton(tooltip: 'Send via WhatsApp', onPressed: () => _share(snap.data!), icon: const Icon(Icons.share)),
                    ],
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
      body: FutureBuilder<_ReportData>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Could not load reports:\n${snap.error}', textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: () => setState(() => _future = _load()),
                      icon: const Icon(Icons.refresh),
                      label: const Text('RETRY'),
                    ),
                  ],
                ),
              ),
            );
          }
          return _reportBody(snap.data!);
        },
      ),
    );
  }

  Widget _summaryCards(_ReportData data) => Row(
        children: [
          Expanded(child: _metric('Collected', data.collectedTotal, Colors.green.shade700)),
          const SizedBox(width: 8),
          Expanded(child: _metric('Spent', data.spentTotal, Colors.red.shade700)),
        ],
      );

  Widget _qarzaSummary(_ReportData data) => Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Qarz-e-Hassanah', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: kBrandGreen)),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: _metric('Issued', data.loanIssued, Colors.red.shade700)),
                  const SizedBox(width: 6),
                  Expanded(child: _metric('Recovered', data.loanRecovered, Colors.green.shade700)),
                  const SizedBox(width: 6),
                  Expanded(child: _metric('Waived', data.loanWaived, Colors.green.shade700)),
                  const SizedBox(width: 6),
                  Expanded(child: _metric('Net', data.qarzaNet, data.qarzaNet < 0 ? Colors.red.shade700 : Colors.orange.shade800)),
                ],
              ),
            ],
          ),
        ),
      );

  Widget _netAvailableCard(_ReportData data) => Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            children: [
              const Text('NET AVAILABLE', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
              const SizedBox(height: 5),
              Text(
                '₹${data.netAvailable.asAmount}',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 27, fontWeight: FontWeight.w900, color: data.netAvailable >= 0 ? kBrandGreen : Colors.red.shade700),
              ),
              const SizedBox(height: 5),
              const Text('Collected − Spent − Qarza Issued + Recovered + Waived', style: TextStyle(fontSize: 11, color: Colors.black54), textAlign: TextAlign.center),
            ],
          ),
        ),
      );

  Widget _metric(String title, double value, Color color) => Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
          child: Column(
            children: [
              Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text('₹${value.asAmount}', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: color)),
            ],
          ),
        ),
      );
}

class _ReportEntry {
  final DateTime date;
  final double credit;
  final double debit;
  final String reference;
  final String type;
  final String party;
  final String username;
  final String approvalStatus;
  final String approvalReason;
  final String approvalRejectedBy;
  final String approvalBy;
  final String? source;
  final int? id;

  _ReportEntry(
    this.date,
    this.credit,
    this.debit,
    this.reference,
    this.type,
    this.party,
    this.username, {
    this.approvalStatus = 'FINAL',
    this.approvalReason = '',
    this.approvalRejectedBy = '',
    this.approvalBy = '',
    this.source,
    this.id,
  });
}

class _BorrowerSummary {
  final String name;
  double issued = 0;
  double recovered = 0;
  double waived = 0;

  _BorrowerSummary(this.name);
}

class _RecurringBeneficiarySummary {
  final int id;
  String name;
  double total = 0;

  _RecurringBeneficiarySummary(this.id, this.name);
}

class _DeletedReceipt {
  final DateTime date;
  final String receiptNumber;
  final double amount;
  final String type;
  final String username;

  _DeletedReceipt({
    required this.date,
    required this.receiptNumber,
    required this.amount,
    required this.type,
    required this.username,
  });
}

class _ReportData {
  final List<_ReportEntry> rows;
  final Map<String, double> collections;
  final Map<String, double> expenses;
  final List<_BorrowerSummary> borrowers;
  final List<_RecurringBeneficiarySummary> recurringBeneficiaries;
  final List<_DeletedReceipt> deletedReceipts;
  final List<_ReportEntry> disapprovedTransactions;
  final double collectedTotal;
  final double spentTotal;
  final double loanIssued;
  final double loanRecovered;
  final double loanWaived;
  final double qarzaNet;
  final double netAvailable;

  const _ReportData({
    required this.rows,
    required this.collections,
    required this.expenses,
    required this.borrowers,
    required this.recurringBeneficiaries,
    required this.deletedReceipts,
    required this.disapprovedTransactions,
    required this.collectedTotal,
    required this.spentTotal,
    required this.loanIssued,
    required this.loanRecovered,
    required this.loanWaived,
    required this.qarzaNet,
    required this.netAvailable,
  });
}
