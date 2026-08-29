"""Versioned Sri Lankan domestic electricity tariff calculations."""

from __future__ import annotations

import json
import re
from copy import deepcopy
from dataclasses import dataclass
from datetime import date, datetime, timedelta, timezone
from pathlib import Path
from tempfile import NamedTemporaryFile


ROOT = Path(__file__).resolve().parents[1]
TARIFF_DIR = ROOT / "tariffs"
AUDIT_LOG = TARIFF_DIR / "audit_log.jsonl"
ALLOWED_STATUSES = {"draft", "verified", "active", "archived"}
SAFE_ID = re.compile(r"^[a-z0-9][a-z0-9_]{2,79}$")


@dataclass(frozen=True)
class Bill:
    energy_charge_lkr: float
    fixed_charge_lkr: float
    total_lkr: float
    monthly_usage_kwh: float
    tariff_id: str


class TariffEngine:
    def __init__(self, configuration: dict):
        self.configuration = configuration

    @classmethod
    def from_file(cls, path: Path) -> "TariffEngine":
        return cls(json.loads(path.read_text()))

    @property
    def id(self) -> str:
        return str(self.configuration["id"])

    def calculate_monthly_bill(self, usage_kwh: float) -> Bill:
        if usage_kwh < 0:
            raise ValueError("Usage cannot be negative")
        if usage_kwh == 0:
            return Bill(0.0, 0.0, 0.0, 0.0, self.id)

        low_user = self.configuration["low_user"]
        if usage_kwh <= low_user["maximum_monthly_kwh"]:
            scheme = low_user
        else:
            scheme = self.configuration["standard_user"]

        energy_charge = 0.0
        for block in scheme["blocks"]:
            lower = float(block["from_kwh"])
            upper = block["to_kwh"]
            applicable_upper = usage_kwh if upper is None else min(
                usage_kwh, float(upper)
            )
            units = max(0.0, applicable_upper - lower)
            energy_charge += units * float(block["rate_lkr_per_kwh"])
            if upper is None or usage_kwh <= float(upper):
                break

        fixed_charge = self._fixed_charge(
            usage_kwh, scheme["fixed_charges"]
        )
        return Bill(
            energy_charge_lkr=round(energy_charge, 2),
            fixed_charge_lkr=round(fixed_charge, 2),
            total_lkr=round(energy_charge + fixed_charge, 2),
            monthly_usage_kwh=round(usage_kwh, 3),
            tariff_id=self.id,
        )

    def incremental_cost(
        self, current_month_kwh: float, additional_kwh: float
    ) -> float:
        if additional_kwh < 0:
            raise ValueError("Additional usage cannot be negative")
        before = self.calculate_monthly_bill(current_month_kwh).total_lkr
        after = self.calculate_monthly_bill(
            current_month_kwh + additional_kwh
        ).total_lkr
        return round(after - before, 2)

    def estimate_balance_days(
        self,
        balance_lkr: float,
        daily_usage_kwh: float,
        current_month_kwh: float,
        billing_days_elapsed: int,
        maximum_days: int = 365,
    ) -> float:
        if balance_lkr <= 0 or daily_usage_kwh <= 0:
            return 0.0
        if not 0 <= billing_days_elapsed < self.configuration[
            "billing_cycle_days"
        ]:
            raise ValueError("Billing days elapsed is outside the cycle")

        remaining = balance_lkr
        usage = current_month_kwh
        cycle_day = billing_days_elapsed
        elapsed = 0.0
        for _ in range(maximum_days):
            cost = self.incremental_cost(usage, daily_usage_kwh)
            if cost <= 0:
                return float(maximum_days)
            if remaining < cost:
                elapsed += remaining / cost
                return round(elapsed, 1)
            remaining -= cost
            elapsed += 1
            usage += daily_usage_kwh
            cycle_day += 1
            if cycle_day >= self.configuration["billing_cycle_days"]:
                cycle_day = 0
                usage = 0.0
        return float(maximum_days)

    @staticmethod
    def _fixed_charge(usage_kwh: float, charges: list[dict]) -> float:
        for entry in charges:
            maximum = entry["maximum_monthly_kwh"]
            if maximum is None or usage_kwh <= float(maximum):
                return float(entry["charge_lkr"])
        raise ValueError("No fixed charge configured")


