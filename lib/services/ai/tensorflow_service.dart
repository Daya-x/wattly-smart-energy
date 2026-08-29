import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/config/app_config.dart';
import '../auth/firebase_auth_client.dart';

class EnergyForecast {
  final double predictionKwh;
  final double estimatedCostLkr;
  final double estimatedRemainingDays;
  final String modelName;
  final double testMaeKwh;
  final double testR2;
  final String quality;
  final String tariffId;
  final String tariffCategory;
  final String tariffEffectiveFrom;
  final String tariffSourceUrl;

  const EnergyForecast({
    required this.predictionKwh,
    required this.estimatedCostLkr,
    required this.estimatedRemainingDays,
    required this.modelName,
    required this.testMaeKwh,
    required this.testR2,
    required this.quality,
    required this.tariffId,
    required this.tariffCategory,
    required this.tariffEffectiveFrom,
    required this.tariffSourceUrl,
  });

  factory EnergyForecast.fromJson(Map<String, dynamic> json) {
    final tariff = json['tariff'] as Map<String, dynamic>;
    return EnergyForecast(
      predictionKwh: (json['prediction_kwh'] as num).toDouble(),
      estimatedCostLkr: (json['estimated_cost_lkr'] as num).toDouble(),
      estimatedRemainingDays: (json['estimated_remaining_days'] as num)
          .toDouble(),
      modelName: json['model_name'] as String,
      testMaeKwh: (json['test_mae_kwh'] as num).toDouble(),
      testR2: (json['test_r2'] as num).toDouble(),
      quality: json['quality'] as String,
      tariffId: tariff['id'] as String,
      tariffCategory: tariff['category'] as String,
      tariffEffectiveFrom: tariff['effective_from'] as String,
      tariffSourceUrl: tariff['source_url'] as String,
    );
  }
}

class AnomalyDetectionResult {
  final bool isAbnormal;
  final String level;
  final String label;
  final String levelExplanation;
  final double abnormalProbability;
  final String modelName;
  final double testPrecision;
  final double testRecall;
  final double testF1;
  final String source;

  const AnomalyDetectionResult({
    required this.isAbnormal,
    required this.level,
    required this.label,
    required this.levelExplanation,
    required this.abnormalProbability,
    required this.modelName,
    required this.testPrecision,
    required this.testRecall,
    required this.testF1,
    required this.source,
  });

  factory AnomalyDetectionResult.fromJson(Map<String, dynamic> json) =>
      AnomalyDetectionResult(
        isAbnormal: json['is_abnormal'] as bool,
        level:
            json['level'] as String? ?? (json['label'] as String).toLowerCase(),
        label: json['label'] as String,
        levelExplanation:
            json['level_explanation'] as String? ??
            'Usage pattern checked by the anomaly model.',
        abnormalProbability: (json['abnormal_probability'] as num).toDouble(),
        modelName: json['model_name'] as String,
        testPrecision: (json['test_precision'] as num).toDouble(),
        testRecall: (json['test_recall'] as num).toDouble(),
        testF1: (json['test_f1'] as num).toDouble(),
        source: json['source'] as String,
      );
}

class ApplianceDetection {
  final String category;
  final double confidence;
  final double meanPowerW;
  final double windowEnergyWh;

  const ApplianceDetection({
    required this.category,
    required this.confidence,
    required this.meanPowerW,
    required this.windowEnergyWh,
  });

  factory ApplianceDetection.fromJson(Map<String, dynamic> json) =>
      ApplianceDetection(
        category: json['category'] as String,
        confidence: (json['confidence'] as num).toDouble(),
        meanPowerW: (json['mean_power_w'] as num).toDouble(),
        windowEnergyWh: (json['window_energy_wh'] as num).toDouble(),
      );
}

class ApplianceDetectionResult {
  final List<ApplianceDetection> detections;
  final String modelName;
  final double knownDeviceAccuracy;
  final double knownDeviceMacroF1;
  final double unseenDeviceMacroF1;
  final String quality;

  const ApplianceDetectionResult({
    required this.detections,
    required this.modelName,
    required this.knownDeviceAccuracy,
    required this.knownDeviceMacroF1,
    required this.unseenDeviceMacroF1,
    required this.quality,
  });

