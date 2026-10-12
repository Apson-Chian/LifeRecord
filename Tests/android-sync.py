"""Validate the actual Kotlin-generated Android wire snapshot against the existing backend.
Run Android unit tests first, then python3 Tests/android-sync.py.
"""
import importlib.util
import json
import os
from pathlib import Path
import tempfile

root = Path(__file__).resolve().parents[1]
fixture = root / 'Android/app/build/outputs/tests/android-sync-snapshot.json'
if not fixture.exists():
    raise SystemExit('Run Android ./gradlew :app:testDebugUnitTest first to generate the wire fixture.')
snapshot = json.loads(fixture.read_text())
with tempfile.TemporaryDirectory() as folder:
    os.environ['LIFERECORD_SYNC_TOKEN'] = 'android-local-test-only'
    os.environ['LIFERECORD_DB'] = str(Path(folder) / 'test.sqlite3')
    os.environ['LIFERECORD_IMAGE_DIR'] = str(Path(folder) / 'images')
    spec = importlib.util.spec_from_file_location('android_test_server', root / 'Backend/server.py')
    server = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(server)
    server.initialize()
    server.merge_snapshot(snapshot)
    result = server.current_snapshot()
    for collection in ('meals', 'bodyMetrics', 'workoutEntries'):
        assert result[collection] == snapshot[collection], collection
    assert result['settings'] == snapshot['settings']
    assert result['meals'][0]['photoIDs'] == ['a' * 32]
    assert result['bodyMetrics'][0]['bodyFat'] is None
    assert result['workoutEntries'][0]['bodyParts'] == ['二头', '三头']
    original = snapshot['workoutEntries'][0]
    server.merge_snapshot({'deletions': [dict(id=original['id'], recordType='workout', deletedAt=original['updatedAt']+1)]})
    server.merge_snapshot(snapshot)
    assert not server.current_snapshot()['workoutEntries']
print('PASS: actual Android JSON accepted, all fields round-trip, workout deletion resists stale Android snapshot')
