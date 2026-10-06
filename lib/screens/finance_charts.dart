import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../database/app_database.dart';
import '../database/chart_data_service.dart';
import '../domain/chart_data.dart';
import '../domain/format.dart';

const Map<String, Color> _incomeColors = <String, Color>{
  'Monthly': Color(0xFF3D85E0),
  'General': Color(0xFFF26B38),
  'Boxes': Color(0xFF9E9E9E),
  'Other': Color(0xFFFFC107),
  'Zakaat': Color(0xFF7E57C2),
  'Sadqa-e-Fitr': Color(0xFF66AA44),
};

const Map<String, Color> _expenseColors = <String, Color>{
  'Zakaat': Color(0xFF3D85E0),
  'Qarza': Color(0xFFF26B38),
  'Sadqa-e-Fitr': Color(0xFF66AA44),
  'Other Expenses': Color(0xFF9E9E9E),
};

/// Four charts: income and expenses by month (stacked by head) and the totals
/// by head for the same period. Two columns on wide screens, one on phones.
class FinanceCharts extends StatelessWidget {
  final ChartData data;
  const FinanceCharts({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    final period = data.periodLabel;
    final incomeStacked = _StackedCard(
      title: 'Income by Month (Stacked)',
      income: true,
      heads: ChartHeads.income,
      colors: _incomeColors,
      months: data.incomeMonths,
    );
    final incomeHeads = _HeadTotalsCard(
      title: 'Total Income by Head ($period)',
      badgeLabel: 'Total Income',
      income: true,
      heads: ChartHeads.income,
      colors: _incomeColors,
      totals: data.incomeTotals,
      total: data.totalIncome,
    );
    final expenseStacked = _StackedCard(
      title: 'Expenses by Month (Stacked)',
      income: false,
      heads: ChartHeads.expense,
      colors: _expenseColors,
      months: data.expenseMonths,
    );
    final expenseHeads = _HeadTotalsCard(
      title: 'Total Expenses by Head ($period)',
      badgeLabel: 'Total Expenses',
      income: false,
      heads: ChartHeads.expense,
      colors: _expenseColors,
      totals: data.expenseTotals,
      total: data.totalExpense,
    );
    const note = Padding(
      padding: EdgeInsets.only(bottom: 8),
      child: Text(
        'Only approved transactions are shown. Qarza means loans issued; loan repayments and waivers are not counted as income or expense here.',
        style: TextStyle(fontSize: 11.5, color: Colors.black54),
      ),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 900) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 6, child: incomeStacked),
                  const SizedBox(width: 14),
                  Expanded(flex: 5, child: incomeHeads),
                ],
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 6, child: expenseStacked),
                  const SizedBox(width: 14),
                  Expanded(flex: 5, child: expenseHeads),
                ],
              ),
              note,
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [incomeStacked, incomeHeads, expenseStacked, expenseHeads, note],
        );
      },
    );
  }
}

class _ChartShell extends StatelessWidget {
  final String title;
  final bool income;
  final Widget? badge;
  final Widget child;

  const _ChartShell({
    required this.title,
    required this.income,
    required this.child,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    final tint = income ? const Color(0xFFE3F1E4) : const Color(0xFFFCE3E3);
    final ink = income ? const Color(0xFF14532D) : const Color(0xFFA11A1A);
    final border = income ? const Color(0xFFBFDCC2) : const Color(0xFFF3BDBD);
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .94),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .06),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: tint,
            padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800, color: ink),
                  ),
                ),
                if (badge != null) ...[const SizedBox(width: 8), badge!],
              ],
            ),
          ),
          Padding(padding: const EdgeInsets.all(12), child: child),
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  final List<String> heads;
  final Map<String, Color> colors;
  const _Legend({required this.heads, required this.colors});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 14,
      runSpacing: 6,
      children: [
        for (final head in heads)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: colors[head] ?? Colors.grey,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 6),
              Text(head, style: const TextStyle(fontSize: 12)),
            ],
          ),
      ],
    );
  }
}

class _StackedCard extends StatelessWidget {
  final String title;
  final bool income;
  final List<String> heads;
  final Map<String, Color> colors;
  final List<MonthStack> months;

  const _StackedCard({
    required this.title,
    required this.income,
    required this.heads,
    required this.colors,
    required this.months,
  });

