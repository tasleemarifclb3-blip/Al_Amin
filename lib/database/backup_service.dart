import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

import 'app_database.dart';
import 'workflow_service.dart';
import 'sync_foundation.dart';
import 'backup_io_stub.dart' if (dart.library.io) 'backup_io.dart';

/// Creates a portable JSON backup of the AABM local data.
///
/// Native platforms write to the application-support directory by default
/// (or to a user-selected folder). Web downloads the backup through the
/// browser because a web application cannot silently write to its app folder.
class BackupService {
  static const String _latestBackupTable = 'aabm_latest_backup';

  static Future<void> _ensureLatestBackupTable(AppDatabase db) async {
    await db.customStatement('''
      CREATE TABLE IF NOT EXISTS $_latestBackupTable (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        created_at TEXT NOT NULL,
        file_name TEXT NOT NULL,
        payload BLOB NOT NULL
      )
    ''');
  }

  static const _driftTables = <String>[
    'households',
    'household_charge_histories',
    'household_months',
    'household_payments',
    'household_concessions',
    'household_concession_allocations',
    'payment_allocations',
    'opening_balance_payment_allocations',
    'opening_balance_concession_allocations',
    'household_status_histories',
    'financial_transactions',
    'manual_balances',
    'zakaat_beneficiaries',
    'zakaat_disbursements',
    'fund_adjustments',
  ];

  static const _workflowTables = <String>[
    'ledger_opening_balances',
    'qarza_parentage',
    'qarza_conditions',
    'qarza_waivers',
    'aabm_approval_requests',
    'aabm_approval_settings',
  ];

  static Future<Map<String, dynamic>> buildBackup(AppDatabase db) async {
    await WorkflowService.ensureTables(db);
    final tables = <String, dynamic>{};

    for (final table in [..._driftTables, ..._workflowTables]) {
      final rows = await db.customSelect('SELECT * FROM "$table"').get();
      tables[table] = rows.map((row) {
        final map = <String, dynamic>{};
        for (final entry in row.data.entries) {
          map[entry.key] = _jsonValue(entry.value);
        }
        return map;
      }).toList();
    }

    return <String, dynamic>{
      'format': 'AABM_BACKUP',
      'version': 1,
      'createdAt': DateTime.now().toIso8601String(),
      'databaseSchemaVersion': 13,
      'tables': tables,
    };
  }

  static dynamic _jsonValue(dynamic value) {
    if (value is DateTime) return value.toIso8601String();
    if (value is Uint8List) return base64Encode(value);
    if (value is List<int>) return base64Encode(value);
    if (value is Map) {
      return value.map((k, v) => MapEntry(k.toString(), _jsonValue(v)));
    }
    if (value is Iterable) return value.map(_jsonValue).toList();
    return value;
  }

  static Future<String?> backup(
    AppDatabase db, {
    bool chooseLocation = false,
    bool updateLatest = true,
  }) async {
    final data = await buildBackup(db);
    final bytes = Uint8List.fromList(
      utf8.encode(const JsonEncoder.withIndent('  ').convert(data)),
    );
    final fileName = 'aabm_backup_${_stamp(DateTime.now())}.json';

    // Always keep an application-local copy of the latest user backup. This
    // is deliberately outside the accounting tables, so a local data wipe
    // does not destroy the last recovery point. Safety backups created just
    // before a restore do not replace this latest user-selected backup.
    if (updateLatest) {
      await _ensureLatestBackupTable(db);
      await db.customStatement('''
        INSERT INTO $_latestBackupTable(id, created_at, file_name, payload)
        VALUES (1, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
          created_at = excluded.created_at,
          file_name = excluded.file_name,
          payload = excluded.payload
      ''', [DateTime.now().toUtc().toIso8601String(), fileName, bytes]);
    }

    return saveNativeBackup(
      bytes: bytes,
      fileName: fileName,
      chooseLocation: chooseLocation,
    );
  }

  static Future<Uint8List?> latestBackupBytes(AppDatabase db) async {
    await _ensureLatestBackupTable(db);
    final rows = await db.customSelect(
      'SELECT payload FROM $_latestBackupTable WHERE id = 1 LIMIT 1',
    ).get();
    if (rows.isEmpty) return null;
    final value = rows.first.data['payload'];
    if (value is Uint8List) return value;
    if (value is List<int>) return Uint8List.fromList(value);
    if (value is String) return Uint8List.fromList(utf8.encode(value));
    return null;
  }

  static Future<String?> latestBackupInfo(AppDatabase db) async {
    await _ensureLatestBackupTable(db);
    final rows = await db.customSelect(
      'SELECT created_at, file_name FROM $_latestBackupTable WHERE id = 1 LIMIT 1',
    ).get();
    if (rows.isEmpty) return null;
    final created = rows.first.data['created_at']?.toString() ?? '';
    final name = rows.first.data['file_name']?.toString() ?? 'Latest backup';
    return '$name|$created';
  }


