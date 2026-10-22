"""Exercise actual profile writes using only an isolated local database."""
import copy
import datetime
import importlib.util
import json
import os
from pathlib import Path
import tempfile
from unittest.mock import patch
from zoneinfo import ZoneInfo

root = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix="liferecord-goal-history-") as folder:
    os.environ["LIFERECORD_SYNC_TOKEN"] = "local-goal-test-only"
    os.environ["LIFERECORD_DB"] = str(Path(folder) / "test.sqlite3")
    os.environ["LIFERECORD_IMAGE_DIR"] = str(Path(folder) / "images")
    spec = importlib.util.spec_from_file_location("goal_test_server", root / "Backend/server.py")
    server = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(server)
    server.initialize()
    zone = ZoneInfo("Asia/Shanghai")
    def stamp(day, hour=12):
        return datetime.datetime.fromisoformat(day).replace(hour=hour, tzinfo=zone).timestamp()
    def goal(profile, day):
        return next((v for v in reversed(profile["goalHistory"]) if v["effectiveDate"] <= day), profile)
    original = dict(server.PROFILE_DEFAULTS, id="profile", updatedAt=stamp("2026-10-20"), goalTimeZone="Asia/Shanghai")
    server.merge_snapshot({"settings": original})
    action = dict(recordType="settings", operation="update", recordID="profile", expectedUpdatedAt=original["updatedAt"],
                  fields=dict(proteinGoal=150, calorieGoal=2400), goalTimeZone="Asia/Shanghai")
    with patch.object(server.time, "time", return_value=stamp("2026-10-22")):
        changes, preview = server.prepare_admin_actions([action], server.current_snapshot())
        assert len(preview[0]["after"]["goalHistory"]) == 2
        server.merge_snapshot(changes)
    current = server.current_snapshot()["settings"]
    assert goal(current, "2026-10-21")["proteinGoal"] == 100
    assert goal(current, "2026-10-22")["proteinGoal"] == 150
    assert goal(current, "2026-10-23")["proteinGoal"] == 150
    # An older client omits the extension. Capture its new target without deleting history.
    old_client = {k: v for k, v in current.items() if k != "goalHistory"}
    old_client.update(proteinGoal=180, updatedAt=stamp("2026-10-23", hour=0))
    server.merge_snapshot({"settings": old_client})
    current = server.current_snapshot()["settings"]
    assert goal(current, "2026-10-22")["proteinGoal"] == 150
    assert goal(current, "2026-10-23")["proteinGoal"] == 180
    # An offline edit on an earlier day contributes its history while losing current-profile LWW.
    earlier = copy.deepcopy(original)
    earlier.update(proteinGoal=125, updatedAt=stamp("2026-10-21"))
    earlier["goalHistory"] = [dict(current["goalHistory"][0]), dict(server.goal_history.values(earlier),
        id="offline-version", effectiveDate="2026-10-21", updatedAt=earlier["updatedAt"])]
    server.merge_snapshot({"settings": earlier})
    current = server.current_snapshot()["settings"]
    assert current["proteinGoal"] == 180 and len(current["goalHistory"]) == 4
    assert goal(current, "2026-10-21")["proteinGoal"] == 125
    assert goal(current, "2026-10-20")["proteinGoal"] == 100
    server.merge_snapshot({"settings": original})
    assert server.current_snapshot()["settings"] == current
    # Explicit empty arrays cannot remove previously committed target versions.
    replay = {**current, "goalHistory": [], "updatedAt": current["updatedAt"] + 1}
    server.merge_snapshot({"settings": replay})
    current = server.current_snapshot()["settings"]
    assert len(current["goalHistory"]) == 4
    before = server.current_snapshot()
    broken = copy.deepcopy(current)
    broken["goalHistory"][-1]["effectiveDate"] = "2026-02-30"
    try:
        server.merge_snapshot({"settings": broken, "bodyMetrics": [dict(id="must-roll-back", date=1, weight=70, updatedAt=1)]})
        raise AssertionError("Invalid history accepted")
    except ValueError:
        pass
    assert server.current_snapshot()["settings"] == before["settings"]
    assert server.current_snapshot()["bodyMetrics"] == before["bodyMetrics"]
    fixture = root / "Android/app/build/outputs/tests/goal-history.json"
    if fixture.exists():
        android = json.loads(fixture.read_text())
        server.validate_admin_record("settings", android)
        assert goal(android, "2026-10-21")["proteinGoal"] == 100
        assert goal(android, "2026-10-22")["proteinGoal"] == 150
    print("PASS: dated targets, local-midnight boundary, admin preview, older clients, offline history union, stale replay and atomic validation")
