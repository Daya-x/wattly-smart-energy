"""Transparent safety rules for calibrated live meter readings."""

from __future__ import annotations


# MQ-2 modules output raw ADC values that vary a lot by board, heater warm-up,
# load resistor, and the small sensitivity potentiometer on the module. This
# prototype treats the raw value as a calibrated threshold, not gas ppm. Dayalan's
# clean-air hardware sits around 1100-1300, so warning must be above that range.
GAS_WARNING_RAW = 1600
GAS_CRITICAL_RAW = 2600
TEMPERATURE_WARNING_C = 45.0
TEMPERATURE_CRITICAL_C = 55.0
POWER_WARNING_W = 2000.0
POWER_CRITICAL_W = 5000.0
VOLTAGE_LOW_WARNING = 200.0
VOLTAGE_HIGH_WARNING = 250.0
VOLTAGE_LOW_CRITICAL = 180.0
VOLTAGE_HIGH_CRITICAL = 260.0
LOW_BALANCE_WARNING_LKR = 500.0
LOW_BALANCE_CRITICAL_LKR = 0.01


def active_conditions(reading: dict, *, recovery: bool = False) -> dict[str, dict]:
    """Return current hazards.

    ``recovery=True`` applies a small safe-side margin.  An incident therefore
    does not repeatedly open and close when a sensor sits on a threshold.
    """
    conditions: dict[str, dict] = {}
    pzem_valid = bool(reading.get("pzem_valid", True))
    dht_valid = bool(reading.get("dht_valid", True))
    gas = int(reading["gas"])
    temperature = float(reading["temperature"])
    power = float(reading["power"])
    voltage = float(reading["voltage"])
    balance = float(reading.get("balance_lkr", 0.0))

    if not pzem_valid:
        conditions["sensor_pzem"] = {
            "severity": "Critical",
            "title": "Energy sensor unavailable",
            "message": "PZEM-004T communication failed. Relay output is kept off.",
            "value": 0,
            "unit": "status",
            "threshold": 1,
        }
    if not dht_valid:
        conditions["sensor_dht"] = {
            "severity": "Critical",
            "title": "Temperature sensor unavailable",
            "message": "DHT22 communication failed. Check its power and DATA connection.",
            "value": 0,
            "unit": "status",
            "threshold": 1,
        }

    balance_warning = (
        LOW_BALANCE_WARNING_LKR + 25.0 if recovery else LOW_BALANCE_WARNING_LKR
    )
    gas_warning = GAS_WARNING_RAW - 150 if recovery else GAS_WARNING_RAW
    temperature_warning = (
        TEMPERATURE_WARNING_C - 2.0 if recovery else TEMPERATURE_WARNING_C
    )
    power_warning = POWER_WARNING_W - 200.0 if recovery else POWER_WARNING_W
    voltage_low_warning = (
        VOLTAGE_LOW_WARNING + 5.0 if recovery else VOLTAGE_LOW_WARNING
    )
    voltage_high_warning = (
        VOLTAGE_HIGH_WARNING - 5.0 if recovery else VOLTAGE_HIGH_WARNING
    )

    if balance < balance_warning:
        critical = balance < LOW_BALANCE_CRITICAL_LKR
        conditions["balance"] = {
            "severity": "Critical" if critical else "Warning",
            "title": "Recharge required" if critical else "Low prepaid balance",
            "message": (
                "Credit is empty. Relay output is locked until recharge."
                if critical
                else f"Available prepaid credit is Rs. {balance:.2f}"
            ),
            "value": round(balance, 2),
            "unit": "LKR",
            "threshold": (
                LOW_BALANCE_CRITICAL_LKR
                if critical
                else LOW_BALANCE_WARNING_LKR
            ),
        }

    if gas >= gas_warning:
        critical = gas >= GAS_CRITICAL_RAW
        conditions["gas"] = {
            "severity": "Critical" if critical else "Warning",
            "title": "Dangerous gas level" if critical else "Gas level elevated",
            "message": f"MQ-2 raw reading is {gas}",
            "value": gas,
            "unit": "raw",
            "threshold": GAS_CRITICAL_RAW if critical else GAS_WARNING_RAW,
        }
    if dht_valid and temperature >= temperature_warning:
        critical = temperature >= TEMPERATURE_CRITICAL_C
        conditions["temperature"] = {
            "severity": "Critical" if critical else "Warning",
            "title": "Meter overheating" if critical else "Temperature elevated",
            "message": f"Enclosure temperature is {temperature:.1f} °C",
            "value": round(temperature, 2),
            "unit": "°C",
            "threshold": (
                TEMPERATURE_CRITICAL_C if critical else TEMPERATURE_WARNING_C
            ),
        }
    if pzem_valid and power >= power_warning:
        critical = power >= POWER_CRITICAL_W
        conditions["power"] = {
            "severity": "Critical" if critical else "Warning",
            "title": "Dangerous power demand" if critical else "High power usage",
            "message": f"Active power is {power:.0f} W",
            "value": round(power, 2),
            "unit": "W",
            "threshold": POWER_CRITICAL_W if critical else POWER_WARNING_W,
        }
    voltage_danger = voltage <= VOLTAGE_LOW_CRITICAL or voltage >= VOLTAGE_HIGH_CRITICAL
    voltage_warning = voltage < voltage_low_warning or voltage > voltage_high_warning
    if pzem_valid and voltage_warning:
        conditions["voltage"] = {
            "severity": "Critical" if voltage_danger else "Warning",
            "title": "Unsafe supply voltage" if voltage_danger else "Voltage outside range",
            "message": f"Supply voltage is {voltage:.1f} V",
            "value": round(voltage, 2),
            "unit": "V",
            "threshold": (
                VOLTAGE_LOW_CRITICAL
                if voltage < VOLTAGE_LOW_WARNING and voltage_danger
                else VOLTAGE_LOW_WARNING
                if voltage < VOLTAGE_LOW_WARNING
                else VOLTAGE_HIGH_CRITICAL
                if voltage_danger
                else VOLTAGE_HIGH_WARNING
            ),
        }
    return conditions


