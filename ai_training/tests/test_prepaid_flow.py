import os
import sys
import tempfile
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path

from fastapi import HTTPException


SRC = Path(__file__).resolve().parents[1] / "src"
sys.path.insert(0, str(SRC))

IMPORT_DB = Path(tempfile.gettempdir()) / f"wattly-import-{os.getpid()}.db"
os.environ["PERSISTENCE_BACKEND"] = "sqlite"
os.environ["SQLITE_DB_PATH"] = str(IMPORT_DB)

import api  # noqa: E402
from persistence import SQLitePersistence  # noqa: E402


class PrepaidFlowTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.store = SQLitePersistence(
            Path(self.temporary.name) / "prepaid.db"
        )
        api._persistence = self.store
        api._local_persistence = self.store
        api._persistence_error = None
        api._device_accounts.clear()
        api._device_readings.clear()
        api._device_recharges.clear()
        api._active_alerts.clear()
        api._manual_alerts.clear()
        api._alerts_initialized.clear()
        api._alert_safe_streaks.clear()
        api._alert_trigger_streaks.clear()
        api._relay_commands.clear()
        api._critical_simulation_restore_relay.clear()
        api._demo_zero_balance_until.clear()
        api._last_persisted_at.clear()
        api._pending_usage.clear()

    def tearDown(self):
        self.temporary.cleanup()

    @staticmethod
    def reading(energy: float, relay: bool = False):
        return api.DeviceReading(
            voltage=230,
            current=0.1,
            power=20,
            energy=energy,
            temperature=29,
            humidity=70,
            gas=500,
            motion=False,
            relay=relay,
        )

    def test_recharge_minimums_and_history_survive_reload(self):
        with self.assertRaises(HTTPException) as first_error:
            api.recharge_device(
                "EM-2048", api.RechargeRequest(amount_lkr=100)
            )
        self.assertEqual(first_error.exception.status_code, 422)

        first = api.recharge_device(
            "EM-2048", api.RechargeRequest(amount_lkr=500)
        )
        second = api.recharge_device(
            "EM-2048", api.RechargeRequest(amount_lkr=100)
        )
        self.assertEqual(first["balance_lkr"], 500)
        self.assertEqual(second["balance_lkr"], 600)

        api._device_accounts.clear()
        api._device_recharges.clear()
        api._local_persistence = SQLitePersistence(self.store.path)
        api._persistence = api._local_persistence
        history = api.device_recharges("EM-2048")
        self.assertEqual(len(history["recharges"]), 2)
        self.assertEqual(history["recharges"][0]["amount_lkr"], 100)

    def test_usage_reduces_balance_and_zero_credit_locks_relay(self):
        api.ingest_device_reading("EM-2048", self.reading(0), None)
        api.recharge_device(
            "EM-2048", api.RechargeRequest(amount_lkr=500)
        )
        api.ingest_device_reading("EM-2048", self.reading(1), None)
        balance = api._device_accounts["EM-2048"]["balance_lkr"]
        self.assertLess(balance, 500)

        api._device_accounts["EM-2048"]["balance_lkr"] = 0.01
        api.ingest_device_reading("EM-2048", self.reading(20), None)
        self.assertEqual(
            api._device_accounts["EM-2048"]["balance_lkr"], 0
        )
        self.assertIn("balance", api._active_alerts["EM-2048"])
        self.assertFalse(
            api._relay_commands["EM-2048"]["relay_requested"]
        )

        with self.assertRaises(HTTPException) as relay_error:
            api.set_relay_command(
                "EM-2048", api.RelayCommandRequest(relay_requested=True)
            )
        self.assertEqual(relay_error.exception.status_code, 402)

        api.recharge_device(
            "EM-2048", api.RechargeRequest(amount_lkr=100)
        )
        command = api.set_relay_command(
            "EM-2048", api.RelayCommandRequest(relay_requested=True)
        )
        self.assertTrue(command["relay_requested"])

    def test_energy_prediction_accepts_day_31_calendar_date(self):
        api.load_runtime()
        result = api.predict_energy(
            balance_lkr=500,
            monthly_usage_kwh=1,
            billing_days_elapsed=31,
        )
        cycle_days = int(
            api._tariff_engine.configuration["billing_cycle_days"]
        )
        self.assertEqual(
            result["tariff"]["billing_days_elapsed"],
            cycle_days - 1,
        )

    def test_tft_and_dashboard_share_primary_recommendation(self):
        api.load_runtime()
        api.ingest_device_reading("EM-2048", self.reading(0), None)
        api.recharge_device(
            "EM-2048", api.RechargeRequest(amount_lkr=500)
        )
        account = api._device_accounts["EM-2048"]
        billing_day = max(1, api.datetime.now(api.COLOMBO).day)
        dashboard = api.predict_summary(
            balance_lkr=account["balance_lkr"],
            monthly_usage_kwh=account["monthly_usage_kwh"],
            billing_days_elapsed=billing_day,
            device_id="EM-2048",
        )
        tft = api.device_display_summary("EM-2048", None)
        primary = dashboard["recommendations"][0]

        self.assertEqual(tft["recommendation_title"], primary["title"])
        self.assertEqual(
            tft["recommendation_line_1"], primary["tft_line_1"]
        )
        self.assertEqual(
            tft["potential_saving_percent"],
            primary["potential_saving_percent"],
        )

    def test_credit_duration_waits_for_measured_history(self):
        api.load_runtime()
        summary = api.predict_summary(
            balance_lkr=1259.18,
            monthly_usage_kwh=0.35,
            billing_days_elapsed=1,
            device_id="EM-2048",
        )
        credit = summary["balance_depletion"]
        self.assertFalse(credit["ready"])
        self.assertIsNone(credit["remaining_days"])
        self.assertEqual(credit["status"], "collecting")

    def test_credit_duration_uses_recent_esp32_usage(self):
        api.load_runtime()
        now = datetime.now(timezone.utc)
        account = {"balance_lkr": 1259.18, "monthly_usage_kwh": 0.35}
        for hours_ago, delta in ((48, 0.0), (24, 0.12), (0, 0.12)):
            self.store.save_snapshot(
                "EM-2048",
                {
                    "received_at": (now - timedelta(hours=hours_ago)).isoformat(),
                    "usage_delta_kwh": delta,
                    "energy": 1.0,
                    "voltage": 230.0,
                    "current": 0.1,
                    "power": 20.0,
                    "temperature": 29.0,
                    "humidity": 70.0,
                    "gas": 500,
                    "motion": False,
                    "relay": False,
                },
                account,
            )

        summary = api.predict_summary(
            balance_lkr=1259.18,
            monthly_usage_kwh=0.35,
            billing_days_elapsed=1,
            device_id="EM-2048",
        )
        credit = summary["balance_depletion"]
        self.assertTrue(credit["ready"])
        self.assertAlmostEqual(credit["daily_usage_kwh"], 0.12, places=3)
        self.assertGreater(credit["remaining_days"], 2.8)
        self.assertEqual(credit["method"], "recent measured ESP32 usage")

    def test_relay_command_round_trip_uses_hardware_reported_state(self):
        api.ingest_device_reading("EM-2048", self.reading(0), None)
        api.recharge_device(
            "EM-2048", api.RechargeRequest(amount_lkr=500)
        )

        requested = api.set_relay_command(
            "EM-2048", api.RelayCommandRequest(relay_requested=True)
        )
        self.assertTrue(requested["relay_requested"])
        self.assertTrue(requested["credit_allowed"])

        fetched = api.get_relay_command("EM-2048", None)
        self.assertTrue(fetched["has_command"])
        self.assertTrue(fetched["relay_requested"])
        self.assertEqual(
            fetched["command_id"],
            requested["command_id"],
        )

        # The dashboard should only show ON after a reading from the ESP32
        # confirms that the physical relay actually changed.
        before_confirmation = api.latest_device_reading("EM-2048")
        self.assertFalse(before_confirmation["relay"])
        api.ingest_device_reading(
            "EM-2048", self.reading(0.01, relay=True), None
        )
        after_confirmation = api.latest_device_reading("EM-2048")
        self.assertTrue(after_confirmation["relay"])

        switched_off = api.set_relay_command(
            "EM-2048", api.RelayCommandRequest(relay_requested=False)
        )
        self.assertFalse(switched_off["relay_requested"])

    def test_failed_pzem_does_not_reset_cumulative_energy(self):
        api.ingest_device_reading("EM-2048", self.reading(10), None)
        failed = self.reading(0)
        failed.pzem_valid = False
        for _ in range(api.ALERT_CONFIRM_DANGEROUS_READINGS - 1):
            api.ingest_device_reading("EM-2048", failed, None)
            self.assertNotIn(
                "sensor_pzem", api._active_alerts["EM-2048"]
            )
        api.ingest_device_reading("EM-2048", failed, None)
        self.assertEqual(
            api._device_accounts["EM-2048"]["last_meter_energy_kwh"],
            10,
        )
        self.assertIn("sensor_pzem", api._active_alerts["EM-2048"])

    def test_confirmed_hazard_locks_relay_until_acknowledged(self):
        api.ingest_device_reading("EM-2048", self.reading(0), None)
        api.recharge_device(
            "EM-2048", api.RechargeRequest(amount_lkr=500)
        )
        high_power = self.reading(0)
        high_power.power = 2500

        for _ in range(api.ALERT_CONFIRM_DANGEROUS_READINGS):
            api.ingest_device_reading("EM-2048", high_power, None)

        incident = api._active_alerts["EM-2048"]["power"]
        incident_id = incident["id"]
        with self.assertRaises(HTTPException) as relay_error:
            api.set_relay_command(
                "EM-2048", api.RelayCommandRequest(relay_requested=True)
            )
        self.assertEqual(relay_error.exception.status_code, 423)

        api.acknowledge_device_alert("EM-2048", incident_id, None)
        command = api.set_relay_command(
            "EM-2048", api.RelayCommandRequest(relay_requested=True)
        )
        self.assertTrue(command["relay_requested"])

    def test_critical_simulation_acknowledge_persists_and_turns_relay_on(self):
        api.ingest_device_reading("EM-2048", self.reading(0, relay=False), None)
        api.recharge_device(
            "EM-2048", api.RechargeRequest(amount_lkr=500)
        )
        simulation = api.run_device_simulation(
            "EM-2048", api.SimulationRequest(scenario="power")
        )
        alert_id = simulation["alert"]["id"]
        self.assertFalse(api._relay_commands["EM-2048"]["relay_requested"])

        result = api.acknowledge_device_alert("EM-2048", alert_id, None)

        self.assertTrue(result["acknowledged"])
        self.assertTrue(result["relay_restored"])
        self.assertTrue(api._relay_commands["EM-2048"]["relay_requested"])
        stored = next(
            alert
            for alert in self.store.list_alerts("EM-2048", 10)
            if alert["id"] == alert_id
        )
        self.assertTrue(stored["acknowledged"])

    def test_firmware_confirmation_applies_only_to_named_hazard(self):
        mixed = self.reading(0)
        mixed.gas = 1800
        mixed.power = 2500
        mixed.safety_confirmed = True
        mixed.confirmed_hazards = ["gas"]

        api.ingest_device_reading("EM-2048", mixed, None)
        self.assertIn("gas", api._active_alerts["EM-2048"])
        self.assertNotIn("power", api._active_alerts["EM-2048"])

    def test_hazard_is_one_incident_and_auto_resolves_after_safe_streak(self):
        api.ingest_device_reading("EM-2048", self.reading(0), None)
        high_power = self.reading(0)
        high_power.power = 2500
        for _ in range(api.ALERT_CONFIRM_DANGEROUS_READINGS):
            api.ingest_device_reading("EM-2048", high_power, None)
        incident_id = api._active_alerts["EM-2048"]["power"]["id"]

        api.ingest_device_reading("EM-2048", high_power, None)
        self.assertEqual(
            api._active_alerts["EM-2048"]["power"]["id"], incident_id
        )
        for _ in range(api.ALERT_RESOLVE_SAFE_READINGS - 1):
            api.ingest_device_reading("EM-2048", self.reading(0), None)
            self.assertIn("power", api._active_alerts["EM-2048"])
        api.ingest_device_reading("EM-2048", self.reading(0), None)
        self.assertNotIn("power", api._active_alerts["EM-2048"])

    def test_zero_balance_demo_preserves_credit_and_locks_relay(self):
        api.ingest_device_reading("EM-2048", self.reading(0), None)
        api.recharge_device(
            "EM-2048", api.RechargeRequest(amount_lkr=500)
        )

        started = api.set_demo_zero_balance(
            "EM-2048",
            api.DemoZeroBalanceRequest(
                enabled=True,
                duration_seconds=300,
            ),
            None,
        )
        self.assertTrue(started["demo_zero_balance"])
        self.assertEqual(started["balance_lkr"], 0)
        self.assertEqual(started["actual_balance_lkr"], 500)

        latest = api.latest_device_reading("EM-2048")
        self.assertEqual(latest["balance_lkr"], 0)
        self.assertEqual(latest["actual_balance_lkr"], 500)
        self.assertTrue(latest["demo_zero_balance"])

        with self.assertRaises(HTTPException) as relay_error:
            api.set_relay_command(
                "EM-2048",
                api.RelayCommandRequest(relay_requested=True),
            )
        self.assertEqual(relay_error.exception.status_code, 402)
        command = api.get_relay_command("EM-2048", None)
        self.assertFalse(command["relay_requested"])
        self.assertFalse(command["credit_allowed"])

        alerts = api.device_alerts("EM-2048")
        demo_alerts = [
            item
            for item in alerts["alerts"]
            if item.get("source") == "demo_zero_balance"
        ]
        self.assertEqual(len(demo_alerts), 1)
        self.assertEqual(demo_alerts[0]["status"], "active")

        restored = api.set_demo_zero_balance(
            "EM-2048",
            api.DemoZeroBalanceRequest(enabled=False),
            None,
        )
        self.assertFalse(restored["demo_zero_balance"])
        self.assertEqual(restored["balance_lkr"], 500)
        latest = api.latest_device_reading("EM-2048")
        self.assertEqual(latest["balance_lkr"], 500)
        self.assertFalse(latest["demo_zero_balance"])

        command = api.set_relay_command(
            "EM-2048",
            api.RelayCommandRequest(relay_requested=True),
        )
        self.assertTrue(command["relay_requested"])

        api.set_demo_zero_balance(
            "EM-2048",
            api.DemoZeroBalanceRequest(enabled=True),
            None,
        )
        api._demo_zero_balance_until["EM-2048"] = (
            api.datetime.now(api.timezone.utc) - api.timedelta(seconds=1)
        )
        expired = api.latest_device_reading("EM-2048")
        self.assertFalse(expired["demo_zero_balance"])
        self.assertEqual(expired["balance_lkr"], 500)


if __name__ == "__main__":
    unittest.main()
