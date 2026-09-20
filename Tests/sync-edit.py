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

    workout = dict(id='workout-test', date=4000, endDate=None, note='深蹲 4 组', updatedAt=4000)
    server.merge_snapshot({'workoutEntries': [workout]})
    assert server.current_snapshot()['workoutEntries'] == [workout]
    finished = {**workout, 'endDate': 7600, 'updatedAt': 7600}
    server.merge_snapshot({'workoutEntries': [finished]})
    server.merge_snapshot({'workoutEntries': [workout]})
    server.merge_snapshot({'meals': []})  # Old clients omit workouts without deleting them.
    assert server.current_snapshot()['workoutEntries'] == [finished]
    try:
        server.merge_snapshot({'workoutEntries': [{**finished, 'endDate': 3999}]})
        raise AssertionError('invalid interval accepted')
    except ValueError:
        pass
    server.merge_snapshot({'deletions': [dict(id='workout-test', recordType='workout', deletedAt=8000)]})
    server.merge_snapshot({'workoutEntries': [finished]})
    assert server.current_snapshot()['workoutEntries'] == []
    print('PASS: workout start/end, stale updates, old clients, validation and deletion')

    # Structured exercise data survives an older client updating only notes.
    structured = dict(id='structured-workout', date=1000, endDate=2000, note='', updatedAt=9000,
                      exercises=[dict(name='卧推', sets=[dict(reps=8, weight=40), dict(reps=6, weight=45)]),
                                 dict(name='平板支撑', sets=[dict(durationSeconds=60)])])
    server.merge_snapshot({'workoutEntries': [structured]})
    assert server.current_snapshot()['workoutEntries'][0]['exercises'] == structured['exercises']
    old = {k:v for k,v in structured.items() if k != 'exercises'}
    old.update(note='older client edit', updatedAt=9001)
    server.merge_snapshot({'workoutEntries': [old]})
    assert server.current_snapshot()['workoutEntries'][0]['exercises'] == structured['exercises']
    for exercises in [[dict(name='', sets=[{}])], [dict(name='蹲', sets=[{}] * 101)],
                      [dict(name='蹲', sets=[dict(reps=-1)])], [dict(name='蹲', sets=[dict(reps=1.5)])],
                      [dict(name='蹲', sets=[dict(weight=True)])], [dict(name='蹲', sets=[dict(durationSeconds=0)])]]:
        try:
            server.merge_snapshot({'workoutEntries': [{**structured, 'exercises': exercises, 'updatedAt': 9002}]})
            raise AssertionError('Invalid exercises accepted')
        except ValueError:
            pass
    server.merge_snapshot({'workoutEntries': [{**structured, 'exercises': [], 'updatedAt': 9003}]})
    assert server.current_snapshot()['workoutEntries'][0]['exercises'] == []
    print('PASS: structured sets round-trip, old-client preservation, explicit clearing and validation')

    name_only = [{"name": "深蹲", "sets": []}]
    server.merge_snapshot({'workoutEntries': [{**structured, 'exercises': name_only, 'updatedAt': 9004}]})
    assert server.current_snapshot()['workoutEntries'][0]['exercises'] == name_only
    print('PASS: name-only exercises sync without sets')
