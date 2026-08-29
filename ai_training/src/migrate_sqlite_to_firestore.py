"""One-time, idempotent migration from local SQLite to Firestore."""

from __future__ import annotations

import json
import os
import sqlite3
from datetime import datetime
from pathlib import Path

from dotenv import load_dotenv
from google.cloud import firestore


ROOT = Path(__file__).resolve().parents[2]
load_dotenv(ROOT / ".env")
SQLITE_PATH = Path(
    os.environ.get(
        "SQLITE_DB_PATH",
        str(ROOT / "ai_training" / "data" / "smart_energy.db"),
    )
)


def main() -> None:
    project = os.environ["FIREBASE_PROJECT_ID"]
    client = firestore.Client(project=project)
    connection = sqlite3.connect(SQLITE_PATH)
    connection.row_factory = sqlite3.Row
    migrated = {"readings": 0, "accounts": 0, "recharges": 0, "alerts": 0}

    for row in connection.execute(
        "SELECT id, device_id, payload FROM readings ORDER BY id"
    ):
        payload = json.loads(row["payload"])
        payload["received_at"] = datetime.fromisoformat(payload["received_at"])
        reference = (
            client.collection("devices")
            .document(row["device_id"])
            .collection("readings")
            .document(f"sqlite_{row['id']}")
        )
        reference.set(payload)
        migrated["readings"] += 1

    for row in connection.execute("SELECT device_id, payload FROM accounts"):
        payload = json.loads(row["payload"])
        (
            client.collection("devices")
            .document(row["device_id"])
            .collection("state")
            .document("account")
            .set(payload)
        )
        migrated["accounts"] += 1

    for row in connection.execute(
        "SELECT id, device_id, payload FROM recharges ORDER BY id"
    ):
        payload = json.loads(row["payload"])
        payload["created_at"] = datetime.fromisoformat(payload["created_at"])
        (
            client.collection("devices")
            .document(row["device_id"])
            .collection("recharges")
            .document(f"sqlite_{row['id']}")
            .set(payload)
        )
        migrated["recharges"] += 1

    for row in connection.execute(
        "SELECT alert_id, device_id, payload FROM alerts ORDER BY created_at"
    ):
        payload = json.loads(row["payload"])
        for field in ("created_at", "updated_at"):
            if isinstance(payload.get(field), str):
                payload[field] = datetime.fromisoformat(payload[field])
        (
            client.collection("devices")
            .document(row["device_id"])
            .collection("alerts")
            .document(row["alert_id"])
            .set(payload)
        )
        migrated["alerts"] += 1

    print(json.dumps({"project": project, "migrated": migrated}))


if __name__ == "__main__":
    main()
