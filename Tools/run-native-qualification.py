#!/usr/bin/env python3
"""Offline native replay supervisor; never invoked by the input service.

A deadline kills/reaps only this disposable test process. It does not make an
in-process C++ call safely cancellable or permit replaying an unknown commit.
"""
import array,hashlib,json,math,os,re,signal,struct,subprocess,sys,tempfile,time
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'evidence/b1-run/qualification'
MINIMUM=1_000_000
CALIBRATION=10_000
TIMEOUTS={'prepare':240,'startup':30,'calibrate':120,'endurance':1200,'host':120}
SCHEMA_COUNT=32

def sha(data):return hashlib.sha256(data).hexdigest()
def write(path,value):path.write_text(json.dumps(value,ensure_ascii=False,indent=2,sort_keys=True)+'\n')
def inventory(root):
    result={}
    for p in sorted(root.rglob('*')):
        if p.is_symlink():raise RuntimeError('symlink in authored qualification tree')
        if p.is_file():result[p.relative_to(root).as_posix()]={'bytes':p.stat().st_size,'sha256':sha(p.read_bytes())}
    return result
def digest(value):return sha(json.dumps(value,sort_keys=True,separators=(',',':')).encode())
def run(command,log,timeout,env):
    started=time.monotonic_ns()
    with log.open('xb') as output:
        child=subprocess.Popen(command,cwd=ROOT,env=env,stdout=output,stderr=subprocess.STDOUT,start_new_session=True)
        try:code=child.wait(timeout=timeout);timed_out=False
        except subprocess.TimeoutExpired:
            # No graceful retry/replay. This process group owns only test children.
            os.killpg(child.pid,signal.SIGKILL);code=child.wait();timed_out=True
    result={'exitCode':code,'timeout':timed_out,'wallNanoseconds':time.monotonic_ns()-started,'deadlineSeconds':timeout}
    write(log.with_suffix('.process.json'),result)
    if code or timed_out:raise RuntimeError('native child failed or incomplete: '+log.name)
    return result

def summarize(path,report):
    # Parse after child teardown. No million-sample arrays affect its RSS.
    totals=[array.array('Q') for _ in range(3)];counts={1:0,2:0,3:0}
    per={key:[array.array('Q') for _ in range(3)] for key in counts}
    data=path.read_bytes()
    if len(data)%32:raise RuntimeError('truncated timing record')
    for kind,owner,action,copy in struct.iter_unpack('<QQQQ',data):
        if kind not in counts:raise RuntimeError('unknown operation record')
        if owner<action+copy:raise RuntimeError('component exceeds owner timer')
        counts[kind]+=1
        for index,value in enumerate([owner,action,copy]):totals[index].append(value);per[kind][index].append(value)
    if len(totals[0])!=report['operationSamples']:raise RuntimeError('missing completed timing samples')
    if counts!={1:report['operationCounts']['key'],2:report['operationCounts']['selection'],3:report['operationCounts']['clear']}:raise RuntimeError('record operation counts differ')
    def stats(values):
        s=sorted(values)
        return {'samples':len(s),'p50Milliseconds':s[math.ceil(len(s)*.5)-1]/1e6,'p95Milliseconds':s[math.ceil(len(s)*.95)-1]/1e6,'p99Milliseconds':s[math.ceil(len(s)*.99)-1]/1e6,'maxMilliseconds':s[-1]/1e6}
    names=['sessionOwner','nativeAction','CContextCommitCopy']
    result={'samples':len(totals[0]),'timingsSHA256':sha(data),'timingsBytes':len(data),
            'combined':dict(zip(names,map(stats,totals))),
            'byOperation':{str(k):dict(zip(names,map(stats,v))) for k,v in per.items()},
            'failedSamplesRemoved':0,'boundary':'completed authored native operations; any failed attempt fails the run and remains in report/process logs'}
    write(path.with_name('timing-summary.json'),result)
    return result

def host_receipt(text):
    rows=re.findall(r"APPKIT_HOST qualification episodes=(\d+) insertCalls=(\d+); real production controller and NSTextView-backed authored IMK client; installed=false",text)
    if rows != [("32","128")]:raise RuntimeError("missing, duplicated or incomplete actual host receipt")
    return {"evidence":"APPKIT_HOST","authoredEpisodes":int(rows[0][0]),"insertCalls":int(rows[0][1]),"framework":"actual IMKControllerDriver + NSTextView-backed protocol client; no IMKServer"}

