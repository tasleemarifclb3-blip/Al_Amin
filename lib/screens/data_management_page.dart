import 'package:flutter/material.dart';

import '../database/app_database.dart';
import '../database/backup_service.dart';
import '../database/data_management_service.dart';
import '../database/sync_firestore_service.dart';
import '../database/sync_foundation.dart';

class DataManagementPage extends StatefulWidget {
  final AppDatabase database;
  const DataManagementPage({super.key, required this.database});

  @override
  State<DataManagementPage> createState() => _DataManagementPageState();
}

class _DataManagementPageState extends State<DataManagementPage> {
  bool _busy = false;

  Future<void> _backup() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      // Default backup goes to the application's private support directory on
      // native platforms. On Web, the browser handles the save/download.
      final savedPath = await BackupService.backup(
        widget.database,
        chooseLocation: false,
      );
      if (!mounted) return;
      if (savedPath == null || savedPath.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Backup cancelled.')),
        );
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Backup created: $savedPath')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Backup failed: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _backupCopy() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      // Explicit export is useful for copying the backup to another device,
      // USB drive or a user-selected folder. It also updates the latest
      // recovery copy only after the backup data has been successfully built.
      final savedPath = await BackupService.backup(
        widget.database,
        chooseLocation: true,
      );
      if (!mounted) return;
      if (savedPath == null || savedPath.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Backup copy cancelled.')),
        );
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Backup copy saved: $savedPath')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Backup copy failed: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore() async {
    if (_busy) return;

