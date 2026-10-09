#!/usr/bin/env python3
"""Acquire immutable research inputs at build time. Never called by the input hot path."""
from pathlib import Path
import hashlib, io, json, re, shlex, shutil, tarfile, urllib.request
ROOT=Path(__file__).resolve().parents[1]
lock=json.loads((ROOT/'Resources/A2/upstream-lock.json').read_text())
cache=ROOT/'.build/a2-cache'; shared=ROOT/'.build/a2-shared'; headers=ROOT/'.build/a2-headers'
for p in (cache,shared,headers):p.mkdir(parents=True,exist_ok=True)
def fetch(item,path):
    if path.exists() and hashlib.sha256(path.read_bytes()).hexdigest()==item['sha256']:return
    data=urllib.request.urlopen(item['url'],timeout=180).read()
    if hashlib.sha256(data).hexdigest()!=item['sha256']:raise SystemExit('digest mismatch: '+item['url'])
    path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes(data)
for item in lock['privateHeaders']:fetch(item,headers/item['path'])
# Logging only changes diagnostics/free ostream friends, not class object layout.
(headers/'src/rime/build_config.h').write_text('#ifndef RIME_BUILD_CONFIG_H_\n#define RIME_BUILD_CONFIG_H_\n#endif\n')
boost=cache/'boost.tar.gz';fetch(lock['boost'],boost)
boost_root=ROOT/'.build/a2-boost'
if not (boost_root/'boost/version.hpp').exists():
    with tarfile.open(boost,'r:gz') as archive:
        for member in archive:
            if not member.isfile() or not member.name.startswith('boost_1_89_0/boost/'):continue
            relative=Path(member.name).relative_to('boost_1_89_0')
            if '..' in relative.parts:raise SystemExit('unsafe boost archive path')
            dest=boost_root/relative;dest.parent.mkdir(parents=True,exist_ok=True);dest.write_bytes(archive.extractfile(member).read())
for item in lock['resources']:
    repo=item['repository'].replace('/','_');path=cache/repo/item['upstreamPath'];fetch(item,path)
    if item['role']=='runtime-corpus':
        dest=shared/item['upstreamPath'];dest.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(path,dest)
    if item['repository']=='BYVoid/OpenCC' and item['upstreamPath'].startswith('data/'):
        dest=shared/'opencc'/Path(item['upstreamPath']).name;dest.parent.mkdir(parents=True,exist_ok=True)
        if path.suffix=='.json':dest.write_text(path.read_text().replace('"ocd2"','"text"').replace('.ocd2','.txt'))
        else:shutil.copyfile(path,dest)
for p in (ROOT/'Resources/Dictionaries/A1Fixture').glob('*'):shutil.copyfile(p,shared/p.name)
def block(text,key):
    match=re.search(r'^'+re.escape(key)+r':\n(.*?)(?=^[a-zA-Z_][\w]*:|\Z)',text,re.M|re.S)
    if not match:raise SystemExit('missing schema block '+key)
    return match.group(0)
for kind,upstream in [('full','rime_ice.schema.yaml'),('flypy','double_pinyin_flypy.schema.yaml'),('natural','double_pinyin.schema.yaml')]:
    original=(cache/'iDvel_rime-ice'/upstream).read_text();speller=block(original,'speller')
    translator=block(original,'translator');preedit=re.search(r'^  preedit_format:[^\n]*\n(?:^    .*\n|^\s*#.*\n|^\n)*',translator,re.M)
    for traditional in (False,True):
        name='paia_a2_'+kind+('_traditional' if traditional else '')
        config=f'''# Research-only GPL-3.0-only derivative of pinned Rime Ice schema; see upstream-lock.json.
schema:
  schema_id: {name}
  name: PAIA A2 core-only {kind}
  version: "1"
switches:
  - name: ascii_mode
    reset: 0
  - name: traditionalization
    reset: {1 if traditional else 0}
engine:
  processors: [speller, selector, navigator, express_editor]
  segmentors: [abc_segmentor, fallback_segmentor]
  translators: [script_translator]
  filters: [simplifier@traditionalize, uniquifier]
menu:
  page_size: 5
translator:
  dictionary: rime_ice
  prism: paia_a2_{kind}
  enable_user_dict: false
  enable_sentence: true
  enable_completion: true
  enable_word_completion: true
'''+(preedit.group(0) if preedit else '')+'''traditionalize:
  option_name: traditionalization
  opencc_config: s2t.json
  tips: none
'''+speller
        (shared/(name+'.schema.yaml')).write_text(config)
revision=hashlib.sha256((ROOT/'Resources/A2/upstream-lock.json').read_bytes()).hexdigest()
(ROOT/'.build/a2-env.sh').write_text('source '+shlex.quote(str(ROOT/'.build/a1-env.sh'))+'\n'+''.join('export '+k+'='+shlex.quote(v)+'\n' for k,v in {'PAIA_A2_SHARED':str(shared),'PAIA_G01_LIBRARY':str(ROOT/'.build/a2-g01.dylib'),'PAIA_A2_REVISION':revision}.items()))
print(json.dumps({'dictionaryRevision':revision,'corpusRows':lock['totalDefaultChineseDictionaryRows'],'privateHeaders':len(lock['privateHeaders']),'corpusBundled':False}))
