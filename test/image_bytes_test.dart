import 'dart:convert';
import 'dart:typed_data';

import 'package:al_amin/domain/image_bytes.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final png = <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 13, 73, 72, 68, 82];

  group('recoverImageBytes', () {
    test('keeps real PNG and JPEG bytes unchanged', () {
      expect(recoverImageBytes(png), Uint8List.fromList(png));
      final jpeg = <int>[0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3];
      expect(recoverImageBytes(jpeg), Uint8List.fromList(jpeg));
    });

    test('recovers a PNG that was stored as the text "[137,80,78,71,...]"', () {
      final asText = utf8.encode('[${png.join(',')}]');
      expect(recoverImageBytes(asText), Uint8List.fromList(png));
    });

    test('recovers the same list written with spaces', () {
      final asText = utf8.encode('[${png.join(', ')}]');
      expect(recoverImageBytes(asText), Uint8List.fromList(png));
    });

    test('recovers a PNG stored as base64 text', () {
      final asText = utf8.encode(base64Encode(png));
      expect(recoverImageBytes(asText), Uint8List.fromList(png));
    });

    test('returns null for anything that is not an image', () {
      expect(recoverImageBytes(null), isNull);
      expect(recoverImageBytes(<int>[]), isNull);
      expect(recoverImageBytes(utf8.encode('hello world')), isNull);
      expect(recoverImageBytes(utf8.encode('[1,2,300]')), isNull);
      expect(recoverImageBytes(utf8.encode('[1,2,3]')), isNull);
    });
  });
}
