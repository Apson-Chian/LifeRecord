"""Self-service registration and password storage against disposable SQLite/HTTP."""
import concurrent.futures
import hashlib
import http.client
import json
import os
from pathlib import Path
import sys
import tempfile
import threading

sys.path.insert(0, str(Path(__file__).resolve().parents[1]/'Backend'))
with tempfile.TemporaryDirectory() as folder:
    os.environ.update(LIFERECORD_DB=folder+'/accounts.sqlite', LIFERECORD_IMAGE_DIR=folder+'/images', LIFERECORD_SYNC_TOKEN='')
    import database
    import server
    server.initialize()
    http_server=server.ThreadingHTTPServer(('127.0.0.1',0),server.Handler)
    threading.Thread(target=http_server.serve_forever,daemon=True).start()

    def request(path,body=None,key=None,origin=None):
        connection=http.client.HTTPConnection('127.0.0.1',http_server.server_port,timeout=20)
        headers={'Content-Type':'application/json'}
        if key: headers['Authorization']='Bearer '+key
        if origin: headers['Origin']=origin
        connection.request('POST' if body is not None else 'GET','/liferecord-api'+path,json.dumps(body) if body is not None else None,headers)
        response=connection.getresponse(); raw=response.read()
        result=(response.status,json.loads(raw) if raw else {},response.getheader('Set-Cookie'))
        connection.close();return result

    password='self-service fixture password 42!'
    try:
        assert request('/account/register',{'username':'bad name','password':password})[0]==400
        assert request('/account/register',{'username':'alice','password':'short'})[0]==400
        assert request('/account/register',{'username':'alice','password':password},origin='https://evil.example')[0]==403
        with server.connect() as db: assert db.execute('SELECT count(*) FROM users').fetchone()[0]==0
        status,alice,cookie=request('/account/register',{'username':'  Alice.One  ','password':password})
        assert status==200 and alice['username']=='alice.one' and alice['userId']
        assert 'HttpOnly' in cookie and 'Secure' in cookie and 'SameSite=Strict' in cookie
        assert request('/account/me',key=alice['token'])[1]['userId']==alice['userId']
        assert request('/snapshot',key=alice['token'])[1]['meals']==[]
        assert request('/account/register',{'username':'ALICE.ONE','password':password})[0]==400
        with server.connect() as db: assert db.execute('SELECT count(*) FROM users').fetchone()[0]==1
        status,bob,_=request('/account/register',{'username':'bob.user','password':password})
        assert status==200 and bob['userId']!=alice['userId']
        with server.connect() as db:
            hashes=[r['password_hash'] for r in db.execute('SELECT password_hash FROM account_credentials')]
            assert len(set(hashes))==2  # same password, independent random salts
            assert all(value.startswith('scrypt$131072$8$1$') and password not in value for value in hashes)
            assert db.execute('SELECT 1 FROM sessions WHERE token_hash=?',(alice['token'],)).fetchone() is None
            assert db.execute('SELECT 1 FROM sessions WHERE token_hash=?',(database.token_hash(alice['token']),)).fetchone()
            database.put_record(db,alice['userId'],'meal','private',{'name':'Alice private meal'},1000)
        assert request('/snapshot',key=bob['token'])[1]['meals']==[]
        assert request('/snapshot',key=alice['token'])[1]['meals'][0]['name']=='Alice private meal'
        assert request('/account/login',{'username':'ALICE.ONE','password':password})[1]['userId']==alice['userId']
        # Two racing requests cannot create duplicate credentials or orphan users.
        with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
            results=list(pool.map(lambda _: request('/account/register',{'username':'race.user','password':password}),range(2)))
        assert sorted(result[0] for result in results)==[200,400]
        with server.connect() as db:
            assert db.execute('SELECT count(*) FROM users').fetchone()[0]==3
            assert db.execute('SELECT count(*) FROM account_credentials').fetchone()[0]==3
            salt='12'*16
            legacy=hashlib.scrypt(password.encode(),salt=bytes.fromhex(salt),n=16384,r=8,p=1).hex()
            db.execute('UPDATE account_credentials SET password_hash=? WHERE user_id=?',(f'scrypt${salt}${legacy}',bob['userId']))
        assert request('/account/login',{'username':'bob.user','password':password})[0]==200
        with server.connect() as db:
            assert db.execute('SELECT password_hash FROM account_credentials WHERE user_id=?',(bob['userId'],)).fetchone()[0].startswith('scrypt$131072$8$1$')
        assert request('/account/delete',{'confirmation':'DELETE MY ACCOUNT'},key=alice['token'])[0]==200
        assert request('/account/login',{'username':'alice.one','password':password})[0]==401
        with server.connect() as db:
            assert db.execute('SELECT 1 FROM account_credentials WHERE user_id=?',(alice['userId'],)).fetchone() is None
        with server._auth_lock: server._failed_auth.clear()
        for _ in range(server.MAX_AUTH_FAILURES):
            assert request('/account/register',{'username':'invalid name','password':password})[0]==400
        assert request('/account/me',key=bob['token'])[0]==200
        assert request('/account/register',{'username':'blocked.user','password':password})[0]==429
        print('PASS: public registration, automatic login, unique salted scrypt hashes, no cleartext tokens, duplicate/race atomicity, user isolation, legacy hash upgrade and independent registration limits')
    finally:
        http_server.shutdown();http_server.server_close()
