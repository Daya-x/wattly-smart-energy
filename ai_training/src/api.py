"""Local inference API for the Smart Energy Flutter dashboard."""

from __future__ import annotations

import json
import os
import secrets
import threading
import uuid
import re
from collections import deque
from datetime import date, datetime, timedelta, timezone
from pathlib import Path
from zoneinfo import ZoneInfo

import joblib
import pandas as pd
import firebase_admin
from firebase_admin import auth as firebase_auth
from firebase_admin import firestore as admin_firestore
from fastapi import Body, Depends, FastAPI, Header, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from pydantic import BaseModel, Field
from dotenv import load_dotenv

load_dotenv(Path(__file__).resolve().parents[2] / ".env")

from train_forecasting import (
    DEFAULT_DATA,
    DEFAULT_METRICS,
    DEFAULT_MODEL,
    build_features,
    load_hourly_energy,
)
from train_anomaly import (
    DEFAULT_DATA as DEFAULT_ANOMALY_DATA,
    DEFAULT_METRICS as DEFAULT_ANOMALY_METRICS,
    DEFAULT_MODEL as DEFAULT_ANOMALY_MODEL,
    FEATURE_COLUMNS as ANOMALY_FEATURE_COLUMNS,
)
from train_appliance import (
    DEFAULT_METRICS as DEFAULT_APPLIANCE_METRICS,
    DEFAULT_MODEL as DEFAULT_APPLIANCE_MODEL,
    FEATURE_CACHE as APPLIANCE_FEATURE_CACHE,
    FEATURE_COLUMNS as APPLIANCE_FEATURE_COLUMNS,
)
from train_safety import (
    ELECTRICAL_DATA,
    ELECTRICAL_MODEL,
    GAS_MODEL,
    GAS_NAMES,
    METRICS_PATH as SAFETY_METRICS,
    SMOKE_DATA,
    SMOKE_FEATURES,
    SMOKE_MODEL,
    electrical_features,
    load_gas_batches,
)
from tariff_engine import (
    activate_tariff,
    active_tariff,
    available_tariffs,
    create_tariff_draft,
    validate_tariff_configuration,
    verify_tariff,
)
from pucsl_monitor import (
    PUCSL_INDEX_URL,
    check_pucsl,
    load_monitor_state,
    start_periodic_monitor,
)
from persistence import DEFAULT_DB, SQLitePersistence, build_persistence
from safety_rules import active_conditions, live_safety_summary


app = FastAPI(title="Smart Energy AI API", version="1.0.0")
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False,
    allow_methods=["GET", "POST"],
    allow_headers=["*"],
)
_ownership_cache: dict[tuple[str, str], datetime] = {}
_ownership_lock = threading.Lock()
OWNERSHIP_CACHE_SECONDS = 300


def _ensure_firebase_admin() -> None:
    if firebase_admin._apps:
        return
    project_id = os.environ.get("FIREBASE_PROJECT_ID")
    options = {"projectId": project_id} if project_id else None
    firebase_admin.initialize_app(options=options)


def _user_owns_device(user: dict, device_id: str) -> bool:
    uid = user["uid"]
    cache_key = (uid, device_id)
    now = datetime.now(timezone.utc)
    with _ownership_lock:
        cached_at = _ownership_cache.get(cache_key)
        if cached_at and (now - cached_at).total_seconds() < OWNERSHIP_CACHE_SECONDS:
            return True

    _ensure_firebase_admin()
    client = admin_firestore.client()
    user_reference = client.collection("users").document(uid)
    device_reference = client.collection("devices").document(device_id)
    user_data = user_reference.get().to_dict() or {}
    device_data = device_reference.get().to_dict() or {}
    assigned_device = user_data.get("assigned_device_id")
    owner_uid = device_data.get("owner_uid")
    if assigned_device not in {None, device_id}:
        return False
    if owner_uid not in {None, uid}:
        return False
    user_reference.set(
        {
            "email": user.get("email"),
            "assigned_device_id": device_id,
            "updated_at": now,
        },
        merge=True,
    )
    device_reference.set(
        {"owner_uid": uid, "owner_updated_at": now},
        merge=True,
    )
    with _ownership_lock:
        _ownership_cache[cache_key] = now
    return True


def _user_auth_exempt(request: Request) -> bool:
    path = request.url.path
    if request.method == "OPTIONS":
        return True
    if path in {"/health", "/openapi.json", "/docs", "/redoc"}:
        return True
    if request.method == "GET" and path.startswith("/predict/"):
        return True
    if request.method == "GET" and (
        path.endswith("/relay-command")
        or path.endswith("/display-summary")
    ):
        return True
    if request.method == "POST" and (
        path.endswith("/readings")
        or "/alerts/test" in path
        or path.endswith("/acknowledge")
        or path.endswith("/acknowledge-all")
        or path.startswith("/tariffs/")
    ):
        return True
    return False


@app.middleware("http")
async def verify_dashboard_user(request: Request, call_next):
    if (
        os.environ.get("REQUIRE_USER_AUTH", "false").lower() != "true"
        or _user_auth_exempt(request)
    ):
        return await call_next(request)
    authorization = request.headers.get("Authorization", "")
    scheme, _, token = authorization.partition(" ")
    if scheme.lower() != "bearer" or not token:
        return JSONResponse(
            status_code=401,
            content={"detail": "Firebase sign-in is required"},
        )
    try:
        _ensure_firebase_admin()
        user = firebase_auth.verify_id_token(token)
        request.state.firebase_user = user
    except Exception:
        return JSONResponse(
            status_code=401,
            content={"detail": "Invalid or expired Firebase login token"},
        )
    match = re.match(r"^/devices/([^/]+)", request.url.path)
    if match:
        try:
            if not _user_owns_device(user, match.group(1)):
                return JSONResponse(
                    status_code=403,
                    content={"detail": "This meter is not assigned to your account"},
                )
        except Exception as error:
            is_local_dashboard = request.client is not None and request.client.host in {
                "127.0.0.1",
                "::1",
                "localhost",
            }
            allow_local_fallback = (
                os.environ.get("ALLOW_LOCAL_AUTH_FALLBACK", "true").lower() == "true"
            )
            if is_local_dashboard and allow_local_fallback:
                request.state.firebase_user = user
                request.state.ownership_warning = str(error)
                return await call_next(request)
            return JSONResponse(
                status_code=503,
                content={"detail": f"Unable to verify meter ownership: {error}"},
            )
    return await call_next(request)

_artifact: dict | None = None
_latest_features = None
_metrics: dict | None = None
_anomaly_artifact: dict | None = None
_latest_anomaly_features = None
_anomaly_metrics: dict | None = None
_appliance_artifact: dict | None = None
_appliance_samples = None
_appliance_metrics: dict | None = None
_smoke_artifact: dict | None = None
_electrical_artifact: dict | None = None
_gas_artifact: dict | None = None
_latest_smoke_features = None
_latest_electrical_features = None
_latest_gas_features = None
_safety_metrics: dict | None = None
_tariff_engine = active_tariff()
_device_readings: dict[str, deque] = {}
_device_accounts: dict[str, dict] = {}
_device_recharges: dict[str, deque] = {}
_device_lock = threading.Lock()
_persistence = build_persistence()
_local_persistence = (
    _persistence
    if isinstance(_persistence, SQLitePersistence)
    else SQLitePersistence(
        Path(
            os.environ.get(
                "SQLITE_FALLBACK_DB_PATH",
                str(DEFAULT_DB),
            )
        )
    )
)
_persistence_error: str | None = None
_last_persisted_at: dict[str, datetime] = {}
_pending_usage: dict[str, float] = {}
_active_alerts: dict[str, dict[str, dict]] = {}
_relay_commands: dict[str, dict] = {}
_manual_alerts: dict[str, dict[str, dict]] = {}
# Remembers whether the load was ON before the first critical presentation
# simulation.  The saved state is restored only after every critical
# simulation has been acknowledged/cleared and no real safety lock remains.
_critical_simulation_restore_relay: dict[str, bool] = {}
_demo_zero_balance_until: dict[str, datetime] = {}
_alerts_initialized: set[str] = set()
_alert_safe_streaks: dict[str, dict[str, int]] = {}
_alert_trigger_streaks: dict[str, dict[str, int]] = {}
_theft_safe_streaks: dict[str, int] = {}
ALERT_CONFIRM_DANGEROUS_READINGS = 3
ALERT_RESOLVE_SAFE_READINGS = 5
SAFETY_LOCK_ALERT_TYPES = {
    "sensor_pzem",
    "sensor_dht",
    "gas",
    "temperature",
    "power",
    "voltage",
    "theft",
}
_persistence_sample_seconds = float(
    os.environ.get("PERSISTENCE_SAMPLE_SECONDS", "60")
)
COLOMBO = ZoneInfo("Asia/Colombo")


def _initialize_active_alerts(device_id: str) -> None:
    if device_id in _alerts_initialized:
        return
    active = {}
    try:
        for alert in _local_persistence.list_alerts(device_id):
            if alert.get("status") == "active":
                active[alert["type"]] = alert
    except Exception:
        pass
    if not active and _local_persistence is not _persistence:
        try:
            for alert in _persistence.list_alerts(device_id):
                if alert.get("status") == "active":
                    active[alert["type"]] = alert
        except Exception:
            pass
    _active_alerts[device_id] = active
    _alert_safe_streaks[device_id] = {}
    _alert_trigger_streaks[device_id] = {}
    _alerts_initialized.add(device_id)


def _alert_sort_key(alert: dict) -> datetime:
    value = alert.get("created_at") or alert.get("updated_at")
    if isinstance(value, datetime):
        return value
    if isinstance(value, str):
        try:
            return datetime.fromisoformat(value.replace("Z", "+00:00"))
        except ValueError:
            pass
    return datetime.min.replace(tzinfo=timezone.utc)


def _merged_device_alerts(device_id: str, persisted_alerts: list[dict], limit: int) -> list[dict]:
    """Return persisted alerts plus live in-memory alerts, de-duplicated by id."""
    merged: dict[str, dict] = {}
    for alert in persisted_alerts:
        merged[str(alert.get("id", uuid.uuid4().hex))] = alert
    for alert in _active_alerts.get(device_id, {}).values():
        merged[str(alert.get("id", uuid.uuid4().hex))] = alert
    for alert in _manual_alerts.get(device_id, {}).values():
        merged[str(alert.get("id", uuid.uuid4().hex))] = alert
    return sorted(merged.values(), key=_alert_sort_key, reverse=True)[:limit]


def _save_alert_reliably(device_id: str, alert: dict) -> None:
    """Keep alerts durable locally even when cloud storage is unavailable."""
    global _persistence_error
    _local_persistence.save_alert(device_id, alert)
    if _local_persistence is not _persistence:
        try:
            _persistence.save_alert(device_id, alert)
            _persistence_error = None
        except Exception as error:
            _persistence_error = str(error)
    else:
        _persistence_error = None


def _process_live_alerts(device_id: str, reading: dict) -> bool:
    global _persistence_error
    _initialize_active_alerts(device_id)
    active = _active_alerts[device_id]
    safe_streaks = _alert_safe_streaks[device_id]
    trigger_streaks = _alert_trigger_streaks[device_id]
    conditions = active_conditions(reading)
    recovery_conditions = active_conditions(reading, recovery=True)
    confirmed_hazards = set(reading.get("confirmed_hazards") or [])
    # Accept the original all-hazards boolean from an older firmware build,
    # while new builds identify exactly which hardware filter was confirmed.
    legacy_firmware_confirmed = bool(
        reading.get("safety_confirmed", False) and not confirmed_hazards
    )
    now = datetime.now(timezone.utc).isoformat()
    changed = False

    for alert_type, condition in conditions.items():
        safe_streaks[alert_type] = 0
        existing = active.get(alert_type)
        if existing is not None and existing["severity"] == condition["severity"]:
            continue
        if existing is not None:
            # Keep one incident per hazard. Severity may rise, but a critical
            # incident is never downgraded while it remains active.
            if existing.get("severity") == "Critical":
                continue
            existing.update(condition)
            existing["updated_at"] = now
            changed = True
            try:
                _save_alert_reliably(device_id, existing)
            except Exception as error:
                _persistence_error = str(error)
            continue
        trigger_streaks[alert_type] = trigger_streaks.get(alert_type, 0) + 1
        firmware_confirmed = (
            alert_type in confirmed_hazards or legacy_firmware_confirmed
        )
        required = 1 if firmware_confirmed else ALERT_CONFIRM_DANGEROUS_READINGS
        if trigger_streaks[alert_type] < required:
            continue
        alert = {
            "id": uuid.uuid4().hex,
            "device_id": device_id,
            "type": alert_type,
            **condition,
            "status": "active",
            "acknowledged": False,
            "created_at": now,
            "updated_at": now,
            "source": "live_threshold_rule",
        }
        active[alert_type] = alert
        trigger_streaks.pop(alert_type, None)
        changed = True
        try:
            _save_alert_reliably(device_id, alert)
        except Exception as error:
            _persistence_error = str(error)

    for alert_type in list(trigger_streaks):
        if alert_type not in conditions:
            trigger_streaks.pop(alert_type, None)

    for alert_type in list(active):
        # Theft incidents have their own PIR recovery logic. The electrical
        # threshold resolver must not close them just because they are not an
        # electrical sensor condition.
        if alert_type not in SAFETY_LOCK_ALERT_TYPES:
            continue
        if alert_type in recovery_conditions:
            continue
        safe_streaks[alert_type] = safe_streaks.get(alert_type, 0) + 1
        if safe_streaks[alert_type] < ALERT_RESOLVE_SAFE_READINGS:
            continue
        alert = active.pop(alert_type)
        safe_streaks.pop(alert_type, None)
        alert["status"] = "resolved"
        alert["updated_at"] = now
        alert["resolution"] = "Reading returned to the safe range"
        changed = True
        try:
            _save_alert_reliably(device_id, alert)
        except Exception as error:
            _persistence_error = str(error)
    return changed


