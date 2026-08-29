import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../providers/dashboard_provider.dart';
import '../../services/ai/tensorflow_service.dart';
import '../../widgets/common/app_shell.dart';

class AIPage extends StatefulWidget {
  const AIPage({super.key});

  @override
  State<AIPage> createState() => _AIPageState();
}

class _AIPageState extends State<AIPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<DashboardProvider>().loadModelReport();
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<DashboardProvider>();
    final forecast = provider.energyForecast;
    final loading = provider.forecastStatus == ForecastStatus.loading;
    final offline = provider.forecastStatus == ForecastStatus.offline;
    final anomalyLoading = provider.anomalyStatus == ForecastStatus.loading;
    final applianceLoading = provider.applianceStatus == ForecastStatus.loading;
    final safetyLoading = provider.safetyStatus == ForecastStatus.loading;
    final recommendationCards = provider.recommendations.isEmpty
        ? const [
            _Insight(
              Icons.hourglass_top_rounded,
              'Building recommendations',
              'Waiting for the unified AI overview…',
              'Loading',
            ),
          ]
        : provider.recommendations
              .map(
                (item) => _Insight(
                  _recommendationIcon(item.type),
                  item.title,
                  item.message,
                  item.potentialSavingPercent > 0
                      ? '${item.impact} • Up to ${item.potentialSavingPercent}% potential saving'
                      : item.impact,
                  accent: _recommendationColor(item.severity),
                ),
              )
              .toList();
    return AppShell(
      selectedIndex: 1,
      title: 'AI insights',
      subtitle: 'Forecasts and practical ways to reduce your usage.',
      actions: [
        AppButton(
          label: 'Refresh forecast',
          icon: Icons.refresh_rounded,
          primary: false,
          onPressed:
              loading || anomalyLoading || applianceLoading || safetyLoading
              ? null
              : () {
                  provider.loadAIOverview();
                  provider.loadModelReport();
                },
        ),
      ],
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 760;
          return Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(26),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF172A22), Color(0xFF102019)],
                  ),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(
                          Icons.auto_awesome_rounded,
                          color: AppColors.neonGreen,
                        ),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'AI forecast sample',
                            style: TextStyle(
                              color: AppColors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Text(
                      forecast == null
                          ? (loading ? 'Loading…' : 'Unavailable')
                          : '${forecast.predictionKwh.toStringAsFixed(2)} units (kWh)',
                      style: TextStyle(
                        color: AppColors.neonGreen,
                        fontSize: forecast == null ? 30 : 42,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -1.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      offline
                          ? 'Local AI API offline • Start the Python server'
                          : forecast == null
                          ? 'Connecting to the trained model'
                          : 'Estimated Rs. ${forecast.estimatedCostLkr.toStringAsFixed(0)} • Public-dataset prototype • Sri Lanka blocks effective ${forecast.tariffEffectiveFrom}',
                      style: TextStyle(
                        color: offline
                            ? AppColors.warningOrange
                            : AppColors.textGrey,
                      ),
                    ),
                    const SizedBox(height: 20),
                    if (loading)
                      const LinearProgressIndicator(color: AppColors.neonGreen)
                    else
                      Row(
                        children: [
                          Icon(
                            offline
                                ? Icons.cloud_off_outlined
                                : Icons.science_outlined,
                            color: offline
                                ? AppColors.warningOrange
                                : AppColors.neonGreen,
                            size: 17,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              forecast == null
                                  ? 'No live prediction available'
                                  : 'Not yet personalized. Accuracy improves after collecting more household meter history.',
                              style: const TextStyle(
                                color: AppColors.textGrey,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              const Row(
                children: [
                  Icon(
                    Icons.tips_and_updates_outlined,
                    color: AppColors.neonGreen,
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'AI recommendations',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (compact)
                Column(
                  children: [
                    for (
                      int index = 0;
                      index < recommendationCards.length;
                      index++
                    ) ...[
                      recommendationCards[index],
                      if (index != recommendationCards.length - 1)
                        const SizedBox(height: 12),
                    ],
                  ],
                )
              else
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (
                      int index = 0;
                      index < recommendationCards.length;
                      index++
                    ) ...[
                      Expanded(child: recommendationCards[index]),
                      if (index != recommendationCards.length - 1)
                        const SizedBox(width: 12),
                    ],
                  ],
                ),
              const SizedBox(height: 18),
              const _MonthlyBillPredictionCard(),
              const SizedBox(height: 18),
              const _AbnormalUsageCard(),
              const SizedBox(height: 18),
              compact
                  ? const Column(
                      children: [
                        _SafetyRisk(),
                        SizedBox(height: 18),
                        _LiveApplianceDetection(),
                      ],
                    )
                  : const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: _SafetyRisk()),
                        SizedBox(width: 18),
                        Expanded(child: _LiveApplianceDetection()),
                      ],
                    ),
              const SizedBox(height: 18),
              const _AIEventHistory(),
              const SizedBox(height: 18),
              const _ModelPerformanceReport(),
              const SizedBox(height: 18),
              const SurfaceCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'How this prediction works',
                      style: TextStyle(
                        color: AppColors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(height: 10),
                    Text(
                      'The overview combines trained prototype models with transparent rules. Balance days and monthly bills use Sri Lankan tariff blocks; recommendations prioritize safety, low credit, bill risk, anomalies, and high-power appliance samples.',
                      style: TextStyle(color: AppColors.textGrey, height: 1.5),
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

  IconData _recommendationIcon(String type) => switch (type) {
    'safety' => Icons.health_and_safety_outlined,
    'anomaly' => Icons.warning_amber_rounded,
    'balance' => Icons.account_balance_wallet_outlined,
    'bill' => Icons.receipt_long_outlined,
    'appliance' => Icons.schedule_rounded,
    _ => Icons.verified_outlined,
  };

  Color _recommendationColor(String severity) => switch (severity) {
    'high' => AppColors.warningRed,
    'warning' => AppColors.warningOrange,
    'info' => AppColors.cyan,
    _ => AppColors.mint,
  };
}

class _SafetyRisk extends StatelessWidget {
  const _SafetyRisk();

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<DashboardProvider>();
    final safety = provider.safetyPrediction;
    final loading = provider.safetyStatus == ForecastStatus.loading;
    final offline = provider.safetyStatus == ForecastStatus.offline;
    final riskColor = safety?.riskLevel == 'high'
        ? AppColors.warningRed
        : safety?.riskLevel == 'moderate'
        ? AppColors.warningOrange
        : AppColors.mint;
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.health_and_safety_outlined, color: riskColor),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Smart safety prediction',
                  style: TextStyle(
                    color: AppColors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (loading)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                _Badge(
                  offline
                      ? 'OFFLINE'
                      : '${(safety?.riskLevel ?? 'waiting').toUpperCase()} RISK',
                  offline ? AppColors.warningOrange : riskColor,
                ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            safety == null
                ? '—'
                : '${(safety.overallRiskProbability * 100).toStringAsFixed(1)}%',
            style: TextStyle(
              color: riskColor,
              fontSize: 34,
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(
            offline
                ? 'Safety API is offline'
                : 'Current live ESP32 threshold risk',
            style: const TextStyle(color: AppColors.textGrey, fontSize: 12),
          ),
          const SizedBox(height: 18),
          _RiskRow(
            'Gas hazard signal',
            safety?.gasRiskProbability ?? 0,
            AppColors.warningRed,
          ),
          const SizedBox(height: 12),
          _RiskRow(
            'Electrical fault signal',
            safety?.electricalFaultProbability ?? 0,
            AppColors.warningOrange,
          ),
          const SizedBox(height: 12),
          _RiskRow(
            'Overheating signal',
            safety?.temperatureRiskProbability ?? 0,
            AppColors.warningOrange,
          ),
          const SizedBox(height: 16),
          Text(
            safety == null
                ? 'Waiting for live meter readings…'
                : 'Live transparent safety rules • Electrical condition: ${safety.electricalCondition}. MQ-2 uses a calibrated raw threshold, not gas ppm.',
            style: const TextStyle(
              color: AppColors.textGrey,
              fontSize: 12,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}

class _MonthlyBillPredictionCard extends StatelessWidget {
  const _MonthlyBillPredictionCard();

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<DashboardProvider>();
    final prediction = provider.monthlyBillPrediction;
    final loading = provider.forecastStatus == ForecastStatus.loading;
    final offline = provider.forecastStatus == ForecastStatus.offline;
    final displayStatus =
        prediction != null &&
            prediction.projectedBillLkr < 1500 &&
            prediction.projectedMonthUnits < 30
        ? 'normal'
        : prediction?.status;
    final statusColor = switch (displayStatus) {
      'high' => AppColors.warningRed,
      'watch' => AppColors.warningOrange,
      'normal' => AppColors.mint,
      _ => AppColors.textGrey,
    };

    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.receipt_long_outlined, color: statusColor),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'End-of-month bill prediction',
                  style: TextStyle(
                    color: AppColors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (loading)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                _Badge(
                  offline
                      ? 'OFFLINE'
                      : (displayStatus ?? 'waiting').toUpperCase(),
                  offline ? AppColors.warningOrange : statusColor,
                ),
            ],
          ),
          const SizedBox(height: 18),
          if (prediction == null)
            Text(
              offline
                  ? 'Monthly prediction is unavailable while the AI API is offline.'
                  : 'Waiting for AI overview…',
              style: TextStyle(
                color: offline ? AppColors.warningOrange : AppColors.textGrey,
              ),
            )
          else ...[
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _BillMetric(
                  'Projected units',
                  '${prediction.projectedMonthUnits.toStringAsFixed(1)} units',
                ),
                _BillMetric(
                  'Projected bill',
                  'Rs. ${prediction.projectedBillLkr.toStringAsFixed(0)}',
                ),
                _BillMetric(
                  'Current month',
                  '${prediction.currentMonthUnits.toStringAsFixed(2)} units',
                ),
                _BillMetric(
                  'Daily average',
                  '${prediction.averageDailyUnits.toStringAsFixed(2)} units',
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              '${prediction.remainingBillingDays} billing days remaining • '
              'Forecast sample ${prediction.nextDayForecastUnits.toStringAsFixed(2)} units • '
              'Sri Lanka tariff blocks applied.',
              style: const TextStyle(
                color: AppColors.textGrey,
                fontSize: 12,
                height: 1.45,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _BillMetric extends StatelessWidget {
  final String label;
  final String value;

  const _BillMetric(this.label, this.value);

  @override
  Widget build(BuildContext context) => Container(
    width: 170,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: AppColors.lightCard.withValues(alpha: .42),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: AppColors.border),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: AppColors.textGrey, fontSize: 11),
        ),
        const SizedBox(height: 8),
        Text(
          value,
          style: const TextStyle(
            color: AppColors.white,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );
}

class _AbnormalUsageCard extends StatelessWidget {
  const _AbnormalUsageCard();

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<DashboardProvider>();
    final anomaly = provider.anomalyDetection;
    final loading = provider.anomalyStatus == ForecastStatus.loading;
    final offline = provider.anomalyStatus == ForecastStatus.offline;
    final color = _levelColor(anomaly?.level);
    final probability = anomaly == null ? 0.0 : anomaly.abnormalProbability;

    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                anomaly?.isAbnormal == true
                    ? Icons.warning_amber_rounded
                    : Icons.verified_outlined,
                color: color,
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Abnormal usage detection',
                  style: TextStyle(
                    color: AppColors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (loading)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                _Badge(
                  offline
                      ? 'OFFLINE'
                      : (anomaly?.label ?? 'Waiting').toUpperCase(),
                  offline ? AppColors.warningOrange : color,
                ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            anomaly == null
                ? '—'
                : '${(probability * 100).toStringAsFixed(1)}%',
            style: TextStyle(
              color: color,
              fontSize: 34,
              fontWeight: FontWeight.w800,
            ),
          ),
          const Text(
            'Abnormal usage probability',
            style: TextStyle(color: AppColors.textGrey, fontSize: 12),
          ),
          const SizedBox(height: 14),
          LinearProgressIndicator(
            value: probability.clamp(0, 1),
            color: color,
            backgroundColor: AppColors.lightCard,
            minHeight: 6,
            borderRadius: BorderRadius.circular(10),
          ),
          const SizedBox(height: 14),
          Text(
            offline
                ? 'Anomaly API is offline. Start the Python server and refresh.'
                : anomaly?.levelExplanation ??
                      'Waiting for the anomaly detection model…',
            style: TextStyle(
              color: offline ? AppColors.warningOrange : AppColors.textGrey,
              fontSize: 12,
              height: 1.45,
            ),
          ),
          if (anomaly != null) ...[
            const SizedBox(height: 10),
            Text(
              'Model ${anomaly.modelName} • Test F1 ${(anomaly.testF1 * 100).toStringAsFixed(1)}%',
              style: const TextStyle(color: AppColors.textGrey, fontSize: 11),
            ),
          ],
        ],
      ),
    );
  }

  Color _levelColor(String? level) => switch (level) {
    'abnormal' => AppColors.warningRed,
    'watch' => AppColors.warningOrange,
    'normal' => AppColors.mint,
    _ => AppColors.textGrey,
  };
}

class _RiskRow extends StatelessWidget {
  final String label;
  final double value;
  final Color color;
  const _RiskRow(this.label, this.value, this.color);

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(color: AppColors.white, fontSize: 12),
            ),
          ),
          Text(
            '${(value * 100).round()}%',
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
      const SizedBox(height: 7),
      LinearProgressIndicator(
        value: value,
        color: color,
        backgroundColor: AppColors.lightCard,
        minHeight: 6,
        borderRadius: BorderRadius.circular(10),
      ),
    ],
  );
}

class _LiveApplianceDetection extends StatelessWidget {
  const _LiveApplianceDetection();

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<DashboardProvider>();
    final result = provider.applianceDetection;
    final loading = provider.applianceStatus == ForecastStatus.loading;
    final offline = provider.applianceStatus == ForecastStatus.offline;
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.home_outlined, color: AppColors.neonGreen),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Appliance detection',
                  style: TextStyle(
                    color: AppColors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (loading)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                _Badge(
                  offline
                      ? 'OFFLINE'
                      : '${result?.detections.length ?? 0} SAMPLES',
                  offline ? AppColors.warningOrange : AppColors.neonGreen,
                ),
            ],
          ),
          const SizedBox(height: 16),
          if (offline)
            const Text(
              'Appliance API is offline. Start the Python server and refresh.',
              style: TextStyle(color: AppColors.warningOrange, fontSize: 12),
            )
          else if (result == null)
            const Text(
              'Loading known-device signature samples…',
              style: TextStyle(color: AppColors.textGrey, fontSize: 12),
            )
          else
            for (final detection in result.detections)
              _Appliance(
                _iconFor(detection.category),
                _labelFor(detection.category),
                '${detection.meanPowerW.toStringAsFixed(1)} W average • ${detection.windowEnergyWh.toStringAsFixed(2)} Wh',
                _confidenceLabel(detection.confidence),
                _colorFor(detection.category),
              ),
          const Divider(color: AppColors.border, height: 28),
          Text(
            result == null
                ? 'Known-device smart-plug prototype.'
                : 'Prototype classifier: known-device accuracy ${(result.knownDeviceAccuracy * 100).toStringAsFixed(1)}% • unseen-device macro-F1 ${(result.unseenDeviceMacroF1 * 100).toStringAsFixed(1)}%. Confidence means sample similarity, not guaranteed appliance identity.',
            style: const TextStyle(
              color: AppColors.textGrey,
              fontSize: 12,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }

  IconData _iconFor(String category) => switch (category) {
    'cooling' => Icons.ac_unit_rounded,
    'kitchen' => Icons.kitchen_outlined,
    'multimedia' => Icons.tv_rounded,
    'washing' => Icons.local_laundry_service_outlined,
    _ => Icons.power_outlined,
  };

  String _labelFor(String category) => switch (category) {
    'cooling' => 'Cooling appliance',
    'kitchen' => 'Kitchen appliance',
    'multimedia' => 'Multimedia appliance',
    'washing' => 'Washing appliance',
    _ => 'Other appliance',
  };

  Color _colorFor(String category) => switch (category) {
    'cooling' => AppColors.cyan,
    'kitchen' => AppColors.mint,
    'multimedia' => AppColors.warningOrange,
    'washing' => AppColors.neonGreen,
    _ => AppColors.textGrey,
  };

  String _confidenceLabel(double confidence) {
    if (confidence >= 0.9) return 'Strong sample match';
    if (confidence >= 0.65) return 'Likely match';
    return 'Low confidence';
  }
}

class _Appliance extends StatelessWidget {
  final IconData icon;
  final String name, detail, matchLabel;
  final Color color;
  const _Appliance(
    this.icon,
    this.name,
    this.detail,
    this.matchLabel,
    this.color,
  );

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 9),
    child: Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: color.withValues(alpha: .10),
            borderRadius: BorderRadius.circular(11),
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                style: const TextStyle(
                  color: AppColors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                detail,
                style: const TextStyle(color: AppColors.textGrey, fontSize: 11),
              ),
            ],
          ),
        ),
        Text(
          matchLabel,
          style: TextStyle(
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );
}

