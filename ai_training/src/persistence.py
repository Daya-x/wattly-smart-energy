"""Persistent meter storage with Firestore and local SQLite backends."""

from __future__ import annotations

import json
import os
import sqlite3
import threading
from contextlib import contextmanager
from datetime import datetime
from pathlib import Path
from typing import Protocol


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_DB = ROOT / "data" / "smart_energy.db"


class Persistence(Protocol):
    name: str

    def save_snapshot(self, device_id: str, reading: dict, account: dict) -> None: ...
    def load_account(self, device_id: str) -> dict | None: ...
    def save_account(self, device_id: str, account: dict) -> None: ...
    def latest_reading(self, device_id: str) -> dict | None: ...
    def readings_between(
        self, device_id: str, start: datetime, end: datetime
    ) -> list[dict]: ...
    def record_recharge(self, device_id: str, recharge: dict, account: dict) -> None: ...
    def list_recharges(self, device_id: str, limit: int = 20) -> list[dict]: ...
    def save_alert(self, device_id: str, alert: dict) -> None: ...
    def list_alerts(self, device_id: str, limit: int = 100) -> list[dict]: ...
    def acknowledge_alert(self, device_id: str, alert_id: str) -> bool: ...


class SQLitePersistence:
    name = "sqlite"

    def __init__(self, path: Path = DEFAULT_DB):
        path.parent.mkdir(parents=True, exist_ok=True)
        self.path = path
        self._lock = threading.Lock()
        self._initialize()

    def _connect(self) -> sqlite3.Connection:
        connection = sqlite3.connect(self.path)
        connection.row_factory = sqlite3.Row
        return connection

    @contextmanager
    def _connection(self):
        connection = self._connect()
        try:
            with connection:
                yield connection
        finally:
            connection.close()

    def _initialize(self) -> None:
        with self._connection() as connection:
            connection.executescript(
                """
                CREATE TABLE IF NOT EXISTS readings (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    device_id TEXT NOT NULL,
                    received_at TEXT NOT NULL,
                    payload TEXT NOT NULL
                );
                CREATE INDEX IF NOT EXISTS readings_device_time
                    ON readings(device_id, received_at);
                CREATE TABLE IF NOT EXISTS accounts (
                    device_id TEXT PRIMARY KEY,
                    payload TEXT NOT NULL,
                    updated_at TEXT NOT NULL
                );
                CREATE TABLE IF NOT EXISTS recharges (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    device_id TEXT NOT NULL,
                    created_at TEXT NOT NULL,
                    payload TEXT NOT NULL
                );
                CREATE TABLE IF NOT EXISTS alerts (
                    alert_id TEXT PRIMARY KEY,
                    device_id TEXT NOT NULL,
                    created_at TEXT NOT NULL,
                    payload TEXT NOT NULL
                );
                CREATE INDEX IF NOT EXISTS alerts_device_time
                    ON alerts(device_id, created_at DESC);
                """
            )

    def save_snapshot(self, device_id: str, reading: dict, account: dict) -> None:
        with self._lock, self._connection() as connection:
            connection.execute(
                "INSERT INTO readings(device_id, received_at, payload) VALUES (?, ?, ?)",
                (device_id, reading["received_at"], json.dumps(reading)),
            )
            self._save_account(connection, device_id, account)

    def load_account(self, device_id: str) -> dict | None:
        with self._lock, self._connection() as connection:
            row = connection.execute(
                "SELECT payload FROM accounts WHERE device_id = ?", (device_id,)
            ).fetchone()
        return None if row is None else json.loads(row["payload"])

    def save_account(self, device_id: str, account: dict) -> None:
        with self._lock, self._connection() as connection:
            self._save_account(connection, device_id, account)

    def latest_reading(self, device_id: str) -> dict | None:
        with self._lock, self._connection() as connection:
            row = connection.execute(
                """
                SELECT payload FROM readings
                WHERE device_id = ?
                ORDER BY received_at DESC LIMIT 1
                """,
                (device_id,),
            ).fetchone()
        return None if row is None else json.loads(row["payload"])

    def readings_between(
        self, device_id: str, start: datetime, end: datetime
    ) -> list[dict]:
        with self._lock, self._connection() as connection:
            rows = connection.execute(
                """
                SELECT payload FROM readings
                WHERE device_id = ? AND received_at >= ? AND received_at < ?
                ORDER BY received_at
                """,
                (device_id, start.isoformat(), end.isoformat()),
            ).fetchall()
        return [json.loads(row["payload"]) for row in rows]

    def record_recharge(self, device_id: str, recharge: dict, account: dict) -> None:
        with self._lock, self._connection() as connection:
            connection.execute(
                "INSERT INTO recharges(device_id, created_at, payload) VALUES (?, ?, ?)",
                (device_id, recharge["created_at"], json.dumps(recharge)),
            )
            self._save_account(connection, device_id, account)

    def list_recharges(self, device_id: str, limit: int = 20) -> list[dict]:
        with self._lock, self._connection() as connection:
            rows = connection.execute(
                """
                SELECT payload FROM recharges
                WHERE device_id = ?
                ORDER BY created_at DESC LIMIT ?
                """,
                (device_id, limit),
            ).fetchall()
        return [json.loads(row["payload"]) for row in rows]

    def save_alert(self, device_id: str, alert: dict) -> None:
        with self._lock, self._connection() as connection:
            connection.execute(
                """
                INSERT INTO alerts(alert_id, device_id, created_at, payload)
                VALUES (?, ?, ?, ?)
                ON CONFLICT(alert_id) DO UPDATE SET payload = excluded.payload
                """,
                (
                    alert["id"],
                    device_id,
                    alert["created_at"],
                    json.dumps(alert),
                ),
            )

    def list_alerts(self, device_id: str, limit: int = 100) -> list[dict]:
        with self._lock, self._connection() as connection:
            rows = connection.execute(
                """
                SELECT payload FROM alerts
                WHERE device_id = ?
                ORDER BY created_at DESC LIMIT ?
                """,
                (device_id, limit),
            ).fetchall()
        return [json.loads(row["payload"]) for row in rows]

    def acknowledge_alert(self, device_id: str, alert_id: str) -> bool:
        with self._lock, self._connection() as connection:
            row = connection.execute(
                """
                SELECT payload FROM alerts
                WHERE device_id = ? AND alert_id = ?
                """,
                (device_id, alert_id),
            ).fetchone()
            if row is None:
                return False
            alert = json.loads(row["payload"])
            alert["acknowledged"] = True
            connection.execute(
                "UPDATE alerts SET payload = ? WHERE alert_id = ?",
                (json.dumps(alert), alert_id),
            )
        return True

    @staticmethod
    def _save_account(
        connection: sqlite3.Connection, device_id: str, account: dict
    ) -> None:
        connection.execute(
            """
            INSERT INTO accounts(device_id, payload, updated_at)
            VALUES (?, ?, ?)
            ON CONFLICT(device_id) DO UPDATE SET
              payload = excluded.payload,
              updated_at = excluded.updated_at
            """,
            (
                device_id,
                json.dumps(account),
                datetime.now().astimezone().isoformat(),
            ),
        )


