"""Detect official PUCSL end-user tariff publications without changing rates."""

from __future__ import annotations

import hashlib
import json
import re
import subprocess
import threading
import time
from datetime import datetime, timezone
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import urljoin, urlparse

from tariff_engine import TARIFF_DIR, available_tariffs


PUCSL_INDEX_URL = "https://www.pucsl.gov.lk/end-user-tariff-decisions/"
MONITOR_STATE = TARIFF_DIR / "pucsl_monitor_state.json"
MONTHS = {
    name.lower(): number
    for number, name in enumerate(
        (
            "",
            "January",
            "February",
            "March",
            "April",
            "May",
            "June",
            "July",
            "August",
            "September",
            "October",
            "November",
            "December",
        )
    )
    if name
}


class _LinkParser(HTMLParser):
    def __init__(self) -> None:
        super().__init__()
        self.links: list[tuple[str, str]] = []
        self._href: str | None = None
        self._text: list[str] = []

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        if tag.lower() != "a":
            return
        self._href = dict(attrs).get("href")
        self._text = []

    def handle_data(self, data: str) -> None:
        if self._href is not None:
            self._text.append(data)

    def handle_endtag(self, tag: str) -> None:
        if tag.lower() == "a" and self._href:
            self.links.append((self._href, " ".join(self._text).strip()))
            self._href = None
            self._text = []


def extract_tariff_publications(html: str, base_url: str = PUCSL_INDEX_URL) -> list[dict]:
    parser = _LinkParser()
    parser.feed(html)
    publications: dict[str, dict] = {}
    for href, title in parser.links:
        url = urljoin(base_url, href)
        lowered = f"{title} {url}".lower()
        parsed = urlparse(url)
        if parsed.scheme != "https" or parsed.netloc not in {
            "pucsl.gov.lk",
            "www.pucsl.gov.lk",
        }:
            continue
        if not (
            "tariff schedule" in lowered
            or "decision on electricity tariff" in lowered
        ):
            continue
        if any(word in lowered for word in ("proposed", "consultation", "bulk supply", "bst")):
            continue
        normalized_url = url.split("#", 1)[0]
        identifier = hashlib.sha256(normalized_url.encode()).hexdigest()[:16]
        publications[normalized_url] = {
            "id": identifier,
            "title": title or Path(parsed.path).stem.replace("-", " "),
            "source_url": normalized_url,
            "status": "detected",
        }
    return sorted(publications.values(), key=lambda item: item["source_url"], reverse=True)


def load_monitor_state(path: Path = MONITOR_STATE) -> dict:
    if not path.exists():
        return {"last_checked_at": None, "last_error": None, "candidates": []}
    return json.loads(path.read_text())


def _publication_period(title: str) -> tuple[int, int] | None:
    year_match = re.search(r"\b(20\d{2})\b", title)
    if not year_match:
        return None
    month_match = re.search(
        r"\b(" + "|".join(MONTHS) + r")\b",
        title,
        flags=re.IGNORECASE,
    )
    month = 1 if month_match is None else MONTHS[month_match.group(1).lower()]
    return int(year_match.group(1)), month


def check_pucsl(
    state_path: Path = MONITOR_STATE,
    tariff_directory: Path = TARIFF_DIR,
    html: str | None = None,
) -> dict:
    checked_at = datetime.now(timezone.utc).isoformat()
    try:
        if html is None:
            response = subprocess.run(
                [
                    "curl",
                    "--fail",
                    "--silent",
                    "--show-error",
                    "--location",
                    "--max-time",
                    "12",
                    "--user-agent",
                    "Wattly-Tariff-Monitor/1.0",
                    PUCSL_INDEX_URL,
                ],
                check=True,
                capture_output=True,
            )
            html = response.stdout.decode("utf-8", errors="replace")
        publications = extract_tariff_publications(html)
        known_urls = {
            item["source_url"] for item in available_tariffs(tariff_directory)
        }
        effective_periods = [
            tuple(
                int(value)
                for value in item["effective_from"].split("-")[:2]
            )
            for item in available_tariffs(tariff_directory)
            if item.get("status") in {"active", "archived"}
        ]
        latest_effective_period = max(effective_periods, default=None)
        previous = {
            item["source_url"]: item
            for item in load_monitor_state(state_path).get("candidates", [])
        }
        candidates = []
        for publication in publications:
            if publication["source_url"] in known_urls:
                publication["status"] = "already_imported"
            elif (
                latest_effective_period is not None
                and (period := _publication_period(publication["title"]))
                and period <= latest_effective_period
            ):
                publication["status"] = "historical"
            elif publication["source_url"] in previous:
                publication["status"] = previous[publication["source_url"]].get(
                    "status", "detected"
                )
            publication["detected_at"] = previous.get(
                publication["source_url"], {}
            ).get("detected_at", checked_at)
            candidates.append(publication)
        state = {
            "index_url": PUCSL_INDEX_URL,
            "last_checked_at": checked_at,
            "last_error": None,
            "candidates": candidates,
        }
    except Exception as error:
        state = load_monitor_state(state_path)
        state["last_checked_at"] = checked_at
        state["last_error"] = str(error)
    state_path.parent.mkdir(parents=True, exist_ok=True)
    temporary = state_path.with_suffix(".tmp")
    temporary.write_text(json.dumps(state, indent=2) + "\n")
    temporary.replace(state_path)
    return state


def start_periodic_monitor(interval_hours: float = 24) -> None:
    if interval_hours <= 0:
        return

    def run() -> None:
        while True:
            check_pucsl()
            time.sleep(max(interval_hours * 3600, 300))

    threading.Thread(target=run, name="pucsl-tariff-monitor", daemon=True).start()
