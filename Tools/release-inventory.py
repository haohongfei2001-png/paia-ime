#!/usr/bin/env python3
"""Freeze/verify exact previous source, app and XCTest bytes; no installations."""
from pathlib import Path
import hashlib,json,plistlib,subprocess,sys
ROOT=Path(__file__).resolve().parents[1]
N='d2f9d62b3d34dba79e958aa1b42e2437691f8d19'
BASE=ROOT/'.build/release-n-source'
EVIDENCE=ROOT/'evidence/imk-run'
def inventory():
    sources={}
    for row in subprocess.check_output(['git','ls-tree','-rz',N],cwd=ROOT).split(b'\0'):
        if not row:continue
        meta,name=row.split(b'\t',1);mode,kind,expected=meta.decode().split()
        assert mode in ('100644','100755') and kind=='blob',(mode,kind,name)
        path=name.decode();data=(BASE/path).read_bytes()
        actual=hashlib.sha1(b'blob '+str(len(data)).encode()+b'\0'+data).hexdigest()
        assert actual==expected,(path,actual,expected)
        sources[path]={'blob':expected,'sha256':hashlib.sha256(data).hexdigest()}
    binary=Path(subprocess.check_output(['swift','build','--show-bin-path'],cwd=BASE,text=True).strip())
    app=BASE/'.build/PAIAInputMethod.app';tests=binary/'PAIAIMEPackageTests.xctest'
    assert tests.is_dir() and app.is_dir()
    info=plistlib.loads((app/'Contents/Info.plist').read_bytes())
    assert info['CFBundleShortVersionString']=='0.3.0' and info['CFBundleVersion']=='1'
    def hashes(folder):return {p.relative_to(folder).as_posix():hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(folder.rglob('*')) if p.is_file()}
    return {'source':N,'tree':subprocess.check_output(['git','rev-parse',N+'^{tree}'],cwd=ROOT,text=True).strip(),
            'version':info['CFBundleShortVersionString'],'build':info['CFBundleVersion'],
            'sourceFiles':sources,'app':str(app),'testBundle':str(tests),'appFiles':hashes(app),'testFiles':hashes(tests)}
if __name__=='__main__':
    assert len(sys.argv)==2 and sys.argv[1] in ('freeze','verify')
    value=inventory();target=EVIDENCE/'release-n-frozen.json'
    if sys.argv[1]=='freeze':
        assert not target.exists();target.write_text(json.dumps(value,sort_keys=True,indent=2)+'\n')
        testexe=Path(value['testBundle'])/'Contents/MacOS/PAIAIMEPackageTests'
        loads=subprocess.check_output(['otool','-L',str(testexe)],text=True)
        (EVIDENCE/'release-n-test-loads.txt').write_text(loads)
        print(loads,end='')
    else:assert json.loads(target.read_text())==value,'Frozen N changed after qualification'
    print('RELEASE_N_'+sys.argv[1].upper()+' source='+N+' version=0.3.0 build=1 original_source_and_binary_hashes=true')
