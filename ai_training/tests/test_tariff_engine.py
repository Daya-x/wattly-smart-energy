import json
import tempfile
import sys
import unittest
from copy import deepcopy
from datetime import date
from pathlib import Path


SRC = Path(__file__).resolve().parents[1] / "src"
sys.path.insert(0, str(SRC))

from tariff_engine import (  # noqa: E402
    activate_tariff,
    active_tariff,
    create_tariff_draft,
    validate_tariff_configuration,
    verify_tariff,
)


class SriLankaDomesticTariffTests(unittest.TestCase):
    def setUp(self):
        self.engine = active_tariff()

    def test_official_block_examples(self):
        expected = {
            30: 230.00,
            60: 630.00,
            90: 1840.00,
            120: 3280.00,
            180: 6420.00,
            240: 10920.00,
        }
        for usage, bill in expected.items():
            with self.subTest(usage=usage):
                self.assertEqual(
                    self.engine.calculate_monthly_bill(usage).total_lkr,
                    bill,
                )

    def test_crossing_60_units_reprices_standard_blocks(self):
        self.assertEqual(
            self.engine.incremental_cost(60, 1),
            630.00,
        )

    def test_zero_and_negative_usage(self):
        self.assertEqual(
            self.engine.calculate_monthly_bill(0).total_lkr,
            0,
        )
        with self.assertRaises(ValueError):
            self.engine.calculate_monthly_bill(-1)

    def test_balance_depletion_is_positive(self):
        days = self.engine.estimate_balance_days(
            balance_lkr=850,
            daily_usage_kwh=25.545,
            current_month_kwh=4.8,
            billing_days_elapsed=1,
        )
        self.assertGreater(days, 0)

    def test_configuration_passes_regression_bills(self):
        results = validate_tariff_configuration(self.engine.configuration)
        self.assertTrue(all(item["passed"] for item in results))

    def test_changed_rate_cannot_pass_stale_regression_bills(self):
        changed = deepcopy(self.engine.configuration)
        changed["low_user"]["blocks"][0]["rate_lkr_per_kwh"] = 6
        with self.assertRaisesRegex(ValueError, "regression"):
            validate_tariff_configuration(changed)

    def test_unofficial_source_is_rejected(self):
        changed = deepcopy(self.engine.configuration)
        changed["source_url"] = "https://example.com/tariff.pdf"
        with self.assertRaisesRegex(ValueError, "official"):
            validate_tariff_configuration(changed)

    def test_draft_verify_activate_lifecycle(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            current = deepcopy(self.engine.configuration)
            (directory / f"{current['id']}.json").write_text(
                json.dumps(current)
            )
            replacement = deepcopy(current)
            replacement["id"] = "lk_domestic_block_2026_06_01"
            replacement["effective_from"] = "2026-06-01"
            replacement["status"] = "active"

            draft = create_tariff_draft(replacement, directory)
            self.assertEqual(draft["status"], "draft")
            verified, checks = verify_tariff(replacement["id"], directory)
            self.assertEqual(verified["status"], "verified")
            self.assertTrue(all(item["passed"] for item in checks))
            activated = activate_tariff(
                replacement["id"], directory, date(2026, 6, 2)
            )
            self.assertEqual(activated["status"], "active")
            self.assertEqual(
                active_tariff(date(2026, 6, 2), directory).id,
                replacement["id"],
            )
            archived = json.loads(
                (directory / f"{current['id']}.json").read_text()
            )
            self.assertEqual(archived["status"], "archived")
            self.assertEqual(archived["effective_to"], "2026-05-31")
            audit = (directory / "audit_log.jsonl").read_text()
            self.assertIn("draft_created", audit)
            self.assertIn("draft_verified", audit)
            self.assertIn("tariff_activated", audit)


if __name__ == "__main__":
    unittest.main()
