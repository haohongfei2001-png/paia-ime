#!/usr/bin/env python3
"""Only the new catalog key remains: missing its dispatch guard must be red."""
from pathlib import Path
import subprocess,sys
root=Path(__file__).resolve().parents[1];source=root/'Sources/IMKHost/IMKServiceEnvironment.swift';original=source.read_bytes();text=original.decode()
protected='"PAIACandidateManifestSHA","PAIACandidateExtensionSHA","PAIACandidateResourceCatalog"]'
assert text.count(protected)==1
try:
    source.write_text(text.replace(protected,'"PAIACandidateManifestSHA","PAIACandidateExtensionSHA"]'))
    run=subprocess.run(['swift','test','--filter','ProductCandidateTests/testCandidateCatalogOnlyMetadataNeverEntersResearchLane'],cwd=root,capture_output=True,text=True,timeout=180)
    output=run.stdout+run.stderr;sys.stdout.write(output)
    assert run.returncode!=0 and 'XCTAssertEqual failed: ("1") is not equal to ("0")' in output,'missing catalog dispatch did not reach the required native entry'
finally:source.write_bytes(original)
assert source.read_bytes()==original
print('CANDIDATE_CATALOG_ROUTING_REGRESSION expected_red_main_attempts=1 exact_source_restored=true')
