"""Account administration with an independent credential and no access to record content."""

import hashlib
import json
import os
import re
import secrets
import sqlite3
import threading
import time
from contextlib import closing
from http.cookies import SimpleCookie
from pathlib import Path
from urllib.parse import parse_qs, urlsplit

import database

PREFIX = "/liferecord-api/user-admin"
COOKIE = "liferecord_admin_session"
SESSION_AGE = 3600
PAGE_SIZE = 30
ACTIVITY_RETENTION = 30 * 86400
ACTIVITY_LIMIT = 100
ACTIVITY_ACTIONS = {
    "/liferecord-api/auth": "login",
    "/liferecord-api/account/login": "login",
    "/liferecord-api/account/register": "register",
    "/liferecord-api/sync": "sync",
    "/liferecord-api/images": "upload",
    "/liferecord-api/ai/chat": "ai_chat",
    "/liferecord-api/ai/plan": "ai_plan",
}
ASSETS = {
    "/": ("index.html", "text/html; charset=utf-8"),
    "/admin.js": ("admin.js", "text/javascript; charset=utf-8"),
    "/admin.css": ("admin.css", "text/css; charset=utf-8"),
}


def initialize(db):
    db.execute("""
        CREATE TABLE IF NOT EXISTS admin_account_suspensions(
            user_id TEXT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE
        )
    """)
    db.execute("""
        CREATE TABLE IF NOT EXISTS admin_account_actions(
            id INTEGER PRIMARY KEY, user_id TEXT NOT NULL, action TEXT NOT NULL, ts INTEGER NOT NULL
        )
    """)
    db.execute("""
        CREATE TABLE IF NOT EXISTS account_activity(
            id INTEGER PRIMARY KEY, user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
            ts INTEGER NOT NULL, action TEXT NOT NULL, platform TEXT NOT NULL, status INTEGER NOT NULL
        )
    """)
    db.execute("CREATE INDEX IF NOT EXISTS account_activity_by_user ON account_activity(user_id,ts DESC,id DESC)")
    db.execute("CREATE INDEX IF NOT EXISTS account_activity_by_time ON account_activity(ts)")


def record_activity(db_path, user, action, platform, status):
    platform = platform.lower()
    if platform not in {"ios", "android", "web"}:
        platform = "unknown"
    # Keep telemetry off the main connection and bound wait time if a writer is busy.
    with closing(sqlite3.connect(db_path, timeout=0.1)) as db, db:
        db.execute("""
            INSERT INTO account_activity(user_id,ts,action,platform,status)
            SELECT id,?,?,?,? FROM users WHERE id=? AND disabled=0
        """, (int(time.time()), action, platform, status, user))


def prune_activity(connect):
    with closing(connect()) as db, db:
        db.execute("DELETE FROM account_activity WHERE ts<?", (int(time.time()) - ACTIVITY_RETENTION,))


def activity_report(db, user):
    if not re.fullmatch(r"[a-z0-9-]{1,40}", user):
        raise ValueError("用户 ID 无效")
    account = db.execute("""
        SELECT u.id,u.label,c.username FROM users u
        LEFT JOIN account_credentials c ON c.user_id=u.id WHERE u.id=?
    """, (user,)).fetchone()
    if account is None:
        return None
    records = db.execute("""
        SELECT record_type, count(*) AS total, max(updated_at) AS last_update
        FROM user_records WHERE user_id=? AND deleted=0 AND record_type IN ('meal','body','workout')
        GROUP BY record_type
    """, (user,)).fetchall()
    images = db.execute("""
        SELECT count(*) AS total,max(created_at) AS last_upload FROM user_images WHERE user_id=?
    """, (user,)).fetchone()
    ai_usage = None
    if db.execute("SELECT 1 FROM sqlite_master WHERE type='table' AND name='ai_daily_usage'").fetchone():
        ai_usage = db.execute("""
            SELECT COALESCE(sum(requests),0) FROM ai_daily_usage WHERE user_id=? AND day>=date('now','-6 days')
        """, (user,)).fetchone()[0]
    cutoff = int(time.time()) - ACTIVITY_RETENTION
    last_login = db.execute("""
        SELECT max(ts) FROM account_activity WHERE user_id=? AND ts>=? AND action='login' AND status BETWEEN 200 AND 299
    """, (user, cutoff)).fetchone()[0]
    events = db.execute("""
        SELECT ts,action,platform,status FROM account_activity WHERE user_id=? AND ts>=?
        ORDER BY ts DESC,id DESC LIMIT ?
    """, (user, cutoff, ACTIVITY_LIMIT))
    return {
        "user": dict(account),
        "records": [dict(row) for row in records],
        "images": dict(images),
        "ai_usage": ai_usage,
        "last_login": last_login,
        "events": [dict(row) for row in events],
    }