class _AIEventHistory extends StatelessWidget {
  const _AIEventHistory();

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<DashboardProvider>();
    final anomaly = provider.anomalyDetection;
    final safety = provider.safetyPrediction;
    final appliances = provider.applianceDetection?.detections ?? [];
    final firstAppliance = appliances.isEmpty ? null : appliances.first;
    final anomalyPercent = anomaly == null
        ? 0.0
        : anomaly.abnormalProbability * 100;
    final anomalyColor = anomaly?.level == 'abnormal'
        ? AppColors.warningRed
        : anomaly?.level == 'watch'
        ? AppColors.warningOrange
        : AppColors.mint;
    final safetyColor = safety?.riskLevel == 'high'
        ? AppColors.warningRed
        : safety?.riskLevel == 'moderate'
        ? AppColors.warningOrange
        : AppColors.mint;
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'AI detection history',
            style: TextStyle(
              color: AppColors.white,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          if (firstAppliance != null)
            _Event(
              Icons.power_outlined,
              'Appliance sample classified',
              '${_applianceLabel(firstAppliance.category)} pattern • ${firstAppliance.meanPowerW.toStringAsFixed(1)} W average',
              'Now',
              AppColors.cyan,
            ),
          if (anomaly != null)
            _Event(
              anomaly.level == 'abnormal'
                  ? Icons.warning_amber_rounded
                  : Icons.verified_outlined,
              'Usage pattern: ${anomaly.label}',
              '${anomalyPercent.toStringAsFixed(1)}% abnormal probability • ${anomaly.modelName}',
              'Now',
              anomalyColor,
            ),
          if (safety != null)
            _Event(
              Icons.health_and_safety_outlined,
              'Safety risk checked',
              '${safety.riskLevel.toUpperCase()} risk • Gas ${(safety.gasRiskProbability * 100).round()}% • Overheat ${(safety.temperatureRiskProbability * 100).round()}%',
              'Now',
              safetyColor,
            ),
          if (firstAppliance == null && anomaly == null && safety == null)
            const Text(
              'Waiting for live model results…',
              style: TextStyle(color: AppColors.textGrey),
            ),
        ],
      ),
    );
  }

  String _applianceLabel(String category) => switch (category) {
    'cooling' => 'Cooling appliance',
    'kitchen' => 'Kitchen appliance',
    'multimedia' => 'Multimedia appliance',
    'washing' => 'Washing appliance',
    _ => 'Other appliance',
  };
}

