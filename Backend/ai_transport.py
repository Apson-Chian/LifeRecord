"""HTTPS AI transport: public DNS only, pinned IP, TLS hostname checks, no redirects."""
import http.client
import ipaddress
import json
import re
import socket
import ssl
from urllib.parse import quote, urlsplit


def endpoint_details(endpoint):
    if not isinstance(endpoint, str) or len(endpoint) > 2048 or any(ord(c) < 33 for c in endpoint):
        raise ValueError('API 地址格式无效')
    try:
        url = urlsplit(endpoint)
        port = url.port
    except ValueError:
        raise ValueError('API 地址格式无效') from None
    if url.scheme != 'https' or not url.hostname or url.username or url.password or url.fragment or url.query or port not in (None, 443):
        raise ValueError('请使用不含账号、查询参数的 HTTPS 地址，端口为 443')
    try:
        host = url.hostname.encode('idna').decode('ascii')
    except UnicodeError:
        raise ValueError('API 域名格式无效') from None
    try:
        results = socket.getaddrinfo(host, 443, type=socket.SOCK_STREAM)
    except OSError:
        raise ValueError('无法解析 API 域名') from None
    addresses = list(dict.fromkeys(row[4][0] for row in results))
    if not addresses or any(not ipaddress.ip_address(ip).is_global for ip in addresses):
        raise ValueError('API 地址必须指向公网，不能访问本机或内网')
    return host, quote(url.path or '/', safe='/%:@!$&()*+,;=-._~'), addresses


def auth_headers(mode, name, key):
    if not isinstance(key, str) or not key.strip() or len(key) > 4096 or any(ord(c) < 32 or ord(c) > 126 for c in key):
        raise ValueError('请填写有效的 API Key')
    if mode == 'bearer':
        return {'Authorization': 'Bearer ' + key.strip()}
    name = 'api-key' if mode == 'api-key' else name
    if mode not in ('api-key', 'custom') or not isinstance(name, str) or not re.fullmatch(r'[A-Za-z][A-Za-z0-9-]{0,63}', name):
        raise ValueError('认证头名称无效')
    if name.lower() in ('host', 'content-length', 'content-type', 'connection', 'transfer-encoding', 'cookie', 'expect', 'upgrade') or name.lower().startswith(('proxy-', 'sec-')):
        raise ValueError('此认证头名称不可使用')
    return {name: key.strip()}


def request_json(endpoint, body, headers):
    host, path, addresses = endpoint_details(endpoint)
    context = ssl.create_default_context()

    class PinnedConnection(http.client.HTTPSConnection):
        def connect(self):
            raw = socket.create_connection((addresses[0], 443), self.timeout)
            try:
                self.sock = context.wrap_socket(raw, server_hostname=host)
            except Exception:
                raw.close()
                raise

    connection = PinnedConnection(host, timeout=75, context=context)
    try:
        connection.request('POST', path, json.dumps(body, ensure_ascii=False).encode(), {'Content-Type': 'application/json', **headers})
        response = connection.getresponse()
        if 300 <= response.status < 400:
            raise ValueError('AI 接口发生重定向，请直接填写最终 HTTPS 地址')
        if response.status != 200:
            raise ValueError(f'AI 服务返回 HTTP {response.status}，请检查地址、模型、密钥和额度')
        raw = response.read(1024 * 1024 + 1)
        if len(raw) > 1024 * 1024:
            raise ValueError('AI 返回内容过大')
        return json.loads(raw)
    except (OSError, http.client.HTTPException):
        raise ValueError('AI 服务连接失败或超时，请稍后重试') from None
    finally:
        connection.close()


def generation_body(payload, model, messages):
    token_field = payload.get('tokenField', 'max_tokens')
    limit = payload.get('maxTokens', 6000)
    temperature = payload.get('temperature', .1)
    if token_field not in ('max_tokens', 'max_completion_tokens') or isinstance(limit, bool) or not isinstance(limit, int) or not 256 <= limit <= 65536:
        raise ValueError('输出 Token 设置无效（256–65536）')
    if isinstance(temperature, bool) or not isinstance(temperature, (int, float)) or not 0 <= temperature <= 2:
        raise ValueError('Temperature 必须在 0–2 之间')
    extra = payload.get('extraParams', {})
    protected = {'model', 'messages', 'stream', 'temperature', 'max_tokens', 'max_completion_tokens', 'response_format'}
    if not isinstance(extra, dict) or len(json.dumps(extra)) > 16000 or protected & extra.keys():
        raise ValueError('额外参数必须为 JSON 对象，不能覆盖模型、消息或生成设置')
    if not isinstance(payload.get('sendTemperature', True), bool) or not isinstance(payload.get('jsonMode', False), bool):
        raise ValueError('生成选项无效')
    body = {**extra, 'model': model.strip(), 'messages': messages, token_field: limit, 'stream': False}
    if payload.get('sendTemperature', True):
        body['temperature'] = temperature
    if payload.get('jsonMode', False):
        body['response_format'] = {'type': 'json_object'}
    return body