    final choice = await showDialog<_RestoreChoice>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Restore AABM Backup'),
        content: const Text(
          'Choose the backup source. The selected backup will replace the '
          'current AABM dataset on this device and will become the new '
          'synchronized dataset after the restore.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CANCEL'),
          ),
          OutlinedButton.icon(
            onPressed: () => Navigator.pop(context, _RestoreChoice.latest),
            icon: const Icon(Icons.history),
            label: const Text('LATEST SAVED BACKUP'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, _RestoreChoice.file),
            icon: const Icon(Icons.folder_open),
            label: const Text('CHOOSE BACKUP FILE'),
          ),
        ],
      ),
    );

    if (choice == null) return;
    String? safetyPath;
    var cloudResetStarted = false;

    try {
      setState(() => _busy = true);

      final bytes = choice == _RestoreChoice.latest
          ? await BackupService.latestBackupBytes(widget.database)
          : await BackupService.pickBackupBytes();

      if (bytes == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              choice == _RestoreChoice.latest
                  ? 'No latest saved backup is available.'
                  : 'No backup file selected.',
            ),
          ),
        );
        return;
      }

      final backup = BackupService.parseBackup(bytes);
      final counts = BackupService.backupCounts(backup);

      if (!mounted) return;

      final summary = <String>[
        'Backup date: ${backup['createdAt'] ?? 'Unknown'}',
        'Households: ${counts['households'] ?? 0}',
        'Financial transactions: ${counts['financial_transactions'] ?? 0}',
        'Zakaat disbursements: ${counts['zakaat_disbursements'] ?? 0}',
        'Fund adjustments: ${counts['fund_adjustments'] ?? 0}',
        'Qarza waivers: ${counts['qarza_waivers'] ?? 0}',
      ];

      // First confirmation: explain that restore is authoritative. It will
      // clear the current cloud change feed and local dataset before the
      // selected backup is restored.
      final confirmed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('Restore Backup?'),
          content: SingleChildScrollView(
            child: Text(
              '${summary.join('\n')}\n\n'
              'The current synchronized AABM dataset will be replaced by '
              'this backup. Existing local data and existing Firebase sync '
              'events will be cleared before the backup is restored.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('CANCEL'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('CONTINUE'),
            ),
          ],
        ),
      );

      if (confirmed != true || !mounted) return;

      // Final confirmation immediately before the destructive cloud reset.
      final finalConfirmed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('FINAL CONFIRMATION'),
          content: const Text(
            'FINAL WARNING\n\n'
            'Firebase sync data and the current local accounting data will '
            'be cleared, then the selected backup will be restored. Other '
            'AABM devices will receive the restored dataset on their next '
            'synchronization.\n\n'
            'Continue?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('CANCEL'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('RESTORE'),
            ),
          ],
        ),
      );

      if (finalConfirmed != true || !mounted) return;

      // Keep a safety copy of the current data and prove the backup can be
      // applied BEFORE anything is deleted locally or in Firebase.
      safetyPath = await BackupService.backup(
        widget.database,
        updateLatest: false,
      );
      await BackupService.verifyRestorable(widget.database, backup);
      cloudResetStarted = true;
      // Make this restore authoritative across the synchronized database.
      // deleteEntireDatabase() writes the global reset marker, clears the
      // Firestore change feed, and clears this device's local accounting data.
      await SyncFirestoreService.deleteEntireDatabase(widget.database);

      // The selected backup is then restored locally. BackupService.restore
      // clears local sync mappings/outbox state, so the restored rows are
      // discovered as new records and uploaded to the now-reset Firestore
      // feed by the normal sync engine.
      await BackupService.restore(widget.database, backup);

      // Start the rebuild immediately instead of waiting for the five-second
      // periodic timer. This also makes the user-visible result much clearer.
      final syncResult = await SyncFirestoreService.syncNow();

      if (!mounted) return;

      if (syncResult.ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Backup restored successfully and the restored data has been '
              'queued/uploaded to Firebase. Other devices can now sync it.',
            ),
            duration: Duration(seconds: 8),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Backup restored locally, but cloud synchronization returned: '
              '${syncResult.message ?? 'unknown error'}',
            ),
            duration: const Duration(seconds: 10),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 12),
          content: Text(
            'Restore failed: $e\n'
            '${cloudResetStarted ? 'The restore stopped after the cloud reset began.' : 'Nothing was changed.'}'
            '${safetyPath == null ? '' : '\nSafety backup of your previous data: $safetyPath'}',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteAllData() async {
    if (_busy) return;

    // Data Management is already protected by the Superuser password when
    // the Data tab is opened. Do not ask for a second password here.
    final scope = await showDialog<_DeleteScope>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Delete AABM Data'),
        content: const Text(
          'Choose exactly what you want to delete.\n\n'
          'LOCAL DATA deletes accounting and workflow data only from this '
          'device/browser.\n\n'
          'ENTIRE DATABASE resets the synchronized AABM dataset in Firebase '
          'and causes other AABM devices to clear their local accounting '
          'data on their next synchronization.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CANCEL'),
          ),
          OutlinedButton.icon(
            onPressed: () => Navigator.pop(context, _DeleteScope.local),
            icon: const Icon(Icons.computer),
            label: const Text('LOCAL DATA ONLY'),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(context, _DeleteScope.entire),
            icon: const Icon(Icons.cloud_off),
            label: const Text('ENTIRE DATABASE'),
          ),
        ],
      ),
    );

    if (scope == null) return;

    try {
      setState(() => _busy = true);

      // REQUIRED BEFORE ANY DELETION: save a backup to a location the user
      // chooses. The save window opens straight from this button press (browsers
      // only allow it right after a click). If the user cancels it or saving
      // fails, nothing is deleted.
      if (!mounted) return;
      final startBackup = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('Save a backup first'),
          content: const Text(
            'Before anything is deleted you must save a backup of your data.\n\n'
            'On the next screen choose where to save it. If you cancel that screen, nothing will be deleted.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('CANCEL'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(context, true),
              icon: const Icon(Icons.save_alt),
              label: const Text('CHOOSE BACKUP LOCATION'),
            ),
          ],
        ),
      );
      if (startBackup != true || !mounted) return;
      final backupPath = await BackupService.backup(
        widget.database,
        chooseLocation: true,
      );

      if (backupPath == null || backupPath.trim().isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Nothing was deleted: the backup was cancelled or could not be saved.',
            ),
          ),
        );
        return;
      }

      if (!mounted) return;

      // First confirmation only appears after the backup has been saved.
      final first = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: Text(
            scope == _DeleteScope.local
                ? 'Delete Local Data?'
                : 'DELETE ENTIRE DATABASE?',
          ),
          content: Text(
            'A complete backup was saved successfully.\n\n'
            'Backup: $backupPath\n\n'
            '${scope == _DeleteScope.local
                ? 'Only this device/browser will be cleared. Firebase and other devices will remain unchanged.'
                : 'Firebase sync data and the local data on this device will be cleared. Other AABM devices will clear their old local data when they next synchronize.'}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('CANCEL'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('CONTINUE'),
            ),
          ],
        ),
      );

      if (first != true || !mounted) return;

      final second = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('FINAL CONFIRMATION'),
          content: Text(
            scope == _DeleteScope.local
                ? 'FINAL WARNING\n\nPermanently DELETE ALL LOCAL ACCOUNTING DATA?'
                : 'FINAL WARNING\n\nPermanently DELETE THE ENTIRE SYNCHRONIZED AABM DATABASE FROM FIREBASE AND ALL DEVICES?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('CANCEL'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.pop(context, true),
              child: Text(
                scope == _DeleteScope.local
                    ? 'DELETE LOCAL DATA'
                    : 'DELETE ENTIRE DATABASE',
              ),
            ),
          ],
        ),
      );

      if (second != true || !mounted) return;

      if (scope == _DeleteScope.local) {
        await DataManagementService.deleteLocalDataOnly(widget.database);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Local accounting data has been deleted. Firebase is unchanged; cloud sync is paused on this device until you reconnect.'),
          ),
        );
      } else {
        final result = await SyncFirestoreService.deleteEntireDatabase(
          widget.database,
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result)),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Delete failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Data Management')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              _ActionCard(
                icon: Icons.backup_outlined,
                title: 'Backup Data',
                description: 'Creates a complete AABM JSON backup. The normal backup is kept in the application support location; use Save Backup Copy to export it elsewhere.',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    FilledButton.icon(
                      onPressed: _busy ? null : _backup,
                      icon: const Icon(Icons.save_alt),
                      label: const Text('BACK UP DATA'),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _backupCopy,
                      icon: const Icon(Icons.folder_open),
                      label: const Text('SAVE BACKUP COPY...'),
                    ),
                  ],
                ),
              ),
              _ActionCard(
                icon: Icons.restore_outlined,
                title: 'Restore Backup',
                description: 'Restore the latest saved backup or select a backup file from another location.',
                child: OutlinedButton.icon(onPressed: _busy ? null : _restore, icon: const Icon(Icons.restore), label: const Text('RESTORE BACKUP')),
              ),
              FutureBuilder<String?>(
                future: SyncFoundation.getState(widget.database, 'local_sync_paused'),
                builder: (context, snapshot) {
                  if (snapshot.data != '1') return const SizedBox.shrink();
                  return _ActionCard(
                    icon: Icons.cloud_sync_outlined,
                    title: 'Cloud Sync Paused on This Device',
                    description: 'Local-only deletion has detached this device from Firebase. Reconnecting may download the existing cloud dataset back onto this device.',
                    child: OutlinedButton.icon(
                      onPressed: _busy ? null : () async {
                        final confirmed = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('Reconnect to Firebase?'),
                            content: const Text('The existing Firebase data may be downloaded to this device again. Continue?'),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('CANCEL')),
                              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('RECONNECT')),
                            ],
                          ),
                        );
                        if (confirmed != true || !mounted) return;
                        setState(() => _busy = true);
                        try {
                          await DataManagementService.resumeCloudSync(widget.database);
                          final result = await SyncFirestoreService.syncNow();
                          if (!mounted) return;
                          ScaffoldMessenger.of(this.context).showSnackBar(SnackBar(content: Text(result.ok ? 'Cloud sync resumed.' : 'Sync resumed with message: ${result.message ?? 'check connection'}')));
                        } catch (e) {
                          if (mounted) ScaffoldMessenger.of(this.context).showSnackBar(SnackBar(content: Text('Could not resume sync: $e')));
                        } finally {
                          if (mounted) setState(() => _busy = false);
                        }
                      },
                      icon: const Icon(Icons.cloud_sync_outlined),
                      label: const Text('RESUME CLOUD SYNC'),
                    ),
                  );
                },
              ),
              _ActionCard(
                icon: Icons.delete_forever_outlined,
                title: 'Delete Data',
                description: 'Choose between deleting only this device or wiping the synchronized AABM database across Firebase and all devices.',
                danger: true,
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : _deleteAllData,
                  icon: const Icon(Icons.delete_forever),
                  label: const Text('DELETE DATA'),
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.red, side: const BorderSide(color: Colors.red)),
                ),
              ),
              if (_busy) const Padding(padding: EdgeInsets.all(18), child: Center(child: CircularProgressIndicator())),
            ],
          ),
        ),
      ),
    );
  }
}

enum _RestoreChoice { latest, file }
enum _DeleteScope { local, entire }

class _ActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final Widget child;
  final bool danger;
  const _ActionCard({required this.icon, required this.title, required this.description, required this.child, this.danger = false});
  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Icon(icon, size: 42, color: danger ? Colors.red : null),
          const SizedBox(height: 8),
          Text(title, textAlign: TextAlign.center, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: danger ? Colors.red : null)),
          const SizedBox(height: 6),
          Text(description, textAlign: TextAlign.center),
          const SizedBox(height: 14),
          child,
        ]),
      ),
    );
  }
}

