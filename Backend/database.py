"""SQLite storage: per-user records and typed fields; JSON is only the wire format."""
import hashlib
import json
import secrets
import time
import hmac
import re

LEGACY_USER = 'legacy-owner'

def token_hash(token):
    return hashlib.sha256(token.encode('utf-8')).hexdigest()

def initialize(db, legacy_token):
    db.executescript('''
    CREATE TABLE IF NOT EXISTS users(id TEXT PRIMARY KEY, label TEXT NOT NULL, token_hash TEXT UNIQUE NOT NULL, created_at REAL NOT NULL, disabled INTEGER NOT NULL DEFAULT 0);
    CREATE TABLE IF NOT EXISTS sessions(token_hash TEXT PRIMARY KEY, user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE, expires_at REAL NOT NULL);
    CREATE TABLE IF NOT EXISTS account_credentials(user_id TEXT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE, username TEXT UNIQUE NOT NULL, password_hash TEXT NOT NULL);
    CREATE TABLE IF NOT EXISTS user_records(user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE, record_type TEXT NOT NULL, record_id TEXT NOT NULL, updated_at REAL NOT NULL, deleted INTEGER NOT NULL CHECK(deleted IN(0,1)), PRIMARY KEY(user_id,record_type,record_id));
    CREATE INDEX IF NOT EXISTS user_records_updated ON user_records(user_id,record_type,updated_at);
    CREATE TABLE IF NOT EXISTS record_fields(user_id TEXT NOT NULL, record_type TEXT NOT NULL, record_id TEXT NOT NULL, node INTEGER NOT NULL, parent INTEGER, name TEXT NOT NULL, kind TEXT NOT NULL CHECK(kind IN('object','array','null','bool','int','real','text')), text_value TEXT, number_value REAL, PRIMARY KEY(user_id,record_type,record_id,node), FOREIGN KEY(user_id,record_type,record_id) REFERENCES user_records(user_id,record_type,record_id) ON DELETE CASCADE);
    CREATE TABLE IF NOT EXISTS user_images(user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE, image_id TEXT NOT NULL, meal_id TEXT NOT NULL, filename TEXT UNIQUE NOT NULL, content_type TEXT NOT NULL, created_at REAL NOT NULL, PRIMARY KEY(user_id,image_id));
    CREATE INDEX IF NOT EXISTS user_images_meal ON user_images(user_id,meal_id);
    ''')
    db.execute("BEGIN IMMEDIATE")
    if legacy_token:
        db.execute('INSERT OR IGNORE INTO users VALUES(?,?,?,?,0)', (LEGACY_USER,'原有私人档案',token_hash(legacy_token),time.time()))
        db.execute('UPDATE users SET token_hash=? WHERE id=?', (token_hash(legacy_token), LEGACY_USER))
    # Transactional one-time conversion. No new user ever inherits this data.
    if db.execute("SELECT 1 FROM sqlite_master WHERE type='table' AND name='records'").fetchone():
        if not legacy_token:
            raise ValueError('Migrating a private database requires LIFERECORD_SYNC_TOKEN')
        for row in db.execute('SELECT * FROM records').fetchall():
            put_record(db,LEGACY_USER,row['record_type'],row['record_id'],json.loads(row['payload']),row['updated_at'],row['deleted'])
        if db.execute("SELECT 1 FROM sqlite_master WHERE type='table' AND name='meal_images'").fetchone():
            db.execute('INSERT OR IGNORE INTO user_images SELECT ?,image_id,meal_id,filename,content_type,created_at FROM meal_images',(LEGACY_USER,))
            db.execute('DROP TABLE meal_images')
        db.execute('DROP TABLE records')
    db.execute('PRAGMA user_version=2')

def put_record(db,user,kind,identifier,payload,stamp,deleted=0):
    row=db.execute('SELECT updated_at FROM user_records WHERE user_id=? AND record_type=? AND record_id=?',(user,kind,identifier)).fetchone()
    if row and row['updated_at'] > stamp: return False
    db.execute('INSERT INTO user_records VALUES(?,?,?,?,?) ON CONFLICT(user_id,record_type,record_id) DO UPDATE SET updated_at=excluded.updated_at,deleted=excluded.deleted',(user,kind,identifier,stamp,deleted))
    db.execute('DELETE FROM record_fields WHERE user_id=? AND record_type=? AND record_id=?',(user,kind,identifier))
    if deleted: return True
    rows=[]
    def flatten(value,parent,name,depth=0):
        if depth>12 or len(rows)>20000: raise ValueError('record is too complex')
        node=len(rows); tag='null'; text=None; number=None
        if isinstance(value,dict): tag='object'
        elif isinstance(value,list): tag='array'
        elif isinstance(value,bool): tag='bool'; number=int(value)
        elif isinstance(value,int): tag='int'; text=str(value)
        elif isinstance(value,float): tag='real'; number=value
        elif isinstance(value,str): tag='text'; text=value
        elif value is not None: raise ValueError('unsupported record value')
        rows.append((user,kind,identifier,node,parent,name,tag,text,number))
        if tag=='object':
            for key,child in value.items(): flatten(child,node,key,depth+1)
        elif tag=='array':
            for index,child in enumerate(value): flatten(child,node,str(index),depth+1)
    flatten(payload,None,'')
    db.executemany('INSERT INTO record_fields VALUES(?,?,?,?,?,?,?,?,?)',rows)
    return True

