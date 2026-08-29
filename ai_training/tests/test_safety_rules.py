import sys
import unittest
from pathlib import Path


SRC = Path(__file__).resolve().parents[1] / "src"
sys.path.insert(0, str(SRC))

from safety_rules import active_conditions, live_safety_summary  # noqa: E402


def reading(**changes):
    result = {
        "voltage": 230,
        "current": 0.1,
        "power": 20,
        "temperature": 29,
        "humidity": 70,
        "gas": 1200,
        "balance_lkr": 850,
    }
    result.update(changes)
    return result


class LiveSafetyRuleTests(unittest.TestCase):
    def test_normal_hardware_reading_is_low_risk(self):
        summary = live_safety_summary(reading())
        self.assertEqual(summary["risk_level"], "low")
        self.assertEqual(summary["active_conditions"], [])

    def test_each_danger_scenario_creates_expected_condition(self):
        self.assertIn("gas", active_conditions(reading(gas=2700)))
        self.assertIn(
            "temperature", active_conditions(reading(temperature=56))
        )
        self.assertIn("power", active_conditions(reading(power=5100)))
        self.assertIn("voltage", active_conditions(reading(voltage=175)))

    def test_warning_is_not_reported_as_critical(self):
        conditions = active_conditions(reading(power=2200))
        self.assertEqual(conditions["power"]["severity"], "Warning")

    def test_empty_balance_creates_critical_recharge_alert(self):
        conditions = active_conditions(reading(balance_lkr=0))
        self.assertEqual(conditions["balance"]["severity"], "Critical")
        self.assertEqual(conditions["balance"]["title"], "Recharge required")

    def test_failed_hardware_sensors_create_clear_critical_alerts(self):
        conditions = active_conditions(
            reading(pzem_valid=False, dht_valid=False, voltage=0)
        )
        self.assertEqual(conditions["sensor_pzem"]["severity"], "Critical")
        self.assertEqual(conditions["sensor_dht"]["severity"], "Critical")
        # A zero placeholder from a failed PZEM is not also presented as a
        # genuine unsafe-voltage measurement.
        self.assertNotIn("voltage", conditions)
        self.assertEqual(
            live_safety_summary(
                reading(pzem_valid=False, dht_valid=False, voltage=0)
            )["risk_level"],
            "high",
        )

    def test_recovery_margin_prevents_threshold_jitter(self):
        # Gas warning begins at 1600, but an open incident stays open until
        # the reading has recovered below 1450.
        self.assertNotIn("gas", active_conditions(reading(gas=1500)))
        self.assertIn(
            "gas", active_conditions(reading(gas=1500), recovery=True)
        )


if __name__ == "__main__":
    unittest.main()