  static const _restoreOrder = <String>[
    'households',
    'household_charge_histories',
    'household_months',
    'household_payments',
    'household_concessions',
    'household_concession_allocations',
    'payment_allocations',
    'opening_balance_payment_allocations',
    'opening_balance_concession_allocations',
    'household_status_histories',
    'financial_transactions',
    'manual_balances',
    'zakaat_beneficiaries',
    'zakaat_disbursements',
    'fund_adjustments',
    'ledger_opening_balances',
    'qarza_parentage',
    'qarza_conditions',
    'qarza_waivers',
    'aabm_approval_requests',
    'aabm_approval_settings',
  ];

  static const _dateColumns = <String>{
    'joined_date',
    'effective_from',
    'effective_to',
    'payment_date',
    'concession_date',
    'event_date',
    'transaction_date',
    'updated_at',
    'disbursement_date',
  };

  static const _blobColumns = <String>{
    'recipient_signature',
    'accountant_signature',
  };

  static const _boolColumns = <String>{'is_active'};

  /// Lets the user select a JSON AABM backup and returns its bytes.
  /// The current file_picker API is used directly so this works on Android,
  /// Windows and Web without dart:io or dart:html imports in this file.
  static Future<Uint8List?> pickBackupBytes() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['json'],
    );
    if (file == null) return null;
    final fileName = file.name.toLowerCase();
    if (!fileName.endsWith('.json')) {
      throw const FormatException('Please select the AABM backup file ending in .json, not a receipt, image, PDF or other file.');
    }
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) {
      throw const FormatException('The selected backup file is empty or could not be read from this device.');
    }
    return bytes;
  }

  static Map<String, dynamic> parseBackup(Uint8List bytes) {
    if (bytes.isEmpty) {
      throw const FormatException('The selected backup file is empty.');
    }

    // Reject common non-JSON file signatures with a useful message instead of
    // exposing a low-level UTF-8/JSON decoder error (for example a PNG logo or PDF).
    if (bytes.length >= 4 && bytes[0] == 0x89 && bytes[1] == 0x50 &&
        bytes[2] == 0x4E && bytes[3] == 0x47) {
      throw const FormatException('The selected file is a PNG image, not an AABM .json backup. Choose the aabm_backup_*.json file.');
    }
    if (bytes.length >= 4 && bytes[0] == 0x25 && bytes[1] == 0x50 &&
        bytes[2] == 0x44 && bytes[3] == 0x46) {
      throw const FormatException('The selected file is a PDF, not an AABM .json backup. Choose the aabm_backup_*.json file.');
    }

    String text;
    try {
      text = utf8.decode(bytes).replaceFirst('\uFEFF', '').trim();
    } on FormatException {
      throw const FormatException('The selected file is not UTF-8 JSON. Select an AABM backup ending in .json.');
    }
    if (text.isEmpty) {
      throw const FormatException('The selected backup file is empty.');
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(text);
      // Some file/export paths have stored a byte buffer as a JSON integer
      // array. Rehydrate it only when it represents UTF-8 JSON bytes.
      if (decoded is List && decoded.isNotEmpty && decoded.every((v) => v is int && v >= 0 && v <= 255)) {
        final candidate = Uint8List.fromList(decoded.cast<int>());
        if (candidate.isNotEmpty && (candidate.first == 0x7B || candidate.first == 0xEF)) {
          decoded = jsonDecode(utf8.decode(candidate).replaceFirst('\uFEFF', '').trim());
        }
      }
      // Tolerate a JSON object that was encoded as a JSON string once.
      if (decoded is String) decoded = jsonDecode(decoded);
    } on FormatException catch (e) {
      throw FormatException('Could not read this backup as JSON. Make sure you selected an AABM .json backup file. Details: ${e.message}');
    }
    if (decoded is! Map) {
      throw const FormatException('The selected file is not an AABM backup object. Select an aabm_backup_*.json file.');
    }
    final data = Map<String, dynamic>.from(
      decoded.map((key, value) => MapEntry(key.toString(), value)),
    );
    if (data['format'] != 'AABM_BACKUP') {
      throw const FormatException('Invalid AABM backup format.');
    }
    if (data['version'] != 1) {
      throw FormatException('Unsupported AABM backup version: ${data['version']}');
    }
    if (data['databaseSchemaVersion'] != 13) {
      throw FormatException(
        'This backup belongs to database schema ${data['databaseSchemaVersion']}, '
        'but this app uses schema 13.',
      );
    }
    final tables = data['tables'];
    if (tables is! Map) {
      throw const FormatException('Backup contains no table data.');
    }
    // buildBackup() always writes every accounting table. A file that lacks
    // one is truncated or not a real backup, and restoring it would wipe data.
    for (final table in _driftTables) {
      if (tables[table] is! List) {
        throw FormatException(
          'The backup is incomplete: table "$table" is missing. Nothing was restored.',
        );
      }
    }
    var totalRows = 0;
    for (final table in _restoreOrder) {
      final rows = tables[table];
      if (rows == null) continue;
      if (rows is! List) {
        throw FormatException('Invalid data for table: $table');
      }
      for (var i = 0; i < rows.length; i++) {
        if (rows[i] is! Map) {
          throw FormatException('Invalid row ${i + 1} in table: $table');
        }
      }
      totalRows += rows.length;
    }
    if (totalRows == 0) {
      throw const FormatException(
        'This backup contains no records. Restoring it would erase all current data, so it was rejected.',
      );
    }
    return data;
  }

  static Map<String, int> backupCounts(Map<String, dynamic> backup) {
    final tables = Map<String, dynamic>.from(backup['tables'] as Map);
    final result = <String, int>{};
    for (final table in _restoreOrder) {
      final rows = tables[table];
      if (rows is List && rows.isNotEmpty) result[table] = rows.length;
    }
    return result;
  }

  /// Restores the selected backup into the local Drift database.
  ///
  /// Call [verifyRestorable] first. Existing local accounting/workflow data
  /// and local sync bookkeeping are replaced inside one database transaction,
  /// so a failure leaves the previous data untouched. The permanent device ID
  /// is preserved. No Firestore records are deleted here.
  static Future<void> restore(AppDatabase db, Map<String, dynamic> backup) async {
    final tables = Map<String, dynamic>.from(backup['tables'] as Map);
    await WorkflowService.ensureTables(db);
    await SyncFoundation.initialize(db);
    await _ensureLatestBackupTable(db);
    final resetToken = await SyncFoundation.getState(db, 'global_reset_token');

    await db.transaction(() async {
      await _replaceTables(db, tables);

      // A restored local database must not replay the old device's sync
      // queue. The device identity itself is intentionally preserved.
      await db.customStatement('DELETE FROM aabm2_sync_outbox');
      await db.customStatement('DELETE FROM aabm2_sync_received');
      await db.customStatement('DELETE FROM aabm2_sync_conflicts');
      await db.customStatement('DELETE FROM aabm2_sync_failures');
      await db.customStatement('DELETE FROM aabm2_sync_state');
      await db.customStatement('DELETE FROM aabm2_sync_map');
    });

    await SyncFoundation.initialize(db);
    if (resetToken != null && resetToken.isNotEmpty) {
      await SyncFoundation.setState(db, 'global_reset_token', resetToken);
    }
  }

  /// Applies the backup inside a transaction and then rolls it back, so
  /// constraint, foreign-key, type and row-count problems are found while the
  /// current data is still intact. Throws if the backup cannot be restored.
  static Future<void> verifyRestorable(
    AppDatabase db,
    Map<String, dynamic> backup,
  ) async {
    final tables = Map<String, dynamic>.from(backup['tables'] as Map);
    await WorkflowService.ensureTables(db);
    try {
      await db.transaction(() async {
        await _replaceTables(db, tables);
        throw const _DryRunComplete();
      });
    } on _DryRunComplete {
      return;
    }
  }

  static Future<void> _replaceTables(
    AppDatabase db,
    Map<String, dynamic> tables,
  ) async {
    // Child-first deletion because the Drift schema uses foreign keys.
    for (final table in _restoreOrder.reversed) {
      await db.customStatement('DELETE FROM "$table"');
    }

    // Restore parents before children so foreign keys are valid.
    for (final table in _restoreOrder) {
      final rawRows = tables[table];
      if (rawRows is! List || rawRows.isEmpty) continue;
      final rows = rawRows
          .map((row) => Map<String, dynamic>.from(row as Map))
          .toList();
      final types = await _tableColumnTypes(db, table);
      final columns = types.keys.toSet();
      for (final row in rows) {
        final names = row.keys.where(columns.contains).toList();
        if (names.isEmpty) {
          throw StateError('A row in "$table" has no recognised columns.');
        }
        final placeholders = List.filled(names.length, '?').join(', ');
        final quotedNames = names.map((name) => '"$name"').join(', ');
        final values = <dynamic>[];
        for (final name in names) {
          final value = restoreValue(table, name, row[name], declaredType: types[name] ?? '');
          if (value != null &&
              value is! bool &&
              value is! num &&
              value is! String &&
              value is! List<int>) {
            throw FormatException(
              'Column "$name" of table "$table" holds a value of an unsupported type (${value.runtimeType}).',
            );
          }
          values.add(value);
        }
        await db.customStatement(
          'INSERT INTO "$table" ($quotedNames) VALUES ($placeholders)',
          values,
        );
      }
    }

    // Every backed-up row must now exist. A mismatch aborts the transaction.
    for (final table in _restoreOrder) {
      final raw = tables[table];
      final expected = raw is List ? raw.length : 0;
      final result = await db
          .customSelect('SELECT COUNT(*) AS c FROM "$table"')
          .get();
      final actual = result.first.read<int>('c');
      if (actual != expected) {
        throw StateError(
          'Restore check failed for "$table": expected $expected rows, found $actual.',
        );
      }
    }
  }

  /// Column name -> declared SQLite type (upper case) for [table].
  static Future<Map<String, String>> _tableColumnTypes(AppDatabase db, String table) async {
    final rows = await db.customSelect('PRAGMA table_info("$table")').get();
    return <String, String>{
      for (final row in rows)
        row.read<String>('name'): (row.data['type'] ?? '').toString().toUpperCase(),
    };
  }

  /// Reads a binary (image/signature) value from a backup.
  ///
  /// Current backups store bytes as base64 text. Older files and some sync paths
  /// stored them as a JSON integer array, either as a real array or as text such
  /// as "[137,80,78,71,...]". All of those forms are accepted. A value that
  /// cannot be read in any of these forms fails the restore check with a clear
  /// message instead of being dropped.
  static Uint8List? decodeBlobValue(String table, String column, dynamic value) {
    Uint8List fromInts(List<dynamic> items) {
      final out = Uint8List(items.length);
      for (var i = 0; i < items.length; i++) {
        final v = items[i];
        if (v is! int || v < 0 || v > 255) {
          throw FormatException(
            'Column "$column" of table "$table" holds a byte list with an invalid value.',
          );
        }
        out[i] = v;
      }
      return out;
    }

    if (value == null) return null;
    if (value is Uint8List) return value;
    if (value is List) return fromInts(value);
    if (value is String) {
      var text = value.trim();
      if (text.isEmpty) return null;
      if (text.startsWith('[')) {
        try {
          final decoded = jsonDecode(text);
          if (decoded is List) return fromInts(decoded);
        } on FormatException {
          // Fall through to the error below.
        }
      } else {
        if (text.startsWith('data:')) {
          final comma = text.indexOf(',');
          if (comma > 0) text = text.substring(comma + 1);
        }
        try {
          return base64.decode(base64.normalize(text.replaceAll(RegExp(r'\s'), '')));
        } on FormatException {
          // Fall through to the error below.
        }
      }
    }
    throw FormatException(
      'Column "$column" of table "$table" contains an image/signature value that cannot be read.',
    );
  }

  static bool _isNumericType(String declaredType) {
    final t = declaredType.toUpperCase();
    return t.contains('INT') || t.contains('REAL') || t.contains('NUM') || t.contains('DATE') || t.contains('FLOA') || t.contains('DOUB');
  }

  /// Converts one backed-up value into something SQLite accepts.
  ///
  /// Backups hold the raw stored values, so integers stay integers and text
  /// stays text (some tables keep ISO date text). Only an ISO date string found
  /// in a numeric (Drift DateTime) column is converted, to whole seconds since
  /// 1970, which is how Drift stores dates. A DateTime object is never returned.
  static dynamic restoreValue(
    String table,
    String column,
    dynamic value, {
    String declaredType = '',
  }) {
    if (value == null) return null;
    if (_blobColumns.contains(column)) {
      return decodeBlobValue(table, column, value);
    }
    if (_boolColumns.contains(column)) {
      if (value is bool) return value ? 1 : 0;
      if (value is num) return value != 0 ? 1 : 0;
      if (value is String) return value.toLowerCase() == 'true' ? 1 : 0;
    }
    if (value is DateTime) {
      return _isNumericType(declaredType)
          ? value.millisecondsSinceEpoch ~/ 1000
          : value.toIso8601String();
    }
    if (_dateColumns.contains(column) && value is String && _isNumericType(declaredType)) {
      final text = value.trim();
      if (text.isEmpty) return null;
      final parsed = DateTime.tryParse(text);
      if (parsed == null) {
        throw FormatException('Invalid date "$value" in column "$column" of table "$table".');
      }
      return parsed.millisecondsSinceEpoch ~/ 1000;
    }
    return value;
  }

  static String _stamp(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}'
      '${d.month.toString().padLeft(2, '0')}'
      '${d.day.toString().padLeft(2, '0')}_'
      '${d.hour.toString().padLeft(2, '0')}'
      '${d.minute.toString().padLeft(2, '0')}'
      '${d.second.toString().padLeft(2, '0')}';
}

class _DryRunComplete implements Exception {
  const _DryRunComplete();
}