def _device_safety_locked(device_id: str) -> bool:
    """Block remote relay-on while a confirmed incident needs attention."""
    _initialize_active_alerts(device_id)
    live_locked = any(
        alert_type in SAFETY_LOCK_ALERT_TYPES
        and alert.get("status") == "active"
        and not alert.get("acknowledged", False)
        for alert_type, alert in _active_alerts.get(device_id, {}).items()
    )
    simulated_locked = any(
        alert.get("source") == "dashboard_simulation"
        and alert.get("severity") == "Critical"
        and alert.get("status") == "active"
        and not alert.get("acknowledged", False)
        for alert in _manual_alerts.get(device_id, {}).values()
    )
    return live_locked or simulated_locked


def _active_simulation(device_id: str) -> dict | None:
    """Return the newest unacknowledged dashboard simulation, if present."""
    simulations = [
        alert
        for alert in _manual_alerts.get(device_id, {}).values()
        if alert.get("source") == "dashboard_simulation"
        and alert.get("status") == "active"
        and not alert.get("acknowledged", False)
    ]
    return max(simulations, key=_alert_sort_key) if simulations else None


def _restore_relay_after_critical_simulation(device_id: str) -> bool:
    """Turn the relay back on after a critical demo is acknowledged safely."""
    if device_id not in _critical_simulation_restore_relay:
        return False
    if _device_safety_locked(device_id):
        return False
    _critical_simulation_restore_relay.pop(device_id)
    credit_allowed = _effective_account_balance(device_id) > 0
    _queue_auxiliary_command(
        device_id,
        relay_requested=credit_allowed,
        source="critical_simulation_acknowledged",
        demo_buzzer=False,
        simulation_scenario="clear",
        safety_locked=False,
        safety_note=(
            "Critical simulation acknowledged; relay automatically turned on."
            if credit_allowed
            else "Critical simulation acknowledged; relay remains off until recharge."
        ),
    )
    return credit_allowed


class DeviceReading(BaseModel):
    voltage: float = Field(ge=0, le=300)
    current: float = Field(ge=0, le=100)
    power: float = Field(ge=0, le=30000)
    energy: float = Field(ge=0)
    temperature: float = Field(ge=-20, le=150)
    humidity: float = Field(ge=0, le=100)
    gas: int = Field(ge=0, le=10000)
    motion: bool
    relay: bool
    pzem_valid: bool = True
    dht_valid: bool = True
    safety_confirmed: bool = False
    confirmed_hazards: list[str] = Field(default_factory=list)


class RechargeRequest(BaseModel):
    amount_lkr: float = Field(ge=100, le=100000)
    payment_method: str = Field(default="demo_card", pattern="^demo_card$")


class TestAlertRequest(BaseModel):
    alert_type: str = Field(pattern="^(gas|temperature|power|voltage)$")
    severity: str = Field(default="Warning", pattern="^(Warning|Critical)$")


class SimulationRequest(BaseModel):
    scenario: str = Field(
        pattern="^(gas|temperature|power|voltage|sensor_pzem|sensor_dht|theft|clear)$"
    )


class TheftSettingsRequest(BaseModel):
    manual_enabled: bool


class RelayCommandRequest(BaseModel):
    relay_requested: bool


class DemoZeroBalanceRequest(BaseModel):
    enabled: bool
    duration_seconds: int = Field(default=300, ge=30, le=600)


def _load_device_account(device_id: str) -> dict:
    account = _device_accounts.get(device_id)
    if account is None:
        try:
            account = _local_persistence.load_account(device_id)
        except Exception:
            account = None
    if account is None and _local_persistence is not _persistence:
        try:
            account = _persistence.load_account(device_id)
        except Exception:
            account = None
    if account is None:
        local_now = datetime.now(COLOMBO)
        account = {
            "balance_lkr": 0.0,
            "monthly_usage_kwh": 0.0,
            "today_usage_kwh": 0.0,
            "usage_date": local_now.date().isoformat(),
            "billing_month": local_now.strftime("%Y-%m"),
            "last_meter_energy_kwh": 0.0,
            "current_bill_lkr": 0.0,
            "has_recharged": False,
        }
    _device_accounts[device_id] = account
    return account


def _save_account_reliably(device_id: str, account: dict) -> None:
    global _persistence_error
    _local_persistence.save_account(device_id, account)
    if _local_persistence is not _persistence:
        try:
            _persistence.save_account(device_id, account)
            _persistence_error = None
        except Exception as error:
            _persistence_error = str(error)


def _theft_security_status(device_id: str) -> dict:
    account = _load_device_account(device_id)
    local_now = datetime.now(COLOMBO)
    automatic_active = 0 <= local_now.hour < 6
    manual_enabled = bool(account.get("theft_manual_enabled", False))
    if manual_enabled:
        mode = "manual"
    elif automatic_active:
        mode = "automatic"
    else:
        mode = "off"
    return {
        "device_id": device_id,
        "manual_enabled": manual_enabled,
        "automatic_enabled": True,
        "automatic_window": "12:00 AM – 6:00 AM",
        "automatic_active": automatic_active,
        "monitoring_active": manual_enabled or automatic_active,
        "mode": mode,
        "local_time": local_now.isoformat(),
    }


def _current_relay_state(device_id: str) -> bool:
    readings = _device_readings.get(device_id)
    if readings:
        return bool(readings[-1].get("relay", False))
    command = _relay_commands.get(device_id)
    return bool(command and command.get("relay_requested", False))


def _queue_auxiliary_command(device_id: str, **fields) -> dict:
    previous = {
        key: value
        for key, value in _relay_commands.get(device_id, {}).items()
        if key not in {"demo_buzzer", "demo_duration_seconds", "simulation_scenario"}
    }
    payload = {
        **previous,
        "device_id": device_id,
        "relay_requested": previous.get(
            "relay_requested", _current_relay_state(device_id)
        ),
        "credit_allowed": _effective_account_balance(device_id) > 0,
        "balance_lkr": round(_effective_account_balance(device_id), 2),
        "command_id": uuid.uuid4().hex,
        "updated_at": datetime.now(timezone.utc).isoformat(),
        **fields,
    }
    _relay_commands[device_id] = payload
    return payload


def _process_theft_detection(device_id: str, reading: dict) -> bool:
    _initialize_active_alerts(device_id)
    active = _active_alerts[device_id]
    status = _theft_security_status(device_id)
    existing = active.get("theft")
    now = datetime.now(timezone.utc).isoformat()

    if status["monitoring_active"] and bool(reading.get("motion")):
        _theft_safe_streaks[device_id] = 0
        if existing is not None:
            return False
        mode_label = "protected hours" if status["mode"] == "automatic" else "manual protection"
        alert = {
            "id": uuid.uuid4().hex,
            "device_id": device_id,
            "type": "theft",
            "severity": "Critical",
            "title": "Possible intrusion detected",
            "message": f"Unexpected movement detected during {mode_label}.",
            "value": 1,
            "unit": "motion",
            "threshold": 0,
            "status": "active",
            "acknowledged": False,
            "created_at": now,
            "updated_at": now,
            "source": "theft_detection",
            "mode": status["mode"],
        }
        active["theft"] = alert
        _save_alert_reliably(device_id, alert)
        return True

    if existing is None:
        return False
    _theft_safe_streaks[device_id] = _theft_safe_streaks.get(device_id, 0) + 1
    if status["monitoring_active"] and _theft_safe_streaks[device_id] < 3:
        return False
    alert = active.pop("theft")
    alert["status"] = "resolved"
    alert["updated_at"] = now
    alert["resolution"] = (
        "No further movement detected" if status["monitoring_active"]
        else "Theft monitoring was disabled"
    )
    _save_alert_reliably(device_id, alert)
    _theft_safe_streaks[device_id] = 0
    return True


def _current_account_balance(device_id: str) -> float:
    account = _device_accounts.get(device_id)
    if account is None:
        try:
            account = _local_persistence.load_account(device_id)
        except Exception:
            account = None
    if account is None and _local_persistence is not _persistence:
        try:
            account = _persistence.load_account(device_id)
        except Exception:
            account = None
    if account is None:
        return 0.0
    return float(account.get("balance_lkr", 0.0))


def _demo_zero_balance_alert_id(device_id: str) -> str:
    return f"demo-zero-balance-{device_id}"


def _resolve_demo_zero_balance_alert(device_id: str, reason: str) -> None:
    alert = _manual_alerts.get(device_id, {}).get(
        _demo_zero_balance_alert_id(device_id)
    )
    if alert is None or alert.get("status") != "active":
        return
    alert["status"] = "resolved"
    alert["acknowledged"] = True
    alert["updated_at"] = datetime.now(timezone.utc).isoformat()
    alert["resolution"] = reason


def _demo_zero_balance_active(device_id: str) -> bool:
    expires_at = _demo_zero_balance_until.get(device_id)
    if expires_at is None:
        return False
    if datetime.now(timezone.utc) < expires_at:
        return True
    _demo_zero_balance_until.pop(device_id, None)
    _resolve_demo_zero_balance_alert(
        device_id,
        "Temporary zero-balance demonstration ended automatically",
    )
    return False


def _effective_account_balance(device_id: str) -> float:
    if _demo_zero_balance_active(device_id):
        return 0.0
    return _current_account_balance(device_id)


def _with_effective_balance(device_id: str, payload: dict) -> dict:
    """Overlay presentation credit without modifying stored prepaid data."""
    result = dict(payload)
    actual_balance = _current_account_balance(device_id)
    demo_active = _demo_zero_balance_active(device_id)
    result["actual_balance_lkr"] = round(actual_balance, 2)
    result["balance_lkr"] = 0.0 if demo_active else round(actual_balance, 2)
    result["demo_zero_balance"] = demo_active
    expires_at = _demo_zero_balance_until.get(device_id) if demo_active else None
    result["demo_expires_at"] = (
        expires_at.isoformat() if expires_at is not None else None
    )
    return result


def _account_has_recharged(device_id: str, account: dict) -> bool:
    """Preserve the Rs. 100 repeat minimum even after credit reaches zero."""
    stored_value = account.get("has_recharged")
    if stored_value is not None:
        return bool(stored_value)
    if float(account.get("balance_lkr", 0.0)) > 0:
        return True
    try:
        if _local_persistence.list_recharges(device_id, 1):
            return True
    except Exception:
        pass
    if _local_persistence is not _persistence:
        try:
            return bool(_persistence.list_recharges(device_id, 1))
        except Exception:
            pass
    return False


def require_device_sender(
    request: Request,
    x_device_key: str | None = Header(default=None),
) -> None:
    expected = os.environ.get("DEVICE_API_KEY")
    if expected:
        if x_device_key is None or not secrets.compare_digest(x_device_key, expected):
            raise HTTPException(status_code=403, detail="Invalid device key")
        return
    client_host = request.client.host if request.client else ""
    if client_host not in {"127.0.0.1", "::1", "localhost", "testclient"}:
        raise HTTPException(
            status_code=403,
            detail="Set DEVICE_API_KEY before accepting network devices",
        )


def require_tariff_admin(
    x_admin_key: str | None = Header(default=None),
) -> None:
    expected = os.environ.get("TARIFF_ADMIN_KEY")
    if not expected:
        raise HTTPException(
            status_code=503,
            detail="Tariff administration is disabled until TARIFF_ADMIN_KEY is set",
        )
    if x_admin_key is None or not secrets.compare_digest(x_admin_key, expected):
        raise HTTPException(status_code=403, detail="Invalid tariff administrator key")


