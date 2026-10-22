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
    # Correct an existing date by identity; stale snapshots must not bring it back.
    history=current["goalHistory"]
    expected=next(v for v in history if v["effectiveDate"]=="2026-10-22")
    correction={**expected,"proteinGoal":135,"effectiveDate":"2026-10-20","revisionAt":stamp("2026-10-24"),"revisionID":"correction-a"}
    corrected={**current,"goalHistory":[*history,correction],"updatedAt":stamp("2026-10-24")}
    server.merge_snapshot({"settings":corrected})
    moved=server.current_snapshot()["settings"]
    assert len([v for v in moved["goalHistory"] if v["id"]==expected["id"]])==1
    assert not any(v["effectiveDate"]=="2026-10-22" for v in moved["goalHistory"])
    server.merge_snapshot({"settings":current})
    replay=server.current_snapshot()["settings"]
    active=server.goal_history.active(replay["goalHistory"])
    assert next(v for v in active if v["id"]==expected["id"])["effectiveDate"]=="2026-10-20"
    baseline=next(v for v in replay["goalHistory"] if v["effectiveDate"]=="1970-01-01")
    fixed={**baseline,"proteinGoal":90,"revisionAt":stamp("2026-10-25"),"revisionID":"baseline-correction"}
    server.merge_snapshot({"settings":{**replay,"goalHistory":[*replay["goalHistory"],fixed],"updatedAt":stamp("2026-10-25")}})
    server.merge_snapshot({"settings":original})
    final=server.current_snapshot()
    assert server.goal_history.active(final["settings"]["goalHistory"])[0]["proteinGoal"]==90
    malformed=copy.deepcopy(final["settings"]);malformed["goalHistory"][0]["revisionAt"]=True
    try:
        server.merge_snapshot({"settings":malformed,"bodyMetrics":[dict(id="revision-rollback",date=1,weight=70,updatedAt=1)]})
        raise AssertionError("Boolean revision stamp accepted")
    except ValueError: pass
    after=server.current_snapshot()
    assert {k:v for k,v in after.items() if k!="serverTime"}=={k:v for k,v in final.items() if k!="serverTime"}
    assert server.goal_history.merged_history(current,corrected)==server.goal_history.merged_history(corrected,current)
    print("PASS: dated targets, local-midnight boundary, admin preview, older clients, offline history union, stale replay and atomic validation")
