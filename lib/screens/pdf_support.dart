import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/widgets.dart' as pw;
import 'package:shared_preferences/shared_preferences.dart';

/// Shared PDF settings: a font that contains the rupee sign and the
/// thermal-roll width.
///
/// Call [load] once at start-up. PDF builders read [theme] and
/// [thermalWidthMm] synchronously. If loading fails, [theme] stays null and
/// the `pdf` package falls back to its built-in font (the rupee sign then
/// cannot be drawn).
class PdfSupport {
  static const String _paperKey = 'receipt_paper_width_mm';

  static pw.ThemeData? theme;

  /// Width of the thermal receipt roll in millimetres (58 or 80).
  static double thermalWidthMm = 58;

  static Future<void> load() async {
    try {
      final regular = pw.Font.ttf(
        await rootBundle.load('assets/fonts/DejaVuSansCondensed.ttf'),
      );
      final bold = pw.Font.ttf(
        await rootBundle.load('assets/fonts/DejaVuSansCondensed-Bold.ttf'),
      );
      theme = pw.ThemeData.withFont(
        base: regular,
        bold: bold,
        italic: regular,
        boldItalic: bold,
      );
    } catch (_) {
      theme = null;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getInt(_paperKey);
      if (saved == 58 || saved == 80) thermalWidthMm = saved!.toDouble();
    } catch (_) {
      // Keep the default width.
    }
  }

  static Future<void> setThermalWidth(int mm) async {
    if (mm != 58 && mm != 80) return;
    thermalWidthMm = mm.toDouble();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_paperKey, mm);
    } catch (_) {
      // The choice still applies for this session.
    }
  }
}