def require_alert_operator(
    request: Request,
    x_admin_key: str | None = Header(default=None),
) -> None:
    """Allow alert acknowledgement by an admin or the signed-in meter owner.

    A private administrator key must not be embedded in the Android APK. The
    dashboard's Firebase token is therefore the normal customer path, while
    the administrator key remains available for local curl/presentation tests.
    """
    expected = os.environ.get("TARIFF_ADMIN_KEY")
    if (
        expected
        and x_admin_key is not None
        and secrets.compare_digest(x_admin_key, expected)
    ):
        return

    user = getattr(request.state, "firebase_user", None)
    if user is None:
        authorization = request.headers.get("Authorization", "")
        scheme, _, token = authorization.partition(" ")
        if scheme.lower() != "bearer" or not token:
            raise HTTPException(
                status_code=401,
                detail="Sign in is required to acknowledge alerts",
            )
        try:
            _ensure_firebase_admin()
            user = firebase_auth.verify_id_token(token)
        except Exception as error:
            raise HTTPException(
                status_code=401,
                detail="Invalid or expired Firebase login token",
            ) from error

    try:
        if not _user_owns_device(user, request.path_params["device_id"]):
            raise HTTPException(
                status_code=403,
                detail="This meter is not assigned to your account",
            )
    except HTTPException:
        raise
    except Exception as error:
        # Preserve the existing local-development fallback used by the auth
        # middleware, but never silently bypass ownership checks remotely.
        client_host = request.client.host if request.client else ""
        local = client_host in {"127.0.0.1", "::1", "localhost", "testclient"}
        allow_local = (
            os.environ.get("ALLOW_LOCAL_AUTH_FALLBACK", "true").lower() == "true"
        )
        if not (local and allow_local):
            raise HTTPException(
                status_code=503,
                detail=f"Unable to verify meter ownership: {error}",
            ) from error


def load_runtime(
    model_path: Path = DEFAULT_MODEL,
    data_path: Path = DEFAULT_DATA,
    metrics_path: Path = DEFAULT_METRICS,
) -> None:
    global _artifact, _latest_features, _metrics
    global _anomaly_artifact, _latest_anomaly_features, _anomaly_metrics
    global _appliance_artifact, _appliance_samples, _appliance_metrics
    global _smoke_artifact, _electrical_artifact, _gas_artifact
    global _latest_smoke_features, _latest_electrical_features
    global _latest_gas_features, _safety_metrics
    if not model_path.exists():
        raise RuntimeError(
            "Forecast model not found. Run train_forecasting.py first."
        )
    _artifact = joblib.load(model_path)
    hourly, _ = load_hourly_energy(data_path)
    features, _ = build_features(hourly)
    _latest_features = features[_artifact["feature_columns"]].tail(1)
    _metrics = json.loads(metrics_path.read_text())

    if not DEFAULT_ANOMALY_MODEL.exists():
        raise RuntimeError(
            "Anomaly model not found. Run train_anomaly.py first."
        )
    _anomaly_artifact = joblib.load(DEFAULT_ANOMALY_MODEL)
    anomaly_data = pd.read_csv(DEFAULT_ANOMALY_DATA)
    _latest_anomaly_features = anomaly_data[
        ANOMALY_FEATURE_COLUMNS
    ].tail(1)
    _anomaly_metrics = json.loads(DEFAULT_ANOMALY_METRICS.read_text())

    if not DEFAULT_APPLIANCE_MODEL.exists():
        raise RuntimeError(
            "Appliance model not found. Run train_appliance.py first."
        )
    _appliance_artifact = joblib.load(DEFAULT_APPLIANCE_MODEL)
    appliance_features = pd.read_csv(APPLIANCE_FEATURE_CACHE)
    appliance_features = appliance_features.loc[
        (appliance_features["max_w"] >= 5.0)
        & (appliance_features["active_ratio"] >= 0.05)
    ]
    _appliance_samples = appliance_features.groupby(
        "source_file", as_index=False
    ).tail(1)
    _appliance_metrics = json.loads(DEFAULT_APPLIANCE_METRICS.read_text())

    _smoke_artifact = joblib.load(SMOKE_MODEL)
    _electrical_artifact = joblib.load(ELECTRICAL_MODEL)
    _gas_artifact = joblib.load(GAS_MODEL)
    _latest_smoke_features = pd.read_csv(SMOKE_DATA)[SMOKE_FEATURES].tail(1)
    _latest_electrical_features = electrical_features(
        pd.read_csv(ELECTRICAL_DATA).tail(1)
    ).reindex(columns=_electrical_artifact["feature_columns"], fill_value=0)
    gas_features, _ = load_gas_batches([10])
    _latest_gas_features = gas_features[-1:]
    _safety_metrics = json.loads(SAFETY_METRICS.read_text())


@app.on_event("startup")
def startup() -> None:
    load_runtime()
    interval = float(os.environ.get("PUCSL_MONITOR_INTERVAL_HOURS", "24"))
    start_periodic_monitor(interval)


@app.get("/health")
def health() -> dict:
    return {
        "status": "ok" if _artifact is not None else "not_ready",
        "models": {
            "energy": (
                None if _artifact is None else _artifact["model_name"]
            ),
            "anomaly": (
                None
                if _anomaly_artifact is None
                else _anomaly_artifact["model_name"]
            ),
            "appliance": (
                None
                if _appliance_artifact is None
                else _appliance_artifact["model_name"]
            ),
            "smoke_fire": (
                None if _smoke_artifact is None else _smoke_artifact["model_name"]
            ),
            "electrical": (
                None
                if _electrical_artifact is None
                else _electrical_artifact["model_name"]
            ),
            "gas_identity": (
                None if _gas_artifact is None else _gas_artifact["model_name"]
            ),
        },
        "persistence": {
            "backend": _persistence.name,
            "healthy": _persistence_error is None,
            "last_error": _persistence_error,
            "sample_seconds": _persistence_sample_seconds,
        },
    }


@app.post("/devices/{device_id}/readings", status_code=202)
def ingest_device_reading(
    device_id: str,
    reading: DeviceReading,
    _: None = Depends(require_device_sender),
) -> dict:
    global _persistence_error
    if device_id != "EM-2048":
        raise HTTPException(status_code=404, detail="Unknown device")
    payload = (
        reading.model_dump()
        if hasattr(reading, "model_dump")
        else reading.dict()
    )
    with _device_lock:
        account = _device_accounts.get(device_id)
        if account is None:
            try:
                account = _local_persistence.load_account(device_id)
            except Exception as error:
                _persistence_error = str(error)
        if account is None and _local_persistence is not _persistence:
            try:
                account = _persistence.load_account(device_id)
            except Exception as error:
                _persistence_error = str(error)
        if account is None:
            monthly_usage = float(reading.energy)
            current_bill = _tariff_engine.calculate_monthly_bill(
                monthly_usage
            ).total_lkr
            local_now = datetime.now(COLOMBO)
            account = {
                "balance_lkr": 0.0,
                "monthly_usage_kwh": monthly_usage,
                "today_usage_kwh": monthly_usage,
                "usage_date": local_now.date().isoformat(),
                "billing_month": local_now.strftime("%Y-%m"),
                "last_meter_energy_kwh": float(reading.energy),
                "current_bill_lkr": current_bill,
                "has_recharged": False,
            }
            _device_accounts[device_id] = account
            incremental_cost = 0.0
            added_usage = monthly_usage
        else:
            _device_accounts[device_id] = account
            # A failed PZEM may report zero. Keep the last valid cumulative
            # value so recovery does not charge the same energy a second time.
            meter_energy = (
                float(reading.energy)
                if reading.pzem_valid
                else float(account["last_meter_energy_kwh"])
            )
            previous_meter_energy = account["last_meter_energy_kwh"]
            local_now = datetime.now(COLOMBO)
            current_month = local_now.strftime("%Y-%m")
            if account.get("billing_month") != current_month:
                account["billing_month"] = current_month
                account["monthly_usage_kwh"] = 0.0
                account["current_bill_lkr"] = 0.0
                added_usage = meter_energy
            else:
                added_usage = max(0.0, meter_energy - previous_meter_energy)
            account["last_meter_energy_kwh"] = meter_energy
            account["monthly_usage_kwh"] += added_usage
            current_date = local_now.date().isoformat()
            if account.get("usage_date") != current_date:
                account["usage_date"] = current_date
                account["today_usage_kwh"] = 0.0
            account["today_usage_kwh"] += added_usage
            previous_bill = account["current_bill_lkr"]
            current_bill = _tariff_engine.calculate_monthly_bill(
                account["monthly_usage_kwh"]
            ).total_lkr
            incremental_cost = max(0.0, current_bill - previous_bill)
            account["current_bill_lkr"] = current_bill
            account["balance_lkr"] = max(
                0.0, account["balance_lkr"] - incremental_cost
            )
        if _effective_account_balance(device_id) <= 0:
            _relay_commands[device_id] = {
                "device_id": device_id,
                "relay_requested": False,
                "credit_allowed": False,
                "balance_lkr": 0.0,
                "command_id": uuid.uuid4().hex,
                "updated_at": datetime.now(timezone.utc).isoformat(),
                "source": (
                    "demo_zero_balance"
                    if _demo_zero_balance_active(device_id)
                    else "credit_lockout"
                ),
                "safety_note": (
                    "Relay forced off for the temporary zero-balance demonstration."
                    if _demo_zero_balance_active(device_id)
                    else "Relay forced off because prepaid credit is empty."
                ),
            }
        has_recharged = _account_has_recharged(device_id, account)
        account["has_recharged"] = has_recharged
        payload.update(
            {
                "device_id": device_id,
                "received_at": datetime.now(timezone.utc).isoformat(),
                "source": "simulator_or_device",
                "monthly_usage_kwh": round(account["monthly_usage_kwh"], 5),
                "today_usage_kwh": round(account["today_usage_kwh"], 5),
                "usage_cost_lkr": round(account["current_bill_lkr"], 2),
                "incremental_cost_lkr": round(incremental_cost, 2),
                "balance_lkr": round(account["balance_lkr"], 2),
                "tariff_id": _tariff_engine.id,
                "has_recharged": has_recharged,
                "minimum_recharge_lkr": 100 if has_recharged else 500,
            }
        )
        alerts_changed = _process_live_alerts(device_id, payload)
        alerts_changed = (
            _process_theft_detection(device_id, payload) or alerts_changed
        )
        readings = _device_readings.setdefault(device_id, deque(maxlen=500))
        previous_reading = readings[-1] if readings else None
        relay_changed = (
            previous_reading is not None
            and previous_reading.get("relay") != payload.get("relay")
        )
        readings.append(payload)
        _pending_usage[device_id] = (
            _pending_usage.get(device_id, 0.0) + added_usage
        )
        now = datetime.now(timezone.utc)
        last_saved = _last_persisted_at.get(device_id)
        persistence_reason = None
        if last_saved is None:
            persistence_reason = "first_reading"
        elif (now - last_saved).total_seconds() >= _persistence_sample_seconds:
            persistence_reason = "scheduled_sample"
        elif alerts_changed:
            persistence_reason = "alert_state_changed"
        elif relay_changed:
            persistence_reason = "relay_state_changed"
        persisted_this_reading = False
        if persistence_reason is not None:
            persisted_payload = dict(payload)
            persisted_payload["usage_delta_kwh"] = round(
                _pending_usage[device_id], 6
            )
            persisted_payload["persistence_reason"] = persistence_reason
            try:
                _local_persistence.save_snapshot(
                    device_id, persisted_payload, dict(account)
                )
                if _local_persistence is not _persistence:
                    try:
                        _persistence.save_snapshot(
                            device_id, persisted_payload, dict(account)
                        )
                        _persistence_error = None
                    except Exception as error:
                        _persistence_error = str(error)
                _pending_usage[device_id] = 0.0
                _last_persisted_at[device_id] = now
                persisted_this_reading = True
                if _local_persistence is _persistence:
                    _persistence_error = None
            except Exception as error:
                _persistence_error = str(error)
    return {
        "accepted": True,
        "device_id": device_id,
        "received_at": payload["received_at"],
        "persisted": persisted_this_reading,
        "persistence_reason": persistence_reason,
        "persistence_backend": _persistence.name,
    }


