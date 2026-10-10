#!/usr/bin/env python3
"""Actual frozen N / N+1 executable and authored-data compatibility qualification.

Direct XCTest loads the frozen original N production modules and original test,
never the current source. App startup evidence is separately labelled. No
installed service, signed update, user profile or production corpus is involved.
"""
from pathlib import Path
import fcntl,hashlib,json,os,plistlib,shutil,stat,subprocess,tempfile
ROOT=Path(__file__).resolve().parents[1];E=ROOT/'evidence/imk-run'
BASE=json.loads((E/'release-n-frozen.json').read_text())
APP=ROOT/'.build/PAIAInputMethod.app'
TESTS=Path(subprocess.check_output(['swift','build','--show-bin-path'],cwd=ROOT,text=True).strip())/'PAIAIMEPackageTests.xctest'
NAPP=Path(BASE['app']);NTESTS=Path(BASE['testBundle'])
assert plistlib.loads((APP/'Contents/Info.plist').read_bytes())['CFBundleShortVersionString']=='0.3.1'
XCTEST=subprocess.check_output(['xcrun','--find','xctest'],text=True).strip()
PLATFORM=Path(subprocess.check_output(['xcrun','--sdk','macosx','--show-sdk-platform-path'],text=True).strip())
# Match SwiftPM's macOS TestingSupport environment, only for XCTest. These are
# official SDK paths, never current/frozen package libraries mixed together.
TEST_ENV={'DYLD_FRAMEWORK_PATH':':'.join(str(PLATFORM/'Developer/Library'/name) for name in ['Frameworks','PrivateFrameworks']),
          'DYLD_LIBRARY_PATH':str(PLATFORM/'Developer/usr/lib'),'SWIFT_TESTING_ENABLED':'0','NO_COLOR':'1'}
(E/'release-test-runner.json').write_text(json.dumps({'runner':XCTEST,'environment':TEST_ENV},sort_keys=True,indent=2)+'\n')
WORK=ROOT/'.build/release-compatibility-data';WORK.mkdir(mode=0o700)
totals={'frozenNHost':0,'nextHost':0,'frozenNApp':0,'explicitNextSave':0,'positiveChecks':0,'negativeChecks':0}
def canonical(value):return json.dumps(value,ensure_ascii=False,sort_keys=True,separators=(',',':')).encode()
def sha(data):return hashlib.sha256(data).hexdigest()
def tree(parent):
    result={}
    def walk(p):
        s=p.lstat();key=p.relative_to(parent).as_posix()
        result[key]={'identity':[s.st_dev,s.st_ino,s.st_mode,s.st_nlink]}
        if stat.S_ISLNK(s.st_mode):result[key]['link']=os.readlink(p)
        elif stat.S_ISREG(s.st_mode):result[key]['sha256']=sha(p.read_bytes())
        elif stat.S_ISDIR(s.st_mode):
            for child in sorted(p.iterdir()):walk(child)
        else:raise AssertionError('Unexpected authored fixture node')
    walk(parent);return result
def record(label,parent,before):
    after=tree(parent);(E/('release-'+label+'-authority.json')).write_text(json.dumps(after,sort_keys=True,indent=2)+'\n')
    assert after==before,(label,'authority bytes, links or identities changed')
def run(label,args,env,ok=True):
    try:p=subprocess.run([str(a) for a in args],env=env,cwd=ROOT,capture_output=True,text=True,timeout=300)
    except subprocess.TimeoutExpired as error:
        (E/('release-'+label+'.txt')).write_bytes((error.stdout or b'')+(error.stderr or b'')+b'\nQUALIFICATION_TIMEOUT\n');raise
    (E/('release-'+label+'.txt')).write_text(p.stdout+p.stderr)
    print('RELEASE_COMMAND '+label+' exit='+str(p.returncode),flush=True);print(p.stdout+p.stderr,end='',flush=True)
    assert (p.returncode==0)==ok,(label,p.returncode)
    return p
def stage(label,parent,version,stage,env,unchanged=False):
    before=tree(parent)
    tests=NTESTS if version=='N' else TESTS;app=NAPP if version=='N' else APP
    testenv=dict(env,**TEST_ENV,PAIA_CANDIDATE_BUNDLE=str(app),PAIA_PRODUCT_PARENT=str(parent),PAIA_PRODUCT_STAGE=stage)
    p=run(label,[XCTEST,'-XCTest','ProductCandidateTests.ProductCandidateTests/testSaveRestartDeleteAndNativeOwnerStage',tests],testenv)
    assert 'Executed 1 test, with 0 failures' in p.stdout+p.stderr
    assert f'PRODUCT_RESTART_STAGE {stage} ENGINE_NATIVE + APPKIT_HOST main_attempts=1 deployments=0' in p.stdout
    if unchanged:record(label,parent,before)
    totals['frozenNHost' if version=='N' else 'nextHost']+=1
    print('RELEASE_FROZEN_HOST '+label+' version='+version+' original_test_bundle='+str(version=='N').lower(),flush=True)