class FirestorePersistence:
    name = "firestore"

    def __init__(self, project: str | None = None):
        try:
            from google.cloud import firestore
            from google.cloud.firestore_v1.base_query import FieldFilter
        except ImportError as error:
            raise RuntimeError(
                "Install google-cloud-firestore from ai_training/requirements.txt"
            ) from error
        self._firestore = firestore
        self._field_filter = FieldFilter
        self.client = firestore.Client(project=project)

    def _device(self, device_id: str):
        return self.client.collection("devices").document(device_id)

    def save_snapshot(self, device_id: str, reading: dict, account: dict) -> None:
        received_at = datetime.fromisoformat(reading["received_at"])
        document = dict(reading)
        document["received_at"] = received_at
        batch = self.client.batch()
        reading_ref = self._device(device_id).collection("readings").document()
        account_ref = self._device(device_id).collection("state").document("account")
        batch.set(reading_ref, document)
        batch.set(account_ref, account)
        batch.set(
            self._device(device_id),
            {"last_seen_at": received_at, "persistence": "firestore"},
            merge=True,
        )
        batch.commit()

    def load_account(self, device_id: str) -> dict | None:
        snapshot = (
            self._device(device_id).collection("state").document("account").get()
        )
        return snapshot.to_dict() if snapshot.exists else None

    def save_account(self, device_id: str, account: dict) -> None:
        self._device(device_id).collection("state").document("account").set(
            account,
            merge=True,
        )

    def latest_reading(self, device_id: str) -> dict | None:
        query = (
            self._device(device_id)
            .collection("readings")
            .order_by("received_at", direction=self._firestore.Query.DESCENDING)
            .limit(1)
        )
        documents = list(query.stream())
        if not documents:
            return None
        return self._normalize(documents[0].to_dict())

    def readings_between(
        self, device_id: str, start: datetime, end: datetime
    ) -> list[dict]:
        query = (
            self._device(device_id)
            .collection("readings")
            .where(
                filter=self._field_filter("received_at", ">=", start)
            )
            .where(filter=self._field_filter("received_at", "<", end))
            .order_by("received_at")
        )
        return [self._normalize(document.to_dict()) for document in query.stream()]

    def record_recharge(self, device_id: str, recharge: dict, account: dict) -> None:
        created_at = datetime.fromisoformat(recharge["created_at"])
        payload = dict(recharge)
        payload["created_at"] = created_at
        batch = self.client.batch()
        batch.set(self._device(device_id).collection("recharges").document(), payload)
        batch.set(
            self._device(device_id).collection("state").document("account"),
            account,
        )
        batch.commit()

    def list_recharges(self, device_id: str, limit: int = 20) -> list[dict]:
        query = (
            self._device(device_id)
            .collection("recharges")
            .order_by("created_at", direction=self._firestore.Query.DESCENDING)
            .limit(limit)
        )
        recharges = []
        for document in query.stream():
            payload = document.to_dict()
            timestamp = payload.get("created_at")
            if isinstance(timestamp, datetime):
                payload["created_at"] = timestamp.isoformat()
            recharges.append(payload)
        return recharges

    def save_alert(self, device_id: str, alert: dict) -> None:
        payload = dict(alert)
        for field in ("created_at", "updated_at"):
            if isinstance(payload.get(field), str):
                payload[field] = datetime.fromisoformat(payload[field])
        self._device(device_id).collection("alerts").document(alert["id"]).set(
            payload
        )

    def list_alerts(self, device_id: str, limit: int = 100) -> list[dict]:
        query = (
            self._device(device_id)
            .collection("alerts")
            .order_by("created_at", direction=self._firestore.Query.DESCENDING)
            .limit(limit)
        )
        alerts = []
        for document in query.stream():
            payload = document.to_dict()
            for field in ("created_at", "updated_at"):
                if isinstance(payload.get(field), datetime):
                    payload[field] = payload[field].isoformat()
            alerts.append(payload)
        return alerts

    def acknowledge_alert(self, device_id: str, alert_id: str) -> bool:
        reference = self._device(device_id).collection("alerts").document(alert_id)
        if not reference.get().exists:
            return False
        reference.update({"acknowledged": True})
        return True

    @staticmethod
    def _normalize(payload: dict) -> dict:
        result = dict(payload)
        timestamp = result.get("received_at")
        if isinstance(timestamp, datetime):
            result["received_at"] = timestamp.isoformat()
        return result


def build_persistence() -> Persistence:
    backend = os.environ.get("PERSISTENCE_BACKEND", "auto").lower()
    firestore_configured = bool(
        os.environ.get("FIREBASE_PROJECT_ID")
        or os.environ.get("GOOGLE_APPLICATION_CREDENTIALS")
    )
    if backend == "firestore" or (backend == "auto" and firestore_configured):
        try:
            return FirestorePersistence(os.environ.get("FIREBASE_PROJECT_ID"))
        except Exception:
            if os.environ.get("PERSISTENCE_STRICT", "false").lower() == "true":
                raise
    return SQLitePersistence(
        Path(os.environ.get("SQLITE_DB_PATH", str(DEFAULT_DB)))
    )
