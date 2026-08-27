#!/usr/bin/env python3
"""Small authenticated sync API for the personal LifeRecord installation."""

from __future__ import annotations

import hashlib
import hmac
import json
import os
import base64
import binascii
import sqlite3
import threading
import time
from collections import defaultdict, deque
from http import HTTPStatus
from http.cookies import SimpleCookie
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlparse


HOST = os.environ.get("LIFERECORD_HOST", "127.0.0.1")
PORT = int(os.environ.get("LIFERECORD_PORT", "18084"))
DB_PATH = Path(os.environ.get("LIFERECORD_DB", "/var/lib/liferecord-sync/liferecord.sqlite3"))
IMAGE_DIR = Path(os.environ.get("LIFERECORD_IMAGE_DIR", str(DB_PATH.parent / "images")))
SYNC_TOKEN = os.environ.get("LIFERECORD_SYNC_TOKEN", "")
MAX_BODY = 8 * 1024 * 1024
MAX_IMAGE_BYTES = 4 * 1024 * 1024
ALLOWED_TYPES = {"meal", "body", "water", "settings"}
COOKIE_NAME = "liferecord_session"

if len(SYNC_TOKEN) < 20:
    raise SystemExit("LIFERECORD_SYNC_TOKEN must contain at least 20 characters")

TOKEN_HASH = hashlib.sha256(SYNC_TOKEN.encode()).hexdigest()
DB_PATH.parent.mkdir(parents=True, exist_ok=True)
IMAGE_DIR.mkdir(parents=True, exist_ok=True)
_db_lock = threading.Lock()
_failed_auth: dict[str, deque[float]] = defaultdict(deque)


def connect() -> sqlite3.Connection:
    connection = sqlite3.connect(DB_PATH, timeout=10)
    connection.row_factory = sqlite3.Row
    connection.execute("PRAGMA journal_mode=WAL")
    connection.execute("PRAGMA foreign_keys=ON")
    return connection


def initialize() -> None:
    with connect() as connection:
        connection.execute(
            """
            CREATE TABLE IF NOT EXISTS records (
                record_type TEXT NOT NULL,
                record_id TEXT NOT NULL,
                payload TEXT NOT NULL,
                updated_at REAL NOT NULL,
                deleted INTEGER NOT NULL DEFAULT 0 CHECK (deleted IN (0, 1)),
                PRIMARY KEY (record_type, record_id)
            )
            """
        )
        connection.execute(
            "CREATE INDEX IF NOT EXISTS idx_records_type_updated ON records(record_type, updated_at)"
        )
        connection.execute(
            """
            CREATE TABLE IF NOT EXISTS meal_images (
                image_id TEXT PRIMARY KEY,
                meal_id TEXT NOT NULL,
                filename TEXT NOT NULL UNIQUE,
                content_type TEXT NOT NULL,
                created_at REAL NOT NULL
            )
            """
        )
        connection.execute(
            "CREATE INDEX IF NOT EXISTS idx_meal_images_meal_id ON meal_images(meal_id)"
        )
        connection.execute("PRAGMA optimize")


def valid_number(value: object, minimum: float = 0, maximum: float = 1e9) -> bool:
    return isinstance(value, (int, float)) and minimum <= float(value) <= maximum


def validate_record(record_type: str, item: dict) -> None:
    if not isinstance(item, dict):
        raise ValueError("record must be an object")
    if not isinstance(item.get("id"), str) or not (1 <= len(item["id"]) <= 80):
        raise ValueError("invalid record id")
    if not valid_number(item.get("updatedAt"), 1, 4_102_444_800):
        raise ValueError("invalid updatedAt")
    if record_type == "meal":
        if not isinstance(item.get("name"), str) or not item["name"].strip():
            raise ValueError("meal name is required")
        for key, maximum in (("calories", 20_000), ("protein", 2_000), ("carbs", 3_000), ("fat", 2_000), ("fiber", 500)):
            if not valid_number(item.get(key, 0), 0, maximum):
                raise ValueError(f"invalid meal {key}")
        photo_ids = item.get("photoIDs", [])
        if not isinstance(photo_ids, list) or len(photo_ids) > 12 or any(
            not isinstance(image_id, str)
            or len(image_id) != 32
            or any(character not in "0123456789abcdef" for character in image_id)
            for image_id in photo_ids
        ):
            raise ValueError("invalid meal photo ids")
    elif record_type == "body":
        if not valid_number(item.get("weight"), 20, 400):
            raise ValueError("invalid weight")
    elif record_type == "water":
        if not valid_number(item.get("milliliters"), 1, 10_000):
            raise ValueError("invalid water amount")


