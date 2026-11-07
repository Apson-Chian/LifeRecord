"""Exercise the administration entry points against an isolated LifeRecord server."""
from http.client import HTTPConnection
import json
import os
import sys
import tempfile
import threading
import time
from contextlib import closing
from pathlib import Path

with tempfile.TemporaryDirectory() as directory:
    root = Path(directory)
    password = "test-only-administration-passphrase"
    password_file = root / "admin-password"
    password_file.write_text(password)
    os.environ.update({
        "LIFERECORD_DB": str(root / "test.sqlite3"),
        "LIFERECORD_ADMIN_PASSWORD_FILE": str(password_file),
        "LIFERECORD_SYNC_TOKEN": "private-owner-key",
        "LIFERECORD_PUBLIC_ORIGIN": "https://admin.example.test",
    })
    sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "Backend"))
    import server

    server.initialize()
    with closing(server.connect()) as db, db:
        user, key = server.database.create_user(db, "Test <Account>")
        deleted, _ = server.database.create_user(db, "Deleted test account")
        db.execute("UPDATE users SET disabled=1 WHERE id=?", (deleted,))
        db.execute("INSERT INTO account_activity(user_id,ts,action,platform,status) VALUES(?,?,?,?,?)",
                   (user, int(time.time())-server.user_admin.ACTIVITY_RETENTION-1, "login", "web", 200))
        db.execute("CREATE TABLE ai_daily_usage(user_id TEXT,day TEXT,requests INTEGER)")
        db.execute("INSERT INTO ai_daily_usage VALUES(?,date('now'),3),(?,date('now'),99)", (user, deleted))
        db.execute("INSERT INTO sessions VALUES(?,?,?)", (server.database.token_hash("old-session"), user, 9999999999))
        server.database.put_record(db, user, "meal", "example", {"note": "private content"}, 1)

    http = server.ThreadingHTTPServer(("127.0.0.1", 0), server.Handler)
    thread = threading.Thread(target=http.serve_forever, daemon=True)
    thread.start()
    prefix = "/liferecord-api/user-admin"

    def request(path, body=None, headers=None):
        with closing(HTTPConnection("127.0.0.1", http.server_port)) as client:
            client.request(
                "GET" if body is None else "POST", path,
                json.dumps(body) if body is not None else None,
                {"Content-Type": "application/json", "Origin": server.PUBLIC_ORIGIN, **(headers or {})},
            )
            response = client.getresponse()
            return response.status, response.getheader("Set-Cookie"), response.read()

    try:
        assert request(prefix + "/")[0] == 200
        assert request(prefix + "/admin.js")[0] == 200
        assert request(prefix + "/api/users", headers={"Authorization": "Bearer " + key})[0] == 401
        assert request(prefix + "/api/login", {"password": key})[0] == 401
        status, cookie, _ = request(prefix + "/api/login", {"password": password})
        assert status == 200 and "HttpOnly" in cookie and "Secure" in cookie
        admin = {"Cookie": cookie.split(";", 1)[0]}
        status, _, payload = request(prefix + "/api/users?q=Test", headers=admin)
        assert status == 200 and json.loads(payload)["total"] == 2
        assert all(word not in payload for word in (b"token_hash", b"password_hash", b"private content"))
        activity = prefix + "/api/users/activity?id=" + user
        assert request(activity, headers={"Authorization": "Bearer " + key})[0] == 401
        assert request(prefix + "/api/users/activity?id=missing", headers=admin)[0] == 404
        summary = json.loads(request(activity, headers=admin)[2])
        assert summary["records"] == [{"record_type": "meal", "total": 1, "last_update": 1}]
        assert summary["images"] == {"total": 0, "last_upload": None}
        assert summary["ai_usage"] == 3 and summary["events"] == [] and summary["last_login"] is None
        assert request("/liferecord-api/auth", {"token": key}, {"X-LifeRecord-Client": "web"})[0] == 204
        assert request("/liferecord-api/sync", {}, {"Authorization": "Bearer " + key, "X-LifeRecord-Client": "ios"})[0] == 200
        assert request("/liferecord-api/images", {}, {"Authorization": "Bearer " + key, "X-LifeRecord-Client": "unrecognized"})[0] == 400
        assert request("/liferecord-api/sync", {}, {"Authorization": "Bearer invalid"})[0] == 401
        result = request(activity, headers=admin)[2]
        report = json.loads(result)
        assert report["last_login"] is not None
        assert [(event["action"], event["platform"], event["status"]) for event in report["events"]] == [
            ("upload", "unknown", 400), ("sync", "ios", 200), ("login", "web", 204),
        ]
        assert b"private content" not in result and key.encode() not in result and b"example" not in result
        assert json.loads(request(prefix + "/api/users/activity?id=" + deleted, headers=admin)[2])["events"] == []
        server.user_admin.prune_activity(server.connect)
        with closing(server.connect()) as db:
            assert db.execute("SELECT count(*) FROM account_activity").fetchone()[0] == 3
        change = prefix + "/api/users/change"
        assert request(change, {"id": user, "action": "suspend"}, {**admin, "Origin": "https://other.test"})[0] == 403
        assert request(change, {"id": server.database.LEGACY_USER, "action": "suspend"}, admin)[0] == 400
        assert request(change, {"id": deleted, "action": "restore"}, admin)[0] == 400
        assert request(change, {"id": user, "action": "suspend"}, admin)[0] == 200
        snapshot = "/liferecord-api/snapshot"
        assert request(snapshot, headers={"Authorization": "Bearer " + key})[0] == 401
        assert request(change, {"id": user, "action": "restore"}, admin)[0] == 200
        assert request(snapshot, headers={"Authorization": "Bearer old-session"})[0] == 401
        assert request(snapshot, headers={"Authorization": "Bearer " + key})[0] == 200
        assert request("/liferecord-api/account/delete", {"confirmation": "DELETE MY ACCOUNT"},
                       {"Authorization": "Bearer " + key})[0] == 200
        assert json.loads(request(activity, headers=admin)[2])["events"] == []
        assert request(prefix + "/api/logout", {}, admin)[0] == 200
        assert request(prefix + "/api/users", headers=admin)[0] == 401
    finally:
        http.shutdown()
        http.server_close()
        thread.join()
    print("LifeRecord user administration verified")
