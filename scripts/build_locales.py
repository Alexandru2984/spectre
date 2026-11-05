#!/usr/bin/env python3
"""Deterministic Romanian public HTML; no content or user invitations enter it."""
import html
from html.parser import HTMLParser
import json
from pathlib import Path
import sys

catalog=json.load(sys.stdin)
check='--check' in sys.argv
void={'meta','link','input','br','hr','img','area','base','col','embed','param','source','track','wbr'}

class Romanian(HTMLParser):
    def __init__(self):super().__init__(convert_charrefs=True);self.parts=[];self.stack=[]
    def translated(self,text):
        trimmed=text.strip()
        return text.replace(trimmed,catalog.get(trimmed,trimmed)) if trimmed else text
    def handle_decl(self,decl):self.parts.append('<!'+decl+'>')
    def handle_comment(self,data):self.parts.append('<!--'+data+'-->')
    def handle_starttag(self,tag,attrs):self.start(tag,attrs,False)
    def handle_startendtag(self,tag,attrs):self.start(tag,attrs,True)
    def start(self,tag,attrs,closed):
        data=dict(attrs);skip=(self.stack and self.stack[-1][1]) or tag in ('script','style','code','kbd') or 'data-untranslated' in data
        original=self.get_starttag_text();name=original[1:].split(None,1)[0].split('>')[0].rstrip('/')
        transformed=[]
        for key,value in attrs:
            if value is None:transformed.append(key);continue
            if key in ('aria-label','placeholder','title') and not skip:value=self.translated(value)
            if tag=='html' and key=='lang':value='ro'
            if tag=='a' and key=='href' and value in ('/','/about','/privacy'):value='/ro'+('' if value=='/' else value)
            if tag=='a' and key=='href' and value.startswith('/?room='):value='/ro'+value[1:]
            if tag=='link' and data.get('rel')=='canonical' and key=='href':value=value.replace('https://spectre.micutu.com/','https://spectre.micutu.com/ro/').rstrip('/')
            if tag=='meta' and key=='content' and data.get('name') in ('description','twitter:title','twitter:description','twitter:image:alt'):value=self.translated(value)
            if tag=='meta' and key=='content' and data.get('property') in ('og:title','og:description','og:image:alt'):value=self.translated(value)
            if tag=='meta' and key=='content' and data.get('property')=='og:url':value=value.replace('https://spectre.micutu.com/','https://spectre.micutu.com/ro/').rstrip('/')
            if tag=='meta' and key=='content' and data.get('property')=='og:locale':value='ro_RO'
            if tag=='meta' and key=='content' and data.get('property')=='og:locale:alternate':value='en_US'
            transformed.append(key+'="'+html.escape(value,quote=True)+'"')
        self.parts.append('<'+name+(' '+' '.join(transformed) if transformed else '')+('/>' if closed else '>'))
        if not closed and tag not in void:self.stack.append((tag,bool(skip),name))
    def handle_endtag(self,tag):
        name=tag
        for i in range(len(self.stack)-1,-1,-1):
            if self.stack[i][0]==tag:name=self.stack[i][2];self.stack=self.stack[:i];break
        self.parts.append('</'+name+'>')
    def handle_data(self,data):
        if self.stack and self.stack[-1][1]:self.parts.append(data)
        else:self.parts.append(html.escape(self.translated(data),quote=False))

for name in ('index','about','privacy'):
    source=Path('priv/static/'+name+'.html').read_text()
    parser=Romanian();parser.feed(source);result=''.join(parser.parts)
    # JSON-LD is a non-executable data block; keep its language and URL accurate.
    import re
    def localize(match):
        data=json.loads(match.group(1))
        def walk(value):
            if isinstance(value,dict):return {key:('ro' if key=='inLanguage' else walk(v)) for key,v in value.items()}
            if isinstance(value,list):return [walk(x) for x in value]
            if isinstance(value,str):
                if value.startswith('https://spectre.micutu.com/') and '/static/' not in value:return value.replace('https://spectre.micutu.com/','https://spectre.micutu.com/ro/').rstrip('/')
                return catalog.get(value,value)
            return value
        return '<script type="application/ld+json">'+json.dumps(walk(data),ensure_ascii=False,separators=(',',':'))+'</script>'
    result=re.sub(r'<script type="application/ld\+json">(.*?)</script>',localize,result,flags=re.S)
    target=Path('priv/static/'+name+'.ro.html')
    if check:
        assert target.exists() and target.read_text()==result,str(target)+' is stale; run node scripts/build-locales.mjs'
    else:target.write_text(result)
print('Romanian public HTML '+('verified' if check else 'generated')+'.')
