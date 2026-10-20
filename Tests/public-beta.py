"""Migration, user isolation, HTTP sessions and CSRF. Uses disposable data only."""
import os,sys,tempfile,sqlite3,json,threading,time,http.client,base64
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'Backend'))
with tempfile.TemporaryDirectory() as folder:
    os.environ.update(LIFERECORD_DB=folder+'/data.sqlite3',LIFERECORD_IMAGE_DIR=folder+'/images',LIFERECORD_SYNC_TOKEN='owner-test-only')
    db=sqlite3.connect(os.environ['LIFERECORD_DB'])
    db.execute('CREATE TABLE records(record_type TEXT,record_id TEXT,payload TEXT,updated_at REAL,deleted INTEGER)')
    meal=dict(id='same-id',name='private original',date=1000,kind='午餐',source='手动',updatedAt=1000,calories=600,protein=30,carbs=70,fat=20)
    db.execute('INSERT INTO records VALUES(?,?,?,?,?)',('meal','same-id',json.dumps(meal),1000,0));db.commit();db.close()
    import server,database
    server.initialize();server.initialize()
    with server.connect() as db:
        a,keya=database.create_user(db,'A');b,keyb=database.create_user(db,'B')
        assert not db.execute("SELECT 1 FROM sqlite_master WHERE name='records'").fetchone()
        assert not db.execute("SELECT 1 FROM pragma_table_info('user_records') WHERE name='payload'").fetchone()
    http=server.ThreadingHTTPServer(('127.0.0.1',0),server.Handler)
    thread=threading.Thread(target=http.serve_forever,daemon=True);thread.start()
    def request(path,body=None,key=None,cookie=None,origin=None,content_type='application/json'):
        conn=httpclient.HTTPConnection('127.0.0.1',http.server_port,timeout=10)
        headers={'Content-Type':content_type}
        if key:headers['Authorization']='Bearer '+key
        if cookie:headers['Cookie']=cookie
        if origin:headers['Origin']=origin
        conn.request('POST' if body is not None else 'GET','/liferecord-api'+path,json.dumps(body) if body is not None else None,headers)
        response=conn.getresponse();raw=response.read(); result=json.loads(raw) if raw else None
        output=response.status,result,response.getheader('Set-Cookie');conn.close();return output
    import http.client as httpclient
    assert request('/snapshot',key=keya)[1]['meals']==[]
    assert request('/snapshot',key='owner-test-only')[1]['meals'][0]['name']=='private original'
    assert request('/sync',{'meals':[{**meal,'name':'A record'}]},key=keya)[0]==200
    assert request('/sync',{'meals':[{**meal,'name':'B record'}]},key=keyb)[0]==200
    assert request('/snapshot',key=keya)[1]['meals'][0]['name']=='A record'
    assert request('/snapshot',key=keyb)[1]['meals'][0]['name']=='B record'
    assert request('/diagnostics')[0]==401
    diagnostics=request('/diagnostics',key=keya)
    assert diagnostics[0]==200 and diagnostics[1]['issues']
    assert diagnostics[1]['snapshot']['meals'][0]['name']=='A record'
    assert 'B record' not in json.dumps(diagnostics[1])
    image=request('/images',{'mealId':'same-id','base64':base64.b64encode(b'\xff\xd8\xfftest').decode()},key=keya)[1]['id']
    assert request('/images/'+image,key=keyb)[0]==404
    assert request('/sync',{'meals':[{**meal,'photoIDs':[image],'updatedAt':2000}]},key=keyb)[0]==400
    status,_,cookie=request('/auth',{'token':keya});cookie=cookie.split(';')[0]
    assert status==204 and request('/snapshot',cookie=cookie)[0]==200
    assert request('/sync',{},cookie=cookie,origin='https://evil.example')[0]==403
    assert request('/sync',{},cookie=cookie,content_type='text/plain')[0]==415
    request('/logout',{},cookie=cookie)
    assert request('/snapshot',cookie=cookie)[0]==401
    status,_,cookie=request('/auth',{'token':keyb});cookie=cookie.split(';')[0]
    with server.connect() as db: db.execute('UPDATE sessions SET expires_at=0 WHERE user_id=?',(b,))
    assert request('/snapshot',cookie=cookie)[0]==401
    assert request('/account/delete',{'confirmation':'DELETE MY ACCOUNT'},key=keya)[0]==200
    assert request('/snapshot',key=keya)[0]==401
    assert request('/snapshot',key=keyb)[1]['meals'][0]['name']=='B record'
    assert list(Path(folder+'/images').iterdir())==[]
    http.shutdown();http.server_close()
    print('PASS: private migration, typed SQL, independent records/photos, expired/revoked sessions, CSRF, account deletion')
