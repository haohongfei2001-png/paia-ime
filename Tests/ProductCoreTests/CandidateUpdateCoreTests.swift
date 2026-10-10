import XCTest
import Foundation
import Darwin
import ResourceCore

// SIMULATED bytes/transactions only; no engine or installed-resource claims.
final class CandidateUpdateCoreTests:XCTestCase {
    func scratch()throws->URL {
        let value=FileManager.default.temporaryDirectory.appendingPathComponent("paia-candidate-update-test-"+UUID().uuidString.lowercased())
        try FileManager.default.createDirectory(at:value,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
        guard let path=realpath(value.path,nil) else{throw ResourceError.io};defer{free(path)}
        let result=URL(fileURLWithPath:String(cString:path),isDirectory:true)
        addTeardownBlock{try? FileManager.default.removeItem(at:result)};return result
    }
    func pack(inputs:[String:Data]?=nil,personal:CandidatePersonalBinding?=nil)throws->VerifiedCandidatePack {
        var sources=inputs ?? Dictionary(uniqueKeysWithValues:CandidateContract.sourcePaths.map{($0,Data(("SIMULATED "+$0).utf8))})
        if inputs==nil {
            let rows=["呢\tni\t900"]+(0..<45).map{"模拟\($0)\tsim \($0)\t1"}
            sources["templates/paia_candidate.dict.yaml"]=Data(("# SIMULATED source identity only\n...\n"+rows.joined(separator:"\n")+"\n").utf8)
        }
        var artifacts=Dictionary(uniqueKeysWithValues:(CandidateContract.publicArtifacts+(personal?.extraArtifacts ?? [])).map{($0,Data(("SIMULATED "+$0).utf8))})
        artifacts["default.yaml"]=sources["templates/default.yaml"]
        for name in CandidateContract.opencc{artifacts["opencc/"+name]=sources["opencc/"+name]}
        let manifest=try CandidateManifest(generation:UUID().uuidString.lowercased(),inputs:sources,artifacts:artifacts,personal:personal)
        let directory=try ResourceDirectory(scratch())
        try VerifiedCandidatePack.write(manifest:manifest,files:sources.merging(artifacts){_,b in b},to:directory)
        return try VerifiedCandidatePack(directory:directory,expected:manifest.reference,personal:personal)
    }
    func policy(_ base:VerifiedCandidatePack)throws->CandidateSourcePolicy {try CandidateSourcePolicy(bundle:base,expectedBundle:base.reference)}
    func inspect(_ snapshot:CandidateResourceSnapshot,_ preset:CandidatePublicPreset)throws {try snapshot.verify()}
    func damage(_ directory:URL,_ reference:ResourceReference)throws {
        try Data("SIMULATED broken public binary".utf8).write(to:directory.appendingPathComponent("generations/"+reference.generation+"/build/paia_candidate.table.bin"))
    }
    func testIncomingManifestCannotDeclareItsOwnSourceTrust()throws {
        let base=try pack(),policy=try policy(base),updated=try pack(inputs:policy.sources(.updated))
        XCTAssertEqual(try policy.admitSourceIdentity(base),.baseline);XCTAssertEqual(try policy.admitSourceIdentity(updated),.updated)
        XCTAssertEqual(policy.contractSHA,base.manifest.dictionaryRevision)
        XCTAssertNotEqual(try policy.inputsSHA(.baseline),try policy.inputsSHA(.updated))
        let changed=CandidateContract.sourcePaths.filter{policy.sources(.baseline)[$0] != policy.sources(.updated)[$0]}
        XCTAssertEqual(changed,["templates/paia_candidate.dict.yaml"])
        var unknown=policy.sources(.baseline);unknown["templates/paia_candidate.dict.yaml"]!.append(Data("陌生来源\tmo sheng lai yuan\t1\n".utf8))
        let unapproved=try pack(inputs:unknown),directory=try scratch().appendingPathComponent("catalog")
        let store=try CandidateResourceStore(directory:directory,policy:policy,create:true);defer{store.close()}
        var probes=0
        XCTAssertThrowsError(try store.publish(unapproved,expectedRevision:0,probe:{_,_ in probes+=1}))
        XCTAssertEqual(probes,0);XCTAssertFalse(FileManager.default.fileExists(atPath:directory.appendingPathComponent("index.json").path))
        let binding=try CandidatePersonalBinding(base:base.reference,authoritySHA:String(repeating:"a",count:64),revision:1,tiers:["pin"])
        let personal=try pack(inputs:policy.sources(.baseline),personal:binding)
        XCTAssertThrowsError(try policy.admitSourceIdentity(personal));XCTAssertThrowsError(try store.publish(personal,expectedRevision:0,probe:{_,_ in probes+=1}))
        XCTAssertEqual(probes,0)
    }
    func testPublicationRecordsVerifiedFallbackInsteadOfCorruptCurrent()throws {
        let base=try pack(),policy=try policy(base),updated=try pack(inputs:policy.sources(.updated))
        let directory=try scratch().appendingPathComponent("catalog"),store=try CandidateResourceStore(directory:directory,policy:policy,create:true);defer{store.close()}
        _=try store.publish(base,expectedRevision:0,probe:inspect)
        let second=try store.publish(updated,expectedRevision:1,probe:inspect)
        XCTAssertEqual(second.index.lastGood,base.reference)
        try damage(directory,updated.reference)
        let catalog=try CandidateResourceCatalog(directory:directory,policy:policy),selected=try catalog.select(probe:inspect);defer{selected.snapshot.close()}
        XCTAssertEqual(selected.reason,.lastGood);XCTAssertEqual(selected.preset,.baseline)
        let next=try pack(inputs:policy.sources(.updated)),third=try store.publish(next,expectedRevision:2,probe:inspect)
        XCTAssertEqual(third.index.current,next.reference);XCTAssertEqual(third.index.lastGood,base.reference)
        XCTAssertNotEqual(third.index.lastGood,updated.reference)
    }
    func testUnknownCrossVersionAndCorruptIndexesNeverScanGenerations()throws {
        let base=try pack(),policy=try policy(base),directory=try scratch().appendingPathComponent("catalog")
        let store=try CandidateResourceStore(directory:directory,policy:policy,create:true)
        _=try store.publish(base,expectedRevision:0,probe:inspect);store.close()
        let path=directory.appendingPathComponent("index.json"),original=try Data(contentsOf:path)
        let object=try XCTUnwrap(JSONSerialization.jsonObject(with:original) as? [String:Any])
        for kind in 0..<4 {
            var value=object
            if kind==0{value["unknown"]=true}
            if kind==1{value["format"]=1}
            if kind==2{value["sourceContract"]=String(repeating:"f",count:64)}
            let bytes=kind==3 ? Data("broken authored index".utf8):try JSONSerialization.data(withJSONObject:value,options:[.sortedKeys,.withoutEscapingSlashes])
            try bytes.write(to:path)
            let catalog=try CandidateResourceCatalog(directory:directory,policy:policy)
            var probes=0;XCTAssertThrowsError(try catalog.select(probe:{_,_ in probes+=1}));XCTAssertEqual(probes,0)
            XCTAssertThrowsError(try CandidateResourceStore(directory:directory,policy:policy))
            XCTAssertEqual(try Data(contentsOf:path),bytes)
        }
    }
    func testMissingLockOrIndexCannotBeRecreatedOnEstablishedRoot()throws {
        for name in [".writer.lock","index.json"] {
            let base=try pack(),policy=try policy(base),directory=try scratch().appendingPathComponent("catalog")
            let store=try CandidateResourceStore(directory:directory,policy:policy,create:true)
            _=try store.publish(base,expectedRevision:0,probe:inspect);store.close()
            let path=directory.appendingPathComponent(name);try FileManager.default.removeItem(at:path)
            XCTAssertThrowsError(try CandidateResourceStore(directory:directory,policy:policy))
            XCTAssertThrowsError(try CandidateResourceCatalog(directory:directory,policy:policy).select(probe:inspect))
            XCTAssertFalse(FileManager.default.fileExists(atPath:path.path))
        }
    }
    func testUnpublishedRootReopenAndWrongRevisionFailClosed()throws {
        let base=try pack(),policy=try policy(base),directory=try scratch().appendingPathComponent("catalog")
        let store=try CandidateResourceStore(directory:directory,policy:policy,create:true)
        XCTAssertThrowsError(try store.publish(base,expectedRevision:1,probe:inspect));store.close()
        let format=try Data(contentsOf:directory.appendingPathComponent(".format"))
        XCTAssertThrowsError(try CandidateResourceStore(directory:directory,policy:policy))
        XCTAssertThrowsError(try CandidateResourceStore(directory:directory,policy:policy,create:true))
        XCTAssertEqual(try Data(contentsOf:directory.appendingPathComponent(".format")),format)
        XCTAssertFalse(FileManager.default.fileExists(atPath:directory.appendingPathComponent("index.json").path))
    }
    func testPublicationFaultsRetainGenerationsAndQuarantineUnknownOutcome()throws {
        for fault in [ResourcePublicationFault.beforeGenerationRename,.afterGenerationRename,.beforeIndexRename,.afterIndexRename] {
            let base=try pack(),policy=try policy(base),updated=try pack(inputs:policy.sources(.updated)),directory=try scratch().appendingPathComponent("catalog")
            let first=try CandidateResourceStore(directory:directory,policy:policy,create:true);_=try first.publish(base,expectedRevision:0,probe:inspect);first.close()
            let old=try Data(contentsOf:directory.appendingPathComponent("index.json"))
            let writer=try CandidateResourceStore(directory:directory,policy:policy,fault:fault);defer{writer.close()}
            XCTAssertThrowsError(try writer.publish(updated,expectedRevision:1,probe:inspect))
            let catalog=try CandidateResourceCatalog(directory:directory,policy:policy),selected=try catalog.select(probe:inspect);defer{selected.snapshot.close()}
            if fault == .afterIndexRename {
                XCTAssertEqual(selected.snapshot.pack.reference,updated.reference)
                XCTAssertThrowsError(try writer.publish(base,expectedRevision:2,probe:inspect))
            } else {
                XCTAssertEqual(try Data(contentsOf:directory.appendingPathComponent("index.json")),old)
                XCTAssertEqual(selected.snapshot.pack.reference,base.reference)
            }
            XCTAssertTrue(FileManager.default.fileExists(atPath:directory.appendingPathComponent("generations/"+base.reference.generation).path))
            if fault != .beforeGenerationRename{
                XCTAssertTrue(FileManager.default.fileExists(atPath:directory.appendingPathComponent("generations/"+updated.reference.generation).path))
                XCTAssertThrowsError(try writer.publish(base,expectedRevision:1,probe:inspect)){error in if case ResourceError.durabilityUnknown=error{}else{XCTFail("Writer was not quarantined: \(error)")}}
            }
        }
    }
    func testFirstPublicationFaultNeverRecreatesUnknownEmptyAuthority()throws {
        for fault in [ResourcePublicationFault.beforeGenerationRename,.afterGenerationRename,.beforeIndexRename,.afterIndexRename] {
            let base=try pack(),policy=try policy(base),directory=try scratch().appendingPathComponent("catalog")
            let writer=try CandidateResourceStore(directory:directory,policy:policy,create:true,fault:fault)
            XCTAssertThrowsError(try writer.publish(base,expectedRevision:0,probe:inspect))
            if fault != .beforeGenerationRename {
                XCTAssertThrowsError(try writer.publish(base,expectedRevision:0,probe:inspect)){error in if case ResourceError.durabilityUnknown=error{}else{XCTFail("Unknown first publication was retried")}}
            }
            writer.close()
            let catalog=try CandidateResourceCatalog(directory:directory,policy:policy)
            if fault == .afterIndexRename {
                let reopened=try CandidateResourceStore(directory:directory,policy:policy);defer{reopened.close()}
                let selected=try catalog.select(probe:inspect);defer{selected.snapshot.close()};XCTAssertEqual(selected.snapshot.pack.reference,base.reference)
            } else {
                XCTAssertThrowsError(try catalog.select(probe:inspect));XCTAssertThrowsError(try CandidateResourceStore(directory:directory,policy:policy))
                XCTAssertFalse(FileManager.default.fileExists(atPath:directory.appendingPathComponent("index.json").path))
            }
        }
    }
    func testSecondWriterAndActivePrivateSnapshotRemainIsolated()throws {
        let base=try pack(),policy=try policy(base),updated=try pack(inputs:policy.sources(.updated)),directory=try scratch().appendingPathComponent("catalog")
        let store=try CandidateResourceStore(directory:directory,policy:policy,create:true);defer{store.close()}
        _=try store.publish(base,expectedRevision:0,probe:inspect)
        XCTAssertThrowsError(try CandidateResourceStore(directory:directory,policy:policy))
        let catalog=try CandidateResourceCatalog(directory:directory,policy:policy),old=try catalog.select(probe:inspect);defer{old.snapshot.close()}
        _=try store.publish(updated,expectedRevision:1,probe:inspect)
        XCTAssertEqual(old.snapshot.pack.reference,base.reference);XCTAssertNoThrow(try old.snapshot.verify())
        let next=try catalog.select(probe:inspect);defer{next.snapshot.close()};XCTAssertEqual(next.snapshot.pack.reference,updated.reference)
        try damage(directory,base.reference);try damage(directory,updated.reference)
        var probes=0;XCTAssertThrowsError(try catalog.select(probe:{_,_ in probes+=1}));XCTAssertEqual(probes,0)
        XCTAssertNoThrow(try old.snapshot.verify());XCTAssertNoThrow(try next.snapshot.verify())
    }
    func testOpenedCatalogRejectsReplacedGenerationsAndWriterIdentity()throws {
        for name in ["generations",".writer.lock"] {
            let base=try pack(),policy=try policy(base),directory=try scratch().appendingPathComponent("catalog")
            let store=try CandidateResourceStore(directory:directory,policy:policy,create:true);defer{store.close()}
            _=try store.publish(base,expectedRevision:0,probe:inspect)
            let reader=try CandidateResourceCatalog(directory:directory,policy:policy)
            let original=directory.appendingPathComponent(name),held=directory.appendingPathComponent("held-"+name)
            try FileManager.default.moveItem(at:original,to:held)
            // A byte-identical replacement is still a different authority.
            try FileManager.default.copyItem(at:held,to:original)
            var probes=0
            XCTAssertThrowsError(try reader.select(probe:{_,_ in probes+=1}));XCTAssertEqual(probes,0)
            XCTAssertThrowsError(try store.publish(base,expectedRevision:1,probe:{_,_ in probes+=1}));XCTAssertEqual(probes,0)
            XCTAssertEqual(try Data(contentsOf:directory.appendingPathComponent("index.json")),try ResourceContract.encode(readerIndex(policy,base)))
        }
    }
    private func readerIndex(_ policy:CandidateSourcePolicy,_ base:VerifiedCandidatePack)->CandidateResourceIndex {
        CandidateResourceIndex(policy:policy,revision:1,current:base.reference,lastGood:nil)
    }
    func testSpecialLinkedAndOversizedCatalogFilesAreRefusedWithoutProbe()throws {
        for kind in ["lock-link","lock-fifo","index-link","index-fifo","index-oversize"] {
            let base=try pack(),policy=try policy(base),parent=try scratch(),directory=parent.appendingPathComponent("catalog")
            let store=try CandidateResourceStore(directory:directory,policy:policy,create:true)
            _=try store.publish(base,expectedRevision:0,probe:inspect);store.close()
            let file=directory.appendingPathComponent(kind.hasPrefix("lock") ? ".writer.lock":"index.json")
            if kind.hasSuffix("link") {XCTAssertEqual(link(file.path,parent.appendingPathComponent("external-copy").path),0)}
            else if kind.hasSuffix("fifo") {try FileManager.default.removeItem(at:file);XCTAssertEqual(mkfifo(file.path,0o600),0)}
            else {try Data(repeating:0x61,count:ResourceContract.maximumJSON+1).write(to:file)}
            var probes=0
            XCTAssertThrowsError(try CandidateResourceCatalog(directory:directory,policy:policy).select(probe:{_,_ in probes+=1}))
            XCTAssertEqual(probes,0);XCTAssertThrowsError(try CandidateResourceStore(directory:directory,policy:policy))
        }
    }
    func testAncestorSymlinkPermissionsAndRootReplacementAreRefused()throws {
        let base=try pack(),policy=try policy(base),parent=try scratch(),directory=parent.appendingPathComponent("catalog")
        let store=try CandidateResourceStore(directory:directory,policy:policy,create:true);defer{store.close()}
        _=try store.publish(base,expectedRevision:0,probe:inspect)
        let alias=try scratch().appendingPathComponent("alias")
        try FileManager.default.createSymbolicLink(at:alias,withDestinationURL:parent)
        XCTAssertThrowsError(try CandidateResourceCatalog(directory:alias.appendingPathComponent("catalog"),policy:policy))
        try FileManager.default.setAttributes([.posixPermissions:0o755],ofItemAtPath:directory.path)
        XCTAssertThrowsError(try CandidateResourceCatalog(directory:directory,policy:policy))
        XCTAssertEqual((try FileManager.default.attributesOfItem(atPath:directory.path)[.posixPermissions] as? NSNumber)?.intValue,0o755)
        try FileManager.default.setAttributes([.posixPermissions:0o700],ofItemAtPath:directory.path)
        let held=parent.appendingPathComponent("held");try FileManager.default.moveItem(at:directory,to:held)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
        XCTAssertThrowsError(try store.publish(base,expectedRevision:1,probe:inspect))
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath:directory.path).isEmpty)
    }
}
