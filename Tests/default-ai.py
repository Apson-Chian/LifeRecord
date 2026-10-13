"""Default service privacy, auth, quotas and server-only configuration. No paid requests."""
from http.client import HTTPConnection
import json
import os
import sys
import tempfile
import threading
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'Backend'))
with tempfile.TemporaryDirectory() as folder:
    os.environ.update(LIFERECORD_DB=folder+'/test.sqlite3',LIFERECORD_IMAGE_DIR=folder+'/images',LIFERECORD_SYNC_TOKEN='fixture-owner-key',
        LIFERECORD_DEFAULT_AI_ENABLED='1',LIFERECORD_DEFAULT_AI_ENDPOINT='https://private-provider.test/v1/chat/completions',
        LIFERECORD_DEFAULT_AI_MODEL='private-model',LIFERECORD_DEFAULT_AI_KEY='fixture-upstream-secret',
        LIFERECORD_DEFAULT_AI_AUTH='api-key',LIFERECORD_DEFAULT_AI_EXTRA='{"chat_template_kwargs":{"enable_thinking":false}}',
        LIFERECORD_DEFAULT_AI_MAX_TOKENS='4096',LIFERECORD_DEFAULT_AI_DAILY_LIMIT='2',LIFERECORD_DEFAULT_AI_GLOBAL_DAILY_LIMIT='5')
    import server, database, default_ai, ai_transport
    server.initialize()
    with server.connect() as db:
        second,second_key=database.create_user(db,'second')
        third,third_key=database.create_user(db,'third')
        fourth,fourth_key=database.create_user(db,'fourth')
    http=server.ThreadingHTTPServer(('127.0.0.1',0),server.Handler)
    threading.Thread(target=http.serve_forever,daemon=True).start()
    def request(payload, key='fixture-owner-key',path='/ai/chat'):
        conn=HTTPConnection('127.0.0.1',http.server_port,timeout=10)
        conn.request('POST','/liferecord-api'+path,json.dumps(payload),{'Authorization':'Bearer '+key,'Content-Type':'application/json'})
        r=conn.getresponse();status=r.status;body=json.loads(r.read());conn.close();return status,body
    payload={'messages':[{'role':'system','content':'respond'},{'role':'user','content':'hello'}], 'maxTokens':12000,
             'endpoint':'https://attacker.test', 'model':'attacker-model', 'apiKey':'attacker-secret', 'extraParams':{'tools':[]}}
    captured=[]
    def upstream(endpoint,body,headers):
        captured.append((endpoint,body,headers))
        return {'model':'private-model','choices':[{'message':{'content':'private-model private-provider.test Dots fixture-upstream-secret'}}]}
    try:
        with patch.object(ai_transport,'request_json',side_effect=upstream):
            assert request(payload,key='wrong-key')[0]==401 and not captured
            status,body=request(payload);assert status==200
            text=body['choices'][0]['message']['content']
            assert not any(s in json.dumps(body) for s in ['private-model','private-provider.test','fixture-upstream-secret','Dots'])
            assert captured[0][0].startswith('https://private-provider.test')
            assert captured[0][1]['model']=='private-model' and captured[0][1]['max_tokens']==4096
            assert captured[0][2]=={'api-key':'fixture-upstream-secret'} and 'tools' not in captured[0][1]
            assert request({'messages':[{'role':'user','content':[{'type':'image_url','image_url':{'url':'http://127.0.0.1/private'}}]}]})[0]==400
            assert request({'messages':[{'role':'user','content':'x'*180001}]})[0]==400
            assert request(payload)[0]==200
            assert request(payload)[0]==429 and len(captured)==2
            assert request(payload,key=second_key)[0]==200 # independent account budget
            default_ai._active[second]=1
            assert request(payload,key=second_key)[0]==429
            default_ai._active.clear()
            with patch.dict(os.environ,{'LIFERECORD_DEFAULT_AI_ENABLED':'0'}): assert request(payload,key=second_key)[0]==503
            with patch.object(ai_transport,'request_json',side_effect=ValueError('private host and key diagnostics')):
                status,body=request(payload,key=second_key);assert status==502 and 'private host' not in json.dumps(body)
            assert request(payload,key=second_key)[0]==429 # failures count, not refundable retry loops
        with server.connect() as db:
            assert db.execute('SELECT requests FROM ai_daily_usage WHERE user_id=?',(second,)).fetchone()[0]==2
        # Budget survives closing connections and cannot be reset by client preferences.
        assert request(payload,key=second_key)[0]==429
        with patch.object(ai_transport,'request_json',return_value={'choices':[{'message':{'content':'{"answer":"OK","actions":[]}'}}]}):
            status,body=request({'provider':'default','instruction':'hello'},key=third_key,path='/ai/plan')
            assert status==200 and body['answer']=='OK'
            assert request(payload,key=fourth_key)[0]==429 # shared daily budget
        # Existing custom routes still work independently of default service budgets.
        with patch.object(ai_transport,'request_json',return_value={'choices':[{'message':{'content':'{"answer":"OK","actions":[]}'}}]}):
            status,body=request({'provider':'custom','endpoint':'https://custom.test/v1/chat/completions','model':'custom-model','apiKey':'fixture-key','instruction':'hello'},path='/ai/plan')
            assert status==200 and body['answer']=='OK'
    finally:
        http.shutdown();http.server_close()
print('PASS: default gateway auth, private configuration, override rejection, token caps, input/image validation, persistent per-user budget, concurrency, neutral errors and custom fallback')
