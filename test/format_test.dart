import 'package:al_amin/domain/format.dart';
import 'package:al_amin/domain/word_case.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('asAmount', () {
    test('groups digits the Indian way', () {
      expect(102000.asAmount, '1,02,000.00');
      expect(1234.5.asAmount, '1,234.50');
      expect(999.99.asAmount, '999.99');
      expect(0.asAmount, '0.00');
      expect(12345678.asAmount, '1,23,45,678.00');
    });

    test('keeps the minus sign', () {
      expect((-1234.5).asAmount, '-1,234.50');
    });
  });

  group('toWordCase', () {
    test('capitalises the first letter of each word', () {
      expect(toWordCase('mohd arif'), 'Mohd Arif');
      expect(toWordCase('house no 12, main road'), 'House No 12, Main Road');
      expect(toWordCase('abdul-rahman'), 'Abdul-Rahman');
      expect(toWordCase('2nd floor'), '2nd Floor');
    });

    test('does not change letters inside a word', () {
      expect(toWordCase('MD ARIF'), 'MD ARIF');
      expect(toWordCase("o'brien"), "O'brien");
    });

    test('formatter keeps length and applies on typing', () {
      const f = WordCaseFormatter();
      final r = f.formatEditUpdate(
        const TextEditingValue(text: 'mohd'),
        const TextEditingValue(
          text: 'mohd a',
          selection: TextSelection.collapsed(offset: 6),
        ),
      );
      expect(r.text, 'Mohd A');
      expect(r.selection.baseOffset, 6);
    });
  });
}
