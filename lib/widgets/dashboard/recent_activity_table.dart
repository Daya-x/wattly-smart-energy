import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../providers/dashboard_provider.dart';

class RecentActivityTable extends StatelessWidget {
  const RecentActivityTable({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<DashboardProvider>();
    final sensor = provider.sensor;
    final time = _timeLabel(provider.deviceUpdatedAt ?? DateTime.now());
    final rows = [
      _ActivityRow(
        time: time,
        event: 'Motion sensor',
        status: sensor.motion ? 'Detected' : 'No motion',
      ),
      _ActivityRow(time: time, event: 'Gas reading', status: '${sensor.gas}'),
      _ActivityRow(
        time: time,
        event: 'Relay output',
        status: sensor.relay ? 'ON' : 'OFF',
      ),
      _ActivityRow(
        time: time,
        event: 'Temperature',
        status: sensor.dhtValid
            ? '${sensor.temperature.toStringAsFixed(1)}°C'
            : 'Sensor unavailable',
      ),
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: AppColors.cardNavy,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Recent activity",
            style: TextStyle(
              color: AppColors.white,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 20),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columnSpacing: 28,
              headingTextStyle: const TextStyle(
                color: AppColors.neonGreen,
                fontWeight: FontWeight.bold,
              ),
              dataTextStyle: const TextStyle(color: AppColors.white),
              columns: const [
                DataColumn(label: Text("Time")),
                DataColumn(label: Text("Event")),
                DataColumn(label: Text("Status")),
              ],
              rows: [
                for (final row in rows)
                  DataRow(
                    cells: [
                      DataCell(Text(row.time)),
                      DataCell(Text(row.event)),
                      DataCell(Text(row.status)),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActivityRow {
  final String time;
  final String event;
  final String status;

  const _ActivityRow({
    required this.time,
    required this.event,
    required this.status,
  });
}

String _timeLabel(DateTime dateTime) {
  final hour = dateTime.hour;
  final minute = dateTime.minute.toString().padLeft(2, '0');
  final suffix = hour >= 12 ? 'PM' : 'AM';
  final displayHour = hour % 12 == 0 ? 12 : hour % 12;
  return '$displayHour:$minute $suffix';
}
