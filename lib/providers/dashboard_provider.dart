import 'dart:async';

import 'package:flutter/material.dart';
import '../models/sensor_model.dart';
import '../services/ai/tensorflow_service.dart';
import '../services/hardware/esp32_service.dart';
import '../services/notifications/browser_notification_service.dart';

enum ForecastStatus { idle, loading, loaded, offline }

enum DeviceStatus { waiting, online, offline }

class DashboardProvider extends ChangeNotifier {
  final TensorFlowService _aiService;
  final Esp32Service _esp32Service;
  final BrowserNotificationService _notificationService;

  DashboardProvider({
    TensorFlowService? aiService,
    Esp32Service? esp32Service,
    BrowserNotificationService? notificationService,
  }) : _aiService = aiService ?? TensorFlowService(),
       _esp32Service = esp32Service ?? Esp32Service(),
       _notificationService =
           notificationService ?? BrowserNotificationService();

  SensorModel _sensor = const SensorModel(
    voltage: 0,
    current: 0,
    power: 0,
    energy: 0,
    temperature: 0,
    humidity: 0,
    gas: 0,
    motion: false,
    relay: false,
    balance: 0,
  );

  SensorModel get sensor => _sensor;

  Timer? _deviceTimer;
  DeviceStatus? _deviceStatus = DeviceStatus.waiting;
  DateTime? _deviceUpdatedAt;
  String? _deviceError;
  bool _deviceRequestInProgress = false;
  int _deviceReadingCount = 0;
  double _actualUsageCostLkr = 0;
  double _todayUsageKwh = 0;
  bool _hasRecharged = false;
  double _minimumRechargeLkr = 500;
  List<LiveAlert> _liveAlerts = const [];
  int _unacknowledgedAlertCount = 0;
  ForecastStatus _alertsStatus = ForecastStatus.idle;
  String? _alertsError;
  bool _notificationsEnabled = false;
  bool _alertsInitializedForNotifications = false;
  final Set<String> _knownAlertIds = {};
  List<DemoRechargeReceipt> _rechargeReceipts = const [];
  ForecastStatus _rechargeHistoryStatus = ForecastStatus.idle;
  String? _rechargeHistoryError;
  bool _relayCommandInProgress = false;
  String? _relayCommandError;
  bool _demoZeroBalance = false;
  double _actualBalanceLkr = 0;
  DateTime? _demoBalanceExpiresAt;
  bool _demoBalanceInProgress = false;
  String? _demoBalanceError;
  TheftSecurityStatus? _theftSecurity;
  ForecastStatus _theftSecurityStatus = ForecastStatus.idle;
  String? _theftSecurityError;
  String? _simulationScenario;
  String? _simulationMessage;

  DeviceStatus get deviceStatus => _deviceStatus ?? DeviceStatus.waiting;
  DateTime? get deviceUpdatedAt => _deviceUpdatedAt;
  String? get deviceError => _deviceError;
  double get actualUsageCostLkr => _actualUsageCostLkr;
  double get todayUsageKwh => _todayUsageKwh;
  bool get hasRecharged => _hasRecharged;
  double get minimumRechargeLkr => _minimumRechargeLkr;
  List<LiveAlert> get liveAlerts => _liveAlerts;
  int get unacknowledgedAlertCount => _unacknowledgedAlertCount;
  ForecastStatus get alertsStatus => _alertsStatus;
  String? get alertsError => _alertsError;
  bool get notificationsEnabled => _notificationsEnabled;
  bool get notificationsSupported => _notificationService.isSupported;
  List<DemoRechargeReceipt> get rechargeReceipts => _rechargeReceipts;
  ForecastStatus get rechargeHistoryStatus => _rechargeHistoryStatus;
  String? get rechargeHistoryError => _rechargeHistoryError;
  bool get relayCommandInProgress => _relayCommandInProgress;
  String? get relayCommandError => _relayCommandError;
  bool get demoZeroBalance => _demoZeroBalance;
  double get actualBalanceLkr => _actualBalanceLkr;
  DateTime? get demoBalanceExpiresAt => _demoBalanceExpiresAt;
  bool get demoBalanceInProgress => _demoBalanceInProgress;
  String? get demoBalanceError => _demoBalanceError;
  TheftSecurityStatus? get theftSecurity => _theftSecurity;
  ForecastStatus get theftSecurityStatus => _theftSecurityStatus;
  String? get theftSecurityError => _theftSecurityError;
  String? get simulationScenario => _simulationScenario;
  String? get simulationMessage => _simulationMessage;
  bool get simulationInProgress => _simulationScenario != null;