  factory ApplianceDetectionResult.fromJson(Map<String, dynamic> json) =>
      ApplianceDetectionResult(
        detections: (json['detections'] as List)
            .map(
              (item) =>
                  ApplianceDetection.fromJson(item as Map<String, dynamic>),
            )
            .toList(),
        modelName: json['model_name'] as String,
        knownDeviceAccuracy: (json['known_device_accuracy'] as num).toDouble(),
        knownDeviceMacroF1: (json['known_device_macro_f1'] as num).toDouble(),
        unseenDeviceMacroF1: (json['unseen_device_macro_f1'] as num).toDouble(),
        quality: json['quality'] as String,
      );
}

class SafetyPrediction {
  final String riskLevel;
  final double overallRiskProbability;
  final double fireProbability;
  final double electricalFaultProbability;
  final String electricalCondition;
  final String gasIdentity;
  final double gasIdentityConfidence;
  final bool gasLeakProbabilityAvailable;
  final double fireF1;
  final double electricalMacroF1;
  final double gasMacroF1;
  final double temperatureRiskProbability;
  final double gasRiskProbability;
  final String source;

  const SafetyPrediction({
    required this.riskLevel,
    required this.overallRiskProbability,
    required this.fireProbability,
    required this.electricalFaultProbability,
    required this.electricalCondition,
    required this.gasIdentity,
    required this.gasIdentityConfidence,
    required this.gasLeakProbabilityAvailable,
    required this.fireF1,
    required this.electricalMacroF1,
    required this.gasMacroF1,
    required this.temperatureRiskProbability,
    required this.gasRiskProbability,
    required this.source,
  });

  factory SafetyPrediction.fromJson(Map<String, dynamic> json) {
    final metrics = json['metrics'] as Map<String, dynamic>;
    return SafetyPrediction(
      riskLevel: json['risk_level'] as String,
      overallRiskProbability: (json['overall_risk_probability'] as num)
          .toDouble(),
      fireProbability: (json['fire_probability'] as num).toDouble(),
      electricalFaultProbability: (json['electrical_fault_probability'] as num)
          .toDouble(),
      electricalCondition: json['electrical_condition'] as String,
      gasIdentity: json['gas_identity'] as String,
      gasIdentityConfidence: (json['gas_identity_confidence'] as num)
          .toDouble(),
      gasLeakProbabilityAvailable:
          json['gas_leak_probability_available'] as bool,
      fireF1: (metrics['fire_f1'] as num).toDouble(),
      electricalMacroF1: (metrics['electrical_macro_f1'] as num).toDouble(),
      gasMacroF1: (metrics['gas_macro_f1'] as num).toDouble(),
      temperatureRiskProbability:
          (json['temperature_risk_probability'] as num? ?? 0).toDouble(),
      gasRiskProbability: (json['gas_risk_probability'] as num? ?? 0)
          .toDouble(),
      source: json['source'] as String? ?? 'unknown',
    );
  }
}

class EnergyRecommendation {
  final String type;
  final String title;
  final String message;
  final String impact;
  final String severity;
  final int potentialSavingPercent;

  const EnergyRecommendation({
    required this.type,
    required this.title,
    required this.message,
    required this.impact,
    required this.severity,
    required this.potentialSavingPercent,
  });

  factory EnergyRecommendation.fromJson(Map<String, dynamic> json) =>
      EnergyRecommendation(
        type: json['type'] as String,
        title: json['title'] as String,
        message: json['message'] as String,
        impact: json['impact'] as String,
        severity: json['severity'] as String,
        potentialSavingPercent: (json['potential_saving_percent'] as num? ?? 0)
            .toInt(),
      );
}

class BalanceDepletion {
  final double currentBalanceLkr;
  final double? dailyUsageKwh;
  final double? dailyCostLkr;
  final double? remainingDays;
  final bool ready;
  final String status;
  final String method;
  final String source;
  final double historyDays;
  final String message;

  const BalanceDepletion({
    required this.currentBalanceLkr,
    required this.dailyUsageKwh,
    required this.dailyCostLkr,
    required this.remainingDays,
    required this.ready,
    required this.status,
    required this.method,
    required this.source,
    required this.historyDays,
    required this.message,
  });

