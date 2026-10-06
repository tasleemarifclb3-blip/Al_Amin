/// Exact monetary value stored as an integer number of paise (INR minor units).
///
/// Existing database columns are still `REAL` (rupees). Use [Money.fromRupees]
/// when reading those legacy values so that all summation happens on integers,
/// and [Money.rupees] only when handing a value back to legacy code.
class Money implements Comparable<Money> {
  final int paise;

  const Money._(this.paise);

  static const Money zero = Money._(0);

  const Money.fromPaise(int value) : paise = value;

  /// Converts a legacy floating-point rupee amount, rounding to the nearest
  /// paisa. Non-finite values are rejected instead of being turned into zero.
  factory Money.fromRupees(num value) {
    if (value is double && !value.isFinite) {
      throw ArgumentError.value(value, 'value', 'Amount must be a finite number.');
    }
    return Money._((value * 100).round());
  }

  /// Parses user input such as `1250`, `1,250.5` or `1,25,000.75`.
  /// Accepts at most two decimal places and rejects everything else.
  factory Money.parse(String input) {
    final cleaned = input.trim().replaceAll(',', '');
    final match = RegExp(r'^(-)?(\d+)(?:\.(\d{1,2}))?$').firstMatch(cleaned);
    if (match == null) {
      throw FormatException('Invalid amount: "$input"');
    }
    final negative = match.group(1) != null;
    final whole = int.parse(match.group(2)!);
    final frac = (match.group(3) ?? '').padRight(2, '0');
    final total = whole * 100 + (frac.isEmpty ? 0 : int.parse(frac));
    return Money._(negative ? -total : total);
  }

  static Money? tryParse(String input) {
    try {
      return Money.parse(input);
    } on FormatException {
      return null;
    }
  }

  Money operator +(Money other) => Money._(paise + other.paise);
  Money operator -(Money other) => Money._(paise - other.paise);
  Money operator -() => Money._(-paise);

  bool operator <(Money other) => paise < other.paise;
  bool operator <=(Money other) => paise <= other.paise;
  bool operator >(Money other) => paise > other.paise;
  bool operator >=(Money other) => paise >= other.paise;

  bool get isZero => paise == 0;
  bool get isNegative => paise < 0;
  bool get isPositive => paise > 0;

  /// Legacy bridge only. Never sum these values.
  double get rupees => paise / 100.0;

  static Money sum(Iterable<Money> values) =>
      values.fold(Money.zero, (a, b) => a + b);

  /// Plain `1250.50` form, suitable for CSV and text fields.
  String toPlainString() {
    final abs = paise.abs();
    final s = '${abs ~/ 100}.${(abs % 100).toString().padLeft(2, '0')}';
    return paise < 0 ? '-$s' : s;
  }

  /// Indian digit grouping, e.g. `1,23,456.50`.
  String toIndianString({bool withSymbol = false}) {
    final abs = paise.abs();
    final whole = (abs ~/ 100).toString();
    final frac = (abs % 100).toString().padLeft(2, '0');
    String grouped;
    if (whole.length <= 3) {
      grouped = whole;
    } else {
      final head = whole.substring(0, whole.length - 3);
      final tail = whole.substring(whole.length - 3);
      final buf = StringBuffer();
      for (var i = 0; i < head.length; i++) {
        if (i > 0 && (head.length - i) % 2 == 0) buf.write(',');
        buf.write(head[i]);
      }
      grouped = '$buf,$tail';
    }
    final sign = paise < 0 ? '-' : '';
    return '$sign${withSymbol ? '₹' : ''}$grouped.$frac';
  }

  @override
  int compareTo(Money other) => paise.compareTo(other.paise);

  @override
  bool operator ==(Object other) => other is Money && other.paise == paise;

  @override
  int get hashCode => paise.hashCode;

  @override
  String toString() => 'Money(${toPlainString()})';
}
