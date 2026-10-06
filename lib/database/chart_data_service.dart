import '../domain/chart_data.dart';
import 'app_database.dart';
import 'workflow_service.dart';

/// Reads every approved income and expense record for the charts, using the
/// same sources and approval rules as the Reports window.
class ChartDataService {
  ChartDataService._();

  static bool _counts(Map<String, Object?> info) {
    final status = info['status'] as String? ?? 'FINAL';
    return status == 'FINAL' || status == 'APPROVED';
  }

  static Future<List<ChartRecord>> load(AppDatabase db) async {
    final records = <ChartRecord>[];

    final payments = await db.select(db.householdPayments).get();
    for (final p in payments) {
      records.add(ChartRecord(date: p.paymentDate, head: 'Monthly', amount: p.amount, isIncome: true));
    }

    final financial = await db.select(db.financialTransactions).get();
    for (final t in financial) {
      String? head;
      switch (t.category.toUpperCase()) {
        case 'GD':
        case 'GENERAL_DONATION':
          head = 'General';
          break;
        case 'BD':
        case 'BOX_DONATION':
          head = 'Boxes';
          break;
        case 'OI':
        case 'OTHER_INCOME':
          head = 'Other';
          break;
        case 'ZK':
        case 'ZAKAAT':
          head = 'Zakaat';
          break;
        case 'SF':
        case 'SADQA_FITR':
          head = 'Sadqa-e-Fitr';
          break;
        default:
          head = null;
      }
      if (head == null) continue;
      records.add(ChartRecord(date: t.transactionDate, head: head, amount: t.amount, isIncome: true));
    }

    final zakaat = await db.select(db.zakaatDisbursements).get();
    for (final d in zakaat) {
      final info = await WorkflowService.approvalInfo(
        db,
        sourceTable: 'zakaat_disbursements',
        transactionId: d.id,
      );
      if (!_counts(info)) continue;
      records.add(ChartRecord(date: d.disbursementDate, head: 'Zakaat', amount: d.amount, isIncome: false));
    }

    final adjustments = await db.select(db.fundAdjustments).get();
    for (final a in adjustments) {
      String? head;
      switch (a.adjustmentType) {
        case 'QARZA_DISBURSEMENT':
          head = 'Qarza';
          break;
        case 'SADQA_EXPENSE':
          head = 'Sadqa-e-Fitr';
          break;
        case 'OTHER_EXPENSE':
          head = 'Other Expenses';
          break;
        default:
          head = null;
      }
      if (head == null) continue;
      final info = await WorkflowService.approvalInfo(
        db,
        sourceTable: 'fund_adjustments',
        transactionId: a.id,
      );
      if (!_counts(info)) continue;
      records.add(ChartRecord(date: a.transactionDate, head: head, amount: a.amount, isIncome: false));
    }
    return records;
  }
}
