import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../providers/dashboard_provider.dart';
import '../../widgets/common/sidebar.dart';
import '../../widgets/dashboard/ai_prediction_card.dart';
import '../../widgets/dashboard/balance_card.dart';
import '../../widgets/dashboard/dashboard_header.dart';
import '../../widgets/dashboard/energy_chart.dart';
import '../../widgets/dashboard/recent_activity_table.dart';
import '../../widgets/dashboard/relay_card.dart';
import '../../widgets/dashboard/safety_alert_panel.dart';
import '../../widgets/dashboard/sensor_card.dart';

class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<DashboardProvider>();
    final sensor = provider.sensor;
    return LayoutBuilder(
      builder: (context, screen) {
        final isMobile = screen.maxWidth < 1000;

        return Scaffold(
          backgroundColor: AppColors.darkNavy,
          drawer: isMobile ? const Drawer(child: Sidebar()) : null,
          body: Row(
            children: [
              if (!isMobile) const Sidebar(),

              Expanded(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    isMobile ? 16 : 30,
                    isMobile ? 16 : 28,
                    isMobile ? 16 : 30,
                    24,
                  ),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final width = constraints.maxWidth;

                      return SingleChildScrollView(
                        child: Column(
                          children: [
                            if (isMobile)
                              Builder(
                                builder: (context) {
                                  return Row(
                                    children: [
                                      IconButton(
                                        icon: const Icon(
                                          Icons.menu,
                                          color: AppColors.white,
                                        ),
                                        onPressed: () {
                                          Scaffold.of(context).openDrawer();
                                        },
                                      ),
                                      const SizedBox(width: 8),
                                      const Text(
                                        'WATTLY',
                                        style: TextStyle(
                                          color: AppColors.neonGreen,
                                          fontSize: 20,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  );
                                },
                              ),

                            if (isMobile) const SizedBox(height: 16),

                            const DashboardHeader(),

                            const SizedBox(height: 28),

                            Row(
                              children: [
                                const Text(
                                  'Live readings',
                                  style: TextStyle(
                                    color: AppColors.white,
                                    fontSize: 17,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const Spacer(),
                                Icon(
                                  Icons.sync_rounded,
                                  color:
                                      provider.deviceStatus ==
                                          DeviceStatus.online
                                      ? AppColors.neonGreen
                                      : AppColors.warningOrange,
                                  size: 15,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  provider.deviceUpdatedAt == null
                                      ? 'Waiting for simulator'
                                      : 'Updated ${_timeAgo(provider.deviceUpdatedAt!)}',
                                  style: const TextStyle(
                                    color: AppColors.textGrey,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 14),

                            Wrap(
                              spacing: 18,
                              runSpacing: 18,
                              children: [
                                _card(
                                  width,
                                  SensorCard(
                                    title: 'Voltage',
                                    value: sensor.pzemValid
                                        ? '${sensor.voltage.toStringAsFixed(0)} V'
                                        : 'Unavailable',
                                    icon: Icons.bolt,
                                    iconColor: AppColors.neonGreen,
                                  ),
                                ),
                                _card(
                                  width,
                                  SensorCard(
                                    title: 'Current',
                                    value: sensor.pzemValid
                                        ? '${sensor.current.toStringAsFixed(2)} A'
                                        : 'Unavailable',
                                    icon: Icons.electrical_services,
                                    iconColor: AppColors.neonGreen,
                                  ),
                                ),
                                _card(
                                  width,
                                  SensorCard(
                                    title: 'Power',
                                    value: sensor.pzemValid
                                        ? '${sensor.power.toStringAsFixed(0)} W'
                                        : 'Unavailable',
                                    icon: Icons.power,
                                    iconColor: AppColors.neonGreen,
                                  ),
                                ),
                                _card(
                                  width,
                                  SensorCard(
                                    title: 'This month',
                                    value:
                                        '${sensor.energy.toStringAsFixed(1)} units (kWh)',
                                    icon: Icons.speed,
                                    iconColor: AppColors.neonGreen,
                                  ),
                                ),
                                _card(
                                  width,
                                  SensorCard(
                                    title: 'Today usage',
                                    value:
                                        '${provider.todayUsageKwh.toStringAsFixed(2)} units',
                                    icon: Icons.today_outlined,
                                    iconColor: AppColors.cyan,
                                  ),
                                ),
                                _card(
                                  width,
                                  SensorCard(
                                    title: 'Temperature',
                                    value: sensor.dhtValid
                                        ? '${sensor.temperature.toStringAsFixed(1)}°C'
                                        : 'Unavailable',
                                    icon: Icons.thermostat,
                                    iconColor: AppColors.warningOrange,
                                  ),
                                ),
                                _card(
                                  width,
                                  SensorCard(
                                    title: 'Humidity',
                                    value: sensor.dhtValid
                                        ? '${sensor.humidity.toStringAsFixed(0)}%'
                                        : 'Unavailable',
                                    icon: Icons.water_drop,
                                    iconColor: AppColors.warningOrange,
                                  ),
                                ),
                                _card(
                                  width,
                                  SensorCard(
                                    title: 'Gas Value',
                                    value: '${sensor.gas}',
                                    icon: Icons.local_fire_department,
                                    iconColor: AppColors.warningRed,
                                  ),
                                ),
                                _card(
                                  width,
                                  SensorCard(
                                    title: 'Motion',
                                    value: sensor.motion ? 'Detected' : 'Clear',
                                    icon: Icons.directions_walk,
                                    iconColor: AppColors.neonGreen,
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 24),

                            _section(
                              isMobile: isMobile,
                              children: const [BalanceCard(), RelayCard()],
                            ),

                            const SizedBox(height: 24),

                            _section(
                              isMobile: isMobile,
                              flexes: const [2, 1],
                              children: const [
                                EnergyChart(),
                                AIPredictionCard(),
                              ],
                            ),

                            const SizedBox(height: 24),

                            _section(
                              isMobile: isMobile,
                              children: const [
                                RecentActivityTable(),
                                SafetyAlertPanel(),
                              ],
                            ),

                            const SizedBox(height: 30),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _timeAgo(DateTime timestamp) {
    final seconds = DateTime.now().difference(timestamp).inSeconds;
    if (seconds < 3) return 'just now';
    if (seconds < 60) return '$seconds seconds ago';
    return '${seconds ~/ 60} minutes ago';
  }

  Widget _card(double width, Widget child) {
    double cardWidth;

    if (width >= 1100) {
      cardWidth = (width - 54) / 4;
    } else if (width >= 650) {
      cardWidth = (width - 18) / 2;
    } else {
      cardWidth = width;
    }

    return SizedBox(width: cardWidth, height: 142, child: child);
  }

  Widget _section({
    required bool isMobile,
    required List<Widget> children,
    List<int>? flexes,
  }) {
    if (isMobile) {
      return Column(
        children: [
          for (int i = 0; i < children.length; i++) ...[
            children[i],
            if (i != children.length - 1) const SizedBox(height: 18),
          ],
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (int i = 0; i < children.length; i++) ...[
          Expanded(flex: flexes == null ? 1 : flexes[i], child: children[i]),
          if (i != children.length - 1) const SizedBox(width: 18),
        ],
      ],
    );
  }
}
