"""Authenticated default AI gateway. Configuration and credentials never leave the server."""
import base64
import binascii
import json
import os
import re
import threading
import time
from http import HTTPStatus
from urllib.parse import urlsplit
import ai_transport


class ServiceError(ValueError):
    def __init__(self, message, status=HTTPStatus.SERVICE_UNAVAILABLE):
        super().__init__(message)
        self.status = status


_lock = threading.RLock()
_active = {}


def setting(name, default, maximum):
    try:
        value = int(os.environ.get('LIFERECORD_DEFAULT_AI_' + name, default))
        if not 1 <= value <= maximum:
            raise ValueError()
        return value
    except ValueError:
        raise ServiceError('默认 AI 服务配置尚未就绪') from None


def configuration():
    if os.environ.get('LIFERECORD_DEFAULT_AI_ENABLED') != '1':
        raise ServiceError('默认 AI 服务暂未开放，请使用自定义接口或稍后重试')
    endpoint = os.environ.get('LIFERECORD_DEFAULT_AI_ENDPOINT', '')
    model = os.environ.get('LIFERECORD_DEFAULT_AI_MODEL', '')
    key = os.environ.get('LIFERECORD_DEFAULT_AI_KEY', '')
    try:
        if not model.strip() or len(model) > 200:
            raise ValueError()
        headers = ai_transport.auth_headers(os.environ.get('LIFERECORD_DEFAULT_AI_AUTH', 'bearer'), os.environ.get('LIFERECORD_DEFAULT_AI_HEADER', ''), key)
        extras = json.loads(os.environ.get('LIFERECORD_DEFAULT_AI_EXTRA', '{}'))
        options = {'maxTokens': setting('MAX_TOKENS', 4096, 8192), 'extraParams': extras, 'jsonMode': False}
        ai_transport.generation_body(options, model, [])
        # Validate URL syntax here; DNS and pinned TLS are checked immediately before sending.
        url = urlsplit(endpoint)
        if url.scheme != 'https' or not url.hostname or url.username or url.password or url.query or url.fragment or url.port not in (None,443):
            raise ValueError()
        return endpoint, model, key, headers, options
    except (ValueError, TypeError):
        raise ServiceError('默认 AI 服务配置尚未就绪') from None


def validate_messages(messages):
    if not isinstance(messages, list) or not 1 <= len(messages) <= 16:
        raise ValueError('AI 对话需包含 1–16 条消息')
    text_size = image_size = image_count = 0
    clean = []
    for item in messages:
        if not isinstance(item, dict) or item.get('role') not in ('system','user','assistant'):
            raise ValueError('AI 消息格式无效')
        content = item.get('content')
        if isinstance(content, str):
            text_size += len(content)
        elif isinstance(content, list) and item['role'] == 'user' and 1 <= len(content) <= 13:
            parts = []
            for part in content:
                if not isinstance(part, dict):
                    raise ValueError('AI 图片格式无效')
                if part.get('type') == 'text' and isinstance(part.get('text'), str):
                    text_size += len(part['text']); parts.append({'type':'text','text':part['text']})
                elif part.get('type') == 'image_url' and isinstance(part.get('image_url'), dict):
                    url = part['image_url'].get('url', '')
                    match = re.fullmatch(r'data:image/(jpeg|png);base64,([A-Za-z0-9+/=]+)', url) if isinstance(url,str) else None
                    if not match:
                        raise ValueError('默认 AI 只接受本次上传的 JPEG/PNG 图片')
                    try:
                        data = base64.b64decode(match[2], validate=True)
                    except binascii.Error:
                        raise ValueError('AI 图片编码无效') from None
                    if not (data.startswith(b'\xff\xd8\xff') if match[1]=='jpeg' else data.startswith(b'\x89PNG\r\n\x1a\n')):
                        raise ValueError('AI 图片格式无效')
                    image_count += 1; image_size += len(data)
                    image = {'url':url}
                    detail = os.environ.get('LIFERECORD_DEFAULT_AI_IMAGE_DETAIL', '')
                    if detail in ('low','medium','high','auto'): image['detail'] = detail
                    parts.append({'type':'image_url','image_url':image})
                else:
                    raise ValueError('AI 消息内容无效')
            content = parts
        else:
            raise ValueError('AI 消息内容无效')
        clean.append({'role':item['role'],'content':content})
    if text_size > 180000 or image_count > 12 or image_size > 5*1024*1024:
        raise ValueError('AI 输入过大，请减少文字或照片')
    if clean[-1]['role'] != 'user':
        raise ValueError('AI 对话最后一条需为用户消息')
    return clean