def live_safety_summary(reading: dict) -> dict:
    conditions = active_conditions(reading)
    gas = int(reading["gas"])
    temperature = float(reading["temperature"])
    power = float(reading["power"])
    voltage = float(reading["voltage"])

    pzem_valid = bool(reading.get("pzem_valid", True))
    dht_valid = bool(reading.get("dht_valid", True))
    gas_risk = _risk(gas, GAS_WARNING_RAW, GAS_CRITICAL_RAW)
    temperature_risk = (
        _risk(temperature, TEMPERATURE_WARNING_C, TEMPERATURE_CRITICAL_C)
        if dht_valid
        else 1.0
    )
    power_risk = (
        _risk(power, POWER_WARNING_W, POWER_CRITICAL_W)
        if pzem_valid
        else 1.0
    )
    if not pzem_valid:
        voltage_risk = 1.0
    elif voltage < VOLTAGE_LOW_WARNING:
        voltage_risk = _inverse_risk(
            voltage, VOLTAGE_LOW_WARNING, VOLTAGE_LOW_CRITICAL
        )
    elif voltage > VOLTAGE_HIGH_WARNING:
        voltage_risk = _risk(
            voltage, VOLTAGE_HIGH_WARNING, VOLTAGE_HIGH_CRITICAL
        )
    else:
        voltage_risk = 0.0
    electrical_risk = max(power_risk, voltage_risk)
    overall = max(gas_risk, temperature_risk, electrical_risk)
    risk_level = "high" if overall >= 0.7 else "moderate" if overall >= 0.3 else "low"
    electrical_condition = (
        "Energy sensor unavailable"
        if not pzem_valid
        else "High power"
        if "power" in conditions
        else "Voltage outside range"
        if "voltage" in conditions
        else "Normal"
    )
    return {
        "risk_level": risk_level,
        "overall_risk_probability": round(overall, 4),
        "fire_probability": 0.0,
        "electrical_fault_probability": round(electrical_risk, 4),
        "temperature_risk_probability": round(temperature_risk, 4),
        "gas_risk_probability": round(gas_risk, 4),
        "electrical_condition": electrical_condition,
        "gas_identity": "MQ-2 raw reading",
        "gas_identity_confidence": 0.0,
        "gas_leak_probability_available": False,
        "active_conditions": list(conditions),
        "quality": "live_threshold_rules",
        "source": "live_device_reading",
    }


def _risk(value: float, warning: float, critical: float) -> float:
    if value < warning:
        return 0.0
    if value >= critical:
        return 1.0
    return 0.3 + 0.7 * (value - warning) / (critical - warning)


def _inverse_risk(value: float, warning: float, critical: float) -> float:
    if value > warning:
        return 0.0
    if value <= critical:
        return 1.0
    return 0.3 + 0.7 * (warning - value) / (warning - critical)
