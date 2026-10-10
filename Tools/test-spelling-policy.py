#!/usr/bin/env python3
"""Static recipe/identity proof, not native decoding or language-quality evidence."""
from pathlib import Path
import hashlib,json,re,sys
from spelling_policy import POLICY,TYPO,FUZZY,suffix,speller,variants
ROOT=Path(__file__).resolve().parents[1]
source=Path(sys.argv[1]) if len(sys.argv)==2 else ROOT/'.build/a2-cache/iDvel_rime-ice'
lock=json.loads((ROOT/'Resources/A2/upstream-lock.json').read_text())
names=[];prisms=set()
for kind,path in [('full','rime_ice.schema.yaml'),('flypy','double_pinyin_flypy.schema.yaml'),('natural','double_pinyin.schema.yaml')]:
    pinned=next(x for x in lock['resources'] if x['repository']=='iDvel/rime-ice' and x['upstreamPath']==path)
    assert POLICY['schemaCommit']==pinned['commit']
    data=(source/path).read_bytes();assert hashlib.sha256(data).hexdigest()==pinned['sha256']
    text=data.decode();match=re.search(r'^speller:\n(.*?)(?=^[a-zA-Z_][\w]*:|\Z)',text,re.M|re.S)
    assert match;original=match.group(0)
    assert speller(original,kind,False,True)==original
    for fuzzy,correction in variants(kind):
        policy=suffix(kind,fuzzy,correction);changed=speller(original,kind,fuzzy,correction)
        if fuzzy:
            inserted=''.join('    - '+rule+'\n' for rule in FUZZY)
            assert changed.split('  algebra:\n',1)[1].startswith(inserted)
            assert changed.replace(inserted,'',1)==speller(original,kind,False,correction)
        if kind=='full' and not correction:
            remaining=changed.split('### 自动纠错',1)[1]
            assert not re.search(r'^\s*-\s+derive/',remaining,re.M)
            assert len(TYPO)==37
            assert 'abbrev/' in changed
            for alias in ['derive/^([nl])ve$/$1ue/','derive/^([jqxy])u/$1v/','derive/^([nl])ue$/$1ve/','derive/^([jqxy])v/$1u/']:assert alias in changed
        prisms.add(kind+policy)
        for traditional in [False,True]:
            for punctuation in [False,True]:names.append('paia_b1_'+kind+('_traditional' if traditional else '')+('_punct' if punctuation else '_ascii')+policy)
    if kind!='full':assert speller(original,kind,False,False)==original and suffix(kind,False,False)==''
    else:
        bad=original.replace(TYPO[0],TYPO[0]+'tampered',1)
        try:speller(bad,kind)
        except ValueError:pass
        else:raise AssertionError('changed upstream rules accepted')
assert len(names)==len(set(names))==32 and len(prisms)==8
assert suffix('full',False,True)==''
print('SIMULATED_POLICY_RECIPE pinned 37 typo derives; unchanged legacy spelling; orthographic aliases retained; 32 schemas / 8 distinct prisms; no engine executed')
