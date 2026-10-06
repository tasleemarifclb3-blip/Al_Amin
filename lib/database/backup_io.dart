import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';

/// Native implementation of AABM backup saving.
///
/// Android's scoped-storage rules do not allow an app to arbitrarily write to
/// paths such as /storage/emulated/0/Aabm/. When the user explicitly chooses
/// a location, use the Android system save-file picker (Storage Access
/// Framework) instead of constructing a public filesystem path.
///
/// When chooseLocation is false, the backup is written to the app-private
/// application-support directory, which does not require storage permission.
Future<String?> saveNativeBackup({
  required Uint8List bytes,
  required String fileName,
  required bool chooseLocation,
}) async {
  if (chooseLocation) {
    // On Windows the save dialog selects a path but file_picker does not
    // reliably persist the supplied bytes itself. Write them explicitly after
    // the user confirms the destination. Keep the plugin-managed SAF path on
    // Android, where returned paths may be content URIs rather than filesystem
    // paths.
    final saved = await FilePicker.saveFile(
      dialogTitle: 'Save AABM Backup',
      fileName: fileName,
      type: FileType.custom,
      allowedExtensions: const ['json'],
      bytes: bytes,
    );
    if (saved == null || saved.toString().trim().isEmpty) return null;
    final path = saved.toString();
    final parsedPath = Uri.tryParse(path);
    final nativePath = parsedPath != null && parsedPath.scheme == 'file'
        ? parsedPath.toFilePath()
        : path;
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      final target = File(nativePath);
      await target.writeAsBytes(bytes, flush: true);
      final persisted = await target.length();
      if (persisted != bytes.length) {
        throw FileSystemException('Backup verification failed after writing the file.', nativePath);
      }
    }
    return path;
  }

  final directory = await getApplicationSupportDirectory();

  if (!await directory.exists()) {
    await directory.create(recursive: true);
  }

  final file = File(
    '${directory.path}${Platform.pathSeparator}$fileName',
  );

  await file.writeAsBytes(bytes, flush: true);

  return file.path;
}