def _tariff_path(tariff_id: str, directory: Path = TARIFF_DIR) -> Path:
    if not SAFE_ID.fullmatch(tariff_id):
        raise ValueError("Tariff id must contain only lowercase letters, numbers, and underscores")
    return directory / f"{tariff_id}.json"


def _atomic_write(path: Path, payload: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with NamedTemporaryFile(
        "w", dir=path.parent, prefix=f".{path.name}.", delete=False
    ) as temporary:
        json.dump(payload, temporary, indent=2)
        temporary.write("\n")
        temporary_path = Path(temporary.name)
    temporary_path.replace(path)


def _audit(
    action: str,
    tariff_id: str,
    details: dict | None = None,
    directory: Path = TARIFF_DIR,
) -> None:
    entry = {
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "action": action,
        "tariff_id": tariff_id,
        "details": details or {},
    }
    audit_path = directory / AUDIT_LOG.name
    with audit_path.open("a") as stream:
        stream.write(json.dumps(entry) + "\n")


def validate_tariff_configuration(
    configuration: dict, *, check_bills: bool = True
) -> list[dict]:
    required = {
        "id",
        "country",
        "currency",
        "provider",
        "category",
        "status",
        "effective_from",
        "effective_to",
        "billing_cycle_days",
        "source_url",
        "source_title",
        "low_user",
        "standard_user",
        "validation_cases",
    }
    missing = sorted(required - configuration.keys())
    if missing:
        raise ValueError(f"Missing tariff fields: {', '.join(missing)}")
    _tariff_path(str(configuration["id"]))
    if configuration["status"] not in ALLOWED_STATUSES:
        raise ValueError("Invalid tariff status")
    if configuration["country"] != "LK" or configuration["currency"] != "LKR":
        raise ValueError("Only Sri Lankan LKR tariffs are supported")
    if configuration["provider"] != "PUCSL":
        raise ValueError("Tariff provider must be PUCSL")
    if not str(configuration["source_url"]).startswith(
        "https://www.pucsl.gov.lk/"
    ):
        raise ValueError("Source must be an official HTTPS PUCSL document")
    start = date.fromisoformat(configuration["effective_from"])
    if configuration["effective_to"] is not None:
        end = date.fromisoformat(configuration["effective_to"])
        if end < start:
            raise ValueError("Tariff effective_to precedes effective_from")
    if int(configuration["billing_cycle_days"]) <= 0:
        raise ValueError("Billing cycle must be positive")

    for scheme_name in ("low_user", "standard_user"):
        scheme = configuration[scheme_name]
        blocks = scheme.get("blocks", [])
        charges = scheme.get("fixed_charges", [])
        if not blocks or not charges:
            raise ValueError(f"{scheme_name} requires blocks and fixed charges")
        expected_lower = 0.0
        for index, block in enumerate(blocks):
            lower = float(block["from_kwh"])
            upper = block["to_kwh"]
            rate = float(block["rate_lkr_per_kwh"])
            if lower != expected_lower or rate < 0:
                raise ValueError(f"{scheme_name} blocks are invalid or non-contiguous")
            if upper is None:
                if index != len(blocks) - 1:
                    raise ValueError("Only the final block may be open-ended")
            else:
                upper_value = float(upper)
                if upper_value <= lower:
                    raise ValueError("Tariff block upper bound must increase")
                expected_lower = upper_value
        previous_limit = -1.0
        for index, charge in enumerate(charges):
            maximum = charge["maximum_monthly_kwh"]
            if float(charge["charge_lkr"]) < 0:
                raise ValueError("Fixed charge cannot be negative")
            if maximum is None:
                if index != len(charges) - 1:
                    raise ValueError("Only the final fixed charge may be open-ended")
            else:
                maximum_value = float(maximum)
                if maximum_value <= previous_limit:
                    raise ValueError("Fixed charge limits must increase")
                previous_limit = maximum_value

    cases = configuration["validation_cases"]
    if not isinstance(cases, list) or len(cases) < 3:
        raise ValueError("At least three official bill validation cases are required")
    results = []
    if check_bills:
        engine = TariffEngine(configuration)
        for case in cases:
            usage = float(case["usage_kwh"])
            expected = float(case["expected_total_lkr"])
            actual = engine.calculate_monthly_bill(usage).total_lkr
            passed = abs(actual - expected) <= 0.01
            results.append(
                {
                    "usage_kwh": usage,
                    "expected_total_lkr": expected,
                    "actual_total_lkr": actual,
                    "passed": passed,
                }
            )
        if not all(item["passed"] for item in results):
            raise ValueError("Tariff failed official bill regression validation")
    return results


def available_tariffs(directory: Path = TARIFF_DIR) -> list[dict]:
    tariffs = []
    for path in sorted(directory.glob("*.json")):
        try:
            item = json.loads(path.read_text())
        except (json.JSONDecodeError, OSError):
            continue
        if isinstance(item, dict) and "id" in item:
            tariffs.append(item)
    return tariffs


def create_tariff_draft(
    configuration: dict, directory: Path = TARIFF_DIR
) -> dict:
    draft = deepcopy(configuration)
    draft["status"] = "draft"
    validate_tariff_configuration(draft, check_bills=False)
    path = _tariff_path(draft["id"], directory)
    if path.exists():
        raise FileExistsError(f"Tariff {draft['id']} already exists")
    _atomic_write(path, draft)
    _audit("draft_created", draft["id"], directory=directory)
    return draft


def verify_tariff(tariff_id: str, directory: Path = TARIFF_DIR) -> tuple[dict, list[dict]]:
    path = _tariff_path(tariff_id, directory)
    if not path.exists():
        raise FileNotFoundError(f"Tariff {tariff_id} not found")
    configuration = json.loads(path.read_text())
    if configuration["status"] != "draft":
        raise ValueError("Only draft tariffs can be verified")
    results = validate_tariff_configuration(configuration)
    configuration["status"] = "verified"
    configuration["verified_at"] = datetime.now(timezone.utc).isoformat()
    _atomic_write(path, configuration)
    _audit("draft_verified", tariff_id, {"validation_cases": results}, directory)
    return configuration, results


def activate_tariff(
    tariff_id: str,
    directory: Path = TARIFF_DIR,
    today: date | None = None,
) -> dict:
    target = today or date.today()
    path = _tariff_path(tariff_id, directory)
    if not path.exists():
        raise FileNotFoundError(f"Tariff {tariff_id} not found")
    incoming = json.loads(path.read_text())
    if incoming["status"] != "verified":
        raise ValueError("Only verified tariffs can be activated")
    validate_tariff_configuration(incoming)
    effective = date.fromisoformat(incoming["effective_from"])
    if effective > target:
        raise ValueError("Future tariffs cannot be activated early")

    originals = {item["id"]: deepcopy(item) for item in available_tariffs(directory)}
    active_starts = [
        date.fromisoformat(item["effective_from"])
        for item in originals.values()
        if item["status"] == "active" and item["id"] != tariff_id
    ]
    if active_starts and effective <= max(active_starts):
        raise ValueError("Replacement tariff must start after the current tariff")
    archived = []
    try:
        for current in originals.values():
            if current["status"] != "active" or current["id"] == tariff_id:
                continue
            current["status"] = "archived"
            current["effective_to"] = (effective - timedelta(days=1)).isoformat()
            _atomic_write(_tariff_path(current["id"], directory), current)
            archived.append(current["id"])
        incoming["status"] = "active"
        incoming["activated_at"] = datetime.now(timezone.utc).isoformat()
        _atomic_write(path, incoming)
    except Exception:
        for original_id, original in originals.items():
            _atomic_write(_tariff_path(original_id, directory), original)
        raise
    _audit("tariff_activated", tariff_id, {"archived": archived}, directory)
    return incoming


def active_tariff(
    on_date: date | None = None, directory: Path = TARIFF_DIR
) -> TariffEngine:
    target = on_date or date.today()
    candidates = []
    for tariff in available_tariffs(directory):
        start = date.fromisoformat(tariff["effective_from"])
        end = (
            None
            if tariff["effective_to"] is None
            else date.fromisoformat(tariff["effective_to"])
        )
        if tariff["status"] == "active" and start <= target and (
            end is None or target <= end
        ):
            candidates.append(tariff)
    if not candidates:
        raise RuntimeError(f"No active tariff for {target.isoformat()}")
    candidates.sort(key=lambda item: item["effective_from"], reverse=True)
    return TariffEngine(candidates[0])
