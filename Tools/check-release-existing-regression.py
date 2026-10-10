#!/usr/bin/env python3
"""SIMULATED stat/open race; expected red without existing-only create guard.

An already-created empty lock is opened after an injected absent observation.
This reproduces the branch inputs without a flaky timing race or a public test
hook. Every byte of production source is restored even on compiler/test failure.
"""
from pathlib import Path
import subprocess,sys
root=Path(__file__).resolve().parents[1];path=root/'Sources/LexiconCore/LexiconStore.swift'
original=path.read_bytes();source=original.decode()
observation='let hadLock=fstatat(rootFD,".writer.lock",&prior,AT_SYMLINK_NOFOLLOW)==0'
guard='guard allowCreateLock,!hadLock,marker==nil'
assert source.count(observation)==1 and source.count(guard)==1
injected=source.replace(observation,'let hadLock=false // SIMULATED absent stat, subsequently present/opened lock')
def check(label,text,expect_success):
    path.write_text(text)
    p=subprocess.run(['swift','test','--filter','ExistingProductLeaseTests/testExistingOnlyLexiconNeverInitializesEmptyAuthority'],cwd=root,capture_output=True,text=True,timeout=180)
    output=p.stdout+p.stderr;(root/('evidence/imk-run/release-race-'+label+'.txt')).write_text(output)
    print(output,end='');assert (p.returncode==0)==expect_success,(label,p.returncode)
    assert 'Executed 1 test' in output and ('with 0 failures' in output if expect_success else 'XCTAssertThrowsError failed' in output)
try:
    check('protected',injected,True)
    check('expected-red',injected.replace(guard,'guard !hadLock,marker==nil'),False)
finally:path.write_bytes(original)
assert path.read_bytes()==original
print('RELEASE_EXISTING_REGRESSION SIMULATED_STAT_RACE protected_green old_guard_red exact_source_restored=true')