  @override
  Widget build(BuildContext context) {
    final hasData = months.any((m) => m.total > 0);
    return _ChartShell(
      title: title,
      income: income,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!hasData)
            const SizedBox(
              height: 120,
              child: Center(child: Text('No approved transactions in this period.')),
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                const slotWidth = 58.0;
                const height = 250.0;
                final needed = months.length * slotWidth + 70;
                final painter = _StackedPainter(months, heads, colors);
                if (needed <= constraints.maxWidth) {
                  return CustomPaint(
                    size: Size(constraints.maxWidth, height),
                    painter: painter,
                  );
                }
                return SizedBox(
                  height: height,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    reverse: true,
                    child: CustomPaint(size: Size(needed, height), painter: painter),
                  ),
                );
              },
            ),
          const SizedBox(height: 10),
          _Legend(heads: heads, colors: colors),
        ],
      ),
    );
  }
}

class _StackedPainter extends CustomPainter {
  final List<MonthStack> months;
  final List<String> heads;
  final Map<String, Color> colors;

  const _StackedPainter(this.months, this.heads, this.colors);

  static double _niceStep(double maximum) {
    if (maximum <= 0) return 1.0;
    final rough = maximum / 5;
    final magnitude = math.pow(10, (math.log(rough) / math.ln10).floor()).toDouble();
    final normal = rough / magnitude;
    final double nice;
    if (normal <= 1) {
      nice = 1.0;
    } else if (normal <= 2) {
      nice = 2.0;
    } else if (normal <= 2.5) {
      nice = 2.5;
    } else if (normal <= 5) {
      nice = 5.0;
    } else {
      nice = 10.0;
    }
    return nice * magnitude;
  }

  static TextPainter _layout(String text, TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    );
    painter.layout();
    return painter;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (months.isEmpty || size.width < 80 || size.height < 80) return;

    var maxTotal = 0.0;
    for (final m in months) {
      if (m.total > maxTotal) maxTotal = m.total;
    }
    final step = _niceStep(maxTotal);
    final top = maxTotal <= 0 ? step : (maxTotal / step).ceil() * step;

    const axisStyle = TextStyle(fontSize: 11, color: Color(0xFF444444));
    final ticks = <double>[];
    for (var v = 0.0; v <= top + step * 0.001; v += step) {
      ticks.add(v);
    }
    var labelWidth = 0.0;
    for (final t in ticks) {
      labelWidth = math.max(labelWidth, _layout(t.asWhole, axisStyle).width);
    }

    final left = labelWidth + 12;
    const topPad = 22.0;
    const bottomPad = 26.0;
    const rightPad = 8.0;
    final plot = Rect.fromLTRB(left, topPad, size.width - rightPad, size.height - bottomPad);

    final grid = Paint()
      ..color = const Color(0xFFDDE3E0)
      ..strokeWidth = 1;
    for (final t in ticks) {
      final y = plot.bottom - plot.height * (t / top);
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), grid);
      final label = _layout(t.asWhole, axisStyle);
      label.paint(canvas, Offset(left - 6 - label.width, y - label.height / 2));
    }
    canvas.drawLine(
      Offset(plot.left, plot.bottom),
      Offset(plot.right, plot.bottom),
      Paint()
        ..color = const Color(0xFF777777)
        ..strokeWidth = 1.4,
    );

    final slot = plot.width / months.length;
    final barWidth = math.min(46.0, slot * 0.62);
    for (var i = 0; i < months.length; i++) {
      final m = months[i];
      final centerX = plot.left + slot * (i + 0.5);
      var cursor = plot.bottom;
      for (final head in heads) {
        final value = m.byHead[head] ?? 0.0;
        if (value <= 0) continue;
        final h = plot.height * value / top;
        final color = colors[head] ?? Colors.grey;
        canvas.drawRect(
          Rect.fromLTWH(centerX - barWidth / 2, cursor - h, barWidth, h),
          Paint()..color = color,
        );
        if (h >= 15) {
          final textColor = color.computeLuminance() > 0.55 ? Colors.black87 : Colors.white;
          final label = _layout(value.asWhole, TextStyle(fontSize: 10, color: textColor));
          if (label.width <= barWidth + 10) {
            label.paint(canvas, Offset(centerX - label.width / 2, cursor - h / 2 - label.height / 2));
          }
        }
        cursor -= h;
      }
      if (m.total > 0) {
        final totalLabel = _layout(
          m.total.asWhole,
          const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.black87),
        );
        totalLabel.paint(canvas, Offset(centerX - totalLabel.width / 2, cursor - totalLabel.height - 2));
      }
      final monthLabel = _layout(ChartData.monthLabel(m.month), axisStyle);
      monthLabel.paint(canvas, Offset(centerX - monthLabel.width / 2, plot.bottom + 6));
    }
  }

  @override
  bool shouldRepaint(covariant _StackedPainter oldDelegate) => true;
}

