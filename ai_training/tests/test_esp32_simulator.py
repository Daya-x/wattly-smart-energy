import random
import sys
import unittest
from pathlib import Path


SRC = Path(__file__).resolve().parents[1] / "src"
sys.path.insert(0, str(SRC))

from esp32_simulator import generate_reading  # noqa: E402


class Esp32SimulatorTests(unittest.TestCase):
    def test_normal_reading_is_in_sensor_range(self):
        reading = generate_reading(1, 4.8, rng=random.Random(1))
        self.assertTrue(220 <= reading["voltage"] <= 240)
        self.assertGreater(reading["power"], 0)
        self.assertTrue(0 <= reading["humidity"] <= 100)

    def test_alert_scenarios_raise_the_expected_signal(self):
        gas = generate_reading(8, 4.8, "gas_alert", random.Random(1))
        hot = generate_reading(8, 4.8, "overheat", random.Random(1))
        spike = generate_reading(8, 4.8, "power_spike", random.Random(1))
        self.assertGreater(gas["gas"], 700)
        self.assertGreater(hot["temperature"], 50)
        self.assertGreater(spike["power"], 1500)


if __name__ == "__main__":
    unittest.main()
