class SensorModel {
  final double voltage;
  final double current;
  final double power;
  final double energy;

  final double temperature;
  final double humidity;

  final int gas;

  final bool motion;

  final bool relay;

  final double balance;

  final bool pzemValid;
  final bool dhtValid;

  const SensorModel({
    required this.voltage,
    required this.current,
    required this.power,
    required this.energy,
    required this.temperature,
    required this.humidity,
    required this.gas,
    required this.motion,
    required this.relay,
    required this.balance,
    this.pzemValid = true,
    this.dhtValid = true,
  });

  SensorModel copyWith({
    double? voltage,
    double? current,
    double? power,
    double? energy,
    double? temperature,
    double? humidity,
    int? gas,
    bool? motion,
    bool? relay,
    double? balance,
    bool? pzemValid,
    bool? dhtValid,
  }) => SensorModel(
    voltage: voltage ?? this.voltage,
    current: current ?? this.current,
    power: power ?? this.power,
    energy: energy ?? this.energy,
    temperature: temperature ?? this.temperature,
    humidity: humidity ?? this.humidity,
    gas: gas ?? this.gas,
    motion: motion ?? this.motion,
    relay: relay ?? this.relay,
    balance: balance ?? this.balance,
    pzemValid: pzemValid ?? this.pzemValid,
    dhtValid: dhtValid ?? this.dhtValid,
  );
}