def reserve(connect, db_lock, user):
    daily = setting('DAILY_LIMIT', 30, 1000)
    global_daily = setting('GLOBAL_DAILY_LIMIT', 300, 10000)
    day = time.strftime('%Y-%m-%d', time.gmtime())
    with _lock:
        if _active.get(user, 0) or sum(_active.values()) >= setting('CONCURRENCY', 4, 16):
            raise ServiceError('默认 AI 正在处理请求，请稍后重试', HTTPStatus.TOO_MANY_REQUESTS)
        with db_lock, connect() as db:
            db.execute('CREATE TABLE IF NOT EXISTS ai_daily_usage(user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE, day TEXT NOT NULL, requests INTEGER NOT NULL, PRIMARY KEY(user_id,day))')
            db.execute('BEGIN IMMEDIATE')
            count = db.execute('SELECT requests FROM ai_daily_usage WHERE user_id=? AND day=?',(user,day)).fetchone()
            total = db.execute('SELECT COALESCE(SUM(requests),0) FROM ai_daily_usage WHERE day=?',(day,)).fetchone()[0]
            if (count[0] if count else 0) >= daily or total >= global_daily:
                raise ServiceError('默认 AI 今日调用额度已用完，可切换自己的接口', HTTPStatus.TOO_MANY_REQUESTS)
            db.execute('INSERT INTO ai_daily_usage VALUES(?,?,1) ON CONFLICT(user_id,day) DO UPDATE SET requests=requests+1',(user,day))
            db.execute('DELETE FROM ai_daily_usage WHERE day < date(?,\'-7 days\')',(day,))
        _active[user] = 1


def complete(connect, db_lock, user, payload, messages):
    endpoint, model, key, headers, options = configuration()
    messages = validate_messages(messages)
    identity = '你是 LifeRecord 默认 AI 助手。服务身份统一为默认 AI 服务，不推测或披露底层供应商、模型标识和私有配置。'
    if messages[0]['role']=='system': messages[0]['content']=identity+'\n'+messages[0]['content']
    else: messages.insert(0,{'role':'system','content':identity})
    requested = payload.get('maxTokens', options['maxTokens'])
    if isinstance(requested, bool) or not isinstance(requested,int) or not 256 <= requested <= 65536:
        raise ValueError('输出 Token 设置无效')
    options['maxTokens'] = min(requested, options['maxTokens'])
    # The caller cannot replace server credentials, model, endpoint, or compatibility options.
    body = ai_transport.generation_body(options, model, messages)
    reserve(connect, db_lock, user)
    try:
        try:
            raw = ai_transport.request_json(endpoint, body, headers)
            text = raw['choices'][0]['message']['content']
            if not isinstance(text,str) or not text.strip(): raise ValueError()
        except (ValueError, KeyError, IndexError, TypeError):
            raise ServiceError('默认 AI 服务暂时不可用，请稍后重试或选择自定义接口', HTTPStatus.BAD_GATEWAY) from None
        # Return only content. Do not forward upstream metadata or diagnostic messages.
        text = text.replace(key, '[私密配置已隐藏]')
        for value in (endpoint, urlsplit(endpoint).hostname, model):
            if value: text = re.sub(re.escape(value), '默认 AI 服务', text, flags=re.IGNORECASE)
        text = re.sub(r'\bdots\b|askdiandian', '默认 AI 服务', text, flags=re.IGNORECASE)
        return text.strip()
    finally:
        with _lock: _active.pop(user, None)