  factory BalanceDepletion.fromJson(Map<String, dynamic> json) =>
      BalanceDepletion(
        currentBalanceLkr: (json['current_balance_lkr'] as num).toDouble(),
        dailyUsageKwh: (json['daily_usage_kwh'] as num?)?.toDouble(),
        dailyCostLkr: (json['daily_cost_lkr'] as num?)?.toDouble(),
        remainingDays: (json['remaining_days'] as num?)?.toDouble(),
        ready: json['ready'] as bool? ?? false,
        status: json['status'] as String,
        method: json['method'] as String,
        source: json['source'] as String? ?? 'meter_history',
        historyDays: (json['history_days'] as num? ?? 0).toDouble(),
        message: json['message'] as String? ?? '',
      );
}

class MonthlyBillPrediction {
  final double currentMonthUnits;
  final double currentBillLkr;
  final double projectedMonthUnits;
  final double projectedBillLkr;
  final double averageDailyUnits;
  final int remainingBillingDays;
  final int billingDaysElapsed;
  final int billingCycleDays;
  final double nextDayForecastUnits;
  final String status;
  final String method;
  final String tariffId;

  const MonthlyBillPrediction({
    required this.currentMonthUnits,
    required this.currentBillLkr,
    required this.projectedMonthUnits,
    required this.projectedBillLkr,
    required this.averageDailyUnits,
    required this.remainingBillingDays,
    required this.billingDaysElapsed,
    required this.billingCycleDays,
    required this.nextDayForecastUnits,
    required this.status,
    required this.method,
    required this.tariffId,
  });

  factory MonthlyBillPrediction.fromJson(Map<String, dynamic> json) =>
      MonthlyBillPrediction(
        currentMonthUnits: (json['current_month_units'] as num).toDouble(),
        currentBillLkr: (json['current_bill_lkr'] as num).toDouble(),
        projectedMonthUnits: (json['projected_month_units'] as num).toDouble(),
        projectedBillLkr: (json['projected_bill_lkr'] as num).toDouble(),
        averageDailyUnits: (json['average_daily_units'] as num).toDouble(),
        remainingBillingDays: (json['remaining_billing_days'] as num).toInt(),
        billingDaysElapsed: (json['billing_days_elapsed'] as num).toInt(),
        billingCycleDays: (json['billing_cycle_days'] as num).toInt(),
        nextDayForecastUnits: (json['next_day_forecast_units'] as num)
            .toDouble(),
        status: json['status'] as String,
        method: json['method'] as String,
        tariffId: json['tariff_id'] as String,
      );
}

class AIOverview {
  final EnergyForecast energy;
  final AnomalyDetectionResult anomaly;
  final ApplianceDetectionResult appliances;
  final SafetyPrediction safety;
  final BalanceDepletion balanceDepletion;
  final MonthlyBillPrediction monthlyBillPrediction;
  final List<EnergyRecommendation> recommendations;

  const AIOverview({
    required this.energy,
    required this.anomaly,
    required this.appliances,
    required this.safety,
    required this.balanceDepletion,
    required this.monthlyBillPrediction,
    required this.recommendations,
  });

  factory AIOverview.fromJson(Map<String, dynamic> json) => AIOverview(
    energy: EnergyForecast.fromJson(json['energy'] as Map<String, dynamic>),
    anomaly: AnomalyDetectionResult.fromJson(
      json['anomaly'] as Map<String, dynamic>,
    ),
    appliances: ApplianceDetectionResult.fromJson(
      json['appliances'] as Map<String, dynamic>,
    ),
    safety: SafetyPrediction.fromJson(json['safety'] as Map<String, dynamic>),
    balanceDepletion: BalanceDepletion.fromJson(
      json['balance_depletion'] as Map<String, dynamic>,
    ),
    monthlyBillPrediction: MonthlyBillPrediction.fromJson(
      json['monthly_bill_prediction'] as Map<String, dynamic>,
    ),
    recommendations: (json['recommendations'] as List)
        .map(
          (item) => EnergyRecommendation.fromJson(item as Map<String, dynamic>),
        )
        .toList(),
  );
}

class AIModelReportItem {
  final String feature;
  final String dataset;
  final String model;
  final String task;
  final String primaryMetric;
  final double primaryScore;
  final String primaryUnit;
  final String secondaryMetric;
  final double secondaryScore;
  final String? trainingDate;
  final String status;
  final String limitation;

  const AIModelReportItem({
    required this.feature,
    required this.dataset,
    required this.model,
    required this.task,
    required this.primaryMetric,
    required this.primaryScore,
    required this.primaryUnit,
    required this.secondaryMetric,
    required this.secondaryScore,
    required this.trainingDate,
    required this.status,
    required this.limitation,
  });