class _HeadTotalsCard extends StatelessWidget {
  final String title;
  final String badgeLabel;
  final bool income;
  final List<String> heads;
  final Map<String, Color> colors;
  final Map<String, double> totals;
  final double total;

  const _HeadTotalsCard({
    required this.title,
    required this.badgeLabel,
    required this.income,
    required this.heads,
    required this.colors,
    required this.totals,
    required this.total,
  });

  @override
  Widget build(BuildContext context) {
    var maximum = 0.0;
    for (final head in heads) {
      final v = totals[head] ?? 0.0;
      if (v > maximum) maximum = v;
    }
    final ink = income ? const Color(0xFF14532D) : const Color(0xFFA11A1A);
    final badgeFill = income ? const Color(0xFFE3F1E4) : const Color(0xFFFCE3E3);
    final badgeBorder = income ? const Color(0xFF8FC795) : const Color(0xFFEA9A9A);
    return _ChartShell(
      title: title,
      income: income,
      badge: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: badgeFill,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: badgeBorder),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(badgeLabel, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: ink)),
            Text(
              '\u20B9${total.asWhole}',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: ink),
            ),
          ],
        ),
      ),
      child: Column(
        children: [
          for (final head in heads)
            _HeadBarRow(
              head: head,
              value: totals[head] ?? 0.0,
              fraction: maximum <= 0 ? 0.0 : (totals[head] ?? 0.0) / maximum,
              color: colors[head] ?? Colors.grey,
            ),
        ],
      ),
    );
  }
}

class _HeadBarRow extends StatelessWidget {
  final String head;
  final double value;
  final double fraction;
  final Color color;

  const _HeadBarRow({
    required this.head,
    required this.value,
    required this.fraction,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          SizedBox(
            width: 92,
            child: Text(head, textAlign: TextAlign.right, style: const TextStyle(fontSize: 12.5)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final available = math.max(0.0, constraints.maxWidth - 82);
                return Row(
                  children: [
                    Container(
                      width: available * fraction,
                      height: 22,
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      value.asWhole,
                      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Loads the approved transactions and shows [FinanceCharts] for the 12 months
/// ending at [to] (default: now). Reloads when [reloadOn] notifies.
class FinanceChartsLoader extends StatefulWidget {
  final AppDatabase database;
  final DateTime? to;
  final Listenable? reloadOn;

  const FinanceChartsLoader({
    super.key,
    required this.database,
    this.to,
    this.reloadOn,
  });

  @override
  State<FinanceChartsLoader> createState() => _FinanceChartsLoaderState();
}

class _FinanceChartsLoaderState extends State<FinanceChartsLoader> {
  late Future<ChartData> _future;

  Future<ChartData> _load() async {
    final records = await ChartDataService.load(widget.database);
    final end = widget.to ?? DateTime.now();
    return ChartData.build(
      records,
      from: DateTime(end.year, end.month - 11, 1),
      to: end,
      maxMonths: 12,
    );
  }

  @override
  void initState() {
    super.initState();
    _future = _load();
    widget.reloadOn?.addListener(_reload);
  }

  @override
  void dispose() {
    widget.reloadOn?.removeListener(_reload);
    super.dispose();
  }

  void _reload() {
    if (!mounted) return;
    setState(() => _future = _load());
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<ChartData>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const SizedBox(height: 140, child: Center(child: CircularProgressIndicator()));
        }
        if (snapshot.hasError) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              children: [
                Text('Could not load the charts: ${snapshot.error}', textAlign: TextAlign.center),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _reload,
                  icon: const Icon(Icons.refresh),
                  label: const Text('RETRY'),
                ),
              ],
            ),
          );
        }
        return FinanceCharts(data: snapshot.data!);
      },
    );
  }
}
