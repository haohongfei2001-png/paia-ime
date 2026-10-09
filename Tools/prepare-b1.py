#!/usr/bin/env python3
"""Build-time B1 lab configuration; keeps the A2 comparator byte-for-byte unchanged."""
from pathlib import Path
import hashlib,json,shlex,shutil
ROOT=Path(__file__).resolve().parents[1]
source=ROOT/'.build/a2-shared';dest=ROOT/'.build/b1-shared'
if not source.is_dir():raise SystemExit('Run verified A1/A2 preparation first')
# Exact pinned data only. This cache is never copied into the distributable A1 app.
shutil.copytree(source,dest,dirs_exist_ok=True)
names=[]
for kind in ['full','flypy','natural']:
    for traditional in [False,True]:
        a2='paia_a2_'+kind+('_traditional' if traditional else '')
        for chinese_punctuation in [False,True]:
            b1=a2.replace('paia_a2_','paia_b1_')+('_punct' if chinese_punctuation else '_ascii')
            text=(source/(a2+'.schema.yaml')).read_text().replace('schema_id: '+a2,'schema_id: '+b1)
            if chinese_punctuation:
                text=text.replace('processors: [speller, selector, navigator, express_editor]','processors: [punctuator, speller, selector, navigator, express_editor]')
                text=text.replace('segmentors: [abc_segmentor, fallback_segmentor]','segmentors: [abc_segmentor, punct_segmentor, fallback_segmentor]')
                text=text.replace('translators: [script_translator]','translators: [punct_translator, script_translator]')
                # Dot, colon, quotes, slash and symbols remain literal in this small B1 lane.
                # No heuristic conversion of decimals, times, versions, URLs or source code.
                text+='''
punctuator:
  half_shape:
    ",": {commit: "，"}
    "?": {commit: "？"}
    "!": {commit: "！"}
    ";": {commit: "；"}
  full_shape:
    ",": {commit: "，"}
    "?": {commit: "？"}
    "!": {commit: "！"}
    ";": {commit: "；"}
'''
            (dest/(b1+'.schema.yaml')).write_text(text);names.append(b1)
inputs={p.relative_to(dest).as_posix():hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(dest.rglob('*')) if p.is_file()}
revision=hashlib.sha256(json.dumps(inputs,sort_keys=True).encode()).hexdigest()
(ROOT/'.build/b1-env.sh').write_text('source '+shlex.quote(str(ROOT/'.build/a2-env.sh'))+'\n'+''.join('export '+k+'='+shlex.quote(v)+'\n' for k,v in {'PAIA_B1_SHARED':str(dest),'PAIA_B1_REVISION':revision,'PAIA_B1_RESEARCH':'1'}.items()))
print(json.dumps({'revision':revision,'schemas':names,'unbundled':True,'punctuation':'comma/question/exclamation/semicolon only; contextual punctuation remains ASCII'}))
