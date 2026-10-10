#!/usr/bin/env python3
"""Closed build-time candidate inputs: authored words, pinned recipes/maps only.

No research corpus directory is read or recursively copied. The input hot path
never downloads, transforms, or compiles these resources.
"""
from pathlib import Path
import hashlib,json,re,urllib.request
from spelling_policy import suffix,variants,speller

ROOT=Path(__file__).resolve().parents[1]
LOCK=json.loads((ROOT/'Resources/A2/upstream-lock.json').read_text())
DEST=ROOT/'.build/candidate-sources'
CACHE=ROOT/'.build/candidate-cache'
RECIPES={'full':'rime_ice.schema.yaml','flypy':'double_pinyin_flypy.schema.yaml','natural':'double_pinyin.schema.yaml'}
MAPS=['data/config/s2t.json','data/dictionary/STCharacters.txt','data/dictionary/STPhrases.txt']

def digest(data):return hashlib.sha256(data).hexdigest()
def canonical(value):return json.dumps(value,ensure_ascii=False,sort_keys=True,separators=(',',':')).encode()
def block(text,key):
    match=re.search(r'^'+re.escape(key)+r':\n(.*?)(?=^[a-zA-Z_][\w]*:|\Z)',text,re.M|re.S)
    if not match:raise ValueError('missing pinned block')
    return match.group(0)
def acquire(item):
    path=CACHE/item['repository'].replace('/','_')/item['upstreamPath']
    # An already acquired upstream cache is reusable only after the same hash check.
    previous=ROOT/'.build/a2-cache'/item['repository'].replace('/','_')/item['upstreamPath']
    data=path.read_bytes() if path.is_file() else previous.read_bytes() if previous.is_file() else urllib.request.urlopen(item['url'],timeout=180).read()
    if len(data)!=item['size'] or digest(data)!=item['sha256']:raise ValueError('pinned input mismatch')
    if not path.exists():path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes(data)
    return data

def prepare():
    if DEST.exists():raise ValueError('candidate sources already exist; use a fresh owned build directory')
    selected=[x for x in LOCK['resources'] if (x['repository']=='iDvel/rime-ice' and x['upstreamPath'] in RECIPES.values()) or (x['repository']=='BYVoid/OpenCC' and x['upstreamPath'] in MAPS)]
    if len(selected)!=6:raise ValueError('closed source selection changed')
    acquired={(x['repository'],x['upstreamPath']):acquire(x) for x in selected}
    DEST.mkdir();(DEST/'opencc').mkdir()
    for name in ['default.yaml','paia_a1.schema.yaml','paia_a1.dict.yaml']:
        (DEST/name).write_bytes((ROOT/'Resources/Dictionaries/A1Fixture'/name).read_bytes())
    rows=[]
    for name in ['A1Fixture/paia_a1.dict.yaml','HabitFixture/paia_habit_fixture.dict.yaml']:
        text=(ROOT/'Resources/Dictionaries'/name).read_text()
        rows.extend(line for line in text.split('...\n',1)[1].splitlines() if line and not line.startswith('#'))
    if len(rows)!=46 or len(set(rows))!=46:raise ValueError('authored row set changed')
    dictionary='# Authored integration words only; not a production language model.\n---\nname: paia_candidate\nversion: "1"\nsort: by_weight\nuse_preset_vocabulary: false\ncolumns: [text, code, weight]\n...\n'+'\n'.join(rows)+'\n'
    (DEST/'paia_candidate.dict.yaml').write_text(dictionary)
    for path in MAPS:
        data=acquired[('BYVoid/OpenCC',path)]
        if path.endswith('.json'):
            text=data.decode().replace('"ocd2"','"text"')
            for old in ['STCharacters','STPhrases']:text=text.replace(old+'.ocd2',old.lower()+'.txt')
            data=text.encode()
        (DEST/'opencc'/Path(path).name.lower()).write_bytes(data)
    names=[];prisms=set()
    for kind,upstream in RECIPES.items():
        original=acquired[('iDvel/rime-ice',upstream)].decode()
        algebra=block(original,'speller');translator=block(original,'translator')
        preedit=re.search(r'^  preedit_format:[^\n]*\n(?:^    .*\n|^\s*#.*\n|^\n)*',translator,re.M)
        for traditional in [False,True]:
            for punctuation in [False,True]:
                for fuzzy,correction in variants(kind):
                    policy=suffix(kind,fuzzy,correction)
                    name='paia_candidate_'+kind+('_traditional' if traditional else '')+('_punct' if punctuation else '_ascii')+policy
                    prism='paia_candidate_'+kind+policy;prisms.add(prism)
                    text=f'''# GPL-3.0-only spelling derivative of pinned Rime Ice; authored dictionary.
schema:
  schema_id: {name}
  name: PAIA authored candidate {kind}
  version: "1"
switches:
  - name: ascii_mode
    reset: 0
  - name: traditionalization
    reset: {int(traditional)}
engine:
  processors: [{"punctuator, " if punctuation else ""}speller, selector, navigator, express_editor]
  segmentors: [abc_segmentor, {"punct_segmentor, " if punctuation else ""}fallback_segmentor]
  translators: [{"punct_translator, " if punctuation else ""}script_translator]
  filters: [simplifier@traditionalize, uniquifier]
menu:
  page_size: 5
translator:
  dictionary: paia_candidate
  prism: {prism}
  enable_user_dict: false
  enable_correction: false
  enable_sentence: true
  enable_completion: true
  enable_word_completion: true
'''+(preedit.group(0) if preedit else '')+'''traditionalize:
  option_name: traditionalization
  opencc_config: s2t.json
  tips: none
'''
                    if punctuation:
                        text+='punctuator:\n'
                        for shape in ['half_shape','full_shape']:
                            text+='  '+shape+':\n'+''.join('    '+json.dumps(a)+': {commit: '+json.dumps(b,ensure_ascii=False)+'}\n' for a,b in [(',','，'),('?','？'),('!','！'),(';','；')])
                    text+=speller(algebra,kind,fuzzy,correction)
                    (DEST/(name+'.schema.yaml')).write_text(text);names.append(name)
    assert len(names)==32 and len(prisms)==8
    files=[{'path':p.relative_to(DEST).as_posix(),'bytes':len(p.read_bytes()),'sha256':digest(p.read_bytes())} for p in sorted(DEST.rglob('*')) if p.is_file()]
    identity=digest(canonical(files))
    result={'format':1,'profile':'authored-candidate-v1','inputsSHA':identity,'inputs':files,'schemas':sorted(names),'prisms':sorted(prisms),'authoredRows':46,'researchCorpusIncluded':False,'upstream':selected,'derivatives':['Only speller and preedit recipes; closed processors with no Lua/user dictionary.','OpenCC s2t uses text maps and lowercase map filenames; mapping bytes unchanged.'],'localInputs':[{ 'path':str(p.relative_to(ROOT)),'sha256':digest(p.read_bytes())} for p in [ROOT/'Resources/Dictionaries/A1Fixture/paia_a1.dict.yaml',ROOT/'Resources/Dictionaries/HabitFixture/paia_habit_fixture.dict.yaml',ROOT/'Resources/A2/spelling-policy.json']]}
    (ROOT/'.build/candidate-inputs.json').write_bytes(canonical(result)+b'\n')
    print(json.dumps({'profile':result['profile'],'inputsSHA':identity,'authoredRows':46,'schemas':32,'prisms':8,'researchCorpusIncluded':False,'sources':len(files)}))

if __name__=='__main__':prepare()