@app.get("/devices/{device_id}/readings/latest")
def latest_device_reading(device_id: str) -> dict:
    readings = _device_readings.get(device_id)
    if not readings:
        try:
            persisted = _local_persistence.latest_reading(device_id)
        except Exception as error:
            persisted = None
            local_error = error
        else:
            local_error = None
        if persisted is None and _local_persistence is not _persistence:
            try:
                persisted = _persistence.latest_reading(device_id)
            except Exception as error:
                detail = str(error)
                if local_error is not None:
                    detail = f"{local_error}; {detail}"
                raise HTTPException(status_code=503, detail=detail) from error
        if persisted is None:
            raise HTTPException(status_code=404, detail="No readings received")
        return _with_effective_balance(device_id, persisted)
    return _with_effective_balance(device_id, readings[-1])


@app.post("/devices/{device_id}/relay-command")
def set_relay_command(
    device_id: str,
    command: RelayCommandRequest,
) -> dict:
    if device_id != "EM-2048":
        raise HTTPException(status_code=404, detail="Unknown device")
    with _device_lock:
        balance_lkr = _effective_account_balance(device_id)
        credit_allowed = balance_lkr > 0
        safety_locked = _device_safety_locked(device_id)
        if command.relay_requested and not credit_allowed:
            raise HTTPException(
                status_code=402,
                detail="Recharge required before relay can be turned on",
            )
        if command.relay_requested and safety_locked:
            raise HTTPException(
                status_code=423,
                detail="Acknowledge the active safety alert before turning the relay on",
            )
        updated_at = datetime.now(timezone.utc).isoformat()
        payload = {
            "device_id": device_id,
            "relay_requested": command.relay_requested,
            "credit_allowed": credit_allowed,
            "safety_locked": safety_locked,
            "balance_lkr": round(balance_lkr, 2),
            "command_id": uuid.uuid4().hex,
            "updated_at": updated_at,
            "source": "dashboard",
            "safety_note": (
                "ESP32 applies this command only when credit and local safety checks pass."
            ),
        }
        _relay_commands[device_id] = payload
    return payload


@app.get("/devices/{device_id}/security")
def get_theft_security(device_id: str) -> dict:
    if device_id != "EM-2048":
        raise HTTPException(status_code=404, detail="Unknown device")
    return _theft_security_status(device_id)


@app.post("/devices/{device_id}/security")
def set_theft_security(
    device_id: str,
    request: TheftSettingsRequest,
) -> dict:
    if device_id != "EM-2048":
        raise HTTPException(status_code=404, detail="Unknown device")
    with _device_lock:
        account = _load_device_account(device_id)
        account["theft_manual_enabled"] = request.manual_enabled
        _save_account_reliably(device_id, account)
        status = _theft_security_status(device_id)
        _queue_auxiliary_command(
            device_id,
            source="security_settings",
            theft_monitoring_active=status["monitoring_active"],
            theft_mode=status["mode"],
        )
    return status


@app.post("/devices/{device_id}/simulations")
def run_device_simulation(
    device_id: str,
    request: SimulationRequest,
) -> dict:
    """Create presentation-only alerts and briefly exercise indicators."""
    if device_id != "EM-2048":
        raise HTTPException(status_code=404, detail="Unknown device")
    labels = {
        "gas": ("Warning", "Simulation: Gas detected", "MQ-2 gas warning demonstration"),
        "temperature": ("Warning", "Simulation: High temperature", "Overheating warning demonstration"),
        "power": ("Critical", "Simulation: Power overload", "High-load safety demonstration"),
        "voltage": ("Warning", "Simulation: Voltage fault", "Unsafe supply-voltage demonstration"),
        "sensor_pzem": ("Critical", "Simulation: Energy sensor failure", "PZEM communication failure demonstration"),
        "sensor_dht": ("Warning", "Simulation: Environment sensor failure", "DHT22 communication failure demonstration"),
        "theft": ("Critical", "Simulation: Possible intrusion", "Unexpected movement during protected hours"),
    }
    now = datetime.now(timezone.utc).isoformat()
    security = _theft_security_status(device_id)
    if request.scenario == "clear":
        resolved = 0
        for alert in _manual_alerts.get(device_id, {}).values():
            if alert.get("source") != "dashboard_simulation" or alert.get("status") != "active":
                continue
            alert["status"] = "resolved"
            alert["updated_at"] = now
            alert["resolution"] = "Presentation simulation cleared"
            _save_alert_reliably(device_id, alert)
            resolved += 1
        _queue_auxiliary_command(
            device_id,
            source="dashboard_simulation",
            demo_buzzer=False,
            simulation_scenario="clear",
            theft_monitoring_active=security["monitoring_active"],
            theft_mode=security["mode"],
        )
        restored = _restore_relay_after_critical_simulation(device_id)
        return {
            "scenario": "clear",
            "resolved": resolved,
            "relay_restored": restored,
            "message": "Simulations cleared",
        }

    severity, title, message = labels[request.scenario]
    alert = {
        "id": uuid.uuid4().hex,
        "device_id": device_id,
        "type": request.scenario,
        "severity": severity,
        "title": title,
        "message": message,
        "value": 0,
        "unit": "simulation",
        "threshold": 0,
        "status": "active",
        "acknowledged": False,
        "created_at": now,
        "updated_at": now,
        "source": "dashboard_simulation",
        "is_test": True,
    }
    _manual_alerts.setdefault(device_id, {})[alert["id"]] = alert
    _save_alert_reliably(device_id, alert)
    if severity == "Critical":
        _critical_simulation_restore_relay.setdefault(
            device_id, _current_relay_state(device_id)
        )
    _queue_auxiliary_command(
        device_id,
        relay_requested=False if severity == "Critical" else _current_relay_state(device_id),
        source="dashboard_simulation",
        demo_buzzer=True,
        demo_duration_seconds=8,
        simulation_scenario=request.scenario,
        theft_monitoring_active=security["monitoring_active"],
        theft_mode=security["mode"],
    )
    return {
        "scenario": request.scenario,
        "alert": alert,
        "device_signal": (
            "Relay OFF, red LED and buzzer requested"
            if severity == "Critical"
            else "Red LED and buzzer requested for 8 seconds"
        ),
        "message": "Simulation started",
    }


@app.get("/devices/{device_id}/relay-command")
def get_relay_command(
    device_id: str,
    _: None = Depends(require_device_sender),
) -> dict:
    if device_id != "EM-2048":
        raise HTTPException(status_code=404, detail="Unknown device")
    balance_lkr = _effective_account_balance(device_id)
    credit_allowed = balance_lkr > 0
    safety_locked = _device_safety_locked(device_id)
    command = _relay_commands.get(device_id)
    security = _theft_security_status(device_id)
    if command is None:
        return {
            "device_id": device_id,
            "has_command": False,
            "relay_requested": False,
            "credit_allowed": credit_allowed,
            "safety_locked": safety_locked,
            "balance_lkr": round(balance_lkr, 2),
            "command_id": "",
            "theft_monitoring_active": security["monitoring_active"],
            "theft_mode": security["mode"],
        }
    if (not credit_allowed or safety_locked) and command.get("relay_requested"):
        lock_source = "credit_lockout" if not credit_allowed else "safety_lockout"
        lock_note = (
            "Relay forced off because prepaid credit is empty."
            if not credit_allowed
            else "Relay forced off until the active safety alert is acknowledged."
        )
        command = {
            **command,
            "relay_requested": False,
            "credit_allowed": credit_allowed,
            "safety_locked": safety_locked,
            "balance_lkr": round(balance_lkr, 2),
            "command_id": uuid.uuid4().hex,
            "updated_at": datetime.now(timezone.utc).isoformat(),
            "source": lock_source,
            "safety_note": lock_note,
        }
        _relay_commands[device_id] = command
    return {
        "has_command": True,
        **command,
        "credit_allowed": credit_allowed,
        "safety_locked": safety_locked,
        "balance_lkr": round(balance_lkr, 2),
        "theft_monitoring_active": security["monitoring_active"],
        "theft_mode": security["mode"],
    }


@app.get("/devices/{device_id}/readings")
def device_reading_history(device_id: str, limit: int = 50) -> dict:
    if not 1 <= limit <= 500:
        raise HTTPException(status_code=422, detail="Limit must be 1 to 500")
    readings = _device_readings.get(device_id, deque())
    return {"device_id": device_id, "readings": list(readings)[-limit:]}


@app.get("/devices/{device_id}/usage")
def persisted_usage_history(
    device_id: str,
    period: str = "week",
    anchor: str | None = None,
) -> dict:
    if period not in {"day", "week", "month"}:
        raise HTTPException(status_code=422, detail="Invalid usage period")
    today = datetime.now(COLOMBO).date()
    try:
        anchor_date = today if anchor is None else date.fromisoformat(anchor)
    except ValueError as error:
        raise HTTPException(status_code=422, detail="Invalid anchor date") from error
    if anchor_date > today:
        raise HTTPException(status_code=422, detail="Future usage is unavailable")

    if period == "day":
        start_date = anchor_date
        count = 24
    elif period == "week":
        start_date = anchor_date - timedelta(days=anchor_date.weekday())
        count = 7
    else:
        start_date = anchor_date.replace(day=1)
        next_month = (
            start_date.replace(day=28) + timedelta(days=4)
        ).replace(day=1)
        count = (next_month - start_date).days
    start_local = datetime.combine(
        start_date, datetime.min.time(), tzinfo=COLOMBO
    )
    end_local = (
        start_local + timedelta(days=1)
        if period == "day"
        else start_local + timedelta(days=count)
    )
    source = _persistence.name
    warning = None
    try:
        rows = _persistence.readings_between(
            device_id,
            start_local.astimezone(timezone.utc),
            end_local.astimezone(timezone.utc),
        )
    except Exception as error:
        start_utc = start_local.astimezone(timezone.utc)
        end_utc = end_local.astimezone(timezone.utc)
        rows = [
            row
            for row in _device_readings.get(device_id, deque())
            if start_utc
            <= datetime.fromisoformat(row["received_at"]).astimezone(timezone.utc)
            < end_utc
        ]
        source = "live_memory_fallback"
        warning = str(error)
    values = [0.0] * count
    previous_monthly_usage: float | None = None
    for row in rows:
        timestamp = datetime.fromisoformat(row["received_at"]).astimezone(
            COLOMBO
        )
        index = (
            timestamp.hour
            if period == "day"
            else (timestamp.date() - start_date).days
        )
        if 0 <= index < count:
            if "usage_delta_kwh" in row:
                delta = float(row.get("usage_delta_kwh", 0.0))
            else:
                monthly_usage = float(row.get("monthly_usage_kwh", 0.0))
                delta = (
                    0.0
                    if previous_monthly_usage is None
                    else max(0.0, monthly_usage - previous_monthly_usage)
                )
                previous_monthly_usage = monthly_usage
            values[index] += delta
    response = {
        "device_id": device_id,
        "period": period,
        "anchor": anchor_date.isoformat(),
        "start": start_date.isoformat(),
        "values": [round(value, 5) for value in values],
        "total_units": round(sum(values), 5),
        "source": source,
    }
    if warning:
        response["warning"] = warning
    return response


@app.get("/devices/{device_id}/alerts")
def device_alerts(device_id: str, limit: int = 100) -> dict:
    if not 1 <= limit <= 500:
        raise HTTPException(status_code=422, detail="Limit must be 1 to 500")
    source = _local_persistence.name
    warning = None
    try:
        persisted_alerts = _local_persistence.list_alerts(device_id, limit)
    except Exception as error:
        persisted_alerts = []
        source = f"{_local_persistence.name}_unavailable"
        warning = str(error)
    if not persisted_alerts and _local_persistence is not _persistence:
        try:
            persisted_alerts = _persistence.list_alerts(device_id, limit)
            source = _persistence.name
        except Exception as error:
            warning = str(error)
    alerts = _merged_device_alerts(device_id, persisted_alerts, limit)
    active_unacknowledged = sum(
        alert.get("status") == "active"
        and not alert.get("acknowledged", False)
        for alert in alerts
    )
    response = {
        "device_id": device_id,
        "alerts": alerts,
        "active_unacknowledged_count": active_unacknowledged,
        "source": source,
    }
    if warning:
        response["warning"] = warning
    return response


