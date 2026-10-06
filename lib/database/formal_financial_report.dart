import 'dart:typed_data';
import '../screens/pdf_support.dart';
import '../domain/format.dart';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'app_database.dart';
import 'workflow_service.dart';
import '../screens/brand.dart';

/// Creates a period-based fund statement for publication/submission review.
/// Pending/rejected approval-controlled transactions are excluded from fund
/// balances. Qarza issue/recovery is presented separately from income/expense.
class FormalFinancialReport {
  static Future<Uint8List> build(
    AppDatabase db, {
    required DateTime from,
    required DateTime to,
  }) async {
    if (from.isAfter(to)) throw ArgumentError('Invalid reporting period.');
    await WorkflowService.ensureTables(db);
    final nonEffective = await WorkflowService.nonEffectiveKeys(db);
    final start = DateTime(from.year, from.month, from.day);
    final endExclusive = DateTime(to.year, to.month, to.day).add(const Duration(days: 1));

    bool effectiveInRange(DateTime date) => !date.isBefore(start) && date.isBefore(endExclusive);
    bool beforePeriod(DateTime date) => date.isBefore(start);

    final donationOpeningConfigured = await WorkflowService.totalOpeningBalance(
      db,
      const ['MONTHLY_DONATION', 'GENERAL_DONATION', 'BOX_COLLECTION', 'OTHER_INCOME', 'OTHER_EXPENSE'],
    );
    final zakaatOpeningConfigured = await WorkflowService.openingBalance(db, 'ZAKAAT');
    final sadqaOpeningConfigured = await WorkflowService.openingBalance(db, 'SADQA_FITR');

    final totals = <String, _FundActivity>{
      'Donations': _FundActivity(opening: donationOpeningConfigured),
      'Zakaat': _FundActivity(opening: zakaatOpeningConfigured),
      'Sadqa-e-Fitr': _FundActivity(opening: sadqaOpeningConfigured),
    };
    final qarza = _QarzaActivity();

    void apply(String fund, DateTime date, {double income = 0, double receipt = 0, double expense = 0}) {
      final a = totals[fund]!;
      if (beforePeriod(date)) {
        a.opening += income + receipt - expense;
      } else if (effectiveInRange(date)) {
        a.income += income;
        a.otherReceipts += receipt;
        a.expense += expense;
      }
    }

    // Monthly household collections are part of the Donations fund.
    final householdPayments = await db.select(db.householdPayments).get();
    for (final p in householdPayments) {
      apply('Donations', p.paymentDate, income: p.amount);
    }

    // General/box/other income, Zakaat receipts and Sadqa-e-Fitr receipts.
    final financial = await db.select(db.financialTransactions).get();
    for (final t in financial) {
      switch (t.category.toUpperCase()) {
        case 'GD':
        case 'GENERAL_DONATION':
        case 'BD':
        case 'BOX_DONATION':
        case 'OI':
        case 'OTHER_INCOME':
          apply('Donations', t.transactionDate, income: t.amount);
          break;
        case 'ZK':
        case 'ZAKAAT':
          apply('Zakaat', t.transactionDate, income: t.amount);
          break;
        case 'SF':
        case 'SADQA_FITR':
          apply('Sadqa-e-Fitr', t.transactionDate, income: t.amount);
          break;
      }
    }

    final zakaat = await db.select(db.zakaatDisbursements).get();
    for (final d in zakaat) {
      if (nonEffective.contains('zakaat_disbursements:${d.id}')) continue;
      apply('Zakaat', d.disbursementDate, expense: d.amount);
    }

    final adjustments = await db.select(db.fundAdjustments).get();
    for (final a in adjustments) {
      if (a.adjustmentType == 'DELETED_RECEIPT') continue;
      if (const {'QARZA_DISBURSEMENT', 'OTHER_EXPENSE', 'SADQA_EXPENSE'}.contains(a.adjustmentType) &&
          nonEffective.contains('fund_adjustments:${a.id}')) {
        continue;
      }
      switch (a.adjustmentType) {
        case 'OTHER_EXPENSE':
          apply('Donations', a.transactionDate, expense: a.amount);
          break;
        case 'SADQA_EXPENSE':
          apply('Sadqa-e-Fitr', a.transactionDate, expense: a.amount);
          break;
        case 'QARZA_DISBURSEMENT':
          if (beforePeriod(a.transactionDate)) {
            qarza.openingOutstanding += a.amount;
          } else if (effectiveInRange(a.transactionDate)) {
            qarza.issued += a.amount;
          }
          apply('Donations', a.transactionDate, expense: a.amount);
          break;
        case 'QARZA_RECOVERY':
          if (beforePeriod(a.transactionDate)) {
            qarza.openingOutstanding -= a.amount;
          } else if (effectiveInRange(a.transactionDate)) {
            qarza.recovered += a.amount;
          }
          apply('Donations', a.transactionDate, receipt: a.amount);
          break;
      }
    }

    final waivers = await WorkflowService.qarzaWaivers(db);
    for (final w in waivers) {
      apply('Zakaat', w.date, expense: w.amount);
      if (beforePeriod(w.date)) {
        qarza.openingOutstanding -= w.amount;
      } else if (effectiveInRange(w.date)) {
        qarza.waived += w.amount;
      }
    }

    // Keep the report honest about the only stored cash/bank snapshot: this
    // application records the latest actual balances, not a historical daily
    // cashbook. Do not mislabel a newer snapshot as a past-period closing.
    String cashBankNote = 'Historical cash/bank balances are not separately stored for every reporting date.';
    String cashBankValue = 'Not available as at ${_date(to)}';
    final manualRows = await db.select(db.manualBalances).get();
    if (manualRows.isNotEmpty && !manualRows.first.updatedAt.isAfter(DateTime(to.year, to.month, to.day, 23, 59, 59))) {
      cashBankValue = 'Cash ₹${manualRows.first.cashInHand.asAmount}  |  Bank ₹${manualRows.first.bankBalance.asAmount}  |  Total ₹${(manualRows.first.cashInHand + manualRows.first.bankBalance).asAmount}';
      cashBankNote = 'Latest recorded cash/bank reconciliation dated ${_date(manualRows.first.updatedAt)}.';
    }

    final doc = pw.Document(theme: PdfSupport.theme);
    final green = PdfColor.fromHex('#145A4A');
    final pale = PdfColor.fromHex('#EAF3EF');
    final border = PdfColor.fromHex('#B9D8CD');
    final tableBorder = pw.TableBorder.all(color: border, width: .55);
    pw.Widget section(String title) => pw.Container(
      width: double.infinity,
      margin: const pw.EdgeInsets.only(top: 12, bottom: 5),
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      color: green,
      child: pw.Text(title, style: pw.TextStyle(color: PdfColors.white, fontSize: 10, fontWeight: pw.FontWeight.bold)),
    );
    pw.Widget cell(String text, {bool bold = false, bool right = false}) => pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      child: pw.Align(
        alignment: right ? pw.Alignment.centerRight : pw.Alignment.centerLeft,
        child: pw.Text(text, style: pw.TextStyle(fontSize: 8.5, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
      ),
    );
    pw.Widget table(List<List<String>> rows, {int headerRows = 1}) => pw.Table(
      border: tableBorder,
      children: rows.asMap().entries.map((entry) => pw.TableRow(
        decoration: entry.key < headerRows ? pw.BoxDecoration(color: pale) : null,
        children: entry.value.asMap().entries.map((e) => cell(e.value, bold: entry.key < headerRows || e.key == 0, right: e.key > 0)).toList(),
      )).toList(),
    );

    final fundRows = <List<String>>[
      ['Fund / Account', 'Opening Balance', 'Receipts / Inflows', 'Outflows', 'Closing Balance'],
      ...totals.entries.map((e) => [
        e.key,
        _money(e.value.opening),
        _money(e.value.income + e.value.otherReceipts),
        _money(e.value.expense),
        _money(e.value.opening + e.value.income + e.value.otherReceipts - e.value.expense),
      ]),
      ['Total Funds', _money(totals.values.fold(0.0, (v, a) => v + a.opening)),
        _money(totals.values.fold(0.0, (v, a) => v + a.income + a.otherReceipts)),
        _money(totals.values.fold(0.0, (v, a) => v + a.expense)),
        _money(totals.values.fold(0.0, (v, a) => v + a.opening + a.income + a.otherReceipts - a.expense))],
    ];
    final incomeRows = <List<String>>[
      ['Income / Receipt Head', 'Amount'],
      ['Donations and collections', _money(totals['Donations']!.income)],
      ['Qarza recovery (principal receipt; not income)', _money(totals['Donations']!.otherReceipts)],
      ['Zakaat receipts', _money(totals['Zakaat']!.income)],
      ['Sadqa-e-Fitr receipts', _money(totals['Sadqa-e-Fitr']!.income)],
      ['Total income', _money(totals.values.fold(0.0, (v, a) => v + a.income))],
      ['Total cash receipts including Qarza recovery', _money(totals.values.fold(0.0, (v, a) => v + a.income + a.otherReceipts))],
    ];
    final expenseRows = <List<String>>[
      ['Expenditure Head', 'Amount'],
      ['Donations fund expenses (excluding Qarza issuance shown separately)', _money(totals['Donations']!.expense - qarza.issued)],
      ['Zakaat disbursements and Qarza waivers', _money(totals['Zakaat']!.expense)],
      ['Sadqa-e-Fitr expenditure', _money(totals['Sadqa-e-Fitr']!.expense)],
      ['Total expenditure (excluding Qarza principal issued)', _money(totals.values.fold(0.0, (v, a) => v + a.expense) - qarza.issued)],
    ];
    final qarzaRows = <List<String>>[
      ['Qarza movement', 'Amount'],
      ['Opening Qarza outstanding (calculated)', _money(qarza.openingOutstanding)],
      ['Qarza issued during period', _money(qarza.issued)],
      ['Qarza recovered during period', _money(qarza.recovered)],
      ['Qarza waived to Zakaat during period', _money(qarza.waived)],
      ['Closing Qarza outstanding (calculated)', _money(qarza.openingOutstanding + qarza.issued - qarza.recovered - qarza.waived)],
    ];

    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(34, 30, 34, 34),
      footer: (context) => pw.Container(
        alignment: pw.Alignment.centerRight,
        margin: const pw.EdgeInsets.only(top: 8),
        child: pw.Text('Page ${context.pageNumber} of ${context.pagesCount}', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
      ),
      build: (context) => [
        pdfBrandHeader(documentTitle: 'PERIODIC FINANCIAL STATEMENT / BALANCE SHEET', large: true),
        pw.Center(child: pw.Text('Reporting period: ${_date(from)} to ${_date(to)}', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold))),
        pw.SizedBox(height: 5),
        pw.Text('Currency: Indian Rupees (INR)  |  Basis: recorded transactions and configured opening balances; pending/rejected approval-controlled transactions excluded.', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
        section('1. Fund Balance Schedule'),
        table(fundRows),
        section('2. Receipts / Income Summary for the Period'),
        table(incomeRows),
        section('3. Expenditure Summary for the Period'),
        table(expenseRows),
        section('4. Qarza-e-Hasanah Movement (Receivable Schedule)'),
        table(qarzaRows),
        section('5. Cash and Bank Reconciliation Note'),
        pw.Container(padding: const pw.EdgeInsets.all(8), decoration: pw.BoxDecoration(border: pw.Border.all(color: border)), child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Text(cashBankValue, style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 3),
          pw.Text(cashBankNote, style: const pw.TextStyle(fontSize: 8)),
          pw.SizedBox(height: 3),
          pw.Text('A reconciliation of ledger fund balances to cash/bank should be completed against bank statements, cashbook and vouchers before formal adoption.', style: const pw.TextStyle(fontSize: 8)),
        ])),
        section('6. Notes and Declaration'),
        pw.Bullet(text: 'Balances are calculated from transactions recorded in this application and opening balances configured for the respective account heads.'),
        pw.Bullet(text: 'Qarza issuance/recovery is shown separately as movement of the recoverable Qarza balance and is not treated as ordinary donation income or expenditure.'),
        pw.Bullet(text: 'This statement is an accounting summary for review. Supporting receipts, payment vouchers, bank statements, approval records and an independent reconciliation should be attached where required.'),
        pw.SizedBox(height: 20),
        pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Expanded(child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [pw.Text('Prepared by: __________________________'), pw.SizedBox(height: 18), pw.Text('Name / Designation: ___________________')])),
          pw.SizedBox(width: 18),
          pw.Expanded(child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [pw.Text('Reviewed / Approved by: ________________'), pw.SizedBox(height: 18), pw.Text('Date and Seal: ________________________')])),
        ]),
      ],
    ));
    return Uint8List.fromList(await doc.save());
  }

  static String _money(double v) => '₹${v.asAmount}';
  static String _date(DateTime d) => '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}

class _FundActivity {
  double opening;
  double income = 0;
  double otherReceipts = 0;
  double expense = 0;
  _FundActivity({required this.opening});
}

class _QarzaActivity {
  double openingOutstanding = 0;
  double issued = 0;
  double recovered = 0;
  double waived = 0;
}
