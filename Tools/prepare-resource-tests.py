#!/usr/bin/env python3
"""Existing pinned engine + authored compiler only; no downloads or installation."""
import hashlib,json,os,pathlib,shlex,subprocess
root=pathlib.Path(__file__).resolve().parents[1]
helper=root/'.build/PAIAInputMethod.app/Contents/MacOS/paia-resources'
library=pathlib.Path(os.environ['PAIA_RIME_LIBRARY'])
store=root/'.build/resource-native-store'
active=root/'.build/resource-active-store'
assert not store.exists() and not active.exists(), 'Use a fresh isolated CI workspace'
def publish(path,preset,revision,mode):
    result=subprocess.run([str(helper),'publish',str(path),preset,str(library),str(revision),mode],capture_output=True,text=True,timeout=120,check=True)
    value=json.loads(result.stdout);assert value['revision']==revision+1
    return value
for path in [store,active]:
    first=publish(path,'baseline',0,'create')
    second=publish(path,'extended',1,'existing')
    assert second['lastGood']==first['current'] and second['current']!=first['current']
variables={'PAIA_RESOURCE_HELPER':str(helper),'PAIA_RESOURCE_HELPER_SHA':hashlib.sha256(helper.read_bytes()).hexdigest(),'PAIA_RESOURCE_TEST_STORE':str(store),'PAIA_RESOURCE_ACTIVE_STORE':str(active)}
(root/'.build/resource-test-env.sh').write_text(''.join('export '+key+'='+shlex.quote(value)+'\n' for key,value in variables.items()))
print(json.dumps({'prepared':'two independent public stores','schemasPerGeneration':2,'generationsPerStore':2,'realCompileAndProbe':True,'network':False,'personalData':False}))