@app.post("/devices/{device_id}/alerts/test")
def create_test_device_alert(
    device_id: str,
    request: TestAlertRequest,
    _: None = Depends(require_tariff_admin),
) -> dict:
    """Create an explicit dashboard test alert without changing safety thresholds."""
    global _persistence_error
    now = datetime.now(timezone.utc).isoformat()
    labels = {
        "gas": ("Test gas alert", "Synthetic MQ-2 alert for dashboard testing"),
        "temperature": (
            "Test overheating alert",
            "Synthetic temperature alert for dashboard testing",
        ),
        "power": (
            "Test power alert",
            "Synthetic high-power alert for dashboard testing",
        ),
        "voltage": (
            "Test voltage alert",
            "Synthetic supply-voltage alert for dashboard testing",
        ),
    }
    title, message = labels[request.alert_type]
    alert = {
        "id": uuid.uuid4().hex,
        "device_id": device_id,
        "type": request.alert_type,
        "severity": request.severity,
        "title": title,
        "message": message,
        "value": 0,
        "unit": "test",
        "threshold": 0,
        "status": "active",
        "acknowledged": False,
        "created_at": now,
        "updated_at": now,
        "source": "administrator_test",
        "is_test": True,
    }
    _manual_alerts.setdefault(device_id, {})[alert["id"]] = alert
    try:
        _save_alert_reliably(device_id, alert)
    except Exception as error:
        _persistence_error = str(error)
        raise HTTPException(status_code=503, detail=str(error)) from error
    return {"alert": alert, "message": "Test alert created"}


@app.post("/devices/{device_id}/alerts/test/{alert_id}/resolve")
def resolve_test_device_alert(
    device_id: str,
    alert_id: str,
    _: None = Depends(require_tariff_admin),
) -> dict:
    """Resolve only alerts that were created by the administrator test endpoint."""
    global _persistence_error
    try:
        persisted_alerts = _persistence.list_alerts(device_id, 500)
    except Exception as error:
        persisted_alerts = []
        _persistence_error = str(error)

    try:
        alert = next(
            (item for item in persisted_alerts if item.get("id") == alert_id),
            _manual_alerts.get(device_id, {}).get(alert_id),
        )
        if alert is None:
            raise HTTPException(status_code=404, detail="Alert not found")
        if alert.get("source") != "administrator_test":
            raise HTTPException(
                status_code=409,
                detail="Only administrator test alerts can be resolved here",
            )
        alert["status"] = "resolved"
        alert["updated_at"] = datetime.now(timezone.utc).isoformat()
        alert["resolution"] = "Administrator completed the safety alert test"
        _manual_alerts.setdefault(device_id, {})[alert_id] = alert
        try:
            _persistence.save_alert(device_id, alert)
            _persistence_error = None
        except Exception as error:
            _persistence_error = str(error)
    except HTTPException:
        raise
    return {"id": alert_id, "status": "resolved"}


@app.post("/devices/{device_id}/alerts/{alert_id}/acknowledge")
def acknowledge_device_alert(
    device_id: str,
    alert_id: str,
    _: None = Depends(require_alert_operator),
) -> dict:
    acknowledged = False
    acknowledged_alert: dict | None = None
    try:
        acknowledged_alert = next(
            (
                alert
                for alert in _local_persistence.list_alerts(device_id, 500)
                if alert.get("id") == alert_id
            ),
            None,
        )
    except Exception:
        pass
    try:
        acknowledged = _local_persistence.acknowledge_alert(device_id, alert_id)
        if _local_persistence is not _persistence:
            acknowledged = (
                _persistence.acknowledge_alert(device_id, alert_id) or acknowledged
            )
    except Exception as error:
        global _persistence_error
        _persistence_error = str(error)
    for alert in _active_alerts.get(device_id, {}).values():
        if alert["id"] == alert_id:
            alert["acknowledged"] = True
            alert["updated_at"] = datetime.now(timezone.utc).isoformat()
            acknowledged_alert = alert
            _save_alert_reliably(device_id, alert)
            acknowledged = True
    manual_alert = _manual_alerts.get(device_id, {}).get(alert_id)
    if manual_alert is not None:
        manual_alert["acknowledged"] = True
        manual_alert["updated_at"] = datetime.now(timezone.utc).isoformat()
        acknowledged_alert = manual_alert
        _save_alert_reliably(device_id, manual_alert)
        acknowledged = True
    if not acknowledged:
        raise HTTPException(status_code=404, detail="Alert not found")
    relay_restored = _restore_relay_after_critical_simulation(device_id)
    if (
        not relay_restored
        and acknowledged_alert is not None
        and acknowledged_alert.get("severity") == "Critical"
        and not _device_safety_locked(device_id)
        and _effective_account_balance(device_id) > 0
    ):
        _queue_auxiliary_command(
            device_id,
            relay_requested=True,
            source="critical_alert_acknowledged",
            demo_buzzer=False,
            simulation_scenario="clear",
            safety_locked=False,
            safety_note="Critical alert acknowledged; relay automatically turned on.",
        )
        relay_restored = True
    return {
        "id": alert_id,
        "acknowledged": True,
        "relay_restored": relay_restored,
    }


@app.post("/devices/{device_id}/alerts/acknowledge-all")
def acknowledge_all_device_alerts(
    device_id: str,
    _: None = Depends(require_alert_operator),
) -> dict:
    count = 0
    critical_acknowledged = False
    try:
        alerts = _local_persistence.list_alerts(device_id, 500)
        for alert in alerts:
            if alert.get("status") == "active" and not alert.get(
                "acknowledged", False
            ):
                critical_acknowledged |= alert.get("severity") == "Critical"
                saved = _local_persistence.acknowledge_alert(device_id, alert["id"])
                if _local_persistence is not _persistence:
                    saved = (
                        _persistence.acknowledge_alert(device_id, alert["id"])
                        or saved
                    )
                if saved:
                    count += 1
    except Exception as error:
        global _persistence_error
        _persistence_error = str(error)

    for alert in _active_alerts.get(device_id, {}).values():
        if alert.get("status") == "active" and not alert.get("acknowledged", False):
            count += 1
            critical_acknowledged |= alert.get("severity") == "Critical"
        alert["acknowledged"] = True
        alert["updated_at"] = datetime.now(timezone.utc).isoformat()
        _save_alert_reliably(device_id, alert)
    for alert in _manual_alerts.get(device_id, {}).values():
        if alert.get("status") == "active" and not alert.get("acknowledged", False):
            count += 1
            critical_acknowledged |= alert.get("severity") == "Critical"
        alert["acknowledged"] = True
        alert["updated_at"] = datetime.now(timezone.utc).isoformat()
        _save_alert_reliably(device_id, alert)
    relay_restored = _restore_relay_after_critical_simulation(device_id)
    if (
        not relay_restored
        and critical_acknowledged
        and not _device_safety_locked(device_id)
        and _effective_account_balance(device_id) > 0
    ):
        _queue_auxiliary_command(
            device_id,
            relay_requested=True,
            source="critical_alerts_acknowledged",
            demo_buzzer=False,
            simulation_scenario="clear",
            safety_locked=False,
            safety_note="Critical alerts acknowledged; relay automatically turned on.",
        )
        relay_restored = True
    return {
        "acknowledged_count": count,
        "relay_restored": relay_restored,
    }


@app.post("/devices/{device_id}/account/recharge")
def recharge_device(
    device_id: str,
    recharge: RechargeRequest,
) -> dict:
    global _persistence_error
    if device_id != "EM-2048":
        raise HTTPException(status_code=404, detail="Unknown device")
    with _device_lock:
        account = _device_accounts.get(device_id)
        if account is None:
            try:
                account = _local_persistence.load_account(device_id)
            except Exception as error:
                _persistence_error = str(error)
        if account is None and _local_persistence is not _persistence:
            try:
                account = _persistence.load_account(device_id)
            except Exception as error:
                _persistence_error = str(error)
        if account is None:
            local_now = datetime.now(COLOMBO)
            account = {
                "balance_lkr": 0.0,
                "monthly_usage_kwh": 0.0,
                "today_usage_kwh": 0.0,
                "usage_date": local_now.date().isoformat(),
                "billing_month": local_now.strftime("%Y-%m"),
                "last_meter_energy_kwh": 0.0,
                "current_bill_lkr": 0.0,
                "has_recharged": False,
            }
        has_recharged = _account_has_recharged(device_id, account)
        minimum_amount = 100.0 if has_recharged else 500.0
        if recharge.amount_lkr < minimum_amount:
            raise HTTPException(
                status_code=422,
                detail=(
                    f"Minimum {'recharge' if has_recharged else 'first recharge'} "
                    f"is Rs. {minimum_amount:.0f}"
                ),
            )
        _device_accounts[device_id] = account
        account["balance_lkr"] += recharge.amount_lkr
        account["has_recharged"] = True
        if _demo_zero_balance_active(device_id):
            _demo_zero_balance_until.pop(device_id, None)
            _resolve_demo_zero_balance_alert(
                device_id,
                "Temporary demonstration ended after a demo recharge",
            )
        readings = _device_readings.get(device_id)
        if readings:
            readings[-1]["balance_lkr"] = round(account["balance_lkr"], 2)
        result = {
            "receipt_id": f"DEMO-{uuid.uuid4().hex[:10].upper()}",
            "device_id": device_id,
            "amount_lkr": round(recharge.amount_lkr, 2),
            "balance_lkr": round(account["balance_lkr"], 2),
            "created_at": datetime.now(timezone.utc).isoformat(),
            "payment_method": "demo_card",
            "demo": True,
        }
        cached_recharges = _device_recharges.setdefault(device_id, deque(maxlen=100))
        cached_recharges.appendleft(dict(result))
        try:
            _local_persistence.record_recharge(device_id, result, dict(account))
            if _local_persistence is not _persistence:
                try:
                    _persistence.record_recharge(
                        device_id, result, dict(account)
                    )
                    _persistence_error = None
                except Exception as error:
                    _persistence_error = str(error)
                    result["storage_warning"] = (
                        "Recharge is safely stored on this computer. Cloud "
                        "history will sync when Firestore is available."
                    )
            else:
                _persistence_error = None
        except Exception as error:
            _persistence_error = str(error)
            result["storage_warning"] = (
                "Recharge is active in this running session, but durable storage "
                "did not confirm the transaction."
            )
    return result


@app.post("/devices/{device_id}/account/demo-zero-balance")
def set_demo_zero_balance(
    device_id: str,
    request: DemoZeroBalanceRequest,
    _: None = Depends(require_tariff_admin),
) -> dict:
    """Temporarily show zero credit without changing the stored balance."""
    if device_id != "EM-2048":
        raise HTTPException(status_code=404, detail="Unknown device")

    with _device_lock:
        actual_balance = _current_account_balance(device_id)
        now = datetime.now(timezone.utc)
        if request.enabled:
            if actual_balance <= 0:
                raise HTTPException(
                    status_code=409,
                    detail=(
                        "The real balance is already empty. Recharge first so "
                        "the demonstration has a balance to restore."
                    ),
                )
            expires_at = now + timedelta(seconds=request.duration_seconds)
            _demo_zero_balance_until[device_id] = expires_at
            _relay_commands[device_id] = {
                "device_id": device_id,
                "relay_requested": False,
                "credit_allowed": False,
                "balance_lkr": 0.0,
                "command_id": uuid.uuid4().hex,
                "updated_at": now.isoformat(),
                "source": "demo_zero_balance",
                "safety_note": (
                    "Relay forced off for the temporary zero-balance demonstration."
                ),
            }
            alert_id = _demo_zero_balance_alert_id(device_id)
            _manual_alerts.setdefault(device_id, {})[alert_id] = {
                "id": alert_id,
                "device_id": device_id,
                "type": "balance",
                "severity": "Critical",
                "title": "Demo: recharge required",
                "message": (
                    "Temporary zero-balance demonstration is active. The real "
                    f"saved balance is Rs. {actual_balance:.2f}."
                ),
                "value": 0.0,
                "unit": "LKR",
                "threshold": 0.01,
                "status": "active",
                "acknowledged": False,
                "created_at": now.isoformat(),
                "updated_at": now.isoformat(),
                "source": "demo_zero_balance",
                "is_test": True,
            }
            message = (
                "Zero-balance demonstration started. Relay ON is blocked and "
                "the real prepaid balance is unchanged."
            )
        else:
            _demo_zero_balance_until.pop(device_id, None)
            _resolve_demo_zero_balance_alert(
                device_id,
                "Real prepaid balance restored by the administrator",
            )
            expires_at = None
            message = (
                "Real prepaid balance restored. The relay remains OFF until "
                "the user turns it on."
            )

    return {
        "device_id": device_id,
        "demo_zero_balance": request.enabled,
        "balance_lkr": 0.0 if request.enabled else round(actual_balance, 2),
        "actual_balance_lkr": round(actual_balance, 2),
        "demo_expires_at": (
            expires_at.isoformat() if expires_at is not None else None
        ),
        "message": message,
    }


