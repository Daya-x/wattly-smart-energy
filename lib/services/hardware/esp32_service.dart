import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/config/app_config.dart';
import '../../models/sensor_model.dart';
import '../auth/firebase_auth_client.dart';

class DeviceReading {
  final SensorModel sensor;
  final DateTime receivedAt;
  final double usageCostLkr;
  final double monthlyUsageKwh;
  final double todayUsageKwh;
  final bool hasRecharged;
  final double minimumRechargeLkr;
  final bool demoZeroBalance;
  final double actualBalanceLkr;
  final DateTime? demoExpiresAt;

  const DeviceReading({
    required this.sensor,
    required this.receivedAt,
    required this.usageCostLkr,
    required this.monthlyUsageKwh,
    required this.todayUsageKwh,
    required this.hasRecharged,
    required this.minimumRechargeLkr,
    required this.demoZeroBalance,
    required this.actualBalanceLkr,
    required this.demoExpiresAt,
  });

  factory DeviceReading.fromJson(Map<String, dynamic> json) => DeviceReading(
    sensor: SensorModel(
      voltage: (json['voltage'] as num).toDouble(),
      current: (json['current'] as num).toDouble(),
      power: (json['power'] as num).toDouble(),
      energy: (json['monthly_usage_kwh'] as num).toDouble(),
      temperature: (json['temperature'] as num).toDouble(),
      humidity: (json['humidity'] as num).toDouble(),
      gas: (json['gas'] as num).toInt(),
      motion: json['motion'] as bool,
      relay: json['relay'] as bool,
      balance: (json['balance_lkr'] as num).toDouble(),
      pzemValid: json['pzem_valid'] as bool? ?? true,
      dhtValid: json['dht_valid'] as bool? ?? true,
    ),
    receivedAt: DateTime.parse(json['received_at'] as String).toLocal(),
    usageCostLkr: (json['usage_cost_lkr'] as num).toDouble(),
    monthlyUsageKwh: (json['monthly_usage_kwh'] as num).toDouble(),
    todayUsageKwh: (json['today_usage_kwh'] as num).toDouble(),
    hasRecharged:
        json['has_recharged'] as bool? ??
        ((json['balance_lkr'] as num).toDouble() > 0),
    minimumRechargeLkr: (json['minimum_recharge_lkr'] as num? ?? 100)
        .toDouble(),
    demoZeroBalance: json['demo_zero_balance'] as bool? ?? false,
    actualBalanceLkr:
        (json['actual_balance_lkr'] as num? ?? json['balance_lkr'] as num)
            .toDouble(),
    demoExpiresAt: json['demo_expires_at'] == null
        ? null
        : DateTime.parse(json['demo_expires_at'] as String).toLocal(),
  );
}

class DemoZeroBalanceStatus {
  final bool active;
  final double displayedBalanceLkr;
  final double actualBalanceLkr;
  final DateTime? expiresAt;
  final String message;

  const DemoZeroBalanceStatus({
    required this.active,
    required this.displayedBalanceLkr,
    required this.actualBalanceLkr,
    required this.expiresAt,
    required this.message,
  });

  factory DemoZeroBalanceStatus.fromJson(Map<String, dynamic> json) =>
      DemoZeroBalanceStatus(
        active: json['demo_zero_balance'] as bool,
        displayedBalanceLkr: (json['balance_lkr'] as num).toDouble(),
        actualBalanceLkr: (json['actual_balance_lkr'] as num).toDouble(),
        expiresAt: json['demo_expires_at'] == null
            ? null
            : DateTime.parse(json['demo_expires_at'] as String).toLocal(),
        message: json['message'] as String,
      );
}

class DemoRechargeReceipt {
  final String id;
  final double amountLkr;
  final double balanceLkr;
  final DateTime createdAt;

  const DemoRechargeReceipt({
    required this.id,
    required this.amountLkr,
    required this.balanceLkr,
    required this.createdAt,
  });

  factory DemoRechargeReceipt.fromJson(Map<String, dynamic> json) =>
      DemoRechargeReceipt(
        id: json['receipt_id'] as String,
        amountLkr: (json['amount_lkr'] as num).toDouble(),
        balanceLkr: (json['balance_lkr'] as num).toDouble(),
        createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
      );
}

class UsageHistoryResult {
  final List<double> values;
  final double totalUnits;
  final String source;

  const UsageHistoryResult({
    required this.values,
    required this.totalUnits,
    required this.source,
  });

  factory UsageHistoryResult.fromJson(Map<String, dynamic> json) =>
      UsageHistoryResult(
        values: (json['values'] as List)
            .map((value) => (value as num).toDouble())
            .toList(),
        totalUnits: (json['total_units'] as num).toDouble(),
        source: json['source'] as String,
      );
}