def merge_snapshot(snapshot: dict) -> None:
    mapping = {"meals": "meal", "bodyMetrics": "body", "waterEntries": "water"}
    operations: list[tuple[str, str, str, float, int]] = []
    for key, record_type in mapping.items():
        items = snapshot.get(key, [])
        if not isinstance(items, list) or len(items) > 10_000:
            raise ValueError(f"invalid {key}")
        for item in items:
            validate_record(record_type, item)
            operations.append((record_type, item["id"], json.dumps(item, ensure_ascii=False, separators=(",", ":")), float(item["updatedAt"]), 0))

    settings = snapshot.get("settings")
    if settings is not None:
        if not isinstance(settings, dict):
            raise ValueError("invalid settings")
        settings = {**settings, "id": "profile"}
        validate_record("settings", settings)
        operations.append(("settings", "profile", json.dumps(settings, ensure_ascii=False, separators=(",", ":")), float(settings["updatedAt"]), 0))

    deletions = snapshot.get("deletions", [])
    if not isinstance(deletions, list) or len(deletions) > 10_000:
        raise ValueError("invalid deletions")
    for item in deletions:
        if not isinstance(item, dict) or item.get("recordType") not in ALLOWED_TYPES - {"settings"}:
            raise ValueError("invalid deletion type")
        if not isinstance(item.get("id"), str) or not valid_number(item.get("deletedAt"), 1, 4_102_444_800):
            raise ValueError("invalid deletion")
        operations.append((item["recordType"], item["id"], "{}", float(item["deletedAt"]), 1))

    statement = """
        INSERT INTO records(record_type, record_id, payload, updated_at, deleted)
        VALUES (?, ?, ?, ?, ?)
        ON CONFLICT(record_type, record_id) DO UPDATE SET
            payload = excluded.payload,
            updated_at = excluded.updated_at,
            deleted = excluded.deleted
        WHERE excluded.updated_at >= records.updated_at
    """
    deleted_image_files: list[str] = []
    deleted_meal_ids = [record_id for record_type, record_id, _, _, deleted in operations if record_type == "meal" and deleted]
    with _db_lock, connect() as connection:
        connection.executemany(statement, operations)
        for meal_id in deleted_meal_ids:
            record = connection.execute(
                "SELECT deleted FROM records WHERE record_type = 'meal' AND record_id = ?",
                (meal_id,),
            ).fetchone()
            if record and record["deleted"]:
                deleted_image_files.extend(
                    row["filename"] for row in connection.execute(
                        "SELECT filename FROM meal_images WHERE meal_id = ?", (meal_id,)
                    ).fetchall()
                )
                connection.execute("DELETE FROM meal_images WHERE meal_id = ?", (meal_id,))
    for filename in deleted_image_files:
        try:
            (IMAGE_DIR / filename).unlink(missing_ok=True)
        except OSError:
            pass


