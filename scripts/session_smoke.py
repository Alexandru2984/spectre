#!/usr/bin/env python3
"""Session-tool authorization, live state and expiry on an isolated shipment."""
import concurrent.futures
import http.client
import json
import os
import secrets
import time
from urllib.parse import urlsplit

base = urlsplit(os.environ.get('BASE_URL', 'http://127.0.0.1:4400'))
assert base.hostname in ('localhost', '127.0.0.1')
prefix = 'session-' + secrets.token_hex(8)
tokens = {role: secrets.token_hex(24) for role in ['owner', 'creator', 'reader']}
checks = 0

def req(method, path, data=None, headers=None, status=200, role='owner'):
    global checks
    h = {'X-Spectre-Client': tokens[role], 'X-Real-IP': prefix + '-' + role}
    h.update(headers or {})
    if data is not None:
        data = json.dumps(data).encode()
        h['Content-Type'] = 'application/json'
    c = http.client.HTTPConnection(base.hostname, base.port, timeout=24)
    c.request(method, path, data, h)
    r = c.getresponse()
    value = json.loads(r.read())
    c.close()
    assert r.status == status, (method, path, r.status, value)
    checks += 1
    return value

created = req('POST', '/api/rooms', {'name': 'Session fixture', 'private': True}, status=201)
other = req('POST', '/api/rooms', {'name': 'Other session', 'private': True}, status=201)
room = created['room']['id']
access = {'X-Room-Key': created['access_key']}
owner = {**access, 'X-Moderator-Key': created['owner_key']}
foreign = {**access, 'X-Moderator-Key': other['owner_key']}
pin = '/api/spotlight?room=' + room

def send(kind, **extra):
    return req('POST', '/api/messages', {'content': 'A temporary fixture', 'ttl': 300000,
               'room': room, 'kind': kind, **extra}, access, status=201, role='creator')

question = send('question')
poll = send('poll', options=['One', 'Two'])
reply = send('question', parent_id=question['id'])
burn = {**access, 'X-Burn-Key': question['burn_key']}
poll_burn = {**access, 'X-Burn-Key': poll['burn_key']}
resolve = f"/api/messages/{question['id']}/resolve?room={room}"
poll_state = f"/api/messages/{poll['id']}/poll-state?room={room}"
vote = f"/api/messages/{poll['id']}/vote?room={room}"

req('POST', pin, {'message_id': question['id']}, status=403)
req('POST', pin, {'message_id': question['id']}, access, status=403)
req('POST', pin, {'message_id': question['id']}, foreign, status=403)
req('POST', pin, {'message_id': reply['id']}, owner, status=400)
req('POST', pin, {'message_id': 12}, owner, status=400)
revision = req('GET', '/api/room?room=' + room, headers=access)['revision']
with concurrent.futures.ThreadPoolExecutor(max_workers=1) as pool:
    watch = pool.submit(req, 'GET', f'/api/events?room={room}&since={revision}', headers=access, role='reader')
    time.sleep(.15)
    assert req('POST', pin, {'message_id': question['id']}, owner)['spotlight_id'] == question['id']
    assert watch.result(timeout=3)['revision'] != revision
assert req('GET', '/api/snapshot?room=' + room, headers=access)['room']['spotlight_id'] == question['id']
req('POST', resolve, {'resolved': True}, access, status=404, role='reader')
req('POST', resolve, {'resolved': True}, foreign, status=404)
req('POST', resolve, {'resolved': True}, {'X-Burn-Key': question['burn_key']}, status=403)
req('POST', resolve, {'resolved': 'true'}, burn, status=400, role='creator')
resolved = req('POST', resolve, {'resolved': True}, burn, role='creator')
assert resolved['resolved'] and resolved['expires_at'] == question['message']['expires_at']
assert not req('POST', resolve, {'resolved': False}, owner)['resolved']
req('POST', f"/api/messages/{reply['id']}/resolve?room={room}", {'resolved': True}, owner, status=400)
req('POST', poll_state, {'closed': True}, access, status=404, role='reader')
req('POST', poll_state, {'closed': True}, foreign, status=404)
req('POST', poll_state, {'closed': 1}, owner, status=400)
req('POST', f"/api/messages/{question['id']}/poll-state?room={room}", {'closed': True}, burn, status=400, role='creator')
assert req('POST', vote, {'option': 0}, access, role='reader')['poll_counts'] == [1, 0]
closed = req('POST', poll_state, {'closed': True}, poll_burn, role='creator')
assert closed['poll_closed'] and closed['poll_counts'] == [1, 0]
with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
    futures = [pool.submit(req, 'POST', vote, {'option': 1}, access, 409, 'reader') for _ in range(4)]
    for future in futures:
        future.result(timeout=3)
opened = req('POST', poll_state, {'closed': False}, owner)
assert opened['poll_counts'] == [1, 0] and opened['expires_at'] == poll['message']['expires_at']
assert req('POST', vote, {'option': 1}, access, role='reader')['poll_counts'] == [0, 1]
req('DELETE', f"/api/messages/{question['id']}?room={room}", headers=burn, role='creator')
assert req('GET', '/api/room?room=' + room, headers=access)['spotlight_id'] == ''
short = send('thought', ttl=3000)
req('POST', pin, {'message_id': short['id']}, owner)
time.sleep(3.2)
snapshot = req('GET', '/api/snapshot?room=' + room, headers=access)
assert snapshot['room']['spotlight_id'] == '' and all(m['id'] != short['id'] for m in snapshot['messages'])
req('POST', pin, {'message_id': poll['id']}, owner)
req('DELETE', '/api/room?room=' + room, headers=owner)
req('GET', '/api/snapshot?room=' + room, headers=access, status=404)
req('DELETE', '/api/room?room=' + other['room']['id'], headers={'X-Room-Key': other['access_key'], 'X-Moderator-Key': other['owner_key']})
print(f'{checks} live session HTTP checks passed: scoped capabilities, live spotlight, explicit resolution, poll closure/reopen, vote races and expiry.')