class LiveAlert {
  final String id;
  final String type;
  final String title;
  final String message;
  final String severity;
  final String status;
  final bool acknowledged;
  final DateTime createdAt;

  const LiveAlert({
    required this.id,
    required this.type,
    required this.title,
    required this.message,
    required this.severity,
    required this.status,
    required this.acknowledged,
    required this.createdAt,
  });

  factory LiveAlert.fromJson(Map<String, dynamic> json) => LiveAlert(
    id: json['id'] as String,
    type: json['type'] as String,
    title: json['title'] as String,
    message: json['message'] as String,
    severity: json['severity'] as String,
    status: json['status'] as String,
    acknowledged: json['acknowledged'] as bool? ?? false,
    createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
  );
}

class LiveAlertsResult {
  final List<LiveAlert> alerts;
  final int activeUnacknowledgedCount;

  const LiveAlertsResult({
    required this.alerts,
    required this.activeUnacknowledgedCount,
  });

  factory LiveAlertsResult.fromJson(Map<String, dynamic> json) =>
      LiveAlertsResult(
        alerts: (json['alerts'] as List)
            .map((item) => LiveAlert.fromJson(item as Map<String, dynamic>))
            .toList(),
        activeUnacknowledgedCount: (json['active_unacknowledged_count'] as num)
            .toInt(),
      );
}

class TheftSecurityStatus {
  final bool manualEnabled;
  final bool automaticActive;
  final bool monitoringActive;
  final String automaticWindow;
  final String mode;

  const TheftSecurityStatus({
    required this.manualEnabled,
    required this.automaticActive,
    required this.monitoringActive,
    required this.automaticWindow,
    required this.mode,
  });

  factory TheftSecurityStatus.fromJson(Map<String, dynamic> json) =>
      TheftSecurityStatus(
        manualEnabled: json['manual_enabled'] as bool? ?? false,
        automaticActive: json['automatic_active'] as bool? ?? false,
        monitoringActive: json['monitoring_active'] as bool? ?? false,
        automaticWindow:
            json['automatic_window'] as String? ?? '12:00 AM – 6:00 AM',
        mode: json['mode'] as String? ?? 'off',
      );
}

class Esp32Service {
  final http.Client _client;
  final String baseUrl;

  Esp32Service({http.Client? client, this.baseUrl = AppConfig.aiApiBaseUrl})
    : _client = client ?? FirebaseAuthClient();