def read_record(db,user,kind,identifier):
    rows=db.execute('SELECT * FROM record_fields WHERE user_id=? AND record_type=? AND record_id=? ORDER BY node',(user,kind,identifier)).fetchall()
    values={}
    for row in rows:
        tag=row['kind']
        value= {} if tag=='object' else [] if tag=='array' else None if tag=='null' else bool(row['number_value']) if tag=='bool' else int(row['text_value']) if tag=='int' else row['number_value'] if tag=='real' else row['text_value']
        values[row['node']]=value
        if row['parent'] is not None:
            parent=values[row['parent']]
            if isinstance(parent,list): parent.append(value)
            else: parent[row['name']]=value
    return values.get(0,{})

def create_user(db,label):
    import uuid
    token=secrets.token_urlsafe(32); identifier=str(uuid.uuid4())
    db.execute('INSERT INTO users VALUES(?,?,?,?,0)',(identifier,label,token_hash(token),time.time()))
    return identifier,token

def user_for_token(db,token):
    if not isinstance(token,str) or not token or len(token)>512: return None
    row=db.execute('SELECT id FROM users WHERE token_hash=? AND disabled=0',(token_hash(token),)).fetchone()
    if row: return row['id']
    row=db.execute('SELECT s.user_id FROM sessions s JOIN users u ON u.id=s.user_id WHERE s.token_hash=? AND s.expires_at>? AND u.disabled=0',(token_hash(token),time.time())).fetchone()
    return row['user_id'] if row else None


def normalize_username(value):
    if not isinstance(value,str): raise ValueError('账号需要 3–32 位字母、数字、下划线或点')
    value=value.strip().lower()
    if not re.fullmatch(r'[a-z0-9][a-z0-9_.]{2,31}',value):
        raise ValueError('账号需要 3–32 位字母、数字、下划线或点，并以字母或数字开头')
    return value


SCRYPT_N = 131072


def password_digest(password, salt=None):
    if not isinstance(password,str) or not 10 <= len(password) <= 128 or not password.strip():
        raise ValueError('密码需要 10–128 个字符')
    salt=salt or secrets.token_hex(16)
    digest=hashlib.scrypt(password.encode('utf-8'),salt=bytes.fromhex(salt),n=SCRYPT_N,r=8,p=1,maxmem=256*1024*1024).hex()
    return f'scrypt${SCRYPT_N}$8$1${salt}${digest}'


def password_matches(password, encoded):
    try:
        if not isinstance(password,str) or not 10 <= len(password) <= 128 or not password.strip(): return False
        parts=encoded.split('$')
        if len(parts)==3:
            algorithm,salt,expected=parts
            n,r,p=16384,8,1  # Read the first password implementation without locking users out.
        else:
            algorithm,n,r,p,salt,expected=parts
            n,r,p=int(n),int(r),int(p)
        if algorithm!='scrypt' or (n,r,p) not in ((16384,8,1),(SCRYPT_N,8,1)): return False
        digest=hashlib.scrypt(password.encode('utf-8'),salt=bytes.fromhex(salt),n=n,r=r,p=p,maxmem=256*1024*1024).hex()
        return hmac.compare_digest(digest,expected)
    except (ValueError,TypeError,AttributeError): return False


# Pay the same password-hashing cost for unknown accounts to avoid a timing oracle.
_DUMMY_PASSWORD = password_digest('unused-dummy-password')


def account_info(db,user):
    row=db.execute('SELECT username FROM account_credentials WHERE user_id=?',(user,)).fetchone()
    return {'userId':user,'username':row['username'] if row else ''}


def authenticate_password(db,username,password):
    try: username=normalize_username(username)
    except ValueError: username=''
    row=db.execute('SELECT c.* FROM account_credentials c JOIN users u ON u.id=c.user_id WHERE c.username=? AND u.disabled=0',(username,)).fetchone()
    matched=password_matches(password,row['password_hash'] if row else _DUMMY_PASSWORD)
    if row and matched and not row['password_hash'].startswith(f'scrypt${SCRYPT_N}$8$1$'):
        db.execute('UPDATE account_credentials SET password_hash=? WHERE user_id=?',(password_digest(password),row['user_id']))
    return row['user_id'] if row and matched else None


def register_account(db,username,password):
    """Caller commits user and credentials in one transaction; no invitation is required."""
    username=normalize_username(username)
    encoded=password_digest(password)
    if db.execute('SELECT 1 FROM account_credentials WHERE username=?',(username,)).fetchone():
        raise ValueError('该账号不可用，请换一个账号')
    user,_=create_user(db,username)
    db.execute('INSERT INTO account_credentials VALUES(?,?,?)',(user,username,encoded))
    return account_info(db,user)


def set_credentials(db,user,username,password,current_password=None):
    username=normalize_username(username)
    encoded=password_digest(password)
    current=db.execute('SELECT password_hash FROM account_credentials WHERE user_id=?',(user,)).fetchone()
    if current and not password_matches(current_password,current['password_hash']):
        raise ValueError('当前密码不正确')
    if db.execute('SELECT 1 FROM account_credentials WHERE username=? AND user_id<>?',(username,user)).fetchone():
        raise ValueError('该账号不可用，请换一个账号')
    db.execute('INSERT INTO account_credentials VALUES(?,?,?) ON CONFLICT(user_id) DO UPDATE SET username=excluded.username,password_hash=excluded.password_hash',(user,username,encoded))
    # Password changes invalidate every previous browser/device login.
    db.execute('DELETE FROM sessions WHERE user_id=?',(user,))
    return account_info(db,user)
