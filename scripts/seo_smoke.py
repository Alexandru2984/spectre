#!/usr/bin/env python3
"""Public indexing metadata checks; uses no room content or credentials."""
from html.parser import HTMLParser
import http.client
import json
import os
from urllib.parse import urlsplit
import xml.etree.ElementTree as ET

base=urlsplit(os.environ.get('BASE_URL','http://127.0.0.1:4400'))
assert base.hostname in ('localhost','127.0.0.1')
origin='https://spectre.micutu.com'
class Page(HTMLParser):
 def __init__(self):super().__init__();self.links=[];self.meta={};self.schema=[];self.h1=0;self.language='';self.structured=False
 def handle_starttag(self,tag,attrs):
  a=dict(attrs)
  if tag=='html':self.language=a.get('lang','')
  if tag=='h1':self.h1+=1
  if tag=='meta':self.meta[a.get('name',a.get('property',''))]=a.get('content','')
  if tag=='link':self.links.append(a)
  if tag=='script' and a.get('type')=='application/ld+json':self.structured=True
 def handle_endtag(self,tag):
  if tag=='script':self.structured=False
 def handle_data(self,text):
  if self.structured:self.schema.append(json.loads(text))
def get(path):
 c=http.client.HTTPConnection(base.hostname,base.port,timeout=5);c.request('GET',path);r=c.getresponse();body=r.read().decode();headers=dict(r.getheaders());c.close();assert r.status==200,(path,r.status);return body,headers
for path,lang in [('/','en'),('/about','en'),('/privacy','en'),('/ro','ro'),('/ro/about','ro'),('/ro/privacy','ro')]:
 body,h=get(path);p=Page();p.feed(body)
 assert p.language==lang and p.h1==1 and len(p.meta['description'])>50
 assert 'x-robots-tag' not in h
 canonical=[link['href'] for link in p.links if link.get('rel')=='canonical'];assert canonical==[origin+path]
 alternates={link['hreflang']:link['href'] for link in p.links if link.get('rel')=='alternate'};assert set(alternates)=={'en','ro','x-default'}
 assert p.meta['og:url']==origin+path and p.meta['og:locale']==('ro_RO' if lang=='ro' else 'en_US')
 assert p.schema and p.schema[0]['inLanguage']==lang
 assert 'room=' not in json.dumps(p.schema) and '#invite=' not in body
 if lang=='ro':assert 'Camere' in body or 'camere' in body
 body,h=get(path+'?room=seo-check');assert h.get('x-robots-tag')=='noindex, nofollow'
body,_=get('/sitemap.xml');tree=ET.fromstring(body)
urls={node.text for node in tree.findall('{*}url/{*}loc')};assert urls=={origin+p for p in ['/','/about','/privacy','/ro','/ro/about','/ro/privacy']}
print('SEO checks passed: six static EN/RO pages, reciprocal alternates, canonical/social/structured metadata, noindex rooms and public-only sitemap.')
