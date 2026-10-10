#!/usr/bin/env python3
"""Explicit synthetic catalog mutation for finite recovery tests; no discovery."""
from pathlib import Path
import hashlib,json,sys
parent=Path(sys.argv[1]).resolve();kind=sys.argv[2];root=parent/'paia-ime-public-resources'
def canonical(value):return json.dumps(value,ensure_ascii=False,sort_keys=True,separators=(',',':')).encode()
def sha(data):return hashlib.sha256(data).hexdigest()
index=json.loads((root/'index.json').read_bytes())
current=root/'generations'/index['current']['generation']
previous=root/'generations'/index['lastGood']['generation']
if kind=='missing_index':(root/'index.json').unlink()
elif kind in ['fallback','both','personal_fallback']:
    (current/'build/paia_candidate.table.bin').write_bytes(b'AUTHORED invalid current compiled table')
    if kind=='both':(previous/'build/paia_candidate.table.bin').write_bytes(b'AUTHORED invalid previous compiled table')
elif kind in ['semantic','wrong_prism']:
    manifest=json.loads((current/'manifest.json').read_bytes())
    if kind=='semantic':
        for item in manifest['artifacts']:(current/item['path']).write_bytes((previous/item['path']).read_bytes())
    else:
        a=current/'build/paia_candidate_flypy.prism.bin';b=current/'build/paia_candidate_natural.prism.bin'
        first=a.read_bytes();a.write_bytes(b.read_bytes());b.write_bytes(first)
    for item in manifest['artifacts']:
        data=(current/item['path']).read_bytes();item.update(bytes=len(data),sha256=sha(data))
    changed=canonical(manifest);(current/'manifest.json').write_bytes(changed)
    index['current']['manifestSHA']=sha(changed);(root/'index.json').write_bytes(canonical(index))
else:raise ValueError('unknown synthetic fault')
print('CANDIDATE_UPDATE_AUTHORED_FAULT '+kind+'; no production/user data')