def advance(label,parent,env):
    p=run(label,[XCTEST,'-XCTest','ReleaseCompatibilityTests.ExplicitCompatibleSaveTests/testAdvanceExistingSettingsRevisionWithoutChangingFormatContract',TESTS],dict(env,**TEST_ENV,PAIA_RELEASE_PARENT=str(parent)))
    assert 'Executed 1 test, with 0 failures' in p.stdout+p.stderr and 'RELEASE_EXPLICIT_SAVE SIMULATED production_store' in p.stdout
    totals['explicitNextSave']+=1
def compat(label,parent,env,reason='bundled',ok=True,args=None):
    before=tree(parent)
    p=run(label,[APP/'Contents/MacOS/PAIAInputMethod']+(args if args is not None else ['--compatibility-check','--isolated-parent',str(parent)]),env,ok)
    record(label,parent,before)
    if ok:
        receipt=json.loads(p.stdout)
        assert receipt['format']==1 and receipt['mainAttempts']==0 and receipt['authorityBytesChanged'] is False
        assert receipt['releaseVersion']=='0.3.1' and receipt['releaseBuild']=='2' and receipt['qualificationBaselineSource']==BASE['source']
        assert receipt['selectionReason']==reason and len(receipt['stores'])==3
        print('RELEASE_COMPATIBILITY '+label+' success main_attempts=0 authority_unchanged=true',flush=True)
        totals['positiveChecks']+=1
        return receipt
    assert 'IMK_COMPATIBILITY_FAILURE' in p.stderr and 'mainAttempts=0' in p.stderr
    print('RELEASE_COMPATIBILITY '+label+' expected_refusal main_attempts=0 authority_unchanged=true',flush=True)
    totals['negativeChecks']+=1
def preflight(label,parent,env,personal=True,reason='bundled',preset='baseline',reference=None):
    before=tree(parent);p=run(label,[NAPP/'Contents/MacOS/PAIAInputMethod','--preflight','--isolated-parent',parent],env)
    assert 'IMK_BUNDLE_PREFLIGHT' in p.stdout and 'mainAttempts=1 deployments=0 privateStores=true' in p.stdout
    assert 'IMK_CANDIDATE_STARTUP schemas=32 personal='+str(personal).lower()+' mainAttempts=1' in p.stdout
    assert f'IMK_CANDIDATE_PUBLIC reason={reason} preset={preset} generation=' in p.stdout
    if reference:assert f'IMK_CANDIDATE_PUBLIC reason={reason} preset={preset} generation='+reference['generation'] in p.stdout
    record(label,parent,before);print('RELEASE_FROZEN_APP '+label+' native_preflight=true installed=false',flush=True)
    totals['frozenNApp']+=1
def copy_parent(source,name):
    result=WORK/name;shutil.copytree(source,result,symlinks=True);return result
def publish(label,parent,preset,revision,mode,env):
    run(label,[APP/'Contents/MacOS/paia-resources','candidate-publish',preset,str(revision),mode,parent],env)