  factory AIModelReportItem.fromJson(Map<String, dynamic> json) =>
      AIModelReportItem(
        feature: json['feature'] as String,
        dataset: json['dataset'] as String,
        model: json['model'] as String,
        task: json['task'] as String,
        primaryMetric: json['primary_metric'] as String,
        primaryScore: (json['primary_score'] as num).toDouble(),
        primaryUnit: json['primary_unit'] as String,
        secondaryMetric: json['secondary_metric'] as String,
        secondaryScore: (json['secondary_score'] as num).toDouble(),
        trainingDate: json['training_date'] as String?,
        status: json['status'] as String,
        limitation: json['limitation'] as String,
      );
}

class AIModelReport {
  final String scope;
  final String tensorflowStatus;
  final String summary;
  final List<AIModelReportItem> items;

  const AIModelReport({
    required this.scope,
    required this.tensorflowStatus,
    required this.summary,
    required this.items,
  });

  factory AIModelReport.fromJson(Map<String, dynamic> json) => AIModelReport(
    scope: json['scope'] as String,
    tensorflowStatus: json['tensorflow_status'] as String,
    summary:
        json['summary'] as String? ??
        'Public-dataset prototype metrics for the current AI features.',
    items: (json['items'] as List)
        .map((item) => AIModelReportItem.fromJson(item as Map<String, dynamic>))
        .toList(),
  );
}

class TariffVersion {
  final String id;
  final String status;
  final String effectiveFrom;
  final String? effectiveTo;
  final String sourceTitle;
  final String sourceUrl;
  final int validationCaseCount;

  const TariffVersion({
    required this.id,
    required this.status,
    required this.effectiveFrom,
    required this.effectiveTo,
    required this.sourceTitle,
    required this.sourceUrl,
    required this.validationCaseCount,
  });

  factory TariffVersion.fromJson(Map<String, dynamic> json) => TariffVersion(
    id: json['id'] as String,
    status: json['status'] as String,
    effectiveFrom: json['effective_from'] as String,
    effectiveTo: json['effective_to'] as String?,
    sourceTitle: json['source_title'] as String,
    sourceUrl: json['source_url'] as String,
    validationCaseCount: (json['validation_case_count'] as num).toInt(),
  );
}

class TariffCandidate {
  final String id;
  final String title;
  final String sourceUrl;
  final String status;
  final String detectedAt;

  const TariffCandidate({
    required this.id,
    required this.title,
    required this.sourceUrl,
    required this.status,
    required this.detectedAt,
  });

  factory TariffCandidate.fromJson(Map<String, dynamic> json) =>
      TariffCandidate(
        id: json['id'] as String,
        title: json['title'] as String,
        sourceUrl: json['source_url'] as String,
        status: json['status'] as String,
        detectedAt: json['detected_at'] as String,
      );
}

class TariffMonitorStatus {
  final bool enabled;
  final double intervalHours;
  final String? lastCheckedAt;
  final String? lastError;
  final List<TariffCandidate> candidates;

  const TariffMonitorStatus({
    required this.enabled,
    required this.intervalHours,
    required this.lastCheckedAt,
    required this.lastError,
    required this.candidates,
  });

  factory TariffMonitorStatus.fromJson(Map<String, dynamic> json) =>
      TariffMonitorStatus(
        enabled: json['enabled'] as bool? ?? true,
        intervalHours: (json['interval_hours'] as num? ?? 24).toDouble(),
        lastCheckedAt: json['last_checked_at'] as String?,
        lastError: json['last_error'] as String?,
        candidates: (json['candidates'] as List? ?? const [])
            .map(
              (item) => TariffCandidate.fromJson(item as Map<String, dynamic>),
            )
            .toList(),
      );
}

class TensorFlowService {
  final http.Client _client;
  final String baseUrl;

  TensorFlowService({
    http.Client? client,
    this.baseUrl = AppConfig.aiApiBaseUrl,
  }) : _client = client ?? FirebaseAuthClient();