  EnergyForecast? _energyForecast;
  ForecastStatus _forecastStatus = ForecastStatus.idle;
  String? _forecastError;

  EnergyForecast? get energyForecast => _energyForecast;
  ForecastStatus get forecastStatus => _forecastStatus;
  String? get forecastError => _forecastError;

  AnomalyDetectionResult? _anomalyDetection;
  ForecastStatus _anomalyStatus = ForecastStatus.idle;
  String? _anomalyError;

  AnomalyDetectionResult? get anomalyDetection => _anomalyDetection;
  ForecastStatus get anomalyStatus => _anomalyStatus;
  String? get anomalyError => _anomalyError;

  ApplianceDetectionResult? _applianceDetection;
  ForecastStatus _applianceStatus = ForecastStatus.idle;
  String? _applianceError;

  ApplianceDetectionResult? get applianceDetection => _applianceDetection;
  ForecastStatus get applianceStatus => _applianceStatus;
  String? get applianceError => _applianceError;

  SafetyPrediction? _safetyPrediction;
  ForecastStatus _safetyStatus = ForecastStatus.idle;
  String? _safetyError;

  SafetyPrediction? get safetyPrediction => _safetyPrediction;
  ForecastStatus get safetyStatus => _safetyStatus;
  String? get safetyError => _safetyError;

  BalanceDepletion? _balanceDepletion;
  MonthlyBillPrediction? _monthlyBillPrediction;
  List<EnergyRecommendation>? _recommendations = const [];

  BalanceDepletion? get balanceDepletion => _balanceDepletion;
  MonthlyBillPrediction? get monthlyBillPrediction => _monthlyBillPrediction;
  List<EnergyRecommendation> get recommendations =>
      _recommendations ?? const [];

  List<TariffVersion> _tariffVersions = const [];
  ForecastStatus _tariffStatus = ForecastStatus.idle;
  String? _tariffError;

  List<TariffVersion> get tariffVersions => _tariffVersions;
  ForecastStatus get tariffStatus => _tariffStatus;
  String? get tariffError => _tariffError;

  AIModelReport? _modelReport;
  ForecastStatus _modelReportStatus = ForecastStatus.idle;
  String? _modelReportError;

  AIModelReport? get modelReport => _modelReport;
  ForecastStatus get modelReportStatus => _modelReportStatus;
  String? get modelReportError => _modelReportError;

  TariffMonitorStatus? _tariffMonitor;
  ForecastStatus _tariffMonitorStatus = ForecastStatus.idle;
  String? _tariffMonitorError;

  TariffMonitorStatus? get tariffMonitor => _tariffMonitor;
  ForecastStatus get tariffMonitorStatus => _tariffMonitorStatus;
  String? get tariffMonitorError => _tariffMonitorError;

  void updateSensor(SensorModel newSensor) {
    _sensor = newSensor;
    notifyListeners();
  }

