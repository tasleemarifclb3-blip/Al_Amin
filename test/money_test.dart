import 'package:al_amin/domain/money.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Money', () {
    test('sums exactly where doubles drift', () {
      // 0.1 + 0.2 != 0.3 in binary floating point.
      final total = Money.fromRupees(0.1) + Money.fromRupees(0.2);
      expect(total, Money.fromPaise(30));
      expect(Money.sum(List.filled(1000, Money.fromRupees(0.1))), Money.fromPaise(10000));
    });

    test('parses valid input and rejects invalid input', () {
      expect(Money.parse('125.50').paise, 12550);
      expect(Money.parse('1,25,000.7').paise, 12500070);
      expect(Money.parse('7').paise, 700);
      expect(Money.tryParse('12.345'), isNull);
      expect(Money.tryParse('abc'), isNull);
      expect(Money.tryParse(''), isNull);
      expect(() => Money.fromRupees(double.nan), throwsArgumentError);
    });

    test('formats with Indian grouping', () {
      expect(Money.fromPaise(12345650).toIndianString(), '1,23,456.50');
      expect(Money.fromPaise(99900).toIndianString(), '999.00');
      expect(Money.fromPaise(100000).toIndianString(), '1,000.00');
      expect(Money.fromPaise(1000000000).toIndianString(withSymbol: true), '₹1,00,00,000.00');
      expect(Money.fromPaise(-5).toPlainString(), '-0.05');
    });

    test('cashbook invariant: opening + receipts - payments = closing', () {
      final opening = Money.parse('10000.00');
      final receipts = [Money.parse('2500.50'), Money.parse('99.99')];
      final payments = [Money.parse('1200.25')];
      final closing = opening + Money.sum(receipts) - Money.sum(payments);
      expect(closing, Money.parse('11400.24'));
    });
  });
}
