// Pure data preparation for the income / expense charts (no Flutter, no
// database), so it can be unit tested and reused by Reports and Total Funds.

class ChartRecord {
  final DateTime date;
  final String head;
  final double amount;
  final bool isIncome;
  const ChartRecord({
    required this.date,
    required this.head,
    required this.amount,
    required this.isIncome,
  });
}

/// Chart heads, in the order they are stacked and listed.
class ChartHeads {
  ChartHeads._();

  static const List<String> income = <String>[
    'Monthly',
    'General',
    'Boxes',
    'Other',
    'Zakaat',
    'Sadqa-e-Fitr',
  ];

  static const List<String> expense = <String>[
    'Zakaat',
    'Qarza',
    'Sadqa-e-Fitr',
    'Other Expenses',
  ];

  /// Maps a report transaction type to an income head, or null when the type is
  /// not income (for example a Qarz repayment, which is not a donation).
  static String? incomeHeadForType(String type) {
    switch (type.trim().toLowerCase()) {
      case 'monthly donation':
        return 'Monthly';
      case 'general donation':
        return 'General';
      case 'box collection':
        return 'Boxes';
      case 'other income':
        return 'Other';
      case 'zakaat':
        return 'Zakaat';
      case 'sadqa-e-fitr':
        return 'Sadqa-e-Fitr';
    }
    return null;
  }

  /// Maps a report transaction type to an expense head, or null when it is not
  /// charted (a Qarz waiver is not a cash payment; the loan was already shown
  /// as Qarza when it was issued).
  static String? expenseHeadForType(String type) {
    switch (type.trim().toLowerCase()) {
      case 'zakaat expenditure':
        return 'Zakaat';
      case 'qarz issued':
        return 'Qarza';
      case 'sadqa-e-fitr expenditure':
        return 'Sadqa-e-Fitr';
      case 'other expense':
        return 'Other Expenses';
    }
    return null;
  }
}

class MonthStack {
  final DateTime month;
  final Map<String, double> byHead;
  const MonthStack(this.month, this.byHead);

  double get total => byHead.values.fold<double>(0.0, (a, b) => a + b);
}

class ChartData {
  final List<MonthStack> incomeMonths;
  final List<MonthStack> expenseMonths;
  final Map<String, double> incomeTotals;
  final Map<String, double> expenseTotals;

  const ChartData({
    required this.incomeMonths,
    required this.expenseMonths,
    required this.incomeTotals,
    required this.expenseTotals,
  });

  static const List<String> _monthNames = <String>[
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  static String monthLabel(DateTime d) =>
      '${_monthNames[d.month - 1]}-${(d.year % 100).toString().padLeft(2, '0')}';

  static int _index(DateTime d) => d.year * 12 + (d.month - 1);

  double get totalIncome =>
      incomeTotals.values.fold<double>(0.0, (a, b) => a + b);
  double get totalExpense =>
      expenseTotals.values.fold<double>(0.0, (a, b) => a + b);

  bool get isEmpty => totalIncome <= 0 && totalExpense <= 0;

  /// "Jan–May 26" or "Nov 25–Apr 26".
  String get periodLabel {
    if (incomeMonths.isEmpty) return '';
    final first = incomeMonths.first.month;
    final last = incomeMonths.last.month;
    final a = _monthNames[first.month - 1];
    final b = _monthNames[last.month - 1];
    String yy(DateTime d) => (d.year % 100).toString().padLeft(2, '0');
    if (first.year == last.year) {
      return first.month == last.month ? '$a ${yy(first)}' : '$a\u2013$b ${yy(last)}';
    }
    return '$a ${yy(first)}\u2013$b ${yy(last)}';
  }

  /// Groups [records] by month and head for the months from [from] to [to]
  /// (at most the latest [maxMonths]). Zero and negative amounts are ignored.
  static ChartData build(
    List<ChartRecord> records, {
    required DateTime from,
    required DateTime to,
    int maxMonths = 12,
  }) {
    var endIndex = _index(to);
    var startIndex = _index(from);
    if (startIndex > endIndex) {
      final swap = startIndex;
      startIndex = endIndex;
      endIndex = swap;
    }
    if (endIndex - startIndex + 1 > maxMonths) {
      startIndex = endIndex - maxMonths + 1;
    }
    final count = endIndex - startIndex + 1;

    DateTime monthOf(int index) => DateTime(index ~/ 12, index % 12 + 1, 1);

    Map<String, double> zeroed(List<String> heads) =>
        <String, double>{for (final h in heads) h: 0.0};

    final income = <MonthStack>[
      for (var i = 0; i < count; i++) MonthStack(monthOf(startIndex + i), zeroed(ChartHeads.income)),
    ];
    final expense = <MonthStack>[
      for (var i = 0; i < count; i++) MonthStack(monthOf(startIndex + i), zeroed(ChartHeads.expense)),
    ];
    final incomeTotals = zeroed(ChartHeads.income);
    final expenseTotals = zeroed(ChartHeads.expense);

    for (final r in records) {
      if (!r.amount.isFinite || r.amount <= 0) continue;
      final slot = _index(r.date) - startIndex;
      if (slot < 0 || slot >= count) continue;
      final stack = r.isIncome ? income[slot] : expense[slot];
      final totals = r.isIncome ? incomeTotals : expenseTotals;
      if (!stack.byHead.containsKey(r.head)) continue;
      stack.byHead[r.head] = stack.byHead[r.head]! + r.amount;
      totals[r.head] = totals[r.head]! + r.amount;
    }

    return ChartData(
      incomeMonths: income,
      expenseMonths: expense,
      incomeTotals: incomeTotals,
      expenseTotals: expenseTotals,
    );
  }
}
