#!/usr/bin/env python3
"""Actual candidate executable startup selection; preflight only, no IMKServer."""
from pathlib import Path
import hashlib,subprocess,tempfile
root=Path(__file__).resolve().parents[1];app=root/'.build/PAIAInputMethod.app';evidence=root/'evidence/imk-run'
exe=app/'Contents/MacOS/PAIAInputMethod'
with tempfile.TemporaryDirectory(prefix='paia-update-entry-') as temp:
    home=Path(temp).resolve();(home/'tmp').mkdir()
    env={'PATH':'/usr/bin:/bin','HOME':str(home),'TMPDIR':str(home/'tmp')+'/','LC_ALL':'en_US.UTF-8'}
    for kind,reason,preset in [('data','current','updated'),('fallback','lastGood','baseline'),('semantic','lastGood','baseline'),('both',None,None),('missing_index',None,None)]:
        parent=root/('.build/candidate-update-'+kind)
        authority=parent/'paia-ime'
        def authority_bytes():return {p.relative_to(authority).as_posix():hashlib.sha256(p.read_bytes()).hexdigest() for p in authority.rglob('*') if p.is_file()}
        before=authority_bytes()
        run=subprocess.run([str(exe),'--preflight','--isolated-parent',str(parent)],env=env,capture_output=True,text=True,timeout=240)
        (evidence/('update-entry-'+kind+'.txt')).write_text(run.stdout+run.stderr)
        assert authority_bytes()==before,(kind,'preflight changed established personal/settings/expression files')
        if reason:
            assert run.returncode==0 and f'IMK_CANDIDATE_PUBLIC reason={reason} preset={preset}' in run.stdout,(kind,run.returncode,run.stderr)
            assert 'mainAttempts=1 deployments=0 privateStores=true' in run.stdout
            assert 'IMK_BUNDLE_PREFLIGHT' in run.stdout
            # Images remain in the preserved log; avoid repeating their payload.
            for line in run.stdout.splitlines():
                if line.startswith('IMK_'):print(line)
        else:
            assert run.returncode!=0 and 'phase=engine-startup mainAttempts=0' in run.stderr,(kind,run.returncode,run.stderr)
        print(f'CANDIDATE_UPDATE_ENTRY {kind} '+('native_preflight_pass' if reason else 'expected_refusal_zero_main_entry'))
print('CANDIDATE_UPDATE_ENTRY_TOTAL positive=3 negative=2 server_started=false installed=false')
