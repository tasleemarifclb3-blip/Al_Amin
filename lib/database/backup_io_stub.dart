import 'dart:js_interop';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

/// Browser save dialog (File System Access API): Chrome, Edge and other
/// Chromium browsers show a real "Save as" window where the user picks the
/// folder and file name.
@JS('showSaveFilePicker')
external JSPromise<_FileHandle> _showSaveFilePicker(JSObject options);

extension type _FileHandle._(JSObject _) implements JSObject {
  external JSString get name;
  external JSPromise<_Writable> createWritable();
}

extension type _Writable._(JSObject _) implements JSObject {
  external JSPromise<JSAny?> write(JSAny data);
  external JSPromise<JSAny?> close();
}

bool _isUserCancel(Object error) {
  final text = error.toString();
  return text.contains('AbortError') || text.contains('aborted a request');
}

/// Web implementation of AABM backup saving.
///
/// * Chromium browsers: the user is asked where to save the file. The call
///   returns the chosen file name only after the file has been written and
///   closed; it returns null only when the user cancels the dialog.
/// * Other browsers (no save dialog available): the file is downloaded to the
///   browser's download folder, and the returned text says so.
Future<String?> saveNativeBackup({
  required Uint8List bytes,
  required String fileName,
  required bool chooseLocation,
}) async {
  try {
    final options = <String, Object>{
      'suggestedName': fileName,
      'types': <Object>[
        <String, Object>{
          'description': 'AABM backup (JSON)',
          'accept': <String, Object>{
            'application/json': <String>['.json'],
          },
        },
      ],
    }.jsify() as JSObject;
    final handle = await _showSaveFilePicker(options).toDart;
    final writable = await handle.createWritable().toDart;
    await writable.write(bytes.toJS).toDart;
    await writable.close().toDart;
    return handle.name.toDart;
  } catch (error) {
    if (_isUserCancel(error)) return null;
    // The save dialog is not available (Firefox/Safari) or the browser refused
    // it. Fall back to a normal download so the backup is still produced.
  }
  await FilePicker.saveFile(
    dialogTitle: 'Save AABM Backup',
    fileName: fileName,
    type: FileType.custom,
    allowedExtensions: const ['json'],
    bytes: bytes,
  );
  return '$fileName (downloaded to your browser\'s download folder)';
}
