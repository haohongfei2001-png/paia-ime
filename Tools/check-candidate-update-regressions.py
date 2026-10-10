#!/usr/bin/env python3
"""Three expected-red source controls; always restore the exact original bytes."""
from pathlib import Path
import subprocess,sys
root=Path(__file__).resolve().parents[1]
controls=[
 ('source-identity','Sources/ResourceCore/CandidateResourceStore.swift','let preset=try policy.admitSourceIdentity(pack) // Before native parsing of the proposed pack.','let preset=CandidatePublicPreset.baseline // Deliberate regression.','CandidateUpdateCoreTests/testIncomingManifestCannotDeclareItsOwnSourceTrust','XCTAssertEqual failed: ("1") is not equal to ("0")'),
 ('unknown-quarantine','Sources/ResourceCore/CandidateResourceStore.swift','try ready();uncertain=true // Irreversible generation publication begins.','try ready();uncertain=false // Deliberate regression.','CandidateUpdateCoreTests/testPublicationFaultsRetainGenerationsAndQuarantineUnknownOutcome','Writer was not quarantined'),
 ('held-lock-identity','Sources/ResourceCore/CandidateCatalogRoot.swift','try Self.privateDirectory(generations);try Self.checkLock(directory,descriptor:lockFD,device:lockDevice,inode:lockInode);try Self.check(ancestors)','try Self.privateDirectory(generations);try Self.check(ancestors) // Deliberate regression.','CandidateUpdateCoreTests/testOpenedCatalogRejectsReplacedGenerationsAndWriterIdentity','XCTAssertThrowsError failed: did not throw error')]
for name,path,protected,mutant,test,expected in controls:
    source=root/path;original=source.read_bytes();text=original.decode();assert text.count(protected)==1
    try:
        source.write_text(text.replace(protected,mutant))
        run=subprocess.run(['swift','test','--filter',test],cwd=root,capture_output=True,text=True,timeout=180)
        output=run.stdout+run.stderr;sys.stdout.write(output)
        assert run.returncode!=0 and expected in output and 'Executed 1 test,' in output,(name,'regression did not produce the required test failure')
    finally:source.write_bytes(original)
    assert source.read_bytes()==original
    print('CANDIDATE_UPDATE_REGRESSION '+name+' expected_red=true exact_source_restored=true')
