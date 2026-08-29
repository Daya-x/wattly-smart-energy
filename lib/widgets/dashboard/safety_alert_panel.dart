import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../providers/dashboard_provider.dart';

class SafetyAlertPanel extends StatelessWidget {
  const SafetyAlertPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final sensor = context.watch<DashboardProvider>().sensor;
    final gasNormal = sensor.gas < 1000;
    final temperatureStable = sensor.dhtValid && sensor.temperature < 45;

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
          const Text(
            'Safety status',
            style: TextStyle(
              color: AppColors.white,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 20),
          _AlertItem(
            icon: gasNormal ? Icons.check_circle : Icons.warning_amber_rounded,
            title: gasNormal ? 'Gas level normal' : 'Gas level elevated',
            subtitle: 'MQ-2 raw reading: ${sensor.gas}',
            color: gasNormal ? AppColors.neonGreen : AppColors.warningRed,
          ),
          _AlertItem(
            icon: temperatureStable
                ? Icons.thermostat
                : Icons.device_thermostat_rounded,
            title: !sensor.dhtValid
                ? 'Temperature sensor unavailable'
                : temperatureStable
                ? 'Temperature stable'
                : 'High temperature warning',
            subtitle: sensor.dhtValid
                ? '${sensor.temperature.toStringAsFixed(1)}°C measured'
                : 'Check the DHT22 power and DATA connection',
            color: temperatureStable
                ? AppColors.warningOrange
                : AppColors.warningRed,
          ),
          _AlertItem(
            icon: Icons.electric_bolt,
            title: sensor.relay ? 'Relay output active' : 'Relay output off',
            subtitle: sensor.relay
                ? 'Hardware relay is currently ON'
                : 'Automatic load control is disabled for safety',
            color: sensor.relay ? AppColors.neonGreen : AppColors.warningRed,
          ),
        ],
      ),
    );
  }
}

class _AlertItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;

  const _AlertItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Row(
        children: [
          Icon(icon, color: color, size: 26),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: AppColors.white)),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: AppColors.textGrey,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
