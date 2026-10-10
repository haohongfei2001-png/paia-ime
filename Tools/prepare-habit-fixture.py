#!/usr/bin/env python3
"""Finite authored native-policy control; never appended to the research corpus."""
from pathlib import Path
import hashlib,json,re,shlex,shutil
ROOT=Path(__file__).resolve().parents[1]
source=ROOT/'.build/b1-shared';dest=ROOT/'.build/habit-fixture-shared'
if dest.exists():raise SystemExit('Use a fresh owned habit fixture directory')
dest.mkdir()
for p in (ROOT/'Resources/Dictionaries/A1Fixture').iterdir():
    if p.is_file():shutil.copyfile(p,dest/p.name)
shutil.copytree(source/'opencc',dest/'opencc')
fixture=ROOT/'Resources/Dictionaries/HabitFixture/paia_habit_fixture.dict.yaml'
shutil.copyfile(fixture,dest/fixture.name)
names=[];prisms=set()
for p in sorted(source.glob('paia_b1_*.schema.yaml')):
    name=p.stem.removesuffix('.schema').replace('paia_b1_','paia_habit_')
    text=p.read_text().replace('schema_id: '+p.stem.removesuffix('.schema'),'schema_id: '+name)
    if text.count('dictionary: rime_ice\n')!=1:raise SystemExit('unexpected policy dictionary')
    text=text.replace('dictionary: rime_ice\n','dictionary: paia_habit_fixture\n')
    text=text.replace('prism: paia_a2_','prism: paia_habit_')
    # Prefix completion remains enabled exactly as in the original research lane.
    # Exhaustive finite negative tests distinguish no target from incomplete search.
    (dest/(name+'.schema.yaml')).write_text(text);names.append(name)
    prisms.add(re.search(r'^  prism: (\S+)$',text,re.M).group(1))
if len(names)!=32 or len(prisms)!=8:raise SystemExit('unexpected effective spelling policy coverage')
inputs={p.relative_to(dest).as_posix():hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(dest.rglob('*')) if p.is_file()}
revision=hashlib.sha256(json.dumps(inputs,sort_keys=True).encode()).hexdigest()
(ROOT/'.build/habit-env.sh').write_text('source '+shlex.quote(str(ROOT/'.build/b1-env.sh'))+'\n'+''.join('export '+k+'='+shlex.quote(v)+'\n' for k,v in {'PAIA_HABIT_SHARED':str(dest),'PAIA_HABIT_REVISION':revision}.items()))
print(json.dumps({'revision':revision,'schemas':names,'prisms':sorted(prisms),'authoredRows':27,'researchCorpusIncluded':False,'files':inputs}))
