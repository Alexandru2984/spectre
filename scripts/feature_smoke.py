#!/usr/bin/env python3
"""Feature and authorization checks against an isolated localhost release."""
import concurrent.futures
import http.client
import json
import os
import secrets
import time
from urllib.parse import urlsplit

base=urlsplit(os.environ.get('BASE_URL','http://127.0.0.1:4400'))
assert base.hostname in ('127.0.0.1','localhost')
client=secrets.token_hex(24)
identity='features-'+secrets.token_hex(8)
checks=0

def req(method,path,body=None,headers=None,status=200):
    global checks
    c=http.client.HTTPConnection(base.hostname,base.port,timeout=24)
    h={'X-Spectre-Client':client,'X-Real-IP':identity}
    if body is not None: body=json.dumps(body).encode();h['Content-Type']='application/json'
    h.update(headers or {})
    c.request(method,path,body,h);r=c.getresponse();raw=r.read();c.close()
    assert r.status==status,(method,path,r.status,raw[:300])
    checks+=1
    return json.loads(raw)

r=req('POST','/api/rooms',{'name':'Test event','topic':'temporary','minutes':15,'discoverable':True},status=201)
room=r['room']['id']; owner={'X-Moderator-Key':r['owner_key']}
assert any(x['id']==room for x in req('GET','/api/rooms'))
msg=req('POST','/api/messages',{'content':'Parent','ttl':3000,'room':room},status=201)
child=req('POST','/api/messages',{'content':'Reply','ttl':300000,'room':room,'parent_id':msg['id']},status=201)
assert child['message']['expires_at']<=msg['message']['expires_at']
req('POST','/api/messages',{'content':'Wrong room','ttl':3000,'room':'lobby','parent_id':msg['id']},status=404)
poll=req('POST','/api/messages',{'content':'Tea or coffee?','ttl':30000,'room':room,'kind':'poll','options':['Tea','Coffee']},status=201)
p=f"/api/messages/{poll['id']}/vote?room={room}"
assert req('POST',p,{'option':0})['poll_counts']==[1,0]
assert req('POST',p,{'option':1})['poll_counts']==[0,1]
req('POST',p,{'option':2},status=400)
req('POST',f"/api/messages/{poll['id']}/report?room={room}",{'reason':'spam'})
req('GET','/api/reports?room='+room,status=403)
assert req('GET','/api/reports?room='+room,headers=owner)[0]['count']==1
req('POST','/api/presence?room='+room,{'alias':'Temporary Ghost'})
assert req('GET','/api/presence?room='+room)['count']==1
revision=req('GET','/api/room?room='+room)['revision']
with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
    futures=[pool.submit(req,'GET',f'/api/events?room={room}&since={revision}') for _ in range(4)]
    time.sleep(.15)
    req('GET',f'/api/events?room={room}&since={revision}',status=429)
    req('DELETE',f"/api/messages/{poll['id']}?room={room}",headers=owner)
    for future in futures: assert future.result(timeout=3)['revision']!=revision
req('DELETE',f"/api/messages/{msg['id']}?room={room}",headers={'X-Burn-Key':msg['burn_key']})
assert req('GET','/api/messages?room='+room)==[]
private=req('POST','/api/rooms',{'name':'Private event','minutes':15,'private':True,'encrypted':True},status=201)
private_id=private['room']['id']; access={'X-Room-Key':private['access_key']};private_owner={**access,'X-Moderator-Key':private['owner_key']}
for path in ['messages','snapshot','room','presence','reports','events']:
    req('GET',f'/api/{path}?room={private_id}',status=403)
assert all(x['id']!=private_id for x in req('GET','/api/rooms'))
assert req('GET','/api/room?room='+private_id,headers=access)['encrypted']
req('POST','/api/messages',{'content':'plaintext forbidden','room':private_id,'ttl':3000},access,status=400)
req('POST','/api/messages',{'content':'private unauthorized','room':private_id,'ttl':3000},status=403)
req('DELETE','/api/room?room='+private_id,headers=access,status=403)
req('DELETE','/api/room?room='+private_id,headers=private_owner)
req('GET','/api/messages?room='+private_id,headers=access,status=404)
req('POST','/api/messages',{'content':'cannot revive','room':private_id,'ttl':3000},status=404)
req('DELETE','/api/room?room='+room,headers=owner)
req('GET','/api/presence?room='+room,status=404)
print(f'{checks} feature/authorization checks passed.')