  Future<EnergyForecast> fetchEnergyForecast({
    required double balanceLkr,
    double monthlyUsageKwh = 0,
  }) async {
    final uri = Uri.parse('$baseUrl/predict/energy').replace(
      queryParameters: {
        'balance_lkr': balanceLkr.toString(),
        'monthly_usage_kwh': monthlyUsageKwh.toString(),
      },
    );
    final response = await _client.get(uri).timeout(const Duration(seconds: 4));
    if (response.statusCode != 200) {
      throw Exception('AI API returned ${response.statusCode}');
    }
    return EnergyForecast.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<AIOverview> fetchAIOverview({
    required double balanceLkr,
    required double monthlyUsageKwh,
  }) async {
    final uri = Uri.parse('$baseUrl/predict/summary').replace(
      queryParameters: {
        'balance_lkr': balanceLkr.toString(),
        'monthly_usage_kwh': monthlyUsageKwh.toString(),
        'billing_days_elapsed': DateTime.now().day.toString(),
        'device_id': 'EM-2048',
      },
    );
    final response = await _client.get(uri).timeout(const Duration(seconds: 8));
    if (response.statusCode != 200) {
      throw Exception('AI API returned ${response.statusCode}');
    }
    return AIOverview.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<AIModelReport> fetchModelReport() async {
    final response = await _client
        .get(Uri.parse('$baseUrl/predict/model-report'))
        .timeout(const Duration(seconds: 5));
    if (response.statusCode != 200) {
      throw Exception('AI model report returned ${response.statusCode}');
    }
    return AIModelReport.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<AnomalyDetectionResult> fetchAnomalyDetection() async {
    final uri = Uri.parse('$baseUrl/predict/anomaly');
    final response = await _client.get(uri).timeout(const Duration(seconds: 4));
    if (response.statusCode != 200) {
      throw Exception('AI API returned ${response.statusCode}');
    }
    return AnomalyDetectionResult.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<ApplianceDetectionResult> fetchApplianceDetections() async {
    final uri = Uri.parse('$baseUrl/predict/appliances');
    final response = await _client.get(uri).timeout(const Duration(seconds: 4));
    if (response.statusCode != 200) {
      throw Exception('AI API returned ${response.statusCode}');
    }
    return ApplianceDetectionResult.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<SafetyPrediction> fetchSafetyPrediction() async {
    final uri = Uri.parse('$baseUrl/predict/safety');
    final response = await _client.get(uri).timeout(const Duration(seconds: 4));
    if (response.statusCode != 200) {
      throw Exception('AI API returned ${response.statusCode}');
    }
    return SafetyPrediction.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<List<TariffVersion>> fetchTariffHistory() async {
    final response = await _client
        .get(Uri.parse('$baseUrl/tariffs/history'))
        .timeout(const Duration(seconds: 4));
    if (response.statusCode != 200) {
      throw Exception('Tariff API returned ${response.statusCode}');
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return (body['tariffs'] as List)
        .map((item) => TariffVersion.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<void> verifyTariff(String id) => _tariffAction(id, 'verify');

  Future<void> activateTariff(String id) => _tariffAction(id, 'activate');

  Future<void> _tariffAction(String id, String action) async {
    if (AppConfig.tariffAdminKey.isEmpty) {
      throw Exception('Start the app with a runtime tariff administrator key');
    }
    final response = await _client
        .post(
          Uri.parse('$baseUrl/tariffs/$id/$action'),
          headers: {'X-Admin-Key': AppConfig.tariffAdminKey},
        )
        .timeout(const Duration(seconds: 6));
    if (response.statusCode != 200) {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      throw Exception(body['detail'] ?? 'Tariff action failed');
    }
  }

  Future<TariffMonitorStatus> fetchTariffMonitor() async {
    final response = await _client
        .get(Uri.parse('$baseUrl/tariffs/monitor'))
        .timeout(const Duration(seconds: 4));
    if (response.statusCode != 200) {
      throw Exception('Tariff monitor returned ${response.statusCode}');
    }
    return TariffMonitorStatus.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<TariffMonitorStatus> checkTariffMonitor() async {
    if (AppConfig.tariffAdminKey.isEmpty) {
      throw Exception('Start the app with a runtime tariff administrator key');
    }
    final response = await _client
        .post(
          Uri.parse('$baseUrl/tariffs/monitor/check'),
          headers: {'X-Admin-Key': AppConfig.tariffAdminKey},
        )
        .timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      throw Exception(body['detail'] ?? 'PUCSL check failed');
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return TariffMonitorStatus.fromJson({
      'enabled': true,
      'interval_hours': 24,
      ...body,
    });
  }
}
