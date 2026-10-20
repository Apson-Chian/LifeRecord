"""Contract regressions. Synthetic data, isolated SQLite, no HTTP or production access."""
import copy
import importlib.util
import json
import os
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
FIXTURE = json.loads((ROOT / 'Tests/Fixtures/data-contract.json').read_text())
TEMP = tempfile.TemporaryDirectory(prefix='liferecord-contract-')
os.environ.update(LIFERECORD_DB=str(Path(TEMP.name)/'test.sqlite3'), LIFERECORD_IMAGE_DIR=str(Path(TEMP.name)/'images'), LIFERECORD_SYNC_TOKEN='synthetic-contract-only')
spec = importlib.util.spec_from_file_location('contract_server', ROOT/'Backend/server.py')
server = importlib.util.module_from_spec(spec)
spec.loader.exec_module(server)
server.initialize()

class ContractTests(unittest.TestCase):
    def setUp(self):
        with server.connect() as db:
            db.execute("DELETE FROM user_records")

    def test_shared_numeric_boundaries_and_types(self):
        for kind, fields in FIXTURE['limits'].items():
            original=FIXTURE['snapshot']['settings'] if kind=='settings' else FIXTURE['snapshot']['meals' if kind=='meal' else 'bodyMetrics'][0]
            for field, (low,high) in fields.items():
                for value in [low,high]:
                    with self.subTest(kind=kind,field=field,value=value): server.validate_admin_record(kind,{**original,field:value})
                for value in [low-1,high+1,True,str(low),[]]:
                    with self.subTest(kind=kind,field=field,value=value), self.assertRaises(ValueError): server.validate_admin_record(kind,{**original,field:value})

    def test_invalid_sync_batch_does_not_write_anything(self):
        meal=FIXTURE['snapshot']['meals'][0]
        for patch in [{'date':None},{'note':[]},{'kind':'invalid'},{'source':False},{'createdAt':'1000'},{'bodyFat':True}]:
            kind='body' if 'bodyFat' in patch else 'meal'
            original=FIXTURE['snapshot']['bodyMetrics'][0] if kind=='body' else meal
            key='bodyMetrics' if kind=='body' else 'meals'
            invalid={**original,**patch,'id':'99999999-9999-4999-8999-999999999999'}
            good={**meal,'id':'88888888-8888-4888-8888-888888888888'}
            batch={key:[invalid]}
            batch.setdefault('meals',[]).insert(0,good)
            with self.subTest(patch=patch), self.assertRaises(ValueError): server.merge_snapshot(batch)
            self.assertFalse(any(r['id']==good['id'] for r in server.current_snapshot()['meals']))
        missing={**meal}; del missing['date']
        with self.assertRaises(ValueError): server.merge_snapshot({'meals':[missing]})

    def test_legacy_missing_fields_kept_raw(self):
        original=FIXTURE['legacyMeal']
        server.merge_snapshot({'meals':[original]})
        with server.connect() as db:
            self.assertEqual(original,server.database.read_record(db,server._user.get(),'meal',original['id']))

    def test_unchanged_historical_outlier_can_be_replayed_but_not_newly_created(self):
        original={**FIXTURE['snapshot']['bodyMetrics'][0],'bodyFat':0}
        with server.connect() as db:
            server.database.put_record(db,server._user.get(),'body',original['id'],original,original['updatedAt'])
        server.merge_snapshot({'bodyMetrics':[original]})
        self.assertEqual([original],server.current_snapshot()['bodyMetrics'])
        with self.assertRaises(ValueError):
            server.merge_snapshot({'bodyMetrics':[{**original,'id':'55555555-5555-4555-8555-555555555555'}]})

    def test_replay_does_not_confuse_booleans_with_numbers(self):
        body={**FIXTURE['snapshot']['bodyMetrics'][0],'date':0,'bodyFat':1}
        server.merge_snapshot({'bodyMetrics':[body]})
        for field in ['date','bodyFat']:
            with self.subTest(field=field), self.assertRaises(ValueError):
                server.merge_snapshot({'bodyMetrics':[{**body,field:False if field=='date' else True}]})
        self.assertEqual([body],server.current_snapshot()['bodyMetrics'])

    def test_changed_invalid_stale_request_still_validates(self):
        original=FIXTURE['snapshot']['workoutEntries'][0]
        server.merge_snapshot({'workoutEntries':[original]})
        with self.assertRaises(ValueError):
            server.merge_snapshot({'workoutEntries':[{**original,'updatedAt':original['updatedAt']-1,'exercises':[{'name':'bad','sets':[{'weight':True}]}]}]})
        self.assertEqual([original],server.current_snapshot()['workoutEntries'])

    def test_uuid_case_alias_cannot_create_duplicate(self):
        meal={**FIXTURE['snapshot']['meals'][0],'id':'abcdefab-cdef-4abc-8abc-abcdefabcdef'}
        server.merge_snapshot({'meals':[meal]})
        server.merge_snapshot({'meals':[{**meal,'id':meal['id'].upper(),'updatedAt':meal['updatedAt']+1}]})
        self.assertEqual([{**meal,'updatedAt':meal['updatedAt']+1}],server.current_snapshot()['meals'])

    def test_diagnostics_are_read_only_and_keep_original_export(self):
        invalid={**FIXTURE['legacyMeal'],'id':'legacy-id','date':None,'body':{'do':'not rewrite'}}
        with server.connect() as db:
            server.database.put_record(db,server._user.get(),'meal',invalid['id'],invalid,invalid['updatedAt'])
        before=server.current_snapshot()
        issues=server.snapshot_diagnostics(before)
        self.assertTrue(any(x['id']=='legacy-id' for x in issues))
        self.assertEqual(before['meals'],server.current_snapshot()['meals'])
        self.assertEqual(invalid,before['meals'][0])

    def test_shared_snapshot_roundtrip(self):
        server.merge_snapshot(FIXTURE['snapshot'])
        snapshot=server.current_snapshot()
        for key,value in FIXTURE['snapshot'].items(): self.assertEqual(value,snapshot[key])
        Path(TEMP.name,'server.json').write_text(json.dumps(snapshot,ensure_ascii=False))

if __name__=='__main__':
    try: unittest.main()
    finally: TEMP.cleanup()