  void startDevicePolling() {
    if (_deviceTimer != null) return;
    pollDevice();
    _deviceTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => pollDevice(),
    );
  }

  Future<void> pollDevice() async {
    if (_deviceRequestInProgress) return;
    _deviceRequestInProgress = true;
    try {
      final reading = await _esp32Service.fetchLatest();
      _sensor = reading.sensor;
      _actualUsageCostLkr = reading.usageCostLkr;
      _todayUsageKwh = reading.todayUsageKwh;
      _hasRecharged = reading.hasRecharged;
      _minimumRechargeLkr = reading.minimumRechargeLkr;
      _demoZeroBalance = reading.demoZeroBalance;
      _actualBalanceLkr = reading.actualBalanceLkr;
      _demoBalanceExpiresAt = reading.demoExpiresAt;
      _deviceUpdatedAt = reading.receivedAt;
      final age = DateTime.now().difference(reading.receivedAt);
      _deviceStatus = age.inSeconds <= 10
          ? DeviceStatus.online
          : DeviceStatus.offline;
      _deviceError = age.inSeconds <= 10
          ? null
          : 'The latest reading is more than 10 seconds old';
      _deviceReadingCount += 1;
      if (_deviceReadingCount % 3 == 0) {
        loadAlerts();
      }
      if (_deviceReadingCount % 15 == 0) {
        loadAIOverview();
      }
    } catch (error) {
      _deviceStatus = DeviceStatus.offline;
      _deviceError = error.toString();
    } finally {
      _deviceRequestInProgress = false;
      notifyListeners();
    }
  }

  Future<DemoRechargeReceipt> recharge(double amount) async {
    final receipt = await _esp32Service.recharge(amountLkr: amount);
    _sensor = _sensor.copyWith(balance: receipt.balanceLkr);
    _actualBalanceLkr = receipt.balanceLkr;
    _demoZeroBalance = false;
    _demoBalanceExpiresAt = null;
    _hasRecharged = true;
    _minimumRechargeLkr = 100;
    _rechargeReceipts = [
      receipt,
      ..._rechargeReceipts.where((item) => item.id != receipt.id),
    ];
    notifyListeners();
    await loadRechargeHistory();
    await loadAIOverview();
    return receipt;
  }

  Future<void> loadRechargeHistory() async {
    _rechargeHistoryStatus = ForecastStatus.loading;
    _rechargeHistoryError = null;
    notifyListeners();
    try {
      _rechargeReceipts = await _esp32Service.fetchRechargeHistory();
      _rechargeHistoryStatus = ForecastStatus.loaded;
    } catch (error) {
      _rechargeHistoryStatus = ForecastStatus.offline;
      _rechargeHistoryError = error.toString();
    }
    notifyListeners();
  }

  Future<void> setRelay(bool enabled) async {
    if (_relayCommandInProgress) return;
    _relayCommandInProgress = true;
    _relayCommandError = null;
    notifyListeners();
    try {
      await _esp32Service.setRelayCommand(enabled: enabled);
      // The command is only a request. The ESP32 can still reject an ON
      // request because of credit or a local safety condition, so the UI must
      // continue showing the last hardware-reported relay state.
      await pollDevice();
    } catch (error) {
      _relayCommandError = error.toString();
      rethrow;
    } finally {
      _relayCommandInProgress = false;
      notifyListeners();
    }
  }

  Future<void> loadTheftSecurity() async {
    _theftSecurityStatus = ForecastStatus.loading;
    _theftSecurityError = null;
    notifyListeners();
    try {
      _theftSecurity = await _esp32Service.fetchTheftSecurity();
      _theftSecurityStatus = ForecastStatus.loaded;
    } catch (error) {
      _theftSecurityStatus = ForecastStatus.offline;
      _theftSecurityError = error.toString();
    }
    notifyListeners();
  }

  Future<void> setManualTheftProtection(bool enabled) async {
    _theftSecurityStatus = ForecastStatus.loading;
    _theftSecurityError = null;
    notifyListeners();
    try {
      _theftSecurity = await _esp32Service.setManualTheftProtection(
        enabled: enabled,
      );
      _theftSecurityStatus = ForecastStatus.loaded;
    } catch (error) {
      _theftSecurityStatus = ForecastStatus.offline;
      _theftSecurityError = error.toString();
      rethrow;
    } finally {
      notifyListeners();
    }
  }

  Future<void> runSimulation(String scenario) async {
    if (_simulationScenario != null) return;
    _simulationScenario = scenario;
    _simulationMessage = null;
    notifyListeners();
    try {
      _simulationMessage = await _esp32Service.runSimulation(scenario);
      await loadAlerts();
      await loadAIOverview();
    } catch (error) {
      _simulationMessage = error.toString();
      rethrow;
    } finally {
      _simulationScenario = null;
      notifyListeners();
    }
  }

  Future<DemoZeroBalanceStatus> setDemoZeroBalance(bool enabled) async {
    if (_demoBalanceInProgress) {
      throw StateError('The presentation safety test is already updating');
    }
    _demoBalanceInProgress = true;
    _demoBalanceError = null;
    notifyListeners();
    try {
      final status = await _esp32Service.setDemoZeroBalance(enabled: enabled);
      _demoZeroBalance = status.active;
      _actualBalanceLkr = status.actualBalanceLkr;
      _demoBalanceExpiresAt = status.expiresAt;
      _sensor = _sensor.copyWith(balance: status.displayedBalanceLkr);
      await pollDevice();
      await loadAlerts();
      return status;
    } catch (error) {
      _demoBalanceError = error.toString();
      rethrow;
    } finally {
      _demoBalanceInProgress = false;
      notifyListeners();
    }
  }

  Future<void> loadEnergyForecast() async {
    _forecastStatus = ForecastStatus.loading;
    _forecastError = null;
    notifyListeners();
    try {
      _energyForecast = await _aiService.fetchEnergyForecast(
        balanceLkr: _sensor.balance,
      );
      _forecastStatus = ForecastStatus.loaded;
    } catch (error) {
      _forecastStatus = ForecastStatus.offline;
      _forecastError = error.toString();
    }
    notifyListeners();
  }

  Future<void> loadAnomalyDetection() async {
    _anomalyStatus = ForecastStatus.loading;
    _anomalyError = null;
    notifyListeners();
    try {
      _anomalyDetection = await _aiService.fetchAnomalyDetection();
      _anomalyStatus = ForecastStatus.loaded;
    } catch (error) {
      _anomalyStatus = ForecastStatus.offline;
      _anomalyError = error.toString();
    }
    notifyListeners();
  }

  Future<void> loadApplianceDetections() async {
    _applianceStatus = ForecastStatus.loading;
    _applianceError = null;
    notifyListeners();
    try {
      _applianceDetection = await _aiService.fetchApplianceDetections();
      _applianceStatus = ForecastStatus.loaded;
    } catch (error) {
      _applianceStatus = ForecastStatus.offline;
      _applianceError = error.toString();
    }
    notifyListeners();
  }

  Future<void> loadSafetyPrediction() async {
    _safetyStatus = ForecastStatus.loading;
    _safetyError = null;
    notifyListeners();
    try {
      _safetyPrediction = await _aiService.fetchSafetyPrediction();
      _safetyStatus = ForecastStatus.loaded;
    } catch (error) {
      _safetyStatus = ForecastStatus.offline;
      _safetyError = error.toString();
    }
    notifyListeners();
  }

  Future<void> loadAIOverview() async {
    _forecastStatus = ForecastStatus.loading;
    _anomalyStatus = ForecastStatus.loading;
    _applianceStatus = ForecastStatus.loading;
    _safetyStatus = ForecastStatus.loading;
    notifyListeners();
    try {
      final overview = await _aiService.fetchAIOverview(
        balanceLkr: _sensor.balance,
        monthlyUsageKwh: _sensor.energy,
      );
      _energyForecast = overview.energy;
      _anomalyDetection = overview.anomaly;
      _applianceDetection = overview.appliances;
      _safetyPrediction = overview.safety;
      _balanceDepletion = overview.balanceDepletion;
      _monthlyBillPrediction = overview.monthlyBillPrediction;
      _recommendations = overview.recommendations;
      _forecastStatus = ForecastStatus.loaded;
      _anomalyStatus = ForecastStatus.loaded;
      _applianceStatus = ForecastStatus.loaded;
      _safetyStatus = ForecastStatus.loaded;
    } catch (error) {
      _forecastError = error.toString();
      _anomalyError = error.toString();
      _applianceError = error.toString();
      _safetyError = error.toString();
      _forecastStatus = ForecastStatus.offline;
      _anomalyStatus = ForecastStatus.offline;
      _applianceStatus = ForecastStatus.offline;
      _safetyStatus = ForecastStatus.offline;
    }
    notifyListeners();
  }

  Future<void> loadModelReport() async {
    _modelReportStatus = ForecastStatus.loading;
    _modelReportError = null;
    notifyListeners();
    try {
      _modelReport = await _aiService.fetchModelReport();
      _modelReportStatus = ForecastStatus.loaded;
    } catch (error) {
      _modelReportStatus = ForecastStatus.offline;
      _modelReportError = error.toString();
    }
    notifyListeners();
  }

  Future<void> loadTariffs() async {
    _tariffStatus = ForecastStatus.loading;
    _tariffError = null;
    notifyListeners();
    try {
      _tariffVersions = await _aiService.fetchTariffHistory();
      _tariffStatus = ForecastStatus.loaded;
    } catch (error) {
      _tariffStatus = ForecastStatus.offline;
      _tariffError = error.toString();
    }
    notifyListeners();
  }

  Future<void> verifyTariff(String id) async {
    await _aiService.verifyTariff(id);
    await loadTariffs();
  }

  Future<void> activateTariff(String id) async {
    await _aiService.activateTariff(id);
    await Future.wait([loadTariffs(), loadAIOverview()]);
  }

  Future<void> loadTariffMonitor() async {
    _tariffMonitorStatus = ForecastStatus.loading;
    _tariffMonitorError = null;
    notifyListeners();
    try {
      _tariffMonitor = await _aiService.fetchTariffMonitor();
      _tariffMonitorStatus = ForecastStatus.loaded;
    } catch (error) {
      _tariffMonitorStatus = ForecastStatus.offline;
      _tariffMonitorError = error.toString();
    }
    notifyListeners();
  }

  Future<void> checkTariffMonitor() async {
    _tariffMonitorStatus = ForecastStatus.loading;
    _tariffMonitorError = null;
    notifyListeners();
    try {
      _tariffMonitor = await _aiService.checkTariffMonitor();
      _tariffMonitorStatus = ForecastStatus.loaded;
    } catch (error) {
      _tariffMonitorStatus = ForecastStatus.offline;
      _tariffMonitorError = error.toString();
      notifyListeners();
      rethrow;
    }
    notifyListeners();
  }

  Future<void> loadAlerts() async {
    _alertsStatus = ForecastStatus.loading;
    _alertsError = null;
    try {
      final result = await _esp32Service.fetchAlerts();
      _notifyForNewAlerts(result.alerts);
      _liveAlerts = result.alerts;
      _unacknowledgedAlertCount = result.activeUnacknowledgedCount;
      _alertsStatus = ForecastStatus.loaded;
    } catch (error) {
      _alertsStatus = ForecastStatus.offline;
      _alertsError = error.toString();
    }
    notifyListeners();
  }

  Future<bool> enableBrowserNotifications(bool enabled) async {
    if (!enabled) {
      _notificationsEnabled = false;
      notifyListeners();
      return true;
    }
    _notificationsEnabled = await _notificationService.requestPermission();
    if (_notificationsEnabled) {
      _notificationService.show(
        title: 'Wattly notifications enabled',
        body: 'Safety alerts will appear on this device.',
      );
    }
    notifyListeners();
    return _notificationsEnabled;
  }

  void _notifyForNewAlerts(List<LiveAlert> alerts) {
    final active = alerts.where(
      (alert) => alert.status == 'active' && !alert.acknowledged,
    );
    if (!_alertsInitializedForNotifications) {
      _knownAlertIds.addAll(active.map((alert) => alert.id));
      _alertsInitializedForNotifications = true;
      return;
    }
    for (final alert in active) {
      if (!_knownAlertIds.add(alert.id) || !_notificationsEnabled) continue;
      _notificationService.show(
        title: '${alert.severity}: ${alert.title}',
        body: alert.message,
      );
    }
  }

  Future<void> acknowledgeAlert(String alertId) async {
    await _esp32Service.acknowledgeAlert(alertId);
    await loadAlerts();
    await pollDevice();
    await loadAIOverview();
  }

  Future<void> acknowledgeAllAlerts() async {
    await _esp32Service.acknowledgeAllAlerts();
    await loadAlerts();
    await pollDevice();
    await loadAIOverview();
  }

  @override
  void dispose() {
    _deviceTimer?.cancel();
    super.dispose();
  }
}