try:
    with tempfile.TemporaryDirectory(prefix='paia-release-home-') as temporary:
        home=Path(temporary).resolve();(home/'tmp').mkdir()
        env={'PATH':'/usr/bin:/bin','HOME':str(home),'TMPDIR':str(home/'tmp')+'/','LC_ALL':'en_US.UTF-8'}
        # N creates the actual root/empty stores; N+1 makes the explicit saves.
        first=WORK/'new-saves';first.mkdir(mode=0o700)
        stage('n-public',first,'N','public',env)
        empty=compat('never-saved',first,env)
        assert [x.get('revision') for x in empty['stores']]==[None,0,None]
        stage('next-save',first,'next','save',env)
        saved=compat('next-saves',first,env)
        assert [x.get('revision') for x in saved['stores']]==[1,2,1]
        preflight('n-app-new-saves',first,env);stage('n-host-new-saves',first,'N','restore',env,True)
        healthy=copy_parent(first,'healthy-template')
        stage('next-delete',first,'next','delete',env)
        compat('next-tombstones',first,env)
        preflight('n-app-tombstones',first,env,personal=False);stage('n-host-tombstones',first,'N','deleted',env,True)
        # Established original N data, then an explicit N+1 settings save.
        established=WORK/'established';established.mkdir(mode=0o700)
        stage('n-original-save',established,'N','save',env)
        advance('next-established-save',established,env)
        stage('n-host-established',established,'N','restore',env,True)
        # Explicitly synthetic historical v1 bytes. N did NOT produce this v1.
        legacy=copy_parent(healthy,'authored-legacy');settings=legacy/'paia-ime/settings/settings.json'
        document={'revision':7,'values':{'spelling':'flypy','traditional':True,'literal':False,'chinesePunctuation':True}}
        settings.write_bytes(canonical({'format':'paia.settings.v1','sha256':sha(canonical(document)),'document':document}))
        receipt=compat('authored-v1',legacy,env);assert receipt['stores'][0]['storedFormat']=='paia.settings.v1'
        advance('next-v1-explicit-save',legacy,env)
        migrated=json.loads(settings.read_bytes());assert migrated['format']=='paia.settings.v2' and migrated['document']['revision']==8
        # Original N's restore oracle expects this application preference. The
        # historical v1 cannot express it, so use N's actual app preflight here;
        # the separate old host checks above cover complete current v2 values.
        preflight('n-app-authored-v1-upgraded',legacy,env)
        # Shared public source contract across the two actual software builds.
        public=copy_parent(healthy,'public-update')
        publish('public-baseline',public,'baseline',0,'create',env)
        publish('public-updated',public,'updated',1,'existing',env)
        current=compat('public-current',public,env,'current');preflight('n-app-public-current',public,env,reason='current',preset='updated',reference=current['publicReference'])
        fallback=copy_parent(public,'public-fallback')
        run('damage-current',['python3',ROOT/'Tools/prepare-candidate-update-fault.py',fallback,'fallback'],dict(env,PATH=os.environ['PATH']))
        previous=compat('public-fallback',fallback,env,'lastGood');preflight('n-app-public-fallback',fallback,env,reason='lastGood',preset='baseline',reference=previous['publicReference'])
        # Every negative retains the complete authored authority tree, including
        # inode/mode/link identity. No acceptance through the fail-soft N entry.
        negatives=['missing-root','missing-slot','missing-root-lock','missing-settings-lock','missing-personal-marker','missing-expression-marker',
                   'future-settings','future-personal','future-expressions','corrupt-settings','interrupted-marker','symlink-slot','hardlink-settings','future-public-contract','both-public-bad']
        for kind in negatives:
            parent=copy_parent(public if kind in ('future-public-contract','both-public-bad') else healthy,kind)
            product=parent/'paia-ime'
            removals={'missing-slot':'settings/.slot','missing-root-lock':'.product.lock','missing-settings-lock':'settings/.writer.lock',
                      'missing-personal-marker':'personal/.initialized','missing-expression-marker':'expressions/.initialized','interrupted-marker':'settings/settings.json'}
            if kind=='missing-root':shutil.rmtree(product)
            elif kind in removals:(product/removals[kind]).unlink()
            elif kind.startswith('future-') and kind!='future-public-contract':
                slot=kind.removeprefix('future-');name={'settings':'settings','personal':'lexicon','expressions':'expressions'}[slot]
                path=product/slot/(name+'.json');value=json.loads(path.read_bytes());value['format']='paia.authored.future.v99';path.write_bytes(canonical(value))
            elif kind=='corrupt-settings':(product/'settings/settings.json').write_bytes(b'AUTHORED corrupt settings')
            elif kind=='symlink-slot':
                (product/'settings').rename(parent/'authored-settings-target');(product/'settings').symlink_to(parent/'authored-settings-target',target_is_directory=True)
            elif kind=='hardlink-settings':os.link(product/'settings/settings.json',parent/'authored-extra-link')
            elif kind=='future-public-contract':
                path=parent/'paia-ime-public-resources/index.json';value=json.loads(path.read_bytes());value['sourceContract']='0'*64;path.write_bytes(canonical(value))
            elif kind=='both-public-bad':run('damage-both',['python3',ROOT/'Tools/prepare-candidate-update-fault.py',parent,'both'],dict(env,PATH=os.environ['PATH']))
            else:raise AssertionError(kind)
            compat('negative-'+kind,parent,env,ok=False)
        for name,lock in [('product','paia-ime/.product.lock'),('public','paia-ime-public-resources/.writer.lock')]:
            with (public/lock).open('r+b') as held:
                fcntl.flock(held,fcntl.LOCK_EX|fcntl.LOCK_NB);compat('competing-'+name,public,env,ok=False)
        for index,args in enumerate([['--compatibility-check'],['--compatibility-check','--isolated-parent','relative'],['--compatibility-check=true'],['--compatibility-check','--preflight']]):
            compat('bad-arguments-'+str(index),healthy,env,ok=False,args=args)
        assert totals=={'frozenNHost':5,'nextHost':2,'frozenNApp':5,'explicitNextSave':2,'positiveChecks':6,'negativeChecks':21},totals
        (E/'release-summary.json').write_text(json.dumps(totals,sort_keys=True,indent=2)+'\n')
        print('RELEASE_COMPATIBILITY_TOTAL '+canonical(totals).decode()+' installed=false signed_update=false',flush=True)
finally:
    # Always preserve the identity comparison, including after failed stages.
    subprocess.run(['python3',str(ROOT/'Tools/release-inventory.py'),'verify'],cwd=ROOT,check=True)
