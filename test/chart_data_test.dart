import 'package:al_amin/domain/chart_data.dart';
import 'package:flutter_test/flutter_test.dart';

ChartRecord _in(int y, int m, String head, double amount) =>
    ChartRecord(date: DateTime(y, m, 15), head: head, amount: amount, isIncome: true);
ChartRecord _out(int y, int m, String head, double amount) =>
    ChartRecord(date: DateTime(y, m, 15), head: head, amount: amount, isIncome: false);

void main() {
  group('ChartData.build', () {
    final records = <ChartRecord>[
      _in(2026, 1, 'Monthly', 1000),
      _in(2026, 1, 'General', 500),
      _in(2026, 1, 'Boxes', 100),
      _in(2026, 5, 'Sadqa-e-Fitr', 4000),
      _in(2026, 5, 'Monthly', 1000),
      _out(2026, 1, 'Zakaat', 800),
      _out(2026, 1, 'Qarza', 100),
      _out(2026, 4, 'Other Expenses', 400),
    ];
    final data = ChartData.build(records, from: DateTime(2026, 1, 1), to: DateTime(2026, 5, 31));

    test('has one stack per month in the range', () {
      expect(data.incomeMonths.length, 5);
      expect(ChartData.monthLabel(data.incomeMonths.first.month), 'Jan-26');
      expect(ChartData.monthLabel(data.incomeMonths.last.month), 'May-26');
    });

    test('stacks income by head and totals each month', () {
      final jan = data.incomeMonths[0];
      expect(jan.byHead['Monthly'], 1000);
      expect(jan.byHead['General'], 500);
      expect(jan.total, 1600);
      expect(data.incomeMonths[4].total, 5000);
      expect(data.incomeMonths[1].total, 0);
    });

    test('totals by head and overall', () {
      expect(data.incomeTotals['Monthly'], 2000);
      expect(data.incomeTotals['Zakaat'], 0);
      expect(data.totalIncome, 6600); // Jan 1,600 + May 5,000
      expect(data.totalExpense, 1300);
      expect(data.expenseTotals['Zakaat'], 800);
      expect(data.expenseMonths[3].byHead['Other Expenses'], 400);
    });

    test('ignores records outside the range, zero amounts and unknown heads', () {
      final d = ChartData.build(
        [
          _in(2025, 12, 'Monthly', 999),
          _in(2026, 2, 'Monthly', 0),
          _in(2026, 2, 'Monthly', -5),
          _in(2026, 2, 'Nonsense', 70),
          _in(2026, 2, 'General', 70),
        ],
        from: DateTime(2026, 1, 1),
        to: DateTime(2026, 3, 31),
      );
      expect(d.totalIncome, 70);
      expect(d.incomeTotals['General'], 70);
    });

    test('limits the number of months shown to the latest ones', () {
      final d = ChartData.build(const [], from: DateTime(2020, 1, 1), to: DateTime(2026, 5, 1), maxMonths: 12);
      expect(d.incomeMonths.length, 12);
      expect(ChartData.monthLabel(d.incomeMonths.last.month), 'May-26');
      expect(ChartData.monthLabel(d.incomeMonths.first.month), 'Jun-25');
      expect(d.isEmpty, isTrue);
    });

    test('period label', () {
      expect(data.periodLabel, 'Jan\u2013May 26');
    });
  });

  group('type to head mapping', () {
    test('income', () {
      expect(ChartHeads.incomeHeadForType('Monthly Donation'), 'Monthly');
      expect(ChartHeads.incomeHeadForType('Box Collection'), 'Boxes');
      expect(ChartHeads.incomeHeadForType('Qarz Recovered'), isNull);
    });

    test('expense', () {
      expect(ChartHeads.expenseHeadForType('Qarz Issued'), 'Qarza');
      expect(ChartHeads.expenseHeadForType('Zakaat Expenditure'), 'Zakaat');
      expect(ChartHeads.expenseHeadForType('Qarz Waived to Zakaat'), isNull);
    });
  });
}