def store_meal_image(payload: dict) -> dict:
    meal_id = payload.get("mealId")
    encoded = payload.get("base64")
    if not isinstance(meal_id, str) or not (1 <= len(meal_id) <= 80):
        raise ValueError("invalid meal id")
    if not isinstance(encoded, str) or not encoded:
        raise ValueError("image data is required")
    try:
        image = base64.b64decode(encoded, validate=True)
    except (ValueError, binascii.Error) as error:
        raise ValueError("invalid image data") from error
    if not image or len(image) > MAX_IMAGE_BYTES:
        raise ValueError("image must be between 1 byte and 4 MB")

    if image.startswith(b"\xff\xd8\xff"):
        content_type, suffix = "image/jpeg", ".jpg"
    elif image.startswith(b"\x89PNG\r\n\x1a\n"):
        content_type, suffix = "image/png", ".png"
    elif len(image) > 12 and image[:4] == b"RIFF" and image[8:12] == b"WEBP":
        content_type, suffix = "image/webp", ".webp"
    else:
        raise ValueError("only JPEG, PNG and WebP images are supported")

    image_id = hashlib.sha256(meal_id.lower().encode() + image).hexdigest()[:32]
    filename = f"{image_id}{suffix}"
    destination = IMAGE_DIR / filename
    destination.write_bytes(image)
    try:
        with _db_lock, connect() as connection:
            connection.execute(
                "INSERT OR REPLACE INTO meal_images(image_id, meal_id, filename, content_type, created_at) VALUES (?, ?, ?, ?, ?)",
                (image_id, meal_id.lower(), filename, content_type, time.time()),
            )
    except Exception:
        destination.unlink(missing_ok=True)
        raise
    return {"id": image_id, "url": f"/liferecord-api/images/{image_id}"}


def image_record(image_id: str) -> sqlite3.Row | None:
    if len(image_id) != 32 or any(character not in "0123456789abcdef" for character in image_id):
        return None
    with _db_lock, connect() as connection:
        return connection.execute(
            "SELECT filename, content_type FROM meal_images WHERE image_id = ?", (image_id,)
        ).fetchone()


def current_snapshot() -> dict:
    result = {"meals": [], "bodyMetrics": [], "waterEntries": [], "settings": None, "deletions": [], "serverTime": time.time()}
    output_keys = {"meal": "meals", "body": "bodyMetrics", "water": "waterEntries"}
    with _db_lock, connect() as connection:
        rows = connection.execute(
            "SELECT record_type, record_id, payload, updated_at, deleted FROM records ORDER BY updated_at"
        ).fetchall()
    for row in rows:
        if row["deleted"]:
            result["deletions"].append({"id": row["record_id"], "recordType": row["record_type"], "deletedAt": row["updated_at"]})
        elif row["record_type"] == "settings":
            result["settings"] = json.loads(row["payload"])
        elif row["record_type"] in output_keys:
            result[output_keys[row["record_type"]]].append(json.loads(row["payload"]))
    return result


