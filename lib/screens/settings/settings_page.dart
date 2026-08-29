import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/config/app_config.dart';
import '../../providers/dashboard_provider.dart';
import '../../services/ai/tensorflow_service.dart';
import '../../widgets/common/app_shell.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool lowBalance = true;
  bool safetyAlerts = true;
  bool weeklyReport = false;
  double lowBalanceAt = 500;
  double gasThreshold = 600;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<DashboardProvider>();
    final forecast = provider.energyForecast;
    return AppShell(
      selectedIndex: 6,
      title: 'Settings',
      subtitle: 'Configure your meter, alerts, and tariff preferences.',
      actions: [
        AppButton(
          label: 'Sign out',
          icon: Icons.logout_rounded,
          primary: false,
          onPressed: () => FirebaseAuth.instance.signOut(),
        ),
        AppButton(
          label: 'Save changes',
          icon: Icons.check_rounded,
          onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Settings saved locally')),
          ),
        ),
      ],
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 760;
          final preferences = SurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _Title('Notifications'),
                _Toggle(
                  'Push notifications',
                  provider.notificationsSupported
                      ? 'Receive browser alerts while Wattly is open'
                      : 'Browser notifications are unavailable here',
                  provider.notificationsEnabled,
                  provider.notificationsSupported
                      ? (value) => _setNotifications(context, value)
                      : (_) {},
                ),
                _Toggle(
                  'Low balance alerts',
                  'Notify when credit falls below your limit',
                  lowBalance,
                  (v) => setState(() => lowBalance = v),
                ),
                _Toggle(
                  'Safety alerts',
                  'Gas, heat, and unusual usage warnings',
                  safetyAlerts,
                  (v) => setState(() => safetyAlerts = v),
                ),
                _Toggle(
                  'Weekly report',
                  'A weekly summary of usage and savings',
                  weeklyReport,
                  (v) => setState(() => weeklyReport = v),
                ),
              ],
            ),
          );
          final thresholds = SurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _Title('Alert thresholds'),
                Text(
                  'Low balance: Rs. ${lowBalanceAt.toStringAsFixed(0)}',
                  style: const TextStyle(color: AppColors.white),
                ),
                Slider(
                  value: lowBalanceAt,
                  min: 100,
                  max: 2000,
                  divisions: 19,
                  onChanged: (v) => setState(() => lowBalanceAt = v),
                ),
                const SizedBox(height: 12),
                Text(
                  'Gas warning: ${gasThreshold.toStringAsFixed(0)} ppm',
                  style: const TextStyle(color: AppColors.white),
                ),
                Slider(
                  value: gasThreshold,
                  min: 300,
                  max: 1000,
                  divisions: 14,
                  onChanged: (v) => setState(() => gasThreshold = v),
                ),
              ],
            ),
          );
          return Column(
            children: [
              compact
                  ? Column(
                      children: [
                        preferences,
                        const SizedBox(height: 16),
                        thresholds,
                      ],
                    )
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: preferences),
                        const SizedBox(width: 16),
                        Expanded(child: thresholds),
                      ],
                    ),
              const SizedBox(height: 16),
              SurfaceCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _Title('Meter details'),
                    const _Detail('Device name', 'Device Meter'),
                    const _Detail('Meter ID', 'EM-2048'),
                    _Detail(
                      'Tariff',
                      forecast == null
                          ? 'Loading approved tariff…'
                          : 'Sri Lanka domestic block • ${forecast.tariffEffectiveFrom}',
                    ),
                    _Detail(
                      'Tariff version',
                      forecast?.tariffId ?? 'Unavailable',
                    ),
                    _Detail(
                      'Firmware',
                      provider.deviceStatus == DeviceStatus.online
                          ? 'ESP32 connected'
                          : 'Waiting for ESP32',
                    ),
                    const SizedBox(height: 12),
                    AppButton(
                      label: 'Edit tariff',
                      icon: Icons.edit_outlined,
                      primary: false,
                      onPressed: () => showDialog<void>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('Tariff settings'),
                          content: Text(
                            forecast == null
                                ? 'The approved tariff configuration is unavailable while the API is offline.'
                                : 'Active: ${forecast.tariffId}\nEffective: ${forecast.tariffEffectiveFrom}\n\nFuture PUCSL changes will be imported as drafts and require administrator approval before activation.',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text('Close'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              SurfaceCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _Title('Tariff approval'),
                    Text(
                      AppConfig.tariffAdminKey.isEmpty
                          ? 'Read-only mode. Drafts can be reviewed here, but verification and activation require a runtime administrator key.'
                          : 'Administrator mode. Only verified PUCSL drafts can be activated.',
                      style: const TextStyle(color: AppColors.textGrey),
                    ),
                    const SizedBox(height: 14),
                    if (provider.tariffStatus == ForecastStatus.loading)
                      const LinearProgressIndicator()
                    else if (provider.tariffError != null)
                      Text(
                        'Tariff registry check is unavailable now. Billing still uses the approved local tariff.',
                        style: const TextStyle(color: AppColors.warningOrange),
                      )
                    else if (provider.tariffVersions.isEmpty)
                      const Text(
                        'No tariff versions found.',
                        style: TextStyle(color: AppColors.textGrey),
                      )
                    else
                      ...provider.tariffVersions.map(
                        (tariff) => _TariffRow(
                          tariff: tariff,
                          canAdminister: AppConfig.tariffAdminKey.isNotEmpty,
                          onVerify: () => _runTariffAction(
                            context,
                            () => context
                                .read<DashboardProvider>()
                                .verifyTariff(tariff.id),
                          ),
                          onActivate: () => _runTariffAction(
                            context,
                            () => context
                                .read<DashboardProvider>()
                                .activateTariff(tariff.id),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              SurfaceCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _Title('PUCSL tariff monitor'),
                    Text(
                      provider.tariffMonitor?.enabled == false
                          ? 'Automatic monitoring is disabled.'
                          : 'Checks the official PUCSL End User Tariff Decisions page every ${provider.tariffMonitor?.intervalHours.toStringAsFixed(0) ?? '24'} hours. Detection never changes billing.',
                      style: const TextStyle(color: AppColors.textGrey),
                    ),
                    const SizedBox(height: 12),
                    _Detail(
                      'Last checked',
                      provider.tariffMonitor?.lastCheckedAt ??
                          'Not checked yet',
                    ),
                    if (provider.tariffMonitorError != null)
                      const Text(
                        'PUCSL website check timed out. Approved billing tariff is still active.',
                        style: TextStyle(color: AppColors.warningOrange),
                      ),
                    if (provider.tariffMonitor?.lastError != null)
                      const Text(
                        'Last PUCSL check could not complete. Try again later when the internet connection is stable.',
                        style: TextStyle(color: AppColors.warningOrange),
                      ),
                    const SizedBox(height: 10),
                    AppButton(
                      label:
                          provider.tariffMonitorStatus == ForecastStatus.loading
                          ? 'Checking…'
                          : 'Check PUCSL now',
                      icon: Icons.sync_rounded,
                      primary: false,
                      onPressed:
                          AppConfig.tariffAdminKey.isEmpty ||
                              provider.tariffMonitorStatus ==
                                  ForecastStatus.loading
                          ? null
                          : () => _runTariffAction(
                              context,
                              () => context
                                  .read<DashboardProvider>()
                                  .checkTariffMonitor(),
                            ),
                    ),
                    const SizedBox(height: 14),
                    if (provider.tariffMonitor?.candidates
                            .where(
                              (candidate) => candidate.status == 'detected',
                            )
                            .isEmpty ??
                        true)
                      Text(
                        provider.tariffMonitor?.lastCheckedAt == null
                            ? 'No publications recorded yet.'
                            : 'No new tariff publication detected.',
                        style: const TextStyle(color: AppColors.textGrey),
                      )
                    else
                      ...provider.tariffMonitor!.candidates
                          .where((candidate) => candidate.status == 'detected')
                          .map(
                            (candidate) => Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.new_releases_outlined,
                                    color: AppColors.warningOrange,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          candidate.title,
                                          style: const TextStyle(
                                            color: AppColors.white,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        Text(
                                          'New official publication—rates require administrator review',
                                          style: const TextStyle(
                                            color: AppColors.textGrey,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _runTariffAction(
    BuildContext context,
    Future<void> Function() action,
  ) async {
    try {
      await action();
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Tariff action completed')));
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _setNotifications(BuildContext context, bool enabled) async {
    final granted = await context
        .read<DashboardProvider>()
        .enableBrowserNotifications(enabled);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          enabled && !granted
              ? 'Notification permission was not granted'
              : enabled
              ? 'Browser safety notifications enabled'
              : 'Browser safety notifications disabled',
        ),
      ),
    );
  }
}

class _TariffRow extends StatelessWidget {
  final TariffVersion tariff;
  final bool canAdminister;
  final VoidCallback onVerify;
  final VoidCallback onActivate;

  const _TariffRow({
    required this.tariff,
    required this.canAdminister,
    required this.onVerify,
    required this.onActivate,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Wrap(
      spacing: 12,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: 360,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tariff.id,
                style: const TextStyle(
                  color: AppColors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                '${tariff.status.toUpperCase()} • effective ${tariff.effectiveFrom} • ${tariff.validationCaseCount} test bills',
                style: const TextStyle(color: AppColors.textGrey, fontSize: 12),
              ),
            ],
          ),
        ),
        if (tariff.status == 'draft')
          AppButton(
            label: 'Verify',
            icon: Icons.fact_check_outlined,
            primary: false,
            onPressed: canAdminister ? onVerify : null,
          ),
        if (tariff.status == 'verified')
          AppButton(
            label: 'Activate',
            icon: Icons.check_circle_outline,
            onPressed: canAdminister ? onActivate : null,
          ),
      ],
    ),
  );
}

class _Title extends StatelessWidget {
  final String text;
  const _Title(this.text);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Text(
      text,
      style: const TextStyle(
        color: AppColors.white,
        fontSize: 18,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

class _Toggle extends StatelessWidget {
  final String title, subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  const _Toggle(this.title, this.subtitle, this.value, this.onChanged);
  @override
  Widget build(BuildContext context) => SwitchListTile(
    contentPadding: EdgeInsets.zero,
    title: Text(title, style: const TextStyle(color: AppColors.white)),
    subtitle: Text(
      subtitle,
      style: const TextStyle(color: AppColors.textGrey, fontSize: 12),
    ),
    value: value,
    activeThumbColor: AppColors.darkNavy,
    activeTrackColor: AppColors.neonGreen,
    onChanged: onChanged,
  );
}

class _Detail extends StatelessWidget {
  final String label, value;
  const _Detail(this.label, this.value);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Row(
      children: [
        Expanded(
          child: Text(label, style: const TextStyle(color: AppColors.textGrey)),
        ),
        Text(value, style: const TextStyle(color: AppColors.white)),
      ],
    ),
  );
}