class _ModelPerformanceReport extends StatelessWidget {
  const _ModelPerformanceReport();

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<DashboardProvider>();
    final report = provider.modelReport;
    final loading = provider.modelReportStatus == ForecastStatus.loading;
    final offline = provider.modelReportStatus == ForecastStatus.offline;

    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                offline ? Icons.cloud_off_outlined : Icons.analytics_outlined,
                color: offline ? AppColors.warningOrange : AppColors.neonGreen,
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'AI system status',
                  style: TextStyle(
                    color: AppColors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (loading)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                _Badge(
                  report == null ? 'OFFLINE' : '${report.items.length} MODELS',
                  report == null
                      ? AppColors.warningOrange
                      : AppColors.neonGreen,
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            report == null
                ? provider.modelReportError ??
                      'Loading training metrics from backend…'
                : 'These checks help estimate usage, safety risk, abnormal behaviour, and appliance patterns. The system is a prototype and improves as more meter data is collected.',
            style: TextStyle(
              color: offline ? AppColors.warningOrange : AppColors.textGrey,
              fontSize: 12,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 16),
          if (report != null)
            for (final item in report.items) _ModelReportRow(item),
        ],
      ),
    );
  }
}

class _ModelReportRow extends StatelessWidget {
  final AIModelReportItem item;