class Handler(BaseHTTPRequestHandler):
    server_version = "LifeRecordSync/1.0"

    def log_message(self, fmt: str, *args: object) -> None:
        print(f"{self.address_string()} - {fmt % args}", flush=True)

    def do_OPTIONS(self) -> None:
        self.send_response(HTTPStatus.NO_CONTENT)
        self._security_headers()
        self.send_header("Allow", "GET, POST, OPTIONS")
        self.end_headers()

    def do_GET(self) -> None:
        path = urlparse(self.path).path.rstrip("/")
        if path == "/liferecord-api/health":
            self._json(HTTPStatus.OK, {"ok": True, "service": "liferecord-sync"})
            return
        if path == "/liferecord-api/snapshot":
            if not self._authorized():
                self._json(HTTPStatus.UNAUTHORIZED, {"error": "需要先配对同步密钥"})
                return
            self._json(HTTPStatus.OK, current_snapshot())
            return
        if path.startswith("/liferecord-api/images/"):
            if not self._authorized():
                self._json(HTTPStatus.UNAUTHORIZED, {"error": "需要先配对同步密钥"})
                return
            image_id = path.rsplit("/", 1)[-1].lower()
            record = image_record(image_id)
            if not record:
                self._json(HTTPStatus.NOT_FOUND, {"error": "image not found"})
                return
            try:
                encoded = (IMAGE_DIR / record["filename"]).read_bytes()
            except OSError:
                self._json(HTTPStatus.NOT_FOUND, {"error": "image not found"})
                return
            self.send_response(HTTPStatus.OK)
            self._security_headers()
            self.send_header("Content-Type", record["content_type"])
            self.send_header("Content-Length", str(len(encoded)))
            self.end_headers()
            self.wfile.write(encoded)
            return
        self._json(HTTPStatus.NOT_FOUND, {"error": "not found"})

    def do_POST(self) -> None:
        path = urlparse(self.path).path.rstrip("/")
        if path == "/liferecord-api/auth":
            self._authenticate_browser()
            return
        if path == "/liferecord-api/logout":
            self.send_response(HTTPStatus.NO_CONTENT)
            self._security_headers()
            self.send_header("Set-Cookie", f"{COOKIE_NAME}=; Path=/liferecord-api/; Max-Age=0; HttpOnly; Secure; SameSite=Strict")
            self.end_headers()
            return
        if path == "/liferecord-api/sync":
            if not self._authorized():
                self._json(HTTPStatus.UNAUTHORIZED, {"error": "同步密钥无效"})
                return
            try:
                payload = self._read_json()
                merge_snapshot(payload)
                self._json(HTTPStatus.OK, current_snapshot())
            except (ValueError, json.JSONDecodeError) as error:
                self._json(HTTPStatus.BAD_REQUEST, {"error": str(error)})
            return
        if path == "/liferecord-api/images":
            if not self._authorized():
                self._json(HTTPStatus.UNAUTHORIZED, {"error": "同步密钥无效"})
                return
            try:
                result = store_meal_image(self._read_json())
                self._json(HTTPStatus.CREATED, result)
            except (ValueError, json.JSONDecodeError) as error:
                self._json(HTTPStatus.BAD_REQUEST, {"error": str(error)})
            return
        self._json(HTTPStatus.NOT_FOUND, {"error": "not found"})

    def _authenticate_browser(self) -> None:
        client = self.client_address[0]
        now = time.time()
        attempts = _failed_auth[client]
        while attempts and attempts[0] < now - 60:
            attempts.popleft()
        if len(attempts) >= 10:
            self._json(HTTPStatus.TOO_MANY_REQUESTS, {"error": "尝试次数过多，请稍后再试"})
            return
        try:
            token = self._read_json().get("token", "")
        except (ValueError, json.JSONDecodeError):
            token = ""
        if not isinstance(token, str) or not hmac.compare_digest(token, SYNC_TOKEN):
            attempts.append(now)
            self._json(HTTPStatus.UNAUTHORIZED, {"error": "同步密钥不正确"})
            return
        attempts.clear()
        self.send_response(HTTPStatus.NO_CONTENT)
        self._security_headers()
        self.send_header("Set-Cookie", f"{COOKIE_NAME}={TOKEN_HASH}; Path=/liferecord-api/; Max-Age=31536000; HttpOnly; Secure; SameSite=Strict")
        self.end_headers()

    def _authorized(self) -> bool:
        authorization = self.headers.get("Authorization", "")
        if authorization.startswith("Bearer ") and hmac.compare_digest(authorization[7:], SYNC_TOKEN):
            return True
        cookie = SimpleCookie(self.headers.get("Cookie", ""))
        value = cookie.get(COOKIE_NAME)
        return bool(value and hmac.compare_digest(value.value, TOKEN_HASH))

    def _read_json(self) -> dict:
        try:
            length = int(self.headers.get("Content-Length", "0"))
        except ValueError as error:
            raise ValueError("invalid content length") from error
        if length <= 0 or length > MAX_BODY:
            raise ValueError("invalid request size")
        payload = json.loads(self.rfile.read(length))
        if not isinstance(payload, dict):
            raise ValueError("request must be an object")
        return payload

    def _security_headers(self) -> None:
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("Referrer-Policy", "no-referrer")

    def _json(self, status: HTTPStatus, payload: dict) -> None:
        encoded = json.dumps(payload, ensure_ascii=False, separators=(",", ":")).encode()
        self.send_response(status)
        self._security_headers()
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(encoded)))
        self.end_headers()
        self.wfile.write(encoded)


if __name__ == "__main__":
    initialize()
    server = ThreadingHTTPServer((HOST, PORT), Handler)
    print(f"LifeRecord sync listening on {HOST}:{PORT}", flush=True)
    server.serve_forever()
