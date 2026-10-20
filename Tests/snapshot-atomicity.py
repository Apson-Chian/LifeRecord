"""Deterministic independent-connection WAL writer, never a user database."""
import importlib.util
import os
from pathlib import Path
import tempfile
import threading
from unittest.mock import patch

root=Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='liferecord-snapshot-atomic-') as directory:
    os.environ.update(LIFERECORD_DB=directory+'/db.sqlite3',LIFERECORD_IMAGE_DIR=directory+'/images',LIFERECORD_SYNC_TOKEN='synthetic-snapshot-only')
    spec=importlib.util.spec_from_file_location('snapshot_server',root/'Backend/server.py')
    server=importlib.util.module_from_spec(spec);spec.loader.exec_module(server);server.initialize()
    meal=dict(id='11111111-1111-4111-8111-111111111111',date=1000,updatedAt=1000,name='before',calories=600)
    body=dict(id='22222222-2222-4222-8222-222222222222',date=1000,updatedAt=1000,weight=70)
    server.merge_snapshot({'meals':[meal],'bodyMetrics':[body]})
    read=server.database.read_record
    connect=server.connect
    triggered=False
    errors=[]
    connections=[]
    def writer():
        try:
            # Bypass process-local lock, as another worker/process would do.
            db=connect()
            try:
                with db:
                    server.database.put_record(db,server._user.get(),'meal',meal['id'],{},2000,1)
                    server.database.put_record(db,server._user.get(),'body',body['id'],{**body,'weight':71,'updatedAt':2000},2000)
            finally: db.close()
        except BaseException as error: errors.append(error)
    def interleave(db,*args):
        global triggered
        if not triggered:
            triggered=True
            thread=threading.Thread(target=writer);thread.start();thread.join(3)
            if thread.is_alive(): raise AssertionError('reader blocked independent WAL writer')
            if errors: raise errors[0]
        return read(db,*args)
    def tracked_connect():
        db=connect();connections.append(db);return db
    with patch.object(server.database,'read_record',side_effect=interleave), patch.object(server,'connect',side_effect=tracked_connect):
        snapshot=server.current_snapshot()
    assert snapshot['meals']==[meal], 'mixed snapshot: deleted fields became an empty meal'
    assert snapshot['bodyMetrics']==[body], 'mixed snapshot: newer body combined with older meal metadata'
    assert snapshot['deletions']==[]
    assert len(connections)==1, 'snapshot must use one connection'
    import sqlite3
    try: connections[0].execute('SELECT 1'); raise AssertionError('snapshot connection left open')
    except sqlite3.ProgrammingError: pass
    after=server.current_snapshot()
    assert after['meals']==[] and after['bodyMetrics'][0]['weight']==71 and len(after['deletions'])==1
print('PASS: single-connection consistent WAL snapshot, concurrent delete/update, explicit resource closure')
