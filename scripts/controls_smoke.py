#!/usr/bin/env python3
"""Owner policy, authorization, live revision and cooldown HTTP regressions."""
import concurrent.futures
import http.client
import json
import os
import secrets
import time
from urllib.parse import urlsplit

base = urlsplit(os.environ.get('BASE_URL', 'http://127.0.0.1:4400'))
assert base.hostname in ('localhost', '127.0.0.1')
token, address = secrets.token_hex(24), 'controls-' + secrets.token_hex(8)
checks = 0

def req(method, path, data=None, headers=None, status=200):
    global checks
    h = {'X-Spectre-Client': token, 'X-Real-IP': address}
    h.update(headers or {})
    if data is not None:
        data = json.dumps(data).encode()
        h['Content-Type'] = 'application/json'
    c = http.client.HTTPConnection(base.hostname, base.port, timeout=24)
    c.request(method, path, data, h)
    r = c.getresponse()
    payload = json.loads(r.read())
    assert r.status == status, (method, path, r.status, payload)
    checks += 1
    result = payload, dict(r.getheaders())
    c.close()
    return result

created, _ = req('POST', '/api/rooms', {'name': 'Owner policy', 'private': True}, status=201)
room = created['room']['id']
access = {'X-Room-Key': created['access_key']}
owner = {**access, 'X-Moderator-Key': created['owner_key']}
path = '/api/room?room=' + room
settings = {'name': 'Live questions', 'topic': '<script>literal topic</script>',
            'posting_mode': 'questions', 'slow_mode_seconds': 5}
req('POST', path, settings, status=403)
req('POST', path, settings, access, status=403)
other, _ = req('POST', '/api/rooms', {'name': 'Unrelated owner'}, status=201)
req('POST', path, settings, {**access, 'X-Moderator-Key': other['owner_key']}, status=403)
req('POST', '/api/room?room=lobby', settings, owner, status=403)
revision = created['room']['revision']
with concurrent.futures.ThreadPoolExecutor(max_workers=1) as pool:
    watch = pool.submit(req, 'GET', f'/api/events?room={room}&since={revision}', headers=access)
    time.sleep(.15)
    updated, _ = req('POST', path, settings, owner)
    assert watch.result(timeout=3)[0]['revision'] != revision
assert updated['topic'] == settings['topic'] and updated['private'] is True
req('POST', path, {**settings, 'slow_mode_seconds': -1}, owner, status=400)
req('POST', path, {**settings, 'posting_mode': 'invalid'}, owner, status=400)
message = {'content': 'A question?', 'kind': 'question', 'ttl': 30000, 'room': room}
req('POST', '/api/messages', {**message, 'kind': 'thought'}, access, status=403)
req('POST', '/api/messages', message, access, status=201)
limited, headers = req('POST', '/api/messages', message, access, status=429)
assert 1 <= int(headers['retry-after']) <= 5
assert int(headers['retry-after']) == limited['retry_after']
time.sleep(int(headers['retry-after']) + .1)
req('POST', '/api/messages', message, access, status=201)
req('POST', path, {**settings, 'posting_mode': 'paused'}, owner)
req('POST', '/api/messages', message, access, status=403)
req('POST', '/api/messages', {**message, 'kind': 'thought'}, owner, status=201)
req('POST', path, {**settings, 'posting_mode': 'open', 'slow_mode_seconds': 0}, owner)
req('POST', '/api/messages', {**message, 'kind': 'thought'}, access, status=201)
req('DELETE', path, headers=owner)
req('POST', path, settings, owner, status=404)
req('DELETE', '/api/room?room=' + other['room']['id'], headers={'X-Moderator-Key': other['owner_key']})
print(f'{checks} owner policy HTTP checks passed, including real cooldown expiry and live policy notifications.')
