#!/usr/bin/env python3
"""No server startup: missing selected pack must fail before engine entry."""
import os,pathlib,subprocess
root=pathlib.Path(__file__).resolve().parents[1]
app=root/'.build/PAIAInputMethodFixture.app'
pack=app/'Contents/Resources/DictionaryFixturePack'
held=root/'.build/resource-pack-held-for-negative-test'
assert pack.is_dir() and not held.exists()
environment=dict(os.environ)
for key in ['PAIA_RIME_LIBRARY','PAIA_FIXTURE_DIR','PAIA_DICTIONARY_REVISION','PAIA_RESOURCE_ROOT','PAIA_RESOURCE_HELPER','PAIA_RESOURCE_HELPER_SHA']:
    environment.pop(key,None)
pack.rename(held)
try:
    result=subprocess.run([str(app/'Contents/MacOS/PAIAInputMethod'),'--preflight'],env=environment,capture_output=True,text=True,timeout=30)
    assert result.returncode!=0 and 'phase=engine-startup mainAttempts=0' in result.stderr,(result.returncode,result.stderr)
    assert 'IMK_RESOURCE_STARTUP' not in result.stdout
finally:
    held.rename(pack)
print('RESOURCE_BUNDLE_MISSING_NATIVE expected failure; main engine attempts zero; pack restored; no IMKServer construction')
