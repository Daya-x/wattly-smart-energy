import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../providers/dashboard_provider.dart';

class RelayCard extends StatelessWidget {
  const RelayCard({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<DashboardProvider>();
    final enabled = provider.sensor.relay;
    final busy = provider.relayCommandInProgress;
    final hasCredit = provider.sensor.balance > 0;
    return Container(
      constraints: const BoxConstraints(minHeight: 170),
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
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Power supply",
                    style: TextStyle(
                      color: AppColors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    "Hardware relay status",
                    style: TextStyle(color: AppColors.textGrey, fontSize: 12),
                  ),
                ],
              ),
              const Spacer(),
              Switch(
                value: enabled,
                onChanged: busy || (!hasCredit && !enabled)
                    ? null
                    : (value) async {
                        final messenger = ScaffoldMessenger.of(context);
                        try {
                          await context.read<DashboardProvider>().setRelay(
                            value,
                          );
                          messenger.showSnackBar(
                            SnackBar(
                              content: Text(
                                value
                                    ? 'Relay ON command sent'
                                    : 'Relay OFF command sent',
                              ),
                            ),
                          );
                        } catch (error) {
                          messenger.showSnackBar(
                            SnackBar(
                              content: Text(
                                'Relay command failed: $error',
                              ),
                            ),
                          );
                        }
                      },
                activeThumbColor: AppColors.darkNavy,
                activeTrackColor: AppColors.neonGreen,
              ),
            ],
          ),
          const SizedBox(height: 26),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              enabled ? "Relay output is on" : "Relay output is off",
              style: TextStyle(
                color: enabled ? AppColors.neonGreen : AppColors.warningRed,
                fontWeight: FontWeight.bold,
                fontSize: 30,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            busy
                ? "Sending command to ESP32..."
                : enabled
                ? "Hardware relay is energized by the ESP32"
                : !hasCredit
                ? "Recharge required before power can be turned on."
                : "Relay is off. Use switch or physical button to turn it on.",
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AppColors.white),
          ),
        ],
      ),
    );
  }
}