def main():
    if os.environ.get('PAIA_B1_RESEARCH')!='1':raise RuntimeError('explicit research mode required')
    OUT.mkdir(parents=True,exist_ok=False)
    scratch=Path(tempfile.mkdtemp(prefix='paia-qualification-'))
    binary=ROOT/'.build/release/paia-qualification';env=os.environ.copy()
    source=Path(env['PAIA_B1_SHARED'])
    source_before=inventory(source);write(OUT/'research-input-inventory.json',source_before)
    lock=json.loads((ROOT/'Resources/A2/upstream-lock.json').read_text())
    write(OUT/'contract.json',{'sourceSHA':env.get('PAIA_SOURCE_SHA'),'corpusRows':lock['totalDefaultChineseDictionaryRows'],
        'sourceLockSHA256':sha((ROOT/'Resources/A2/upstream-lock.json').read_bytes()),'librarySHA256':sha(Path(env['PAIA_RIME_LIBRARY']).read_bytes()),
        'researchInputSHA256':digest(source_before),'requestedNativeOperations':MINIMUM,'calibrationNativeOperations':CALIBRATION,
        'deadlinesSeconds':TIMEOUTS,'seed':str(0x5041494132303236),'scope':'repeatable authored endurance, not one million distinct language tasks',
        'resourceRights':'research only, not cleared production corpus redistribution',
        'artifactContents':'authored receipts, metadata, all completed timing records, logs; no corpus or engine binaries'})
    def child(mode,name,shared):
        user=scratch/(name+'-user');user.mkdir();before=inventory(user)
        write(OUT/(name+'-user-before.json'),before)
        try:
            process=run([str(binary),mode,str(shared),str(user),str(OUT/name)],OUT/(name+'.log'),TIMEOUTS[mode],env)
        finally:
            after=inventory(user);write(OUT/(name+'-user-after.json'),after)
        if any('userdb' in n.lower() for n in after):raise RuntimeError('unexpected user dictionary persisted')
        report=json.loads((OUT/name/'report.json').read_text())
        if not report['complete']:raise RuntimeError('incomplete native receipt: '+name)
        return user,report,process
    user,prepared,_=child('prepare','deployment',source)
    if len(prepared['schemas'])!=SCHEMA_COUNT:raise RuntimeError('missing schema deployments')
    pack=scratch/'precompiled';pack.mkdir();(pack/'build').mkdir();(pack/'opencc').mkdir()
    # Source copies come from the already verified immutable preparation. Only
    # declared compiled outputs are used by every fresh measured child.
    (pack/'default.yaml').write_bytes((source/'default.yaml').read_bytes())
    for p in (source/'opencc').iterdir():
        if not p.is_file() or p.is_symlink():raise RuntimeError('unexpected OpenCC source entry')
        (pack/'opencc'/p.name).write_bytes(p.read_bytes())
    build=user/'build'
    for p in build.iterdir():
        if not p.is_file() or p.is_symlink() or not p.stat().st_size:raise RuntimeError('invalid compiled artifact')
        (pack/'build'/p.name).write_bytes(p.read_bytes())
    for schema in prepared['schemas']:
        p=pack/'build'/(schema+'.schema.yaml')
        if not p.is_file() or 'enable_user_dict: false' not in p.read_text():raise RuntimeError('missing compiled schema or learning disabled declaration')
    if not any((pack/'build').glob('*.table.bin')) or not any((pack/'build').glob('*.prism.bin')):raise RuntimeError('compiled dictionary absent')
    expected=inventory(pack);write(OUT/'precompiled-inventory.json',expected)
    env['PAIA_QUALIFICATION_PACK_SHA']=digest(expected)
    for index in range(3):
        if inventory(pack)!=expected:raise RuntimeError('precompiled authority changed before startup')
        child('startup','startup-'+str(index+1),pack)
        if inventory(pack)!=expected:raise RuntimeError('precompiled authority changed after startup')
    summary={}
    for mode,minimum in [('calibrate',CALIBRATION),('endurance',MINIMUM)]:
        if inventory(pack)!=expected:raise RuntimeError('precompiled authority changed before replay')
        _,report,process=child(mode,mode,pack)
        if report['operationSamples']<minimum or report['requestedMinimumNativeInputOperations']!=minimum:raise RuntimeError('million denominator not completed')
        if inventory(pack)!=expected:raise RuntimeError('precompiled authority changed after replay')
        if (OUT/mode/'diagnostics-before.json').read_bytes()!=(OUT/mode/'diagnostics-after.json').read_bytes():raise RuntimeError('native candidate drift')
        timing=summarize(OUT/mode/'timings.bin',report)
        summary[mode]={'nativeOperations':report['operationSamples'],'episodes':report['episodes'],'process':process,'timing':timing,'RSS':report['rssCheckpoints']}
        if mode=='calibrate':
            # Estimate is disclosed, never used to reduce the full denominator.
            summary[mode]['linearMillionSecondsEstimate']=report['workloadWallNanoseconds']/1e9*MINIMUM/report['operationSamples']
        write(OUT/'summary.json',{'complete':False,'checkpoints':summary})
    if inventory(source)!=source_before:raise RuntimeError('original research inputs changed')
    env['PAIA_QUALIFICATION_SHARED']=str(pack);env['PAIA_QUALIFICATION_HOST_USER']=str(scratch/'host-user');Path(env['PAIA_QUALIFICATION_HOST_USER']).mkdir()
    try:
        run(['swift','test','--skip-build','--filter','QualificationHostTests'],OUT/'host.log',TIMEOUTS['host'],env)
    finally:write(OUT/'host-user-after.json',inventory(Path(env['PAIA_QUALIFICATION_HOST_USER'])))
    if any('userdb' in n.lower() for n in inventory(Path(env['PAIA_QUALIFICATION_HOST_USER']))):raise RuntimeError('host persisted user dictionary')
    if inventory(pack)!=expected:raise RuntimeError('host changed precompiled authority')
    summary['host']=host_receipt((OUT/'host.log').read_text())
    write(OUT/'summary.json',{'complete':True,'evidence':'ENGINE_NATIVE + separate APPKIT_HOST','checkpoints':summary,
        'millionGate':'completed seeded native replay only','unverified':['installed IME','visible latency','M1 budget','8h continuous','500h real use','language quality','production resource rights']})
    print('Native qualification complete: '+str(summary['endurance']['nativeOperations'])+' actual native input operations; bounded host subset separate.')
if __name__=='__main__':
    try:main()
    except Exception as error:
        if OUT.exists():write(OUT/'supervisor-failure.json',{'complete':False,'failure':str(error),'requestedNativeOperations':MINIMUM})
        print('Qualification failed or incomplete: '+str(error),file=sys.stderr);sys.exit(1)
