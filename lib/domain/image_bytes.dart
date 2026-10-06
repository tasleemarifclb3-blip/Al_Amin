import 'dart:convert';
import 'dart:typed_data';

// Recovers usable PNG/JPEG bytes from a stored signature value.
//
// A signature should be the raw bytes of a PNG image. Some stored values hold
// the same bytes written out as text, such as "[137,80,78,71,...]" (this is what
// made printing fail with "Unable to guess the image type"), or as base64 text.
// These helpers turn all of those forms back into real image bytes and return
// null when the value is not an image at all, so a bad signature never stops a
// receipt or voucher from printing.

bool isPngBytes(List<int> b) =>
    b.length > 8 && b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47;

bool isJpegBytes(List<int> b) => b.length > 3 && b[0] == 0xFF && b[1] == 0xD8;

bool isImageBytes(List<int> b) => isPngBytes(b) || isJpegBytes(b);

Uint8List? _fromIntList(Object? decoded) {
  if (decoded is! List) return null;
  final out = Uint8List(decoded.length);
  for (var i = 0; i < decoded.length; i++) {
    final v = decoded[i];
    if (v is! int || v < 0 || v > 255) return null;
    out[i] = v;
  }
  return out;
}

/// Returns real image bytes, or null if [raw] cannot be turned into an image.
Uint8List? recoverImageBytes(List<int>? raw) {
  if (raw == null || raw.isEmpty) return null;
  if (isImageBytes(raw)) return raw is Uint8List ? raw : Uint8List.fromList(raw);

  // The value may be text. Decode it as ASCII/UTF-8 and look at what it is.
  String text;
  try {
    text = utf8.decode(raw, allowMalformed: true).trim();
  } catch (_) {
    return null;
  }
  if (text.isEmpty) return null;

  if (text.startsWith('[')) {
    try {
      final bytes = _fromIntList(jsonDecode(text));
      if (bytes != null && isImageBytes(bytes)) return bytes;
    } catch (_) {
      // Not a JSON list; fall through.
    }
    return null;
  }

  var base64Text = text;
  final comma = base64Text.indexOf(',');
  if (base64Text.startsWith('data:') && comma > 0) {
    base64Text = base64Text.substring(comma + 1);
  }
  try {
    final bytes = base64.decode(base64.normalize(base64Text.replaceAll(RegExp(r'\s'), '')));
    if (isImageBytes(bytes)) return Uint8List.fromList(bytes);
  } catch (_) {
    // Not base64 either.
  }
  return null;
}
