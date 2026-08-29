import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../providers/dashboard_provider.dart';
import '../../services/hardware/esp32_service.dart';
import '../../widgets/common/app_shell.dart';

class AlertsPage extends StatefulWidget {
  const AlertsPage({super.key});

  @override
  State<AlertsPage> createState() => _AlertsPageState();
}

class _AlertsPageState extends State<AlertsPage> {
  String filter = 'All';

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<DashboardProvider>();
    final visible = provider.liveAlerts.where((alert) {
      if (filter == 'All') return true;
      if (filter == 'Resolved') return alert.status == 'resolved';
      return alert.status == 'active' && alert.severity == filter;
    }).toList();

    return AppShell(
      selectedIndex: 4,
      title: 'Alerts',
      subtitle: 'Live safety events from meter readings.',
      actions: [
        AppButton(
          label: 'Acknowledge all',
          icon: Icons.done_all_rounded,
          primary: false,
          onPressed: provider.unacknowledgedAlertCount == 0
              ? null
              : () => _acknowledgeAll(context),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: ['All', 'Critical', 'Warning', 'Resolved']
                .map(
                  (item) => ChoiceChip(
                    label: Text(item),
                    selected: filter == item,
                    onSelected: (_) => setState(() => filter = item),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(
                provider.alertsStatus == ForecastStatus.offline
                    ? Icons.cloud_off_outlined
                    : Icons.sensors_rounded,
                color: provider.alertsStatus == ForecastStatus.offline
                    ? AppColors.warningOrange
                    : AppColors.mint,
                size: 16,
              ),
              const SizedBox(width: 7),
              Text(
                provider.alertsError ?? 'Monitoring live ESP32 readings',
                style: const TextStyle(color: AppColors.textGrey, fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: 18),
          if (provider.alertsStatus == ForecastStatus.loading &&
              provider.liveAlerts.isEmpty)
            const SurfaceCard(child: Center(child: CircularProgressIndicator()))
          else if (visible.isEmpty)
            const SurfaceCard(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 48),
                child: Center(
                  child: Column(
                    children: [
                      Icon(
                        Icons.check_circle_outline_rounded,
                        color: AppColors.neonGreen,
                        size: 42,
                      ),
                      SizedBox(height: 12),
                      Text(
                        'No alerts in this category',
                        style: TextStyle(color: AppColors.white),
                      ),
                      SizedBox(height: 5),
                      Text(
                        'Current readings are within configured thresholds.',
                        style: TextStyle(
                          color: AppColors.textGrey,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else
            for (final alert in visible) ...[
              _AlertRow(
                alert: alert,
                onAcknowledge: () => _acknowledge(context, alert.id),
              ),
              const SizedBox(height: 12),
            ],
        ],
      ),
    );
  }

  Future<void> _acknowledge(BuildContext context, String id) async {
    try {
      await context.read<DashboardProvider>().acknowledgeAlert(id);
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _acknowledgeAll(BuildContext context) async {
    try {
      await context.read<DashboardProvider>().acknowledgeAllAlerts();
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }
}

class _AlertRow extends StatelessWidget {
  final LiveAlert alert;
  final VoidCallback onAcknowledge;

  const _AlertRow({required this.alert, required this.onAcknowledge});

  @override
  Widget build(BuildContext context) {
    final resolved = alert.status == 'resolved';
    final color = resolved
        ? AppColors.mint
        : alert.severity == 'Critical'
        ? AppColors.warningRed
        : AppColors.warningOrange;
    final icon = switch (alert.type) {
      'gas' => Icons.local_fire_department_rounded,
      'temperature' => Icons.device_thermostat_rounded,
      'power' => Icons.electric_bolt_rounded,
      'voltage' => Icons.power_outlined,
      'balance' => Icons.account_balance_wallet_outlined,
      'sensor_pzem' => Icons.electrical_services_rounded,
      'sensor_dht' => Icons.sensors_off_rounded,
      _ => Icons.warning_amber_rounded,
    };
    return SurfaceCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: color.withValues(alpha: .10),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(resolved ? Icons.check_rounded : icon, color: color),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      alert.title,
                      style: const TextStyle(
                        color: AppColors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: .10),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        resolved ? 'Resolved' : alert.severity,
                        style: TextStyle(color: color, fontSize: 10),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  alert.message,
                  style: const TextStyle(
                    color: AppColors.textGrey,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  DateFormat('MMM d, h:mm:ss a').format(alert.createdAt),
                  style: const TextStyle(
                    color: AppColors.textGrey,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          if (!resolved)
            TextButton(
              onPressed: alert.acknowledged ? null : onAcknowledge,
              child: Text(alert.acknowledged ? 'Acknowledged' : 'Acknowledge'),
            ),
        ],
      ),
    );
  }
}
