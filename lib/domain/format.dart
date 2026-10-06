import 'money.dart';

/// Display formatting for rupee amounts with digit-group separators.
///
/// `102000.5.asAmount` -> `1,02,000.50` (Indian grouping).
/// Use only for text shown to people (screens, receipts, PDFs). Never use it
/// to pre-fill an editable amount field or to write data files: those must stay
/// plain numbers such as `102000.50`.
extension AmountFormat on num {
  String get asAmount {
    if (isNaN || isInfinite) return toStringAsFixed(2);
    return Money.fromRupees(this).toIndianString();
  }

  /// Same as [asAmount] but without the `.00` when the value is whole,
  /// e.g. `13100` -> `13,100` (used on charts).
  String get asWhole {
    final text = asAmount;
    return text.endsWith('.00') ? text.substring(0, text.length - 3) : text;
  }
}
