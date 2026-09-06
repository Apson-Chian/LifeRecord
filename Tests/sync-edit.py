"""Run with python3 Tests/sync-edit.py; uses an isolated temporary database."""
import importlib.util
import os
from pathlib import Path
import tempfile

with tempfile.TemporaryDirectory() as folder:
    os.environ['LIFERECORD_SYNC_TOKEN'] = 'local-test-only'
    os.environ['LIFERECORD_DB'] = str(Path(folder) / 'test.sqlite3')
    os.environ['LIFERECORD_IMAGE_DIR'] = str(Path(folder) / 'images')
    spec = importlib.util.spec_from_file_location('server', Path(__file__).resolve().parents[1] / 'Backend/server.py')
    server = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(server)
    server.initialize()
    original = dict(id='meal-test', name='午餐', date=1000, createdAt=1000, updatedAt=1000,
                    calories=650, protein=42, carbs=78, fat=18, fiber=5,
                    source='AI 估算', photoIDs=['a' * 32])
    server.merge_snapshot({'meals': [original]})
    edited = {**original, 'calories': 325, 'protein': 0, 'updatedAt': 2000}
    server.merge_snapshot({'meals': [edited]})
    server.merge_snapshot({'meals': [original]})  # A stale device must not undo the edit.
    result = server.current_snapshot()
    assert result['meals'] == [edited]
    assert result['waterEntries'] == []
    server.merge_snapshot({'deletions': [dict(id='meal-test', recordType='meal', deletedAt=3000)]})
    server.merge_snapshot({'meals': [edited]})
    assert server.current_snapshot()['meals'] == []
    print('PASS: same-ID update, photos preserved, stale snapshots ignored, deletion preserved')