@app.get("/devices/{device_id}/account/recharges")
def device_recharges(device_id: str, limit: int = 20) -> dict:
    if device_id != "EM-2048":
        raise HTTPException(status_code=404, detail="Unknown device")
    if not 1 <= limit <= 100:
        raise HTTPException(status_code=422, detail="Limit must be 1 to 100")
    storage_warning = None
    try:
        recharges = _local_persistence.list_recharges(device_id, limit)
    except Exception as error:
        recharges = []
        storage_warning = str(error)
    if not recharges and _local_persistence is not _persistence:
        try:
            recharges = _persistence.list_recharges(device_id, limit)
        except Exception as error:
            storage_warning = str(error)
    cached = list(_device_recharges.get(device_id, ()))
    if cached:
        by_receipt = {item.get("receipt_id"): item for item in recharges}
        for item in reversed(cached):
            receipt_id = item.get("receipt_id")
            if receipt_id and receipt_id not in by_receipt:
                recharges.insert(0, item)
        recharges = recharges[:limit]
    response = {
        "device_id": device_id,
        "recharges": recharges,
        "source": _local_persistence.name,
    }
    if storage_warning:
        response["storage_warning"] = storage_warning
    return response


def _training_date(path: Path) -> str | None:
    if not path.exists():
        return None
    return datetime.fromtimestamp(path.stat().st_mtime, tz=COLOMBO).date().isoformat()


@app.get("/predict/model-report")
def model_performance_report() -> dict:
    """Summarise prototype AI model datasets, metrics, and limitations."""
    if (
        _metrics is None
        or _anomaly_metrics is None
        or _appliance_metrics is None
        or _safety_metrics is None
    ):
        raise HTTPException(status_code=503, detail="Model metrics are not ready")

    forecasting_test = _metrics["test"]
    anomaly_test = _anomaly_metrics["test"]
    appliance_known = _appliance_metrics["known_device_random_split"]
    appliance_unseen = _appliance_metrics["device_holdout"]
    smoke = _safety_metrics["smoke_fire"]
    electrical = _safety_metrics["electrical_fault"]
    gas = _safety_metrics["gas_identity"]

    return {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "scope": "prototype_public_dataset_models",
        "tensorflow_status": "planned_later_storage_limited",
        "summary": (
            "The current AI layer is a public-dataset prototype. It proves the "
            "forecasting, anomaly, appliance, and safety workflows before the "
            "final TensorFlow/Keras retraining step."
        ),
        "items": [
            {
                "feature": "Energy consumption prediction",
                "dataset": "Household Power Consumption",
                "model": _metrics["selected_model"],
                "task": "Predict tomorrow's total household energy use from timestamped voltage, current, power, and sub-meter readings.",
                "samples": _metrics["samples"],
                "primary_metric": "MAE",
                "primary_score": round(forecasting_test["mae_kwh"], 3),
                "primary_unit": "units/kWh",
                "secondary_metric": "R²",
                "secondary_score": round(forecasting_test["r2"], 3),
                "training_date": _training_date(DEFAULT_METRICS),
                "status": "Needs tuning",
                "limitation": (
                    "This is useful for demonstrating the forecast pipeline, but "
                    "the current MAE/R² show it still needs better time-series "
                    "features or a TensorFlow sequence model before production use."
                ),
            },
            {
                "feature": "Abnormal usage detection",
                "dataset": "Smart Meter Electricity Consumption Dataset",
                "model": _anomaly_metrics["selected_model"],
                "task": "Classify whether the latest usage pattern looks normal, watch-level, or abnormal.",
                "samples": _anomaly_metrics["samples"],
                "primary_metric": "F1 abnormal",
                "primary_score": round(anomaly_test["f1_abnormal"], 3),
                "primary_unit": "score",
                "secondary_metric": "Recall abnormal",
                "secondary_score": round(anomaly_test["recall_abnormal"], 3),
                "training_date": _training_date(DEFAULT_ANOMALY_METRICS),
                "status": "Working prototype",
                "limitation": (
                    "It uses public anomaly labels, so the final threshold should "
                    "be calibrated to Sri Lankan household usage after deployment."
                ),
            },
            {
                "feature": "Appliance usage detection",
                "dataset": "Real Appliance Power Signatures / Household Appliances Power Consumption",
                "model": (
                    _appliance_artifact["model_name"]
                    if _appliance_artifact
                    else _appliance_metrics.get("model_name", "extra_trees")
                ),
                "task": "Estimate appliance category from short power-signature windows, then show likely high-load appliances.",
                "samples": {
                    "feature_rows": _appliance_metrics["feature_rows"],
                    "train_windows": _appliance_metrics["train_windows"],
                    "test_windows": _appliance_metrics["test_windows"],
                },
                "primary_metric": "Known-device accuracy",
                "primary_score": round(appliance_known["accuracy"], 3),
                "primary_unit": "score",
                "secondary_metric": "Unseen-device macro-F1",
                "secondary_score": round(appliance_unseen["macro_f1"], 3),
                "training_date": _training_date(DEFAULT_APPLIANCE_METRICS),
                "status": "Prototype sample classifier",
                "limitation": (
                    "Known-device score is strong, but unseen-device macro-F1 is "
                    "low; this means real homes need more appliance examples or "
                    "a TensorFlow CNN/LSTM signature model."
                ),
            },
            {
                "feature": "Fire / smoke safety prediction",
                "dataset": "Smoke Detection Dataset",
                "model": _smoke_artifact["model_name"] if _smoke_artifact else "extra_trees",
                "task": "Classify smoke/fire alarm risk from IoT-style environmental sensor readings.",
                "samples": {
                    "rows": smoke["rows"],
                    "train_rows": smoke["train_rows"],
                    "test_rows": smoke["test_rows"],
                },
                "primary_metric": "F1 fire",
                "primary_score": round(smoke["f1_fire"], 3),
                "primary_unit": "score",
                "secondary_metric": "Balanced accuracy",
                "secondary_score": round(smoke["balanced_accuracy"], 3),
                "training_date": _training_date(SAFETY_METRICS),
                "status": "Working prototype",
                "limitation": (
                    "The public sensor columns are not identical to MQ-2/DHT22, "
                    "therefore the live dashboard also uses transparent calibrated "
                    "hardware thresholds."
                ),
            },
            {
                "feature": "Electrical fault risk",
                "dataset": "Power Quality Fault Detection Dataset",
                "model": _electrical_artifact["model_name"] if _electrical_artifact else "extra_trees",
                "task": "Detect unsafe electrical conditions such as sag, swell, transient, and harmonic patterns.",
                "samples": {"rows": electrical["rows"]},
                "primary_metric": "Macro-F1",
                "primary_score": round(electrical["macro_f1"], 3),
                "primary_unit": "score",
                "secondary_metric": "Accuracy",
                "secondary_score": round(electrical["accuracy"], 3),
                "training_date": _training_date(SAFETY_METRICS),
                "status": "Working prototype",
                "limitation": (
                    "The model is trained on public waveform/fault examples; "
                    "relay shutdown must remain manual/safe until real hardware "
                    "validation is completed."
                ),
            },
            {
                "feature": "Gas identity support",
                "dataset": "Gas Sensor Array Drift Dataset",
                "model": _gas_artifact["model_name"] if _gas_artifact else "extra_trees",
                "task": "Support gas-type research by classifying gas identity patterns from sensor-array readings.",
                "samples": {
                    "train_rows": gas["train_rows"],
                    "test_rows": gas["test_rows"],
                },
                "primary_metric": "Macro-F1",
                "primary_score": round(gas["macro_f1"], 3),
                "primary_unit": "score",
                "secondary_metric": "Accuracy",
                "secondary_score": round(gas["accuracy"], 3),
                "training_date": _training_date(SAFETY_METRICS),
                "status": "Research support model",
                "limitation": (
                    "This dataset identifies gas classes, not safe/unsafe leak "
                    "probability. For live alerts, the project correctly uses "
                    "MQ-2 raw threshold rules."
                ),
            },
        ],
    }


@app.get("/predict/energy")
def predict_energy(
    balance_lkr: float = 850.0,
    tariff_lkr_per_kwh: float | None = None,
    monthly_usage_kwh: float = 4.8,
    billing_days_elapsed: int = 1,
) -> dict:
    if _artifact is None or _latest_features is None or _metrics is None:
        raise HTTPException(status_code=503, detail="Model is not ready")
    if balance_lkr < 0 or monthly_usage_kwh < 0:
        raise HTTPException(status_code=422, detail="Invalid billing values")

    prediction = float(_artifact["model"].predict(_latest_features)[0])
    estimated_cost = _tariff_engine.incremental_cost(
        monthly_usage_kwh, prediction
    )
    # Calendar months may contain 31 days while the configured prepaid
    # billing cycle is 30 days. Keep the balance simulation within the
    # tariff engine's valid zero-based cycle range instead of failing the
    # ESP32 display-summary request on the last day of a long month.
    billing_cycle_days = int(
        _tariff_engine.configuration["billing_cycle_days"]
    )
    balance_cycle_day = min(
        max(0, int(billing_days_elapsed)),
        billing_cycle_days - 1,
    )
    remaining_days = _tariff_engine.estimate_balance_days(
        balance_lkr=balance_lkr,
        daily_usage_kwh=prediction,
        current_month_kwh=monthly_usage_kwh,
        billing_days_elapsed=balance_cycle_day,
    )
    test_metrics = _metrics["test"]
    return {
        "prediction_kwh": round(prediction, 3),
        "forecast_horizon_hours": 24,
        "estimated_cost_lkr": round(estimated_cost, 2),
        "estimated_remaining_days": round(remaining_days, 1),
        "model_name": _artifact["model_name"],
        "test_mae_kwh": round(test_metrics["mae_kwh"], 3),
        "test_r2": round(test_metrics["r2"], 3),
        "quality": "prototype",
        "source": "trained_model",
        "tariff": {
            "id": _tariff_engine.id,
            "category": _tariff_engine.configuration["category"],
            "effective_from": _tariff_engine.configuration["effective_from"],
            "source_url": _tariff_engine.configuration["source_url"],
            "monthly_usage_before_forecast_kwh": monthly_usage_kwh,
            "billing_days_elapsed": balance_cycle_day,
            "calculation": "progressive_block_increment",
        },
    }


def _recent_household_balance_estimate(
    device_id: str | None,
    balance_lkr: float,
    monthly_usage_kwh: float,
    billing_days_elapsed: int,
    lookback_days: int = 7,
    minimum_history_hours: float = 24.0,
) -> dict:
    """Estimate prepaid lifetime from recent measured household consumption.

    The public forecasting model is intentionally not used here. Credit lifetime
    must be based on the customer's own stored meter readings so a prototype
    forecast cannot create a misleading low-balance warning.
    """
    collecting = {
        "current_balance_lkr": round(balance_lkr, 2),
        "daily_usage_kwh": None,
        "daily_cost_lkr": None,
        "remaining_days": None,
        "ready": False,
        "status": "collecting",
        "method": "recent measured ESP32 usage",
        "source": "meter_history",
        "history_days": 0.0,
        "minimum_history_hours": minimum_history_hours,
        "message": "Collecting at least 24 hours of meter usage data.",
        "tariff_id": _tariff_engine.id,
    }
    if not device_id:
        return collecting
    if balance_lkr <= 0:
        return {
            **collecting,
            "remaining_days": 0.0,
            "ready": True,
            "status": "critical",
            "message": "No prepaid credit remains. Recharge is required.",
        }

    end_utc = datetime.now(timezone.utc)
    start_utc = end_utc - timedelta(days=lookback_days)
    rows: list[dict] = []
    source = _local_persistence.name
    try:
        rows = _local_persistence.readings_between(
            device_id, start_utc, end_utc
        )
    except Exception:
        rows = []
    if not rows and _local_persistence is not _persistence:
        try:
            rows = _persistence.readings_between(
                device_id, start_utc, end_utc
            )
            source = _persistence.name
        except Exception:
            rows = []
    if not rows:
        rows = [
            row
            for row in _device_readings.get(device_id, deque())
            if datetime.fromisoformat(row["received_at"]).astimezone(
                timezone.utc
            ) >= start_utc
        ]
        source = "live_memory"

    timed_rows: list[tuple[datetime, dict]] = []
    for row in rows:
        try:
            timestamp = datetime.fromisoformat(
                str(row["received_at"]).replace("Z", "+00:00")
            )
            if timestamp.tzinfo is None:
                timestamp = timestamp.replace(tzinfo=timezone.utc)
            timed_rows.append((timestamp.astimezone(timezone.utc), row))
        except (KeyError, TypeError, ValueError):
            continue
    timed_rows.sort(key=lambda item: item[0])
    if len(timed_rows) < 2:
        return {**collecting, "source": source}

    history_hours = (
        timed_rows[-1][0] - timed_rows[0][0]
    ).total_seconds() / 3600
    history_days = history_hours / 24
    if history_hours < minimum_history_hours:
        return {
            **collecting,
            "source": source,
            "history_days": round(history_days, 2),
            "message": (
                f"Collecting meter data: {history_hours:.1f} of "
                f"{minimum_history_hours:.0f} required hours recorded."
            ),
        }

    measured_usage = 0.0
    # Skip the first stored delta because it may include energy accumulated
    # before the selected seven-day observation window.
    if any("usage_delta_kwh" in row for _, row in timed_rows[1:]):
        measured_usage = sum(
            max(0.0, float(row.get("usage_delta_kwh", 0.0)))
            for _, row in timed_rows[1:]
        )
    else:
        previous_energy = float(timed_rows[0][1].get("energy", 0.0))
        for _, row in timed_rows[1:]:
            current_energy = float(row.get("energy", previous_energy))
            measured_usage += max(0.0, current_energy - previous_energy)
            previous_energy = current_energy

    daily_usage = measured_usage / history_days if history_days > 0 else 0.0
    if daily_usage <= 0:
        return {
            **collecting,
            "source": source,
            "history_days": round(history_days, 2),
            "status": "no_recent_usage",
            "message": "No measurable consumption was recorded recently.",
        }

    billing_cycle_days = int(
        _tariff_engine.configuration["billing_cycle_days"]
    )
    balance_cycle_day = min(
        max(0, int(billing_days_elapsed)), billing_cycle_days - 1
    )
    daily_cost = _tariff_engine.incremental_cost(
        monthly_usage_kwh, daily_usage
    )
    remaining_days = _tariff_engine.estimate_balance_days(
        balance_lkr=balance_lkr,
        daily_usage_kwh=daily_usage,
        current_month_kwh=monthly_usage_kwh,
        billing_days_elapsed=balance_cycle_day,
        maximum_days=3650,
    )
    return {
        **collecting,
        "daily_usage_kwh": round(daily_usage, 5),
        "daily_cost_lkr": round(daily_cost, 2),
        "remaining_days": round(remaining_days, 1),
        "ready": True,
        "status": (
            "critical" if remaining_days < 1
            else "low" if remaining_days < 3
            else "healthy"
        ),
        "source": source,
        "history_days": round(history_days, 2),
        "message": (
            f"Estimated from {min(history_days, lookback_days):.1f} days "
            "of recent measured usage."
        ),
    }


