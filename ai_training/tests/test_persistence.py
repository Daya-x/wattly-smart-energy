import sys
import tempfile
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path


SRC = Path(__file__).resolve().parents[1] / "src"
sys.path.insert(0, str(SRC))

from persistence import SQLitePersistence  # noqa: E402


class PersistenceTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.store = SQLitePersistence(
            Path(self.temporary.name) / "meter.db"
        )
        self.now = datetime.now(timezone.utc)
        self.account = {
            "balance_lkr": 849.5,
            "monthly_usage_kwh": 5.0,
        }
        self.reading = {
            "received_at": self.now.isoformat(),
            "usage_delta_kwh": 0.2,
            "power": 300,
        }

    def tearDown(self):
        self.temporary.cleanup()

    def test_snapshot_and_account_survive_new_store_instance(self):
        self.store.save_snapshot("EM-2048", self.reading, self.account)
        reopened = SQLitePersistence(self.store.path)
        self.assertEqual(
            reopened.load_account("EM-2048")["balance_lkr"], 849.5
        )
        self.assertEqual(
            reopened.latest_reading("EM-2048")["power"], 300
        )

    def test_time_range_and_recharge_are_persisted(self):
        self.store.save_snapshot("EM-2048", self.reading, self.account)
        rows = self.store.readings_between(
            "EM-2048",
            self.now - timedelta(minutes=1),
            self.now + timedelta(minutes=1),
        )
        self.assertEqual(len(rows), 1)
        updated = dict(self.account, balance_lkr=1349.5)
        recharge = {
            "receipt_id": "DEMO-TEST-1",
            "amount_lkr": 500,
            "created_at": self.now.isoformat(),
        }
        self.store.record_recharge("EM-2048", recharge, updated)
        self.assertEqual(
            self.store.load_account("EM-2048")["balance_lkr"], 1349.5
        )
        reopened = SQLitePersistence(self.store.path)
        history = reopened.list_recharges("EM-2048")
        self.assertEqual(len(history), 1)
        self.assertEqual(history[0]["receipt_id"], "DEMO-TEST-1")
        self.assertEqual(history[0]["amount_lkr"], 500)

    def test_alert_lifecycle_is_persisted(self):
        alert = {
            "id": "alert-1",
            "type": "gas",
            "status": "active",
            "acknowledged": False,
            "created_at": self.now.isoformat(),
            "updated_at": self.now.isoformat(),
        }
        self.store.save_alert("EM-2048", alert)
        self.assertEqual(len(self.store.list_alerts("EM-2048")), 1)
        self.assertTrue(
            self.store.acknowledge_alert("EM-2048", "alert-1")
        )
        saved = self.store.list_alerts("EM-2048")[0]
        self.assertTrue(saved["acknowledged"])


if __name__ == "__main__":
    unittest.main()
