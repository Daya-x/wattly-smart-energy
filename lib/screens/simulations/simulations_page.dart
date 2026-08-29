import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../providers/dashboard_provider.dart';
import '../../widgets/common/app_shell.dart';

class SimulationsPage extends StatelessWidget {
  const SimulationsPage({super.key});

  static const _scenarios = [
    ('gas', 'Gas warning', 'MQ-2 danger alert', Icons.local_fire_department),
    ('temperature', 'Overheating', 'High temperature alert', Icons.thermostat),
    ('power', 'Power overload', 'High-load critical alert', Icons.bolt),
    ('voltage', 'Voltage fault', 'Unsafe supply warning', Icons.electric_meter),
    ('sensor_pzem', 'PZEM failure', 'Energy sensor failure', Icons.power_off),
    (
      'sensor_dht',
      'DHT22 failure',
      'Environment sensor failure',
      Icons.device_thermostat,
    ),
    (
      'theft',
      'Possible intrusion',
      'Protected-hours motion alert',
      Icons.security,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<DashboardProvider>();
    final security = provider.theftSecurity;
    return AppShell(
      selectedIndex: 5,
      title: 'Simulations',
      subtitle:
          'Demonstrate alerts, notifications, the red LED, and buzzer safely.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SurfaceCard(
            child: LayoutBuilder(
              builder: (context, constraints) => Wrap(
                spacing: 22,
                runSpacing: 18,
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: constraints.maxWidth < 720
                        ? constraints.maxWidth
                        : 520,
                    child: const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.shield_outlined, color: AppColors.mint),
                            SizedBox(width: 10),
                            Text(
                              'Theft protection',
                              style: TextStyle(
                                color: AppColors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 10),
                        Text(
                          'Automatic protection is always active from 12:00 AM to 6:00 AM. Manual mode protects the home at any time.',
                          style: TextStyle(
                            color: AppColors.textGrey,
                            height: 1.45,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            security?.monitoringActive == true
                                ? 'Protection active'
                                : 'Automatic schedule ready',
                            style: TextStyle(
                              color: security?.monitoringActive == true
                                  ? AppColors.mint
                                  : AppColors.textGrey,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            security?.mode == 'automatic'
                                ? 'Automatic mode'
                                : security?.manualEnabled == true
                                ? 'Manual mode'
                                : '12 AM – 6 AM',
                            style: const TextStyle(
                              color: AppColors.textGrey,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(width: 12),
                      Switch(
                        value: security?.manualEnabled ?? false,
                        onChanged:
                            provider.theftSecurityStatus ==
                                ForecastStatus.loading
                            ? null
                            : (value) => _setTheft(context, value),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (provider.theftSecurityError != null) ...[
            const SizedBox(height: 10),
            Text(
              provider.theftSecurityError!,
              style: const TextStyle(color: AppColors.warningOrange),
            ),
          ],
          const SizedBox(height: 24),
          const Text(
            'Alert demonstrations',
            style: TextStyle(
              color: AppColors.white,
              fontSize: 21,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Each button creates a clearly labelled test alert and runs the meter buzzer/red LED for 8 seconds. It does not change sensor thresholds or switch the load.',
            style: TextStyle(color: AppColors.textGrey, height: 1.4),
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth < 620
                  ? constraints.maxWidth
                  : constraints.maxWidth < 1050
                  ? (constraints.maxWidth - 14) / 2
                  : (constraints.maxWidth - 28) / 3;
              return Wrap(
                spacing: 14,
                runSpacing: 14,
                children: [
                  for (final scenario in _scenarios)
                    SizedBox(
                      width: width,
                      child: _ScenarioCard(
                        title: scenario.$2,
                        description: scenario.$3,
                        icon: scenario.$4,
                        busy: provider.simulationScenario == scenario.$1,
                        disabled: provider.simulationInProgress,
                        onPressed: () => _simulate(context, scenario.$1),
                      ),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              AppButton(
                label: 'Clear simulations',
                icon: Icons.clear_all_rounded,
                primary: false,
                onPressed: provider.simulationInProgress
                    ? null
                    : () => _simulate(context, 'clear'),
              ),
              if (provider.simulationMessage != null) ...[
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    provider.simulationMessage!,
                    style: const TextStyle(color: AppColors.mint),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _simulate(BuildContext context, String scenario) async {
    try {
      await context.read<DashboardProvider>().runSimulation(scenario);
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    }
  }

  Future<void> _setTheft(BuildContext context, bool enabled) async {
    try {
      await context.read<DashboardProvider>().setManualTheftProtection(enabled);
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    }
  }
}

class _ScenarioCard extends StatelessWidget {
  final String title;
  final String description;
  final IconData icon;
  final bool busy;
  final bool disabled;
  final VoidCallback onPressed;

  const _ScenarioCard({
    required this.title,
    required this.description,
    required this.icon,
    required this.busy,
    required this.disabled,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) => SurfaceCard(
    child: Row(
      children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: AppColors.warningRed.withValues(alpha: .12),
            borderRadius: BorderRadius.circular(13),
          ),
          child: Icon(icon, color: AppColors.warningRed),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: AppColors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                description,
                style: const TextStyle(color: AppColors.textGrey, fontSize: 12),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        IconButton.filledTonal(
          tooltip: 'Run $title simulation',
          onPressed: disabled ? null : onPressed,
          icon: busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.play_arrow_rounded),
        ),
      ],
    ),
  );
}
