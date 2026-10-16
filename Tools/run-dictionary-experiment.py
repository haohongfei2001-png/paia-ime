#!/usr/bin/env python3
"""Three explicit research lanes, three fresh processes each, five rounds of 48 tasks.
No quality threshold is fabricated. Engine errors fail; missing expected vocabulary
is a measured result. Existing A2 G01/mixed regressions remain a separate gate.
"""
import importlib.util,json,os,re,shutil,subprocess,sys
from pathlib import Path
import dictionary_experiment as d
spec=importlib.util.spec_from_file_location('qualification',Path(__file__).with_name('run-native-qualification.py'))
q=importlib.util.module_from_spec(spec);spec.loader.exec_module(q)
ROOT=d.ROOT

def main():
 if os.environ.get('PAIA_DICTIONARY_EXPERIMENT')!='1':raise RuntimeError('explicit research opt-in required')
 lock,data,dictionary,conversion=d.verify()
 source=Path(os.environ['PAIA_A2_SHARED']);before=q.inventory(source)
 out=ROOT/'evidence/a2-run/dictionary-experiment';out.mkdir(parents=True,exist_ok=False)
 build=ROOT/'.build/dictionary-experiment';build.mkdir(parents=True,exist_ok=False)
 tasks=d.RESOURCE/'tasks-v1.json';task_data=json.loads(tasks.read_text())
 if len(task_data)!=48 or len({t['id'] for t in task_data})!=48:raise RuntimeError('task identity')
 schema=(source/'paia_a2_full.schema.yaml').read_text()
 summaries=[]
 q.write(out/'contract.json',{'sourceSHA':os.environ['PAIA_SOURCE_SHA'],'taskSHA256':d.digest(tasks.read_bytes()),'sourceLockSHA256':d.digest((d.RESOURCE/'source-lock.json').read_bytes()),'binarySHA256':d.digest((ROOT/'.build/release/paia-dictionary-experiment').read_bytes()),'originalInputRevision':q.digest(before),'sourceInventory':before,'lanePolicy':'same full-pinyin schema/speller/options, dictionary only differs; learning disabled; no frequency equivalence','taskOrigin':'new authored v1: 24 single characters, 24 words/phrases; last six reused A2 comparator prompts; old uncommitted experiment task file unavailable, no identity claim'})
 q.write(out/'conversion.json',conversion)
 for lane,name in [('authored','paia_a1'),('unihan','paia_unihan_experiment'),('research','rime_ice')]:
  shared=build/lane;shutil.copytree(source,shared)
  if lane=='unihan':(shared/'paia_unihan_experiment.dict.yaml').write_bytes(dictionary)
  text=schema.replace('schema_id: paia_a2_full','schema_id: paia_dictionary_experiment').replace('dictionary: rime_ice','dictionary: '+name)
  (shared/'paia_dictionary_experiment.schema.yaml').write_text(text)
  inventory=q.inventory(shared);revision=q.digest(inventory)
  q.write(out/(lane+'-inputs.json'),{'revision':revision,'files':inventory})
  for process in range(3):
   env=os.environ.copy();env.update(PAIA_DICTIONARY_LANE=lane,PAIA_DICTIONARY_SHARED=str(shared),PAIA_DICTIONARY_REVISION=revision,PAIA_DICTIONARY_TASKS=str(tasks))
   log=out/f'{lane}-{process}.json';env['PAIA_DICTIONARY_RESULT']=str(log.with_suffix('.result.json'));q.run([str(ROOT/'.build/release/paia-dictionary-experiment')],log,180,env)
   # Swift writes stdout JSON, while librime may emit diagnostics to stderr.
   # The native executable uses a dedicated result path for unambiguous parsing.
   report=json.loads(log.with_suffix('.result.json').read_text())
   rows=report['observations']
   expected={(t['id'],r) for t in task_data for r in range(5)}
   if len(rows)!=240 or {(x['task'],x['round']) for x in rows}!=expected or any(x.get('error') for x in rows):raise RuntimeError('incomplete native diagnostic')
   if report['revision']!=revision or report['sourceSHA']!=env['PAIA_SOURCE_SHA'] or report['lane']!=lane:raise RuntimeError('wrong native identity')
   summaries.append({'lane':lane,'process':process,'observations':len(rows),'topPageExpected':sum(x.get('expectedRank') is not None for x in rows),'topOneExpected':sum(x.get('expectedRank')==1 for x in rows),'errors':0})
   if q.inventory(shared)!=inventory:raise RuntimeError('shared input mutation')
 if q.inventory(source)!=before:raise RuntimeError('original research input mutation')
 q.write(out/'summary.json',{'runs':summaries,'nativeObservations':2160,'complete':True,'productionQualityEstablished':False,'installedIME':False,'defaultDictionaryChanged':False})
if __name__=='__main__':main()
