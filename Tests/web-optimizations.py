"""Conditional reads and safe custom AI transport, with disposable data and no paid API calls."""
import json, os, sys, tempfile, threading, http.client
from pathlib import Path
from unittest.mock import patch
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'Backend'))
import ai_transport

def dns(address):
    return [(2,1,6,'',(address,443))]
for address in ['127.0.0.1','10.0.0.1','169.254.169.254','192.168.1.1','::1','fe80::1','100.64.0.1','::ffff:127.0.0.1']:
    with patch.object(ai_transport.socket,'getaddrinfo',return_value=dns(address)):
        try: ai_transport.endpoint_details('https://api.example.com/v1/chat/completions');raise AssertionError('private address accepted: '+address)
        except ValueError: pass
for url in ['http://api.example.com/v1','https://user:pass@api.example.com/v1','https://api.example.com:8443/v1','https://api.example.com/v1?secret=x','https://api.example.com/v1#x','https://api.example.com/\n']:
    try: ai_transport.endpoint_details(url);raise AssertionError('unsafe URL accepted')
    except ValueError: pass
with patch.object(ai_transport.socket,'getaddrinfo',return_value=dns('1.1.1.1')+dns('127.0.0.1')):
    try: ai_transport.endpoint_details('https://api.example.com/v1');raise AssertionError('mixed DNS accepted')
    except ValueError: pass
for name in ['Host','Content-Length','Cookie','Proxy-Authorization','Bad\r\nHeader','Content-Type']:
    try: ai_transport.auth_headers('custom',name,'fixture-key');raise AssertionError('unsafe auth header accepted')
    except ValueError: pass
assert ai_transport.auth_headers('custom','X-API-Key','fixture-key')=={'X-API-Key':'fixture-key'}
try: ai_transport.auth_headers('bearer','','key\r\nHost: internal');raise AssertionError('injection accepted')
except ValueError: pass
body=ai_transport.generation_body(dict(maxTokens=12000,tokenField='max_completion_tokens',sendTemperature=False,jsonMode=True,extraParams={'top_p':.9}),'model',[{'role':'user','content':'hi'}])
assert body['max_completion_tokens']==12000 and 'temperature' not in body and body['response_format']=={'type':'json_object'}
for payload in [{'maxTokens':True},{'maxTokens':1},{'temperature':float('nan')},{'extraParams':{'messages':[]}},{'extraParams':[]}]:
    try: ai_transport.generation_body(payload,'model',[]);raise AssertionError('bad params accepted')
    except ValueError: pass

class Connection:
    def __init__(self,host,timeout,context):self.timeout=timeout
    def request(self,*args):self.connect()
    def getresponse(self):return response
    def close(self):pass
class Response:
    status=200
    def read(self,*args):return b'{"ok":true}'
response=Response()
with patch.object(ai_transport.socket,'getaddrinfo',return_value=dns('1.1.1.1')),patch.object(ai_transport.socket,'create_connection') as connect,patch.object(ai_transport.ssl,'create_default_context') as tls,patch.object(ai_transport.http.client,'HTTPSConnection',Connection):
    assert ai_transport.request_json('https://api.example.com/v1',{}, {})=={'ok':True}
    assert connect.call_args.args[0]==('1.1.1.1',443)
    assert tls.return_value.wrap_socket.call_args.kwargs['server_hostname']=='api.example.com'
    response.status=302
    try: ai_transport.request_json('https://api.example.com/v1',{},{});raise AssertionError('redirect accepted')
    except ValueError as error: assert '重定向' in str(error)

with tempfile.TemporaryDirectory() as folder:
    os.environ.update(LIFERECORD_DB=folder+'/db.sqlite3',LIFERECORD_IMAGE_DIR=folder+'/images',LIFERECORD_SYNC_TOKEN='fixture-owner-key')
    import server,database
    server.initialize()
    with server.connect() as db: other,other_key=database.create_user(db,'other')
    http=server.ThreadingHTTPServer(('127.0.0.1',0),server.Handler)
    threading.Thread(target=http.serve_forever,daemon=True).start()
    def request(path='/snapshot',method='GET',body=None,etag=None,key='fixture-owner-key'):
        conn=httpclient.HTTPConnection('127.0.0.1',http.server_port,timeout=10)
        headers={'Authorization':'Bearer '+key,'Content-Type':'application/json'}
        if etag:headers['If-None-Match']=etag
        conn.request(method,'/liferecord-api'+path,json.dumps(body) if body is not None else None,headers)
        response=conn.getresponse();result=response.status,response.read(),response.getheader('ETag');conn.close();return result
    import http.client as httpclient
    status,raw,etag=request();assert status==200 and etag
    assert request(etag=etag)[:2]==(304,b'')
    assert request(etag=etag,key='invalid-key')[0]==401
    assert request('/admin','POST',{'actions':[{'operation':'add','recordType':'body','fields':{'date':1000,'weight':70}}]})[0]==200
    assert request(etag=etag)[0]==200
    assert json.loads(request(key=other_key)[1])['bodyMetrics']==[]
    original_dns=ai_transport.socket.getaddrinfo
    with patch.object(ai_transport.socket,'getaddrinfo',side_effect=lambda host,*args,**kwargs: dns('127.0.0.1') if host=='localhost' else original_dns(host,*args,**kwargs)):
        assert request('/ai/config/check','POST',dict(provider='custom',endpoint='https://localhost/v1',model='model',apiKey='fixture-key'))[0]==400
    http.shutdown();http.server_close()
print('PASS: public HTTPS only, private/mixed DNS rejected, credentials pinned to TLS hostname, redirect/header injection rejected, generation params validated, authenticated ETag refresh and user isolation')