@app.get("/predict/anomaly")
def predict_anomaly(
    electricity_consumed: float | None = None,
    temperature: float | None = None,
    humidity: float | None = None,
    wind_speed: float | None = None,
    avg_past_consumption: float | None = None,
) -> dict:
    if (
        _anomaly_artifact is None
        or _latest_anomaly_features is None
        or _anomaly_metrics is None
    ):
        raise HTTPException(status_code=503, detail="Model is not ready")

    supplied = [
        electricity_consumed,
        temperature,
        humidity,
        wind_speed,
        avg_past_consumption,
    ]
    if any(value is not None for value in supplied):
        if not all(value is not None for value in supplied):
            raise HTTPException(
                status_code=422,
                detail="Supply all five normalized anomaly features",
            )
        if not all(0 <= value <= 1 for value in supplied if value is not None):
            raise HTTPException(
                status_code=422,
                detail="Anomaly features must be normalized from 0 to 1",
            )
        row = pd.DataFrame(
            [supplied], columns=ANOMALY_FEATURE_COLUMNS
        )
        source = "request_normalized_features"
    else:
        row = _latest_anomaly_features
        source = "latest_dataset_sample"

    probability = float(
        _anomaly_artifact["model"].predict_proba(row)[0, 1]
    )
    abnormal = probability >= 0.5
    level = "abnormal" if probability >= 0.5 else "watch" if probability >= 0.2 else "normal"
    test = _anomaly_metrics["test"]
    result = {
        "is_abnormal": abnormal,
        "level": level,
        "label": level.title(),
        "level_explanation": (
            "High probability of unusual usage; inspect active appliances."
            if level == "abnormal"
            else "Usage is not abnormal, but it is higher than the normal band."
            if level == "watch"
            else "Usage pattern is within the normal band."
        ),
        "abnormal_probability": round(probability, 4),
        "model_name": _anomaly_artifact["model_name"],
        "test_precision": round(test["precision_abnormal"], 4),
        "test_recall": round(test["recall_abnormal"], 4),
        "test_f1": round(test["f1_abnormal"], 4),
        "quality": "prototype",
        "source": source,
    }
    simulation = _active_simulation("EM-2048")
    simulation_probabilities = {
        "power": 0.98,
        "voltage": 0.88,
        "sensor_pzem": 1.0,
        "theft": 1.0,
    }
    if simulation is not None and simulation.get("type") in simulation_probabilities:
        probability = simulation_probabilities[simulation["type"]]
        result.update(
            {
                "is_abnormal": True,
                "level": "abnormal",
                "label": "Abnormal",
                "level_explanation": (
                    f"Active {simulation['title'].lower()} is being demonstrated."
                ),
                "abnormal_probability": probability,
                "source": "dashboard_simulation",
            }
        )
    return result


@app.get("/predict/appliances")
def predict_appliances(limit: int = 3) -> dict:
    if (
        _appliance_artifact is None
        or _appliance_samples is None
        or _appliance_metrics is None
    ):
        raise HTTPException(status_code=503, detail="Model is not ready")
    if limit < 1 or limit > 5:
        raise HTTPException(status_code=422, detail="Limit must be 1 to 5")

    features = _appliance_samples[
        _appliance_artifact["feature_columns"]
    ]
    probabilities = _appliance_artifact["model"].predict_proba(features)
    classes = _appliance_artifact["model"].classes_
    labels = classes[probabilities.argmax(axis=1)]
    confidence = probabilities.max(axis=1)
    candidates = _appliance_samples[
        ["mean_w", "energy_wh", "source_file"]
    ].copy()
    candidates["category"] = labels
    candidates["confidence"] = confidence
    candidates = candidates.sort_values("confidence", ascending=False)

    detections = []
    seen = set()
    for row in candidates.itertuples(index=False):
        if row.category in seen:
            continue
        seen.add(row.category)
        detections.append(
            {
                "category": row.category,
                "confidence": round(float(row.confidence), 4),
                "mean_power_w": round(float(row.mean_w), 2),
                "window_energy_wh": round(float(row.energy_wh), 3),
                "sample_source": row.source_file,
            }
        )
        if len(detections) == limit:
            break

    return {
        "detections": detections,
        "model_name": _appliance_artifact["model_name"],
        "known_device_accuracy": round(
            _appliance_metrics["known_device_random_split"]["accuracy"], 4
        ),
        "known_device_macro_f1": round(
            _appliance_metrics["known_device_random_split"]["macro_f1"], 4
        ),
        "unseen_device_macro_f1": round(
            _appliance_metrics["device_holdout"]["macro_f1"], 4
        ),
        "quality": "known_device_prototype",
        "source": "isolated_smart_plug_dataset_samples",
    }


@app.get("/predict/safety")
def predict_safety() -> dict:
    try:
        reading = latest_device_reading("EM-2048")
    except HTTPException:
        reading = None
    if reading is None:
        summary = {
            "risk_level": "low",
            "overall_risk_probability": 0.0,
            "fire_probability": 0.0,
            "electrical_fault_probability": 0.0,
            "temperature_risk_probability": 0.0,
            "gas_risk_probability": 0.0,
            "electrical_condition": "Waiting for meter",
            "gas_identity": "Waiting for meter",
            "gas_identity_confidence": 0.0,
            "gas_leak_probability_available": False,
            "active_conditions": [],
            "quality": "no_live_reading",
            "source": "no_live_reading",
        }
    else:
        summary = live_safety_summary(reading)
    simulation = _active_simulation("EM-2048")
    simulation_risks = {
        "gas": (0.82, 0.0, 0.0),
        "temperature": (0.0, 0.0, 0.82),
        "power": (0.0, 1.0, 0.0),
        "voltage": (0.0, 0.9, 0.0),
        "sensor_pzem": (0.0, 1.0, 0.0),
        "sensor_dht": (0.0, 0.0, 0.85),
        "theft": (0.0, 0.0, 0.0),
    }
    if simulation is not None and simulation.get("type") in simulation_risks:
        gas_risk, electrical_risk, temperature_risk = simulation_risks[
            simulation["type"]
        ]
        overall = max(
            gas_risk,
            electrical_risk,
            temperature_risk,
            1.0 if simulation["type"] == "theft" else 0.0,
        )
        summary.update(
            {
                "risk_level": "high" if overall >= 0.7 else "moderate",
                "overall_risk_probability": overall,
                "electrical_fault_probability": electrical_risk,
                "temperature_risk_probability": temperature_risk,
                "gas_risk_probability": gas_risk,
                "electrical_condition": (
                    "Simulated fault"
                    if electrical_risk > 0
                    else summary.get("electrical_condition", "Normal")
                ),
                "active_conditions": [simulation["type"]],
                "quality": "presentation_simulation",
                "source": "dashboard_simulation",
            }
        )
    summary["metrics"] = {
        "fire_f1": (
            0.0
            if _safety_metrics is None
            else round(_safety_metrics["smoke_fire"]["f1_fire"], 4)
        ),
        "electrical_macro_f1": (
            0.0
            if _safety_metrics is None
            else round(_safety_metrics["electrical_fault"]["macro_f1"], 4)
        ),
        "gas_macro_f1": (
            0.0
            if _safety_metrics is None
            else round(_safety_metrics["gas_identity"]["macro_f1"], 4)
        ),
    }
    return summary


def build_recommendations(
    energy: dict,
    anomaly: dict,
    appliances: dict,
    safety: dict,
    monthly_bill: dict,
    balance_depletion: dict,
) -> list[dict]:
    recommendations = []
    if safety["risk_level"] in {"high", "moderate"}:
        gas_pct = safety.get("gas_risk_probability", 0.0) * 100
        electrical_pct = safety.get("electrical_fault_probability", 0.0) * 100
        temperature_pct = safety.get("temperature_risk_probability", 0.0) * 100
        active_signals = []
        if gas_pct > 0:
            active_signals.append(f"gas {gas_pct:.0f}%")
        if electrical_pct > 0:
            active_signals.append(f"electrical {electrical_pct:.0f}%")
        if temperature_pct > 0:
            active_signals.append(f"temperature {temperature_pct:.0f}%")
        signal_text = (
            ", ".join(active_signals)
            if active_signals
            else f"electrical condition: {safety['electrical_condition']}"
        )
        recommendations.append(
            {
                "type": "safety",
                "title": "Review live safety signals",
                "message": (
                    f"Current safety level is {safety['risk_level']}. "
                    f"Active signal: {signal_text}. Verify the meter area "
                    "before enabling any relay action."
                ),
                "impact": "Safety priority",
                "severity": "high"
                if safety["risk_level"] == "high"
                else "warning",
                "tft_line_1": "Review safety signals",
                "tft_line_2": "Check the meter area",
                "potential_saving_percent": 0,
            }
        )

    measured_remaining_days = balance_depletion.get("remaining_days")
    if (
        balance_depletion.get("ready")
        and measured_remaining_days is not None
        and measured_remaining_days < 3
    ):
        urgent = measured_remaining_days < 1
        daily_cost_lkr = balance_depletion.get("daily_cost_lkr") or 0.0
        recommendations.append(
            {
                "type": "balance",
                "title": "Recharge balance soon" if not urgent else "Recharge immediately",
                "message": (
                    f"Based on recent measured usage, about Rs. "
                    f"{daily_cost_lkr:.0f} is used per day. Current credit "
                    f"lasts about {measured_remaining_days:.1f} days."
                ),
                "impact": "Low balance" if not urgent else "Critical balance",
                "severity": "warning" if not urgent else "high",
                "tft_line_1": (
                    "Recharge balance soon"
                    if not urgent
                    else "Recharge immediately"
                ),
                "tft_line_2": (
                    f"About {measured_remaining_days:.1f} days left"
                ),
                "potential_saving_percent": 0,
            }
        )

    if monthly_bill["status"] in {"watch", "high"}:
        recommendations.append(
            {
                "type": "bill",
                "title": "Watch monthly bill projection",
                "message": (
                    f"This month is projected at "
                    f"{monthly_bill['projected_month_units']:.1f} units "
                    f"(about Rs. {monthly_bill['projected_bill_lkr']:.0f}) "
                    f"after {monthly_bill['billing_days_elapsed']} billing days."
                ),
                "impact": "Bill forecast",
                "severity": "warning"
                if monthly_bill["status"] == "watch"
                else "high",
                "tft_line_1": "Watch monthly bill",
                "tft_line_2": (
                    f"Projected Rs. {monthly_bill['projected_bill_lkr']:.0f}"
                ),
                "potential_saving_percent": 0,
            }
        )

    if anomaly.get("level") in {"watch", "abnormal"}:
        recommendations.append(
            {
                "type": "anomaly",
                "title": "Inspect usage pattern",
                "message": (
                    f"The anomaly model reports {anomaly['label'].lower()} "
                    f"usage with {anomaly['abnormal_probability'] * 100:.1f}% "
                    "abnormal probability. Compare active loads with the "
                    "normal household schedule."
                ),
                "impact": "Review now"
                if anomaly.get("level") == "abnormal"
                else "Keep watching",
                "severity": "high"
                if anomaly.get("level") == "abnormal"
                else "warning",
                "tft_line_1": "Check unusual usage",
                "tft_line_2": (
                    f"Risk {anomaly['abnormal_probability'] * 100:.0f}%"
                ),
                "potential_saving_percent": 0,
            }
        )

    if appliances["detections"]:
        highest_power = max(
            appliances["detections"], key=lambda item: item["mean_power_w"]
        )
        confidence = highest_power.get("confidence", 0.0)
        confidence_text = (
            "strong sample match"
            if confidence >= 0.7
            else "likely sample match"
            if confidence >= 0.45
            else "low-confidence sample"
        )
        potential_saving_percent = (
            15
            if highest_power["mean_power_w"] >= 300 and confidence >= 0.7
            else 10
            if highest_power["mean_power_w"] >= 100
            else 5
        )
        recommendations.append(
            {
                "type": "appliance",
                "title": f"Schedule {highest_power['category']} loads",
                "message": (
                    f"The sample averages {highest_power['mean_power_w']:.1f} "
                    f"W and has a {confidence_text}. Shift flexible use "
                    "outside household peak periods."
                ),
                "impact": "Energy saving",
                "severity": "info",
                "tft_line_1": f"Schedule {highest_power['category']}",
                "tft_line_2": "Outside peak hours",
                "potential_saving_percent": potential_saving_percent,
            }
        )
    if not recommendations:
        recommendations.append(
            {
                "type": "status",
                "title": "Usage remains stable",
                "message": (
                    "No urgent anomaly, safety, or balance action is indicated "
                    "by the current prototype samples."
                ),
                "impact": "On track",
                "severity": "normal",
                "tft_line_1": "Usage looks stable",
                "tft_line_2": "Keep monitoring",
                "potential_saving_percent": 0,
            }
        )
    return recommendations[:3]


