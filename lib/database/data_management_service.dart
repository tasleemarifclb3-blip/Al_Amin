import 'package:drift/drift.dart';
import 'app_database.dart';
import 'sync_foundation.dart';
import 'workflow_service.dart';

class DataManagementService {
  static const _driftTables = <String>[
    'household_concession_allocations',
    'payment_allocations',
    'opening_balance_payment_allocations',
    'opening_balance_concession_allocations',
    'household_status_histories',
    'household_payments',
    'household_concessions',
    'household_months',
    'household_charge_histories',
    'zakaat_disbursements',
    'zakaat_beneficiaries',
    'fund_adjustments',
    'financial_transactions',
    'manual_balances',
    'households',
  ];

  static const _workflowTables = <String>[
    'aabm_approval_requests',
    'qarza_waivers',
    'qarza_conditions',
    'qarza_parentage',
    'ledger_opening_balances',
  ];

  static const _syncBookkeepingTables = <String>[
    'aabm2_sync_outbox',
    'aabm2_sync_received',
    'aabm2_sync_conflicts',
    'aabm2_sync_failures',
    'aabm2_sync_state',
    'aabm2_sync_map',
  ];

  static Future<bool> _tableExists(AppDatabase db, String table) async {
    final rows = await db.customSelect(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ? LIMIT 1",
      variables: [Variable<String>(table)],
    ).get();
    return rows.isNotEmpty;
  }

  static Future<int> _rowCount(AppDatabase db, String table) async {
    final rows = await db.customSelect('SELECT COUNT(*) AS c FROM "$table"').get();
    return rows.isEmpty ? 0 : (rows.first.data['c'] as num?)?.toInt() ?? 0;
  }

  /// Deletes every accounting and workflow record on this device and clears the
  /// local sync bookkeeping. The device identity, approver settings and the
  /// application's latest recovery backup are kept.
  ///
  /// Throws if any record is still present afterwards, so a failed wipe is
  /// never mistaken for a successful one.
  static Future<void> deleteAllData(AppDatabase db) async {
    await WorkflowService.ensureTables(db);
    await SyncFoundation.initialize(db);
    final resetToken = await SyncFoundation.getState(db, 'global_reset_token');
    await db.transaction(() async {
      // Children before parents because several accounting tables use foreign
      // keys. A table that does not exist yet (older database) is skipped.
      for (final table in [..._driftTables, ..._workflowTables, ..._syncBookkeepingTables]) {
        if (await _tableExists(db, table)) {
          await db.customStatement('DELETE FROM "$table"');
        }
      }
    });
    final leftovers = <String>[];
    for (final table in [..._driftTables, ..._workflowTables]) {
      if (!await _tableExists(db, table)) continue;
      final count = await _rowCount(db, table);
      if (count > 0) leftovers.add('$table ($count)');
    }
    if (leftovers.isNotEmpty) {
      throw StateError('Local data was not fully deleted: ${leftovers.join(', ')}.');
    }
    // Start from a clean sync state without changing the device identity.
    await SyncFoundation.initialize(db);
    if (resetToken != null && resetToken.isNotEmpty) {
      await SyncFoundation.setState(db, 'global_reset_token', resetToken);
    }
  }

  static Future<void> deleteLocalDataOnly(AppDatabase db) async {
    await deleteAllData(db);
    // Detach this installation after a local-only wipe. This prevents its
    // next automatic sync from downloading the still-intact cloud dataset.
    await SyncFoundation.setState(db, 'local_sync_paused', '1');
  }

  static Future<void> resumeCloudSync(AppDatabase db) async {
    await SyncFoundation.initialize(db);
    await SyncFoundation.setState(db, 'local_sync_paused', '0');
  }
}
