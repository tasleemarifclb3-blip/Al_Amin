import 'package:flutter/services.dart';

/// Capitalises the first letter of every word ("mohd arif" -> "Mohd Arif").
///
/// A new word starts at the beginning of the text and after whitespace or one of
/// `- / . (`. Letters inside a word are left exactly as typed, so "MD" or
/// "McDonald" are not damaged. Apostrophes do not start a new word.
String toWordCase(String input) {
  final out = StringBuffer();
  var startOfWord = true;
  for (final rune in input.runes) {
    final ch = String.fromCharCode(rune);
    if (startOfWord && ch.toUpperCase() != ch.toLowerCase()) {
      out.write(ch.toUpperCase());
    } else {
      out.write(ch);
    }
    startOfWord = ch.trim().isEmpty || '-/.('.contains(ch);
  }
  return out.toString();
}

/// Applies [toWordCase] while the user types or pastes.
class WordCaseFormatter extends TextInputFormatter {
  const WordCaseFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = toWordCase(newValue.text);
    // Never change the length, so the cursor and composing range stay valid.
    if (text == newValue.text || text.length != newValue.text.length) {
      return newValue;
    }
    return newValue.copyWith(text: text);
  }
}