def list_users(db, query):
    search = query.get("q", [""])[0].strip()
    status = query.get("status", ["all"])[0]
    page = int(query.get("page", ["1"])[0])
    if len(search) > 100 or status not in {"all", "active", "disabled"} or page < 1:
        raise ValueError("筛选条件无效")
    where = """
        FROM users u LEFT JOIN account_credentials c ON c.user_id=u.id
        LEFT JOIN admin_account_suspensions a ON a.user_id=u.id
        WHERE (instr(lower(u.label), lower(?)) OR instr(c.username, lower(?)) OR instr(u.id, lower(?)))
    """
    params = [search] * 3
    if status != "all":
        where += " AND u.disabled=?"
        params.append(int(status == "disabled"))
    total = db.execute("SELECT count(*) " + where, params).fetchone()[0]
    page = min(page, max(1, (total + PAGE_SIZE - 1) // PAGE_SIZE))
    rows = db.execute("""
        SELECT u.id,u.label,u.created_at,u.disabled,c.username,a.user_id IS NOT NULL AS restorable
    """ + where + " ORDER BY u.created_at DESC,u.id LIMIT ? OFFSET ?",
        [*params, PAGE_SIZE, (page - 1) * PAGE_SIZE],
    )
    return {"users": [dict(row) for row in rows], "total": total, "page": page, "page_size": PAGE_SIZE}


def change_user(db, user, action):
    if not isinstance(user, str) or not re.fullmatch(r"[a-z0-9-]{1,40}", user):
        raise ValueError("用户 ID 无效")
    if action not in ("suspend", "restore", "revoke-sessions"):
        raise ValueError("操作无效")
    if user == database.LEGACY_USER:
        raise ValueError("原有私人档案受保护")
    current = db.execute("SELECT disabled FROM users WHERE id=?", (user,)).fetchone()
    if not current:
        raise ValueError("账号不存在")
    if action == "restore":
        removed = db.execute("DELETE FROM admin_account_suspensions WHERE user_id=?", (user,))
        if not removed.rowcount:
            raise ValueError("只有通过本后台停用的账号可以恢复")
        db.execute("UPDATE users SET disabled=0 WHERE id=?", (user,))
    else:
        if current["disabled"]:
            raise ValueError("账号已停用")
        if action == "suspend":
            db.execute("INSERT INTO admin_account_suspensions VALUES(?)", (user,))
            db.execute("UPDATE users SET disabled=1 WHERE id=?", (user,))
        db.execute("DELETE FROM sessions WHERE user_id=?", (user,))
    db.execute("INSERT INTO admin_account_actions(user_id,action,ts) VALUES(?,?,?)", (user, action, int(time.time())))


class Console:
    def __init__(self, connect, origin, auth_blocked, note_failure, clear_failures):
        filename = os.environ.get("LIFERECORD_ADMIN_PASSWORD_FILE")
        self.password_hash = None
        if filename:
            try:
                password = Path(filename).read_bytes().strip()
                if len(password) < 24 or len(password) > 256:
                    raise ValueError("invalid password length")
                self.password_hash = hashlib.sha256(password).digest()
            except (OSError, ValueError):
                print("LifeRecord user administration disabled: check the admin password file.", flush=True)
        self.connect = connect
        self.origin = origin
        self.auth_blocked = auth_blocked
        self.note_failure = note_failure
        self.clear_failures = clear_failures
        self.sessions = {}
        self.lock = threading.Lock()

    @staticmethod
    def matches(path):
        return path == PREFIX or path.startswith(PREFIX + "/")

    @staticmethod
    def reply(handler, status, data=None, content_type="application/json; charset=utf-8", headers=None):
        if not isinstance(data, bytes):
            data = json.dumps(data, ensure_ascii=False).encode()
        handler.send_response(status)
        handler._security_headers()
        handler.send_header("Content-Security-Policy", "default-src 'none'; script-src 'self'; style-src 'self'; connect-src 'self'; form-action 'self'; frame-ancestors 'none'; base-uri 'none'")
        handler.send_header("Content-Type", content_type)
        handler.send_header("Content-Length", str(len(data)))
        for name, value in (headers or {}).items():
            handler.send_header(name, value)
        handler.end_headers()
        if handler.command != "HEAD":
            handler.wfile.write(data)

    @staticmethod
    def session_token(handler):
        try:
            cookie = SimpleCookie(handler.headers.get("Cookie", "")).get(COOKIE)
            return cookie.value if cookie else ""
        except ValueError:
            return ""

    @staticmethod
    def cookie(token, age):
        return {"Set-Cookie": f"{COOKIE}={token}; Path={PREFIX}/; Max-Age={age}; HttpOnly; Secure; SameSite=Strict"}

    def handle(self, handler, raw_path):
        if self.password_hash is None:
            return self.reply(handler, 404, {"error": "页面不存在"})
        path = raw_path[len(PREFIX):]
        if handler.command in {"GET", "HEAD"}:
            if not path:
                return self.reply(handler, 308, b"", headers={"Location": PREFIX + "/"})
            if path in ASSETS:
                name, content_type = ASSETS[path]
                return self.reply(handler, 200, (Path(__file__).parent / "user_admin" / name).read_bytes(), content_type)
        elif handler.headers.get("Origin") != self.origin or handler.headers.get("Sec-Fetch-Site") == "cross-site":
            return self.reply(handler, 403, {"error": "请求来源不匹配"})

        token = self.session_token(handler)
        try:
            if handler.command == "POST" and path == "/api/login":
                return self.login(handler)
            with self.lock:
                authorized = bool(token) and self.sessions.get(token, 0) > time.monotonic()
            if handler.command in {"GET", "HEAD"} and path == "/api/session":
                return self.reply(handler, 200, {"authenticated": authorized})
            if not authorized:
                return self.reply(handler, 401, {"error": "请先登录管理后台"})
            if handler.command == "GET" and path == "/api/users":
                with closing(self.connect()) as db, db:
                    db.execute("BEGIN")
                    result = list_users(db, parse_qs(urlsplit(handler.path).query))
                return self.reply(handler, 200, result)
            if handler.command == "GET" and path == "/api/users/activity":
                user = parse_qs(urlsplit(handler.path).query).get("id", [""])[0]
                with closing(self.connect()) as db, db:
                    db.execute("BEGIN")
                    result = activity_report(db, user)
                if result is None:
                    return self.reply(handler, 404, {"error": "账号不存在"})
                return self.reply(handler, 200, result)
            if handler.command == "POST" and path == "/api/logout":
                with self.lock:
                    self.sessions.pop(token, None)
                return self.reply(handler, 200, {"ok": True}, headers=self.cookie("", 0))
            if handler.command == "POST" and path == "/api/users/change":
                data = self.body(handler)
                with closing(self.connect()) as db, db:
                    db.execute("BEGIN IMMEDIATE")
                    change_user(db, data.get("id"), data.get("action"))
                return self.reply(handler, 200, {"ok": True})
            return self.reply(handler, 404, {"error": "接口不存在"})
        except (ValueError, TypeError) as error:
            return self.reply(handler, 400, {"error": str(error)})
        except sqlite3.Error:
            return self.reply(handler, 503, {"error": "数据库暂不可用，请重试"})

    @staticmethod
    def body(handler):
        if handler.headers.get_content_type() != "application/json":
            raise ValueError("需要 JSON 请求")
        if not 0 < int(handler.headers.get("Content-Length", "0")) <= 2048:
            raise ValueError("请求大小无效")
        return handler._read_json()

    def login(self, handler):
        client = "user-admin:" + handler._client_identity()
        if self.auth_blocked(client):
            return self.reply(handler, 429, {"error": "尝试次数过多，请稍后再试"})
        password = self.body(handler).get("password")
        digest = hashlib.sha256(password.encode()).digest() if isinstance(password, str) else b""
        if not secrets.compare_digest(digest, self.password_hash):
            self.note_failure(client)
            return self.reply(handler, 401, {"error": "管理口令不正确"})
        self.clear_failures(client)
        token = secrets.token_urlsafe(32)
        now = time.monotonic()
        with self.lock:
            self.sessions = {key: expiry for key, expiry in self.sessions.items() if expiry > now}
            if len(self.sessions) >= 16:
                self.sessions.pop(next(iter(self.sessions)))
            self.sessions[token] = now + SESSION_AGE
        return self.reply(handler, 200, {"ok": True}, headers=self.cookie(token, SESSION_AGE))
