#!/usr/bin/env python3
"""Build-time only: fetch official pinned engine, verify every input, never read user data."""
from pathlib import Path
import hashlib, io, json, shlex, tarfile, urllib.request
ROOT=Path(__file__).resolve().parents[1]
lock=json.loads((ROOT/'Resources/a1-lock.json').read_text())
def digest(data):return hashlib.sha256(data).hexdigest()
for item in lock['files']:
    data=(ROOT/item['path']).read_bytes()
    if digest(data)!=item['sha256']:raise SystemExit('resource digest mismatch: '+item['path'])
archive=urllib.request.urlopen(lock['engine']['url'],timeout=120).read()
if digest(archive)!=lock['engine']['sha256']:raise SystemExit('engine archive digest mismatch')
out=ROOT/'.build/a1-engine';out.mkdir(parents=True,exist_ok=True)
# Extract exact regular files only. No archive paths/symlinks/plugins are trusted or installed.
with tarfile.open(fileobj=io.BytesIO(archive),mode='r:bz2') as tar:
    for source,dest in [('dist/lib/librime.1.16.0.dylib','librime.1.16.0.dylib'),('dist/include/rime_api.h','rime_api.h')]:
        member=tar.getmember(source)
        if not member.isfile():raise SystemExit('expected regular archive member')
        data=tar.extractfile(member).read();(out/dest).write_bytes(data)
if digest((out/'rime_api.h').read_bytes())!=lock['headerSha256']:raise SystemExit('archive header does not match pinned ABI')
env={'PAIA_RIME_LIBRARY':str(out/'librime.1.16.0.dylib'),'PAIA_FIXTURE_DIR':str(ROOT/'Resources/Dictionaries/A1Fixture'),'PAIA_DICTIONARY_REVISION':lock['dictionaryRevision']}
(ROOT/'.build/a1-env.sh').write_text(''.join('export '+k+'='+shlex.quote(v)+'\n' for k,v in env.items()))
print(json.dumps({'engine':lock['engine'],'dictionaryRevision':lock['dictionaryRevision'],'verifiedFiles':len(lock['files'])},indent=2))
