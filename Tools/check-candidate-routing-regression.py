#!/usr/bin/env python3
"""Prove missing metadata cannot silently select an explicit research lane."""
from pathlib import Path
import subprocess,sys
root=Path(__file__).resolve().parents[1]
source=root/'Sources/IMKHost/IMKServiceEnvironment.swift';original=source.read_bytes()
text=original.decode()
protected='if applicationBundle.bundleIdentifier=="dev.paia.ime.candidate" || candidateMarkers.contains(where:{applicationBundle.object(forInfoDictionaryKey:$0) != nil}) {'
assert text.count(protected)==1
try:
    source.write_text(text.replace(protected,'if applicationBundle.object(forInfoDictionaryKey:"PAIACandidateProfile") != nil {'))
    result=subprocess.run(['swift','test','--filter','ProductCandidateTests/testMissingCandidateMetadataCannotEnterResearchLane'],cwd=root,capture_output=True,text=True,timeout=180)
    sys.stdout.write(result.stdout);sys.stdout.write(result.stderr)
    output=result.stdout+result.stderr
    assert result.returncode!=0 and 'XCTAssertEqual failed: ("1") is not equal to ("0")' in output,'unprotected metadata dispatch did not reach native entry as expected'
finally:
    source.write_bytes(original)
assert source.read_bytes()==original
print('CANDIDATE_ROUTING_REGRESSION expected red at native entry count=1; exact source restored')
