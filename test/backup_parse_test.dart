import 'dart:convert';
import 'dart:typed_data';

import 'package:al_amin/database/backup_service.dart';
import 'package:flutter_test/flutter_test.dart';

const _driftTables = <String>[
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

Uint8List _bytes(Map<String, dynamic> tables) => Uint8List.fromList(
      utf8.encode(jsonEncode({
        'format': 'AABM_BACKUP',
        'version': 1,
        'databaseSchemaVersion': 13,
        'createdAt': '2026-01-01T00:00:00.000',
        'tables': tables,
      })),
    );

Map<String, dynamic> _fullTables({int rows = 1}) => {
      for (final t in _driftTables)
        t: t == 'households'
            ? List.generate(rows, (i) => {'id': i + 1, 'name': 'H$i'})
            : <dynamic>[],
    };

void main() {
  group('BackupService.parseBackup', () {
    test('accepts a complete backup with records', () {
      final data = BackupService.parseBackup(_bytes(_fullTables()));
      expect(BackupService.backupCounts(data)['households'], 1);
    });

    test('rejects a backup with a missing accounting table', () {
      final tables = _fullTables()..remove('financial_transactions');
      expect(
        () => BackupService.parseBackup(_bytes(tables)),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects an empty tables object instead of wiping data', () {
      expect(
        () => BackupService.parseBackup(_bytes({})),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects a backup that contains no records at all', () {
      expect(
        () => BackupService.parseBackup(_bytes(_fullTables(rows: 0))),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects rows that are not objects', () {
      final tables = _fullTables()..['households'] = [1, 2, 3];
      expect(
        () => BackupService.parseBackup(_bytes(tables)),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects truncated JSON', () {
      final good = _bytes(_fullTables());
      final cut = Uint8List.sublistView(good, 0, good.length ~/ 2);
      expect(
        () => BackupService.parseBackup(cut),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('BackupService.decodeBlobValue', () {
    final png = [137, 80, 78, 71, 13, 10, 26, 10];

    test('reads base64 text', () {
      final text = base64Encode(png);
      expect(BackupService.decodeBlobValue('t', 'recipient_signature', text), Uint8List.fromList(png));
    });

    test('reads a JSON integer array stored as text (older backups)', () {
      final text = '[${png.join(',')}]';
      expect(BackupService.decodeBlobValue('t', 'recipient_signature', text), Uint8List.fromList(png));
    });

    test('reads a real list and an empty value', () {
      expect(BackupService.decodeBlobValue('t', 'c', png), Uint8List.fromList(png));
      expect(BackupService.decodeBlobValue('t', 'c', ''), isNull);
      expect(BackupService.decodeBlobValue('t', 'c', null), isNull);
    });

    test('rejects unreadable values instead of dropping them', () {
      expect(() => BackupService.decodeBlobValue('t', 'c', '!!not base64!!'), throwsA(isA<FormatException>()));
      expect(() => BackupService.decodeBlobValue('t', 'c', '[1,2,300]'), throwsA(isA<FormatException>()));
    });
  });

  group('BackupService.restoreValue', () {
    test('keeps integers and text exactly as stored', () {
      expect(BackupService.restoreValue('t', 'payment_date', 1790000000, declaredType: 'INTEGER'), 1790000000);
      expect(
        BackupService.restoreValue('t', 'updated_at', '2026-10-03T20:04:00.000', declaredType: 'TEXT'),
        '2026-10-03T20:04:00.000',
      );
    });

    test('converts an ISO date string only for a numeric date column, to seconds', () {
      final iso = DateTime.utc(2026, 10, 3, 12).toIso8601String();
      final seconds = DateTime.utc(2026, 10, 3, 12).millisecondsSinceEpoch ~/ 1000;
      expect(BackupService.restoreValue('t', 'transaction_date', iso, declaredType: 'INTEGER'), seconds);
    });

    test('never returns a DateTime object', () {
      final value = BackupService.restoreValue('t', 'payment_date', DateTime(2026, 1, 2), declaredType: 'INTEGER');
      expect(value, isA<int>());
      final text = BackupService.restoreValue('t', 'note', DateTime(2026, 1, 2), declaredType: 'TEXT');
      expect(text, isA<String>());
    });

    test('rejects an unreadable date for a numeric date column', () {
      expect(
        () => BackupService.restoreValue('t', 'payment_date', 'not a date', declaredType: 'INTEGER'),
        throwsA(isA<FormatException>()),
      );
    });

    test('booleans become 0 or 1', () {
      expect(BackupService.restoreValue('t', 'is_active', true), 1);
      expect(BackupService.restoreValue('t', 'is_active', 'false'), 0);
    });
  });
}
