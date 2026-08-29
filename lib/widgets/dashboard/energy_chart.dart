import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../providers/dashboard_provider.dart';
import '../../services/hardware/esp32_service.dart';

class EnergyChart extends StatefulWidget {
  const EnergyChart({super.key});

  @override
  State<EnergyChart> createState() => _EnergyChartState();
}

class _EnergyChartState extends State<EnergyChart> {
  final Esp32Service _esp32Service = Esp32Service();
  List<double>? _storedWeekValues;

  @override
  void initState() {
    super.initState();
    _loadStoredWeek();
  }

  Future<void> _loadStoredWeek() async {
    try {
      final result = await _esp32Service.fetchUsageHistory(
        period: 'week',
        anchor: DateTime.now(),
      );
      if (!mounted) return;
      setState(() => _storedWeekValues = result.values);
    } catch (_) {
      if (!mounted) return;
      setState(() => _storedWeekValues = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final todayUsage = context.watch<DashboardProvider>().todayUsageKwh;
    final values = _storedWeekValues?.length == 7
        ? _storedWeekValues!
        : [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, todayUsage];
    final total = values.fold<double>(0, (sum, value) => sum + value);
    final labels = List.generate(7, (index) {
      final date = DateTime.now().subtract(Duration(days: 6 - index));
      const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      return names[date.weekday - 1];
    });
    final maximum = values.reduce((a, b) => a > b ? a : b);

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: AppColors.cardNavy,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Energy consumption',
                      style: TextStyle(
                        color: AppColors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _storedWeekValues == null
                          ? 'Live estimate • units (kWh)'
                          : 'Stored last 7 days • units (kWh)',
                      style: const TextStyle(
                        color: AppColors.textGrey,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${total.toStringAsFixed(1)} units',
                    style: const TextStyle(
                      color: AppColors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pushNamed(context, '/history'),
                    child: const Text('View history'),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 18),
          SizedBox(
            height: 240,
            child: LineChart(
              LineChartData(
                minX: 0,
                maxX: 6,
                minY: 0,
                maxY: maximum < 1 ? 1 : maximum * 1.2,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (_) =>
                      const FlLine(color: AppColors.border, strokeWidth: 1),
                ),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  leftTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: true, reservedSize: 34),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      interval: 1,
                      reservedSize: 28,
                      getTitlesWidget: (value, meta) {
                        final index = value.round();
                        if (index < 0 || index >= labels.length) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            labels[index],
                            style: TextStyle(
                              color: index == 6
                                  ? AppColors.neonGreen
                                  : AppColors.textGrey,
                              fontSize: 11,
                              fontWeight: index == 6
                                  ? FontWeight.w700
                                  : FontWeight.w400,
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
                            '${labels[spot.x.round()]}\n${spot.y.toStringAsFixed(2)} units',
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
                    barWidth: 3,
                    dotData: const FlDotData(show: true),
                    color: AppColors.neonGreen,
                    belowBarData: BarAreaData(
                      show: true,
                      color: AppColors.neonGreen.withValues(alpha: 0.15),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
