#!/usr/bin/env python3
"""Move an unsigned authored app off-cache; run preflight only, never a service."""
from pathlib import Path
import hashlib,json,os,plistlib,shutil,subprocess,tempfile
root=Path(__file__).resolve().parents[1]
app=root/'.build/PAIAInputMethod.app';negative=root/'.build/candidate-negative-components/paia-g01.dylib'
temporary=Path(tempfile.mkdtemp(prefix='paia-movable-candidate-')).resolve()
held=root/'.build-hidden-candidate-verification';build=root/'.build'
assert app.is_dir() and negative.is_file() and not held.exists()
copy=temporary/'MovedCandidate.app';shutil.copytree(app,copy)
bad_bridge=negative.read_bytes();evidence=root/'evidence/imk-run'
for name in ['home','tmp']:(temporary/name).mkdir(mode=0o700)
environment={'PATH':'/usr/bin:/bin','HOME':str(temporary/'home'),'TMPDIR':str(temporary/'tmp')+'/','LC_ALL':'en_US.UTF-8'}
executable=copy/'Contents/MacOS/PAIAInputMethod';resources=copy/'Contents/Resources';info=copy/'Contents/Info.plist'
def preflight(label,success,extra=None):
    result=subprocess.run([str(executable),'--preflight'],env=environment|({} if extra is None else extra),capture_output=True,text=True,timeout=180)
    (evidence/('candidate-'+label+'.txt')).write_text(result.stdout+result.stderr)
    if success:
        assert result.returncode==0 and 'IMK_CANDIDATE_STARTUP schemas=32 personal=false mainAttempts=1 deployments=0 privateStores=true' in result.stdout,(label,result.returncode,result.stderr)
        assert 'IMK_BUNDLE_PREFLIGHT' in result.stdout
        print(result.stdout,end='')
    else:
        assert result.returncode!=0 and 'phase=engine-startup mainAttempts=0' in result.stderr,(label,result.returncode,result.stderr)
        assert 'IMK_CANDIDATE_STARTUP' not in result.stdout
    print('CANDIDATE_MOVABLE_'+label.upper()+' '+('PASS clean-env native preflight, original .build absent' if success else 'EXPECTED_REJECTION main_attempts=0'))
try:
    build.rename(held)
    preflight('relocated',True)
    pack=resources/'CandidatePack';pack_held=resources/'held-pack';pack.rename(pack_held)
    try:preflight('missing_pack',False)
    finally:pack_held.rename(pack)
    mapping=pack/'opencc/s2t.json';mapping_bytes=mapping.read_bytes();mapping.unlink()
    try:preflight('missing_conversion',False)
    finally:mapping.write_bytes(mapping_bytes)
    bridge=resources/'Engine/paia-g01.dylib';original=bridge.read_bytes();original_info=info.read_bytes()
    try:
        bridge.write_bytes(bad_bridge)
        altered=plistlib.loads(original_info);altered['PAIACandidateExtensionSHA']=hashlib.sha256(bad_bridge).hexdigest();info.write_bytes(plistlib.dumps(altered))
        preflight('g01_without_mixed',False)
    finally:bridge.write_bytes(original);info.write_bytes(original_info)
    engine=resources/'Engine/librime.1.dylib';engine_held=resources/'Engine/held-engine';engine.rename(engine_held);os.link(engine_held,engine)
    try:preflight('hardlinked_engine',False)
    finally:engine.unlink();engine_held.rename(engine)
    helper=copy/'Contents/MacOS/paia-resources';helper_bytes=helper.read_bytes()
    try:
        helper.write_bytes(helper_bytes[:-1]+bytes([helper_bytes[-1]^1]));preflight('wrong_helper_hash',False)
    finally:helper.write_bytes(helper_bytes)
    # Even an internally consistent unsigned manifest cannot turn swapped
    # double-Pinyin semantics into a qualified resource generation.
    flypy=pack/'build/paia_candidate_flypy.prism.bin';natural=pack/'build/paia_candidate_natural.prism.bin'
    flypy_bytes=flypy.read_bytes();natural_bytes=natural.read_bytes();manifest=pack/'manifest.json';manifest_bytes=manifest.read_bytes()
    try:
        flypy.write_bytes(natural_bytes);natural.write_bytes(flypy_bytes)
        value=json.loads(manifest_bytes)
        for item in value['artifacts']:
            if item['path'] in ['build/paia_candidate_flypy.prism.bin','build/paia_candidate_natural.prism.bin']:
                data=(pack/item['path']).read_bytes();item.update(bytes=len(data),sha256=hashlib.sha256(data).hexdigest())
        changed=json.dumps(value,ensure_ascii=False,sort_keys=True,separators=(',',':')).encode();manifest.write_bytes(changed)
        altered=plistlib.loads(original_info);altered['PAIACandidateManifestSHA']=hashlib.sha256(changed).hexdigest();info.write_bytes(plistlib.dumps(altered))
        preflight('coherent_wrong_prisms',False)
    finally:flypy.write_bytes(flypy_bytes);natural.write_bytes(natural_bytes);manifest.write_bytes(manifest_bytes);info.write_bytes(original_info)
    try:
        altered=plistlib.loads(original_info);del altered['PAIACandidateProfile'];info.write_bytes(plistlib.dumps(altered))
        preflight('missing_profile',False,{'PAIA_IMK_RESEARCH':'1','PAIA_B1_RESEARCH':'1',
            'PAIA_RIME_LIBRARY':str(resources/'Engine/librime.1.dylib'),
            'PAIA_G01_LIBRARY':str(resources/'Engine/paia-g01.dylib'),
            'PAIA_B1_SHARED':str(pack/'templates'),'PAIA_B1_REVISION':'authored-metadata-routing-negative'})
    finally:info.write_bytes(original_info)
    preflight('restored',True)
finally:
    if held.exists():held.rename(build)
    shutil.rmtree(temporary)
assert build.is_dir() and not held.exists()
print('CANDIDATE_MOVABLE_TOTAL native_positive=2 expected_negative=7 installed=false server_started=false')
