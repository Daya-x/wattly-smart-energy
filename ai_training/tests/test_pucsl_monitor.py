import sys
import tempfile
import unittest
from pathlib import Path


SRC = Path(__file__).resolve().parents[1] / "src"
sys.path.insert(0, str(SRC))

from pucsl_monitor import check_pucsl, extract_tariff_publications  # noqa: E402


HTML = """
<a href="https://www.pucsl.gov.lk/wp-content/uploads/2026/05/final.pdf">
Decision on Electricity Tariff – 2026 May</a>
<a href="https://www.pucsl.gov.lk/wp-content/uploads/2026/05/schedule.pdf">
Tariff Schedule – 2026 May</a>
<a href="https://example.com/fake.pdf">Tariff Schedule – fake</a>
<a href="/proposed.pdf">Proposed Electricity Tariff Schedule</a>
"""


class PucslMonitorTests(unittest.TestCase):
    def test_only_final_official_publications_are_detected(self):
        publications = extract_tariff_publications(HTML)
        self.assertEqual(len(publications), 2)
        self.assertTrue(
            all("pucsl.gov.lk" in item["source_url"] for item in publications)
        )

    def test_check_persists_candidates_without_creating_tariffs(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            tariff_directory = root / "tariffs"
            tariff_directory.mkdir()
            state_path = root / "state.json"
            state = check_pucsl(state_path, tariff_directory, html=HTML)
            self.assertEqual(len(state["candidates"]), 2)
            self.assertTrue(state_path.exists())
            self.assertEqual(list(tariff_directory.glob("*.json")), [])


if __name__ == "__main__":
    unittest.main()