  Future<DeviceReading> fetchLatest({String deviceId = 'EM-2048'}) async {
    final response = await _client
        .get(Uri.parse('$baseUrl/devices/$deviceId/readings/latest'))
        .timeout(const Duration(seconds: 3));
    if (response.statusCode == 404) {
      throw StateError('Waiting for the first simulator reading');
    }
    if (response.statusCode != 200) {
      throw Exception('Device API returned ${response.statusCode}');
    }
    return DeviceReading.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<DemoRechargeReceipt> recharge({
    String deviceId = 'EM-2048',
    required double amountLkr,
  }) async {
    final response = await _client
        .post(
          Uri.parse('$baseUrl/devices/$deviceId/account/recharge'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'amount_lkr': amountLkr,
            'payment_method': 'demo_card',
          }),
        )
        .timeout(const Duration(seconds: 4));
    if (response.statusCode != 200) {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      throw Exception(body['detail'] ?? 'Recharge payment failed');
    }
    return DemoRechargeReceipt.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<List<DemoRechargeReceipt>> fetchRechargeHistory({
    String deviceId = 'EM-2048',
  }) async {
    final response = await _client
        .get(Uri.parse('$baseUrl/devices/$deviceId/account/recharges'))
        .timeout(const Duration(seconds: 4));
    if (response.statusCode != 200) {
      throw Exception('Recharge history API returned ${response.statusCode}');
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return (body['recharges'] as List)
        .map(
          (item) => DemoRechargeReceipt.fromJson(item as Map<String, dynamic>),
        )
        .toList();
  }

  Future<UsageHistoryResult> fetchUsageHistory({
    String deviceId = 'EM-2048',
    required String period,
    required DateTime anchor,
  }) async {
    String twoDigits(int value) => value.toString().padLeft(2, '0');
    final date =
        '${anchor.year}-${twoDigits(anchor.month)}-${twoDigits(anchor.day)}';
    final uri = Uri.parse(
      '$baseUrl/devices/$deviceId/usage',
    ).replace(queryParameters: {'period': period, 'anchor': date});
    final response = await _client.get(uri).timeout(const Duration(seconds: 5));
    if (response.statusCode != 200) {
      throw Exception('Usage history API returned ${response.statusCode}');
    }
    return UsageHistoryResult.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<void> setRelayCommand({
    String deviceId = 'EM-2048',
    required bool enabled,
  }) async {
    final response = await _client
        .post(
          Uri.parse('$baseUrl/devices/$deviceId/relay-command'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'relay_requested': enabled}),
        )
        .timeout(const Duration(seconds: 4));
    if (response.statusCode != 200) {
      String detail = 'Relay command API returned ${response.statusCode}';
      try {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        detail = body['detail'] as String? ?? detail;
      } catch (_) {
        // Keep the HTTP status message when the API body is not JSON.
      }
      throw Exception(detail);
    }
  }

  Future<DemoZeroBalanceStatus> setDemoZeroBalance({
    String deviceId = 'EM-2048',
    required bool enabled,
    int durationSeconds = 300,
  }) async {
    if (AppConfig.tariffAdminKey.isEmpty) {
      throw Exception(
        'Start the dashboard with the administrator key to use this demo.',
      );
    }
    final response = await _client
        .post(
          Uri.parse('$baseUrl/devices/$deviceId/account/demo-zero-balance'),
          headers: {
            'Content-Type': 'application/json',
            'X-Admin-Key': AppConfig.tariffAdminKey,
          },
          body: jsonEncode({
            'enabled': enabled,
            'duration_seconds': durationSeconds,
          }),
        )
        .timeout(const Duration(seconds: 4));
    if (response.statusCode != 200) {
      String detail =
          'Zero-balance demonstration returned ${response.statusCode}';
      try {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        detail = body['detail'] as String? ?? detail;
      } catch (_) {
        // Keep the HTTP status message when the API body is not JSON.
      }
      throw Exception(detail);
    }
    return DemoZeroBalanceStatus.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<LiveAlertsResult> fetchAlerts({String deviceId = 'EM-2048'}) async {
    final response = await _client
        .get(Uri.parse('$baseUrl/devices/$deviceId/alerts'))
        .timeout(const Duration(seconds: 4));
    if (response.statusCode != 200) {
      throw Exception('Alerts API returned ${response.statusCode}');
    }
    return LiveAlertsResult.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<TheftSecurityStatus> fetchTheftSecurity({
    String deviceId = 'EM-2048',
  }) async {
    final response = await _client
        .get(Uri.parse('$baseUrl/devices/$deviceId/security'))
        .timeout(const Duration(seconds: 4));
    if (response.statusCode != 200) {
      throw Exception('Security API returned ${response.statusCode}');
    }
    return TheftSecurityStatus.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<TheftSecurityStatus> setManualTheftProtection({
    String deviceId = 'EM-2048',
    required bool enabled,
  }) async {
    final response = await _client
        .post(
          Uri.parse('$baseUrl/devices/$deviceId/security'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'manual_enabled': enabled}),
        )
        .timeout(const Duration(seconds: 4));
    if (response.statusCode != 200) {
      throw Exception('Security update returned ${response.statusCode}');
    }
    return TheftSecurityStatus.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<String> runSimulation(
    String scenario, {
    String deviceId = 'EM-2048',
  }) async {
    final response = await _client
        .post(
          Uri.parse('$baseUrl/devices/$deviceId/simulations'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'scenario': scenario}),
        )
        .timeout(const Duration(seconds: 5));
    if (response.statusCode != 200) {
      String detail = 'Simulation returned ${response.statusCode}';
      try {
        detail =
            (jsonDecode(response.body) as Map<String, dynamic>)['detail']
                as String? ??
            detail;
      } catch (_) {}
      throw Exception(detail);
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return body['message'] as String? ?? 'Simulation started';
  }

  Future<void> acknowledgeAlert(
    String alertId, {
    String deviceId = 'EM-2048',
  }) async {
    await _protectedAlertPost(
      '$baseUrl/devices/$deviceId/alerts/$alertId/acknowledge',
    );
  }

  Future<void> acknowledgeAllAlerts({String deviceId = 'EM-2048'}) async {
    await _protectedAlertPost(
      '$baseUrl/devices/$deviceId/alerts/acknowledge-all',
    );
  }

  Future<void> _protectedAlertPost(String url) async {
    final headers = <String, String>{};
    if (AppConfig.tariffAdminKey.isNotEmpty) {
      headers['X-Admin-Key'] = AppConfig.tariffAdminKey;
    }
    final response = await _client
        .post(
          Uri.parse(url),
          headers: headers,
        )
        .timeout(const Duration(seconds: 4));
    if (response.statusCode != 200) {
      var detail = 'Alert action returned ${response.statusCode}';
      try {
        detail =
            (jsonDecode(response.body) as Map<String, dynamic>)['detail']
                as String? ??
            detail;
      } catch (_) {}
      throw Exception(detail);
    }
  }
}
