"""Isolated admin/AI contract regression: python3 Tests/admin-api.py."""
import importlib.util
import json
import os
from pathlib import Path
import tempfile
from unittest.mock import patch

with tempfile.TemporaryDirectory() as folder:
    os.environ['LIFERECORD_SYNC_TOKEN'] = 'test-only-token'
    os.environ['LIFERECORD_DB'] = str(Path(folder) / 'test.sqlite3')
    os.environ['LIFERECORD_IMAGE_DIR'] = str(Path(folder) / 'images')
    spec = importlib.util.spec_from_file_location('server', Path(__file__).resolve().parents[1] / 'Backend/server.py')
    server = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(server)
    server.initialize()

    def action(kind, op, item=None, **fields):
        return dict(recordType=kind, operation=op, recordID=item['id'] if item else None,
                    expectedUpdatedAt=item['updatedAt'] if item else None, fields=fields)

    first = server.apply_admin_actions([action('body','add',weight=70,bodyFat=18.5,note='晨起')])['bodyMetrics'][0]
    changed = server.apply_admin_actions([action('body','update',first,bodyFat=None,weight=69.5)])['bodyMetrics'][0]
    assert changed['bodyFat'] is None and changed['weight'] == 69.5 and changed['date'] == first['date']
    assert changed['id'] == first['id']
    try:
        server.apply_admin_actions([action('body','update',first,weight=80)])
        raise AssertionError('stale edit accepted')
    except ValueError:
        pass
    try:
        server.apply_admin_actions([action('water','add',milliliters=250), action('body','update',changed,bodyFat=101)])
        raise AssertionError('invalid batch accepted')
    except ValueError:
        assert not server.current_snapshot()['waterEntries']
    profile=server.apply_admin_actions([action('settings','update',displayName='测试',waterGoal=3000)])['settings']
    assert profile['height']==181 and profile['waterGoal']==3000

    class Response:
        def __enter__(self): return self
        def __exit__(self,*args): pass
        def read(self,*args):
            return json.dumps({'choices':[{'message':{'content':json.dumps({'answer':'将体重改为 68.5 kg','actions':[{'recordType':'body','operation':'update','recordID':changed['id'],'fields':{'weight':68.5}}]})}}]}).encode()

    with patch.object(server.urllib.request, 'urlopen', return_value=Response()) as request:
        plan=server.ai_plan(dict(instruction='修改体重',provider='deepseek',model='test-model',apiKey='test-key'))
        assert plan['actions'][0]['expectedUpdatedAt']==changed['updatedAt']
        assert server.current_snapshot()['bodyMetrics'][0]['weight']==69.5  # A preview does not write.
        assert 'test-key' not in request.call_args.args[0].data.decode()
    updated=server.apply_admin_actions(plan['actions'])['bodyMetrics'][0]
    assert updated['weight']==68.5 and updated['bodyFat'] is None
    server.apply_admin_actions([action('body','delete',updated)])
    assert not server.current_snapshot()['bodyMetrics']
    print('PASS: full CRUD, nullable fat, timestamps, version conflicts, atomic validation, profile defaults, AI preview/apply')
