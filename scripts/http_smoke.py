#!/usr/bin/env python3
"""Bounded regression checks. Run against an isolated localhost instance only."""
import http.client
import json
import os
import secrets
import time
from urllib.parse import urlsplit

base = urlsplit(os.environ.get('BASE_URL', 'http://127.0.0.1:4400'))
assert base.hostname in ('127.0.0.1', 'localhost'), 'Use an isolated localhost server.'
room = 'test-' + secrets.token_hex(6)
client = secrets.token_hex(24)
checks = 0


def request(method, path='/', body=None, headers=None, expect=200):
    global checks
    conn = http.client.HTTPConnection(base.hostname, base.port or 80, timeout=10)
    request_headers = {'X-Real-IP': 'test-' + room}
    if isinstance(body, dict):
        body = json.dumps(body, ensure_ascii=False).encode()
        request_headers['Content-Type'] = 'application/json'
    request_headers.update(headers or {})
    conn.request(method, path, body=body, headers=request_headers)
    res = conn.getresponse()
    raw = res.read()
    status = res.status
    response_headers = dict(res.getheaders())
    conn.close()
    assert status == expect, (method, path, status, raw[:200])
    assert response_headers.get('x-content-type-options') == 'nosniff'
    checks += 1
    return raw, response_headers


request('HEAD')
request('GET', '/healthz')
text = 'Salutări 👻 "quotes" \\ slash\n<script>alert(1)</script>'
raw, _ = request('POST', '/api/messages', {'content': text, 'ttl': 3000, 'room': room, 'kind': 'idea'}, expect=201)
created = json.loads(raw)
key, message_id = created['burn_key'], created['id']
assert len(key) == 48 and key != message_id
raw, headers = request('GET', '/api/messages?room=' + room)
messages = json.loads(raw)
assert len(messages) == 1 and messages[0]['content'] == text
assert key.encode() not in raw and b'burn_key' not in raw
assert headers['cache-control'] == 'no-store' and 'noindex' in headers['x-robots-tag']
assert int(headers['x-server-time']) > 0
assert json.loads(request('GET', '/api/messages?room=other-' + room)[0]) == []
reaction_path = '/api/messages/' + message_id + '/reactions?room='
reaction_headers = {'X-Spectre-Client': client}
request('POST', reaction_path + 'other-' + room, {'emoji': 'spark'}, reaction_headers, expect=404)
raw, _ = request('POST', reaction_path + room, {'emoji': 'spark'}, reaction_headers)
assert json.loads(raw)['reactions']['spark'] == 1
raw, _ = request('POST', reaction_path + room, {'emoji': 'spark'}, reaction_headers)
assert json.loads(raw)['reactions']['spark'] == 0
burn_path = '/api/messages/' + message_id + '?room='
request('DELETE', burn_path + room, headers={'X-Burn-Key': '0' * 48}, expect=404)
request('DELETE', burn_path + 'other-' + room, headers={'X-Burn-Key': key}, expect=404)
request('DELETE', burn_path + room, headers={'X-Burn-Key': key})
assert json.loads(request('GET', '/api/messages?room=' + room)[0]) == []
request('POST', '/api/messages', {'content': 'expires without listing', 'ttl': 3000, 'room': room}, expect=201)
time.sleep(3.2)
assert json.loads(request('GET', '/api/messages?room=' + room)[0]) == []
request('POST', '/api/messages', {}, {'Origin': 'https://evil.example'}, expect=403)
request('POST', '/api/messages', {}, {'Sec-Fetch-Site': 'cross-site'}, expect=403)
request('POST', '/api/messages', '{} trailing', {'Content-Type': 'application/json'}, expect=400)
request('POST', '/api/messages', b'\xff\xfe', {'Content-Type': 'application/json'}, expect=400)
request('POST', '/api/messages', '{}', {'Content-Type': 'text/plain'}, expect=415)
request('POST', '/api/messages', 'x' * 8200, {'Content-Type': 'application/json'}, expect=413)
request('POST', '/api/messages', {'content': '   ', 'ttl': 3000}, expect=400)
request('POST', '/api/messages', {'content': 'a' * 501, 'ttl': 3000}, expect=400)
request('POST', '/api/messages', {'content': 'hello', 'ttl': -1}, expect=400)
request('POST', '/api/messages', {'content': 'hello', 'ttl': 300001}, expect=400)
request('GET', '/api/messages?room=../invalid', expect=400)
request('PUT', '/api/messages', expect=405)
request('GET', '/does-not-exist', expect=404)
# Use a distinct trusted-proxy test identity to exhaust only its write budget.
limit_identity = {'X-Real-IP': 'limit-' + room}
for _ in range(30):
    request('POST', '/api/messages', {}, limit_identity, expect=400)
raw, headers = request('POST', '/api/messages', {}, limit_identity, expect=429)
assert 1 <= int(headers['retry-after']) <= 60
request('GET', '/api/messages?room=' + room, headers=limit_identity)
print(f'{checks} HTTP security/product checks passed ({room}).')