def predict_monthly_bill(
    monthly_usage_kwh: float,
    billing_days_elapsed: int,
    next_day_prediction_kwh: float,
) -> dict:
    if monthly_usage_kwh < 0:
        raise HTTPException(status_code=422, detail="Invalid monthly usage")
    cycle_days = int(_tariff_engine.configuration["billing_cycle_days"])
    elapsed = min(max(1, billing_days_elapsed), cycle_days)
    remaining_days = max(0, cycle_days - elapsed)
    average_daily_usage = monthly_usage_kwh / elapsed
    projected_monthly_usage = max(
        monthly_usage_kwh, average_daily_usage * cycle_days
    )
    projected_bill = _tariff_engine.calculate_monthly_bill(
        projected_monthly_usage
    )
    current_bill = _tariff_engine.calculate_monthly_bill(monthly_usage_kwh)

    pace_ratio = (
        0.0
        if average_daily_usage <= 0
        else next_day_prediction_kwh / average_daily_usage
    )
    projected_bill_value = projected_bill.total_lkr
    meaningful_usage = projected_monthly_usage >= 30
    if (
        projected_monthly_usage >= 90
        or projected_bill_value >= 3000
        or (meaningful_usage and pace_ratio >= 1.5)
    ):
        status = "high"
    elif (
        projected_monthly_usage >= 60
        or projected_bill_value >= 1500
        or (meaningful_usage and pace_ratio >= 1.15)
    ):
        status = "watch"
    else:
        status = "normal"

    return {
        "current_month_units": round(monthly_usage_kwh, 3),
        "current_bill_lkr": round(current_bill.total_lkr, 2),
        "projected_month_units": round(projected_monthly_usage, 3),
        "projected_bill_lkr": round(projected_bill.total_lkr, 2),
        "average_daily_units": round(average_daily_usage, 3),
        "remaining_billing_days": remaining_days,
        "billing_days_elapsed": elapsed,
        "billing_cycle_days": cycle_days,
        "next_day_forecast_units": round(next_day_prediction_kwh, 3),
        "status": status,
        "method": "current-month pace projection with tariff bill calculation",
        "tariff_id": _tariff_engine.id,
    }


@app.get("/predict/summary")
def predict_summary(
    balance_lkr: float = 850.0,
    tariff_lkr_per_kwh: float | None = None,
    monthly_usage_kwh: float = 4.8,
    billing_days_elapsed: int = 1,
    device_id: str | None = None,
) -> dict:
    energy = predict_energy(
        balance_lkr,
        tariff_lkr_per_kwh,
        monthly_usage_kwh,
        billing_days_elapsed,
    )
    anomaly = predict_anomaly()
    appliances = predict_appliances(limit=3)
    safety = predict_safety()
    monthly_bill = predict_monthly_bill(
        monthly_usage_kwh,
        billing_days_elapsed,
        energy["prediction_kwh"],
    )
    balance_depletion = _recent_household_balance_estimate(
        device_id=device_id,
        balance_lkr=balance_lkr,
        monthly_usage_kwh=monthly_usage_kwh,
        billing_days_elapsed=billing_days_elapsed,
    )
    return {
        "energy": energy,
        "anomaly": anomaly,
        "appliances": appliances,
        "safety": safety,
        "balance_depletion": balance_depletion,
        "monthly_bill_prediction": monthly_bill,
        "recommendations": build_recommendations(
            energy,
            anomaly,
            appliances,
            safety,
            monthly_bill,
            balance_depletion,
        ),
        "generated_from": "trained_models_and_deterministic_rules",
    }


@app.get("/devices/{device_id}/display-summary")
def device_display_summary(
    device_id: str,
    _: None = Depends(require_device_sender),
) -> dict:
    """Small authenticated payload for the ESP32 TFT display.

    The meter polls this endpoint once per minute instead of repeatedly
    downloading the full dashboard prediction response.
    """
    if device_id != "EM-2048":
        raise HTTPException(status_code=404, detail="Unknown device")

    balance_lkr = _effective_account_balance(device_id)
    monthly_usage_kwh = 0.0
    account = _device_accounts.get(device_id)
    if account is None:
        try:
            account = _local_persistence.load_account(device_id)
        except Exception:
            account = None
    if account is None and _local_persistence is not _persistence:
        try:
            account = _persistence.load_account(device_id)
        except Exception:
            account = None
    if account is not None:
        monthly_usage_kwh = float(account.get("monthly_usage_kwh", 0.0))

    billing_days_elapsed = max(1, datetime.now(COLOMBO).day)
    overview = predict_summary(
        balance_lkr=balance_lkr,
        monthly_usage_kwh=monthly_usage_kwh,
        billing_days_elapsed=billing_days_elapsed,
        device_id=device_id,
    )
    energy = overview["energy"]
    balance_depletion = overview["balance_depletion"]
    primary_recommendation = overview["recommendations"][0]
    return {
        "device_id": device_id,
        "tomorrow_usage_kwh": energy["prediction_kwh"],
        "estimated_cost_lkr": energy["estimated_cost_lkr"],
        "remaining_days": (
            balance_depletion["remaining_days"]
            if balance_depletion["ready"]
            else -1.0
        ),
        "remaining_days_ready": balance_depletion["ready"],
        "remaining_days_message": balance_depletion["message"],
        "balance_lkr": round(balance_lkr, 2),
        "credit_allowed": balance_lkr > 0,
        "account_status": "Active" if balance_lkr > 0 else "Recharge required",
        "recommendation_type": primary_recommendation["type"],
        "recommendation_title": primary_recommendation["title"],
        "recommendation_message": primary_recommendation["message"],
        "recommendation_impact": primary_recommendation["impact"],
        "recommendation_line_1": primary_recommendation["tft_line_1"],
        "recommendation_line_2": primary_recommendation["tft_line_2"],
        "potential_saving_percent": primary_recommendation[
            "potential_saving_percent"
        ],
        "recommendation_note": "Same recommendation as the dashboard",
        "updated_at": datetime.now(timezone.utc).isoformat(),
    }


@app.get("/tariffs/active")
def get_active_tariff() -> dict:
    configuration = _tariff_engine.configuration
    return {
        "id": configuration["id"],
        "country": configuration["country"],
        "currency": configuration["currency"],
        "provider": configuration["provider"],
        "category": configuration["category"],
        "status": configuration["status"],
        "effective_from": configuration["effective_from"],
        "effective_to": configuration["effective_to"],
        "billing_cycle_days": configuration["billing_cycle_days"],
        "source_url": configuration["source_url"],
        "low_user": configuration["low_user"],
        "standard_user": configuration["standard_user"],
    }


@app.get("/tariffs/history")
def get_tariff_history() -> dict:
    return {
        "tariffs": [
            {
                "id": item["id"],
                "status": item["status"],
                "effective_from": item["effective_from"],
                "effective_to": item["effective_to"],
                "source_url": item["source_url"],
                "source_title": item["source_title"],
                "validation_case_count": len(item.get("validation_cases", [])),
                "verified_at": item.get("verified_at"),
                "activated_at": item.get("activated_at"),
            }
            for item in available_tariffs()
        ]
    }


@app.get("/tariffs/monitor")
def get_tariff_monitor() -> dict:
    state = load_monitor_state()
    return {
        "enabled": float(
            os.environ.get("PUCSL_MONITOR_INTERVAL_HOURS", "24")
        ) > 0,
        "interval_hours": float(
            os.environ.get("PUCSL_MONITOR_INTERVAL_HOURS", "24")
        ),
        "index_url": PUCSL_INDEX_URL,
        **state,
    }


@app.post("/tariffs/monitor/check")
def check_tariff_monitor(
    _: None = Depends(require_tariff_admin),
) -> dict:
    state = check_pucsl()
    if state.get("last_error"):
        raise HTTPException(
            status_code=502,
            detail=f"PUCSL check failed: {state['last_error']}",
        )
    return state


@app.post("/tariffs/drafts", status_code=201)
def create_draft(
    configuration: dict = Body(...),
    _: None = Depends(require_tariff_admin),
) -> dict:
    try:
        draft = create_tariff_draft(configuration)
    except FileExistsError as error:
        raise HTTPException(status_code=409, detail=str(error)) from error
    except (KeyError, TypeError, ValueError) as error:
        raise HTTPException(status_code=422, detail=str(error)) from error
    return {
        "id": draft["id"],
        "status": draft["status"],
        "message": "Draft saved. It cannot affect billing until verified and activated.",
    }


@app.post("/tariffs/{tariff_id}/verify")
def verify_draft(
    tariff_id: str,
    _: None = Depends(require_tariff_admin),
) -> dict:
    try:
        configuration, results = verify_tariff(tariff_id)
    except FileNotFoundError as error:
        raise HTTPException(status_code=404, detail=str(error)) from error
    except (KeyError, TypeError, ValueError) as error:
        raise HTTPException(status_code=409, detail=str(error)) from error
    return {
        "id": configuration["id"],
        "status": configuration["status"],
        "validation_cases": results,
        "message": "All regression bills passed. Administrator activation is still required.",
    }


@app.post("/tariffs/{tariff_id}/activate")
def activate_verified_tariff(
    tariff_id: str,
    _: None = Depends(require_tariff_admin),
) -> dict:
    global _tariff_engine
    try:
        configuration = activate_tariff(tariff_id)
        _tariff_engine = active_tariff()
    except FileNotFoundError as error:
        raise HTTPException(status_code=404, detail=str(error)) from error
    except (KeyError, TypeError, ValueError) as error:
        raise HTTPException(status_code=409, detail=str(error)) from error
    return {
        "id": configuration["id"],
        "status": configuration["status"],
        "effective_from": configuration["effective_from"],
        "message": "Verified tariff activated; the previous tariff was archived.",
    }


@app.post("/tariffs/{tariff_id}/validate")
def validate_tariff(
    tariff_id: str,
    _: None = Depends(require_tariff_admin),
) -> dict:
    matches = [item for item in available_tariffs() if item["id"] == tariff_id]
    if not matches:
        raise HTTPException(status_code=404, detail=f"Tariff {tariff_id} not found")
    try:
        results = validate_tariff_configuration(matches[0])
    except (KeyError, TypeError, ValueError) as error:
        raise HTTPException(status_code=409, detail=str(error)) from error
    return {"id": tariff_id, "passed": True, "validation_cases": results}