  const _ModelReportRow(this.item);

  @override
  Widget build(BuildContext context) {
    final customerStatus = _customerStatus(item);
    final customerNote = _customerNote(item);
    final purpose = _customerPurpose(item);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.lightCard.withValues(alpha: .42),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_customerIcon(item), color: _statusColor(item.status)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _customerTitle(item),
                  style: const TextStyle(
                    color: AppColors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              _Badge(customerStatus.toUpperCase(), _statusColor(item.status)),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            purpose,
            style: const TextStyle(
              color: AppColors.textGrey,
              fontSize: 12,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              _MetricChip('Confidence', _customerConfidence(item)),
              if (item.trainingDate != null)
                _MetricChip('Updated', item.trainingDate!),
              _MetricChip('Data source', _customerDataSource(item)),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            customerNote,
            style: const TextStyle(
              color: AppColors.textGrey,
              fontSize: 11,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  String _customerTitle(AIModelReportItem item) {
    final feature = item.feature.toLowerCase();
    if (feature.contains('energy consumption')) return 'Usage forecast';
    if (feature.contains('abnormal')) return 'Unusual usage check';
    if (feature.contains('appliance')) return 'Appliance pattern check';
    if (feature.contains('fire')) return 'Smoke and fire safety check';
    if (feature.contains('electrical')) return 'Electrical condition check';
    if (feature.contains('gas')) return 'Gas sensor support';
    return item.feature;
  }

  IconData _customerIcon(AIModelReportItem item) {
    final feature = item.feature.toLowerCase();
    if (feature.contains('energy consumption')) return Icons.auto_graph_rounded;
    if (feature.contains('abnormal')) return Icons.manage_search_rounded;
    if (feature.contains('appliance')) return Icons.home_work_outlined;
    if (feature.contains('fire')) return Icons.local_fire_department_outlined;
    if (feature.contains('electrical')) {
      return Icons.electrical_services_rounded;
    }
    if (feature.contains('gas')) return Icons.sensors_rounded;
    return Icons.analytics_outlined;
  }

  String _customerPurpose(AIModelReportItem item) {
    final feature = item.feature.toLowerCase();
    if (feature.contains('energy consumption')) {
      return 'Shows a public-dataset forecast sample until enough household meter history is collected.';
    }
    if (feature.contains('abnormal')) {
      return 'Checks whether the current usage pattern looks unusual compared with normal meter behaviour.';
    }
    if (feature.contains('appliance')) {
      return 'Looks at power patterns and suggests the type of appliance that may be active.';
    }
    if (feature.contains('fire')) {
      return 'Supports smoke/fire risk awareness using environmental sensor patterns.';
    }
    if (feature.contains('electrical')) {
      return 'Helps identify unsafe supply conditions such as voltage or power-quality problems.';
    }
    if (feature.contains('gas')) {
      return 'Supports MQ-2 gas monitoring. Live alerts still use calibrated sensor thresholds.';
    }
    return item.task;
  }

  String _customerStatus(AIModelReportItem item) {
    final lower = item.status.toLowerCase();
    if (lower.contains('needs')) return 'Improving';
    if (lower.contains('research')) return 'Support';
    if (lower.contains('prototype')) return 'Prototype';
    return 'Active';
  }

  String _customerConfidence(AIModelReportItem item) {
    final feature = item.feature.toLowerCase();
    if (feature.contains('energy consumption')) return 'Needs more tuning';
    if (feature.contains('appliance')) return 'Good for known samples';
    if (feature.contains('gas')) return 'Support only';
    if (item.primaryUnit == 'score' && item.primaryScore >= 0.85) return 'Good';
    if (item.primaryUnit == 'score' && item.primaryScore >= 0.6) {
      return 'Medium';
    }
    return 'Prototype';
  }

  String _customerDataSource(AIModelReportItem item) {
    final feature = item.feature.toLowerCase();
    if (feature.contains('energy consumption')) return 'Public energy data';
    if (feature.contains('abnormal')) return 'Public smart-meter data';
    if (feature.contains('appliance')) return 'Appliance samples';
    if (feature.contains('fire')) return 'Smoke sensor data';
    if (feature.contains('electrical')) return 'Power-quality data';
    if (feature.contains('gas')) return 'Gas sensor data';
    return 'Public dataset';
  }

  String _customerNote(AIModelReportItem item) {
    final feature = item.feature.toLowerCase();
    if (feature.contains('energy consumption')) {
      return 'This is not fully personalized yet; it becomes more useful after the meter collects more household history.';
    }
    if (feature.contains('abnormal')) {
      return 'For best accuracy, the system should learn each home’s normal daily routine over time.';
    }
    if (feature.contains('appliance')) {
      return 'Appliance names are estimates from sample patterns, not guaranteed device identities.';
    }
    if (feature.contains('fire')) {
      return 'Live safety decisions also use direct sensor thresholds from the ESP32 hardware.';
    }
    if (feature.contains('electrical')) {
      return 'Automatic relay cut-off remains disabled until safe hardware validation is complete.';
    }
    if (feature.contains('gas')) {
      return 'Gas identity is research support; live gas alerts use MQ-2 raw threshold checks.';
    }
    return item.limitation;
  }

  Color _statusColor(String status) {
    final lower = status.toLowerCase();
    if (lower.contains('needs')) return AppColors.warningOrange;
    if (lower.contains('research')) return AppColors.cyan;
    return AppColors.mint;
  }
}

class _MetricChip extends StatelessWidget {
  final String label;
  final String value;

  const _MetricChip(this.label, this.value);

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    decoration: BoxDecoration(
      color: AppColors.darkNavy.withValues(alpha: .45),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: AppColors.border),
    ),
    child: RichText(
      text: TextSpan(
        children: [
          TextSpan(
            text: '$label: ',
            style: const TextStyle(color: AppColors.textGrey, fontSize: 11),
          ),
          TextSpan(
            text: value,
            style: const TextStyle(
              color: AppColors.white,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    ),
  );
}

class _Event extends StatelessWidget {
  final IconData icon;
  final String title, detail, time;
  final Color color;
  const _Event(this.icon, this.title, this.detail, this.time, this.color);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Row(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: AppColors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                detail,
                style: const TextStyle(color: AppColors.textGrey, fontSize: 11),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Text(
          time,
          style: const TextStyle(color: AppColors.textGrey, fontSize: 11),
        ),
      ],
    ),
  );
}

class _Badge extends StatelessWidget {
  final String text;
  final Color color;
  const _Badge(this.text, this.color);

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .10),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      text,
      style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.w700),
    ),
  );
}

class _Insight extends StatelessWidget {
  final IconData icon;
  final String title, body, tag;
  final Color accent;
  const _Insight(
    this.icon,
    this.title,
    this.body,
    this.tag, {
    this.accent = AppColors.neonGreen,
  });
  @override
  Widget build(BuildContext context) => SurfaceCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: accent),
        const SizedBox(height: 18),
        Text(
          title,
          style: const TextStyle(
            color: AppColors.white,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          body,
          style: const TextStyle(
            color: AppColors.textGrey,
            fontSize: 13,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          tag,
          style: TextStyle(
            color: accent,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );
}
