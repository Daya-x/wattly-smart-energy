import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../services/export/file_download_service.dart';
import '../../services/hardware/esp32_service.dart';
import '../../widgets/common/app_shell.dart';

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  String range = 'Week';
  DateTime selectedDate = DateTime.now();
  final Esp32Service _esp32Service = Esp32Service();
  final FileDownloadService _downloadService = FileDownloadService();
  List<double>? _persistedValues;
  bool _loadingHistory = true;
  String? _historyError;
  String? _historySource;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  @override
  Widget build(BuildContext context) {
    final values = _values();
    final total = values.fold<double>(0, (sum, value) => sum + value);
    final average = total / values.length;
    final peak = values.reduce(math.max);
    final peakIndex = values.indexOf(peak);

    return AppShell(
      selectedIndex: 2,
      title: 'Usage history',
      subtitle: 'Explore energy use by hour, weekday, or calendar date.',
      actions: [
        AppButton(
          label: 'Export report',
          icon: Icons.download_rounded,
          primary: false,
          onPressed: () => _exportReport(values),
        ),
      ],
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 760;
          return Column(
            children: [
              _PeriodControls(
                range: range,
                periodLabel: _periodLabel(),
                onRangeChanged: (value) {
                  setState(() => range = value);
                  _loadHistory();
                },
                onPrevious: () => _movePeriod(-1),
                onNext: () => _movePeriod(1),
                onToday: () {
                  setState(() => selectedDate = DateTime.now());
                  _loadHistory();
                },
                onPickDate: _pickDate,
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  if (_loadingHistory)
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    Icon(
                      _historyError == null
                          ? Icons.cloud_done_outlined
                          : Icons.cloud_off_outlined,
                      size: 15,
                      color: _historyError == null
                          ? AppColors.mint
                          : AppColors.warningOrange,
                    ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      _loadingHistory
                          ? 'Loading persisted usage…'
                          : _historyError ??
                                'Stored usage • ${_historySource ?? 'persistence'}',
                      style: const TextStyle(
                        color: AppColors.textGrey,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              if (range == 'Month') ...[
                _MonthCalendar(
                  month: selectedDate,
                  values: values,
                  selectedDay: selectedDate.day,
                  onDaySelected: (day) => setState(
                    () => selectedDate = DateTime(
                      selectedDate.year,
                      selectedDate.month,
                      day,
                    ),
                  ),
                ),
                const SizedBox(height: 18),
              ],
              SurfaceCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Consumption trend',
                      style: TextStyle(
                        color: AppColors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '${_periodLabel()} • units (kWh)',
                      style: const TextStyle(
                        color: AppColors.textGrey,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 26),
                    SizedBox(
                      height: 300,
                      child: total <= 0.00001
                          ? _EmptyUsageChart(range: range)
                          : LineChart(_chartData(values)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              _UsageBreakdown(
                title: range == 'Day'
                    ? 'Hourly usage'
                    : range == 'Week'
                    ? 'Daily usage'
                    : 'Usage by date',
                labels: [
                  for (var i = 0; i < values.length; i++)
                    _axisLabel(i, detailed: true),
                ],
                values: values,
              ),
              const SizedBox(height: 18),
              _SummaryGrid(
                compact: compact,
                items: [
                  _Summary(_totalTitle(), '${total.toStringAsFixed(1)} units'),
                  _Summary(
                    range == 'Day' ? 'Hourly average' : 'Daily average',
                    '${average.toStringAsFixed(2)} units',
                  ),
                  _Summary(
                    'Peak usage',
                    '${peak.toStringAsFixed(2)} units',
                    _axisLabel(peakIndex, detailed: true),
                  ),
                  _Summary(
                    'Data points',
                    '${values.length}',
                    range == 'Day'
                        ? '24 hours'
                        : range == 'Week'
                        ? 'Monday–Sunday'
                        : 'Every date',
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  List<double> _values() {
    final expectedLength = range == 'Day'
        ? 24
        : range == 'Week'
        ? 7
        : DateTime(selectedDate.year, selectedDate.month + 1, 0).day;
    if (_persistedValues?.length == expectedLength) {
      return _persistedValues!;
    }
    return List.filled(expectedLength, 0);
  }

  Future<void> _loadHistory() async {
    setState(() {
      _loadingHistory = true;
      _historyError = null;
      _persistedValues = null;
    });
    try {
      final result = await _esp32Service.fetchUsageHistory(
        period: range.toLowerCase(),
        anchor: selectedDate,
      );
      if (!mounted) return;
      setState(() {
        _persistedValues = result.values;
        _historySource = result.source;
        _loadingHistory = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _historyError = error.toString();
        _loadingHistory = false;
      });
    }
  }

  LineChartData _chartData(List<double> values) {
    final maximum = values.reduce(math.max);
    final horizontalInterval = maximum <= 0.05
        ? 0.01
        : maximum <= 1
        ? 0.2
        : maximum / 4;
    return LineChartData(
      minX: 0,
      maxX: (values.length - 1).toDouble(),
      minY: 0,
      maxY: math.max(maximum * 1.2, 0.05),
      borderData: FlBorderData(show: false),
      gridData: FlGridData(
        drawVerticalLine: false,
        horizontalInterval: horizontalInterval,
        getDrawingHorizontalLine: (_) =>
            const FlLine(color: AppColors.border, strokeWidth: 1),
      ),
      titlesData: FlTitlesData(
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles: const AxisTitles(
          sideTitles: SideTitles(showTitles: false),
        ),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 42,
            interval: horizontalInterval,
            getTitlesWidget: (value, meta) {
              if (value < 0) return const SizedBox.shrink();
              final label = maximum <= 0.05
                  ? value.toStringAsFixed(2)
                  : value.toStringAsFixed(value < 1 ? 1 : 0);
              return Text(
                label,
                style: const TextStyle(color: AppColors.textGrey, fontSize: 11),
              );
            },
          ),
        ),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 34,
            interval: 1,
            getTitlesWidget: (value, meta) {
              final index = value.round();
              if (index < 0 ||
                  index >= values.length ||
                  !_showAxisLabel(index)) {
                return const SizedBox.shrink();
              }
              return Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  _axisLabel(index),
                  style: const TextStyle(
                    color: AppColors.textGrey,
                    fontSize: 11,
                  ),
                ),
              );
            },
          ),
        ),
      ),
      lineTouchData: LineTouchData(
        touchTooltipData: LineTouchTooltipData(
          getTooltipColor: (_) => AppColors.lightCard,
          getTooltipItems: (spots) => spots
              .map(
                (spot) => LineTooltipItem(
                  '${_axisLabel(spot.x.round(), detailed: true)}\n${spot.y.toStringAsFixed(2)} units (${spot.y.toStringAsFixed(2)} kWh)',
                  const TextStyle(
                    color: AppColors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              )
              .toList(),
        ),
      ),
      lineBarsData: [
        LineChartBarData(
          spots: [
            for (var i = 0; i < values.length; i++)
              FlSpot(i.toDouble(), values[i]),
          ],
          isCurved: false,
          color: AppColors.neonGreen,
          barWidth: 3,
          dotData: FlDotData(show: range == 'Week'),
          belowBarData: BarAreaData(
            show: true,
            color: AppColors.neonGreen.withValues(alpha: .10),
          ),
        ),
      ],
    );
  }

  bool _showAxisLabel(int index) {
    if (range == 'Day') return index % 3 == 0 || index == 23;
    if (range == 'Week') return true;
    return index == 0 || (index + 1) % 5 == 0 || index == _values().length - 1;
  }

  String _axisLabel(int index, {bool detailed = false}) {
    if (range == 'Day') {
      final hour = index;
      if (detailed) {
        return '${_dateLabel(selectedDate)}, ${_hourLabel(hour)}';
      }
      return _hourLabel(hour);
    }
    if (range == 'Week') {
      const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      final date = _weekStart().add(Duration(days: index));
      return detailed
          ? '${weekdays[index]}, ${_dateLabel(date)}'
          : weekdays[index];
    }
    final date = DateTime(selectedDate.year, selectedDate.month, index + 1);
    return detailed ? _dateLabel(date) : '${index + 1}';
  }

  String _hourLabel(int hour) {
    if (hour == 0) return '12 AM';
    if (hour == 12) return '12 PM';
    return hour < 12 ? '$hour AM' : '${hour - 12} PM';
  }

  DateTime _weekStart() => selectedDate.subtract(
    Duration(days: selectedDate.weekday - DateTime.monday),
  );

  String _periodLabel() {
    if (range == 'Day') return _dateLabel(selectedDate);
    if (range == 'Week') {
      final start = _weekStart();
      final end = start.add(const Duration(days: 6));
      return '${_shortDate(start)} – ${_shortDate(end)}';
    }
    return '${_monthName(selectedDate.month)} ${selectedDate.year}';
  }

  String _totalTitle() {
    if (range == 'Day') {
      final today = DateTime.now();
      final isToday =
          selectedDate.year == today.year &&
          selectedDate.month == today.month &&
          selectedDate.day == today.day;
      return isToday ? 'Today usage' : 'Selected day usage';
    }
    if (range == 'Week') return 'Week usage';
    return 'Month usage';
  }

  void _movePeriod(int direction) {
    var changed = false;
    setState(() {
      final today = _dateOnly(DateTime.now());
      if (range == 'Day') {
        final candidate = selectedDate.add(Duration(days: direction));
        if (!candidate.isAfter(today)) {
          selectedDate = candidate;
          changed = true;
        }
      } else if (range == 'Week') {
        final candidate = selectedDate.add(Duration(days: direction * 7));
        final candidateStart = candidate.subtract(
          Duration(days: candidate.weekday - DateTime.monday),
        );
        final currentStart = today.subtract(
          Duration(days: today.weekday - DateTime.monday),
        );
        if (!candidateStart.isAfter(currentStart)) {
          selectedDate = candidate;
          changed = true;
        }
      } else {
        final candidate = DateTime(
          selectedDate.year,
          selectedDate.month + direction,
          1,
        );
        if (!candidate.isAfter(DateTime(today.year, today.month))) {
          selectedDate = candidate;
          changed = true;
        }
      }
    });
    if (changed) _loadHistory();
  }

  Future<void> _pickDate() async {
    final today = _dateOnly(DateTime.now());
    final picked = await showDatePicker(
      context: context,
      initialDate: selectedDate.isAfter(today) ? today : selectedDate,
      firstDate: DateTime(2020),
      lastDate: today,
      helpText: range == 'Month' ? 'SELECT A MONTH' : 'SELECT A DATE',
    );
    if (picked != null) {
      setState(() => selectedDate = picked);
      _loadHistory();
    }
  }

  void _exportReport(List<double> values) {
    final rows = <List<String>>[
      ['Wattly usage report'],
      ['Period', range],
      ['Selected date', _dateLabel(selectedDate)],
      ['Generated at', DateTime.now().toIso8601String()],
      ['Source', _historySource ?? 'dashboard'],
      [],
      ['Label', 'Usage units (kWh)'],
      for (var i = 0; i < values.length; i++)
        [_axisLabel(i, detailed: true), values[i].toStringAsFixed(4)],
    ];
    final csv = rows.map(_csvRow).join('\n');
    final filename =
        'wattly_usage_${range.toLowerCase()}_${_fileDate(selectedDate)}.csv';
    _downloadService.downloadText(
      filename: filename,
      content: csv,
      mimeType: 'text/csv;charset=utf-8',
    );
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Downloaded $filename')));
  }
}

class _PeriodControls extends StatelessWidget {
  final String range;
  final String periodLabel;
  final ValueChanged<String> onRangeChanged;
  final VoidCallback onPrevious, onNext, onToday, onPickDate;

  const _PeriodControls({
    required this.range,
    required this.periodLabel,
    required this.onRangeChanged,
    required this.onPrevious,
    required this.onNext,
    required this.onToday,
    required this.onPickDate,
  });

  @override
  Widget build(BuildContext context) => SurfaceCard(
    padding: const EdgeInsets.all(14),
    child: Wrap(
      spacing: 12,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      alignment: WrapAlignment.spaceBetween,
      children: [
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'Day', label: Text('Day')),
            ButtonSegment(value: 'Week', label: Text('Week')),
            ButtonSegment(value: 'Month', label: Text('Month')),
          ],
          selected: {range},
          onSelectionChanged: (value) => onRangeChanged(value.first),
        ),
        Wrap(
          spacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            IconButton(
              tooltip: 'Previous period',
              onPressed: onPrevious,
              icon: const Icon(Icons.chevron_left),
            ),
            OutlinedButton.icon(
              onPressed: onPickDate,
              icon: const Icon(Icons.calendar_month_outlined, size: 18),
              label: Text(periodLabel),
            ),
            IconButton(
              tooltip: 'Next period',
              onPressed: onNext,
              icon: const Icon(Icons.chevron_right),
            ),
            TextButton(onPressed: onToday, child: const Text('Today')),
          ],
        ),
      ],
    ),
  );
}

class _MonthCalendar extends StatelessWidget {
  final DateTime month;
  final List<double> values;
  final int selectedDay;
  final ValueChanged<int> onDaySelected;

  const _MonthCalendar({
    required this.month,
    required this.values,
    required this.selectedDay,
    required this.onDaySelected,
  });

  @override
  Widget build(BuildContext context) {
    final leading = DateTime(month.year, month.month, 1).weekday - 1;
    final maximum = values.reduce(math.max);
    final scaleMaximum = maximum <= 0 ? 1.0 : maximum;
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Monthly calendar',
            style: TextStyle(
              color: AppColors.white,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              for (final day in [
                'Mon',
                'Tue',
                'Wed',
                'Thu',
                'Fri',
                'Sat',
                'Sun',
              ])
                Expanded(
                  child: Center(
                    child: Text(
                      day,
                      style: const TextStyle(
                        color: AppColors.textGrey,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              mainAxisExtent: 54,
              crossAxisSpacing: 6,
              mainAxisSpacing: 6,
            ),
            itemCount: leading + values.length,
            itemBuilder: (context, index) {
              if (index < leading) return const SizedBox.shrink();
              final day = index - leading + 1;
              final value = values[day - 1];
              final selected = day == selectedDay;
              final future = DateTime(
                month.year,
                month.month,
                day,
              ).isAfter(_dateOnly(DateTime.now()));
              return InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: future ? null : () => onDaySelected(day),
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.neonGreen.withValues(
                      alpha: .08 + .28 * (value / scaleMaximum),
                    ),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: selected ? AppColors.neonGreen : AppColors.border,
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '$day',
                        style: const TextStyle(
                          color: AppColors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        future ? '—' : value.toStringAsFixed(1),
                        style: const TextStyle(
                          color: AppColors.textGrey,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _EmptyUsageChart extends StatelessWidget {
  final String range;

  const _EmptyUsageChart({required this.range});

  @override
  Widget build(BuildContext context) {
    final period = range == 'Day'
        ? 'day'
        : range == 'Week'
        ? 'week'
        : 'month';
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.darkNavy.withValues(alpha: .25),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.show_chart_rounded,
            color: AppColors.textGrey.withValues(alpha: .8),
            size: 38,
          ),
          const SizedBox(height: 12),
          const Text(
            'No usage recorded for this period',
            style: TextStyle(
              color: AppColors.white,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Run the meter or presentation demo to collect $period usage.',
            style: const TextStyle(color: AppColors.textGrey, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _Summary {
  final String title, value;
  final String? detail;
  const _Summary(this.title, this.value, [this.detail]);
}

class _UsageBreakdown extends StatelessWidget {
  final String title;
  final List<String> labels;
  final List<double> values;

  const _UsageBreakdown({
    required this.title,
    required this.labels,
    required this.values,
  });

  @override
  Widget build(BuildContext context) => SurfaceCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: AppColors.white,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Every usage amount for the selected period',
          style: TextStyle(color: AppColors.textGrey, fontSize: 12),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (var i = 0; i < values.length; i++)
              Container(
                width: 165,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.lightCard,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      labels[i],
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textGrey,
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      values[i] == 0
                          ? 'No data'
                          : '${values[i].toStringAsFixed(2)} units',
                      style: const TextStyle(
                        color: AppColors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ],
    ),
  );
}

class _SummaryGrid extends StatelessWidget {
  final bool compact;
  final List<_Summary> items;
  const _SummaryGrid({required this.compact, required this.items});

  @override
  Widget build(BuildContext context) => compact
      ? Column(
          children: [
            for (var i = 0; i < items.length; i++) ...[
              _Metric(items[i]),
              if (i < items.length - 1) const SizedBox(height: 12),
            ],
          ],
        )
      : Row(
          children: [
            for (var i = 0; i < items.length; i++) ...[
              Expanded(child: _Metric(items[i])),
              if (i < items.length - 1) const SizedBox(width: 12),
            ],
          ],
        );
}

class _Metric extends StatelessWidget {
  final _Summary item;
  const _Metric(this.item);

  @override
  Widget build(BuildContext context) => SurfaceCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          item.title,
          style: const TextStyle(color: AppColors.textGrey, fontSize: 12),
        ),
        const SizedBox(height: 10),
        Text(
          item.value,
          style: const TextStyle(
            color: AppColors.white,
            fontSize: 22,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          item.detail ?? 'Selected period',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: AppColors.mint, fontSize: 11),
        ),
      ],
    ),
  );
}

const _months = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

String _monthName(int month) => _months[month - 1];
String _dateLabel(DateTime date) =>
    '${_monthName(date.month)} ${date.day}, ${date.year}';
String _shortDate(DateTime date) =>
    '${_monthName(date.month).substring(0, 3)} ${date.day}, ${date.year}';
DateTime _dateOnly(DateTime date) => DateTime(date.year, date.month, date.day);
String _fileDate(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

String _csvRow(List<String> cells) => cells.map(_csvCell).join(',');

String _csvCell(String value) {
  final escaped = value.replaceAll('"', '""');
  return value.contains(',') || value.contains('"') || value.contains('\n')
      ? '"$escaped"'
      : escaped;
}
