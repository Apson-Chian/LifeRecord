"""Password setup/login, session rotation and user isolation; disposable HTTP/SQLite only."""
import http.client
import json
import os
from pathlib import Path
import sys
import tempfile
import threading
import runpy
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'Backend'))

with tempfile.TemporaryDirectory() as folder:
    os.environ.update(LIFERECORD_DB=folder+'/accounts.sqlite', LIFERECORD_IMAGE_DIR=folder+'/images', LIFERECORD_SYNC_TOKEN='')
    import server
    import database
    server.initialize()
    server.initialize()
    with server.connect() as db:
        alice, alice_key = database.create_user(db, 'Alice invitation')
        bob, bob_key = database.create_user(db, 'Bob invitation')
        database.put_record(db, alice, 'meal', 'private', {'name': 'private meal'}, 1000)
    http_server = server.ThreadingHTTPServer(('127.0.0.1', 0), server.Handler)
    threading.Thread(target=http_server.serve_forever, daemon=True).start()

    def request(path, body=None, key=None, cookie=None, origin=None):
        conn = http.client.HTTPConnection('127.0.0.1', http_server.server_port, timeout=10)
        headers = {'Content-Type': 'application/json'}
        if key: headers['Authorization'] = 'Bearer ' + key
        if cookie: headers['Cookie'] = cookie
        if origin: headers['Origin'] = origin
        conn.request('GET' if body is None else 'POST', '/liferecord-api'+path, json.dumps(body) if body is not None else None, headers)
        response = conn.getresponse()
        raw = response.read()
        result = (response.status, json.loads(raw) if raw else {}, response.getheader('Set-Cookie'))
        conn.close()
        return result

    password = 'Correct horse 42!'
    setup = {'username': '  Alice.One ', 'password': password}
    try:
        assert request('/account/credentials', setup)[0] == 401
        assert request('/account/credentials', {**setup, 'password': 'short'}, key=alice_key)[0] == 400
        assert request('/account/credentials', {**setup, 'username': 'bad name'}, key=alice_key)[0] == 400
        status, result, cookie = request('/account/credentials', setup, key=alice_key)
        assert status == 200 and result['username'] == 'alice.one' and result['userId'] == alice
        first_session = result['token']
        assert request('/account/me', key=first_session)[1]['userId'] == alice
        assert request('/account/credentials', setup, key=bob_key)[0] == 400
        assert request('/account/login', {'username': 'alice.one', 'password': 'incorrect password'})[0] == 401
        unknown = request('/account/login', {'username': 'unknown', 'password': password})
        assert unknown[:2] == request('/account/login', {'username': 'alice.one', 'password': 'incorrect password'})[:2]
        status, login, cookie = request('/account/login', {'username': 'ALICE.ONE', 'password': password})
        assert status == 200 and login['userId'] == alice
        assert all(flag in cookie for flag in ['HttpOnly', 'Secure', 'SameSite=Strict'])
        session = login['token']
        assert request('/snapshot', key=session)[1]['meals'][0]['name'] == 'private meal'
        assert request('/snapshot', key=bob_key)[1]['meals'] == []
        assert request('/account/me', cookie=cookie.split(';')[0])[1]['userId'] == alice
        assert request('/account/credentials', {**setup, 'currentPassword': 'wrong current password'}, key=session)[0] == 400
        assert request('/account/credentials', setup, key=session, origin='https://evil.example')[0] == 403
        changed = {**setup, 'password': 'New correct password 43!', 'currentPassword': password}
        status, rotated, _ = request('/account/credentials', changed, key=session)
        assert status == 200 and rotated['userId'] == alice
        assert request('/account/me', key=session)[0] == 401
        assert request('/account/me', key=first_session)[0] == 401
        assert request('/account/me', key=rotated['token'])[0] == 200
        assert request('/account/me', key=alice_key)[0] == 200  # existing clients keep working
        assert request('/account/login', {'username': 'alice.one', 'password': password})[0] == 401
        status, login, _ = request('/account/login', {'username': 'alice.one', 'password': changed['password']})
        assert status == 200
        assert request('/logout', {}, key=login['token'])[0] == 204
        assert request('/account/me', key=login['token'])[0] == 401
        with server.connect() as db:
            saved = db.execute('SELECT * FROM account_credentials WHERE user_id=?', (alice,)).fetchone()
            assert password not in saved['password_hash'] and changed['password'] not in saved['password_hash']
            assert saved['password_hash'].startswith('scrypt$')
            db.execute('UPDATE sessions SET expires_at=0')
        assert request('/account/me', key=rotated['token'])[0] == 401
        assert request('/account/delete', {'confirmation': 'DELETE MY ACCOUNT'}, key=alice_key)[0] == 200
        assert request('/account/login', {'username': 'alice.one', 'password': changed['password']})[0] == 401
        # Administrative recovery uses hidden interactive input, never command-line passwords.
        recovery_password = 'recovery fixture password 84!'
        with patch.object(sys, 'argv', ['manage_users.py', 'set-password', bob, 'bob.user']), patch('getpass.getpass', side_effect=[recovery_password, recovery_password]):
            runpy.run_path(str(Path(__file__).resolve().parents[1]/'Backend/manage_users.py'), run_name='__main__')
        status, recovered, _ = request('/account/login', {'username': 'bob.user', 'password': recovery_password})
        assert status == 200 and recovered['userId'] == bob
        assert request('/account/me', key=bob_key)[0] == 200
        with server._auth_lock: server._failed_auth.clear()
        for _ in range(server.MAX_AUTH_FAILURES):
            assert request('/account/login', {'username': 'unknown', 'password': password})[0] == 401
        assert request('/account/login', {'username': 'unknown', 'password': password})[0] == 429
        # Valid bearer authentication cannot reset the password-attempt budget.
        assert request('/account/me', key=bob_key)[0] == 200
        assert request('/account/login', {'username': 'unknown', 'password': password})[0] == 429
        print('PASS: invited setup, normalization, password hashing/change, bearer/cookie sessions, expiry/logout, isolation, CSRF and rate limits')
    finally:
        http_server.shutdown()
        http_server.server_close()
