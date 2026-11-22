#!/usr/bin/env python3
"""Check the locked public Hex package inventory against OSV; never send code or runtime data."""
import json
from pathlib import Path
import sys
import tomllib
import urllib.error
import urllib.request

packages = [p for p in tomllib.loads(Path('manifest.toml').read_text())['packages'] if p['source'] == 'hex']
payload = {'queries': [{'package': {'name': p['name'], 'ecosystem': 'Hex'}, 'version': p['version']} for p in packages]}
request = urllib.request.Request('https://api.osv.dev/v1/querybatch', data=json.dumps(payload).encode(),
                                 headers={'Content-Type': 'application/json', 'User-Agent': 'spectre-dependency-check'})
try:
    with urllib.request.urlopen(request, timeout=30) as response:
        result = json.load(response)['results']
    if len(result) != len(packages) or not all(isinstance(item, dict) for item in result):
        raise ValueError('Incomplete OSV response')
except (OSError, ValueError, KeyError, urllib.error.URLError) as error:
    print('Hex advisory lookup failed; no clean result can be claimed: ' + str(error), file=sys.stderr)
    sys.exit(1)

findings = [(p, r['vulns']) for p, r in zip(packages, result) if r.get('vulns')]
for package, advisories in findings:
    for advisory in advisories:
        print(f"{package['name']} {package['version']}: https://osv.dev/vulnerability/{advisory['id']}")
if findings:
    print('Review the matched Hex advisories before shipping.', file=sys.stderr)
    sys.exit(1)
print(f'OSV: no matching advisories for {len(packages)} locked Hex packages. Database coverage is not a security guarantee.')
