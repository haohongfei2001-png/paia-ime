import XCTest
import Foundation
import Darwin
import ResourceCore

// SIMULATED container bytes only; these tests never claim a decoded candidate.
final class CandidatePackTests:XCTestCase {
    func root()throws->URL {
        let url=FileManager.default.temporaryDirectory.appendingPathComponent("paia-pack-test-"+UUID().uuidString.lowercased())
        try FileManager.default.createDirectory(at:url,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
        addTeardownBlock{try? FileManager.default.removeItem(at:url)};return url
    }
    func fixture()throws->(URL,VerifiedCandidatePack) {
        let url=try root(),directory=try ResourceDirectory(url)
        let inputs=Dictionary(uniqueKeysWithValues:CandidateContract.sourcePaths.map{($0,Data(("SIMULATED "+$0).utf8))})
        var artifacts=Dictionary(uniqueKeysWithValues:CandidateContract.publicArtifacts.map{($0,Data(("SIMULATED "+$0).utf8))})
        artifacts["default.yaml"]=inputs["templates/default.yaml"]
        for name in CandidateContract.opencc{artifacts["opencc/"+name]=inputs["opencc/"+name]}
        let manifest=try CandidateManifest(generation:UUID().uuidString.lowercased(),inputs:inputs,artifacts:artifacts)
        try VerifiedCandidatePack.write(manifest:manifest,files:inputs.merging(artifacts){_,b in b},to:directory)
        return (url,try VerifiedCandidatePack(directory:directory,expected:manifest.reference))
    }
    func testClosedVersionTwoInventoryDoesNotReinterpretVersionOne()throws {
        let (_,pack)=try fixture()
        XCTAssertEqual(CandidateContract.schemas.count,32);XCTAssertEqual(CandidateContract.prisms.count,8);XCTAssertEqual(CandidateContract.baselineSchemas.count,8)
        XCTAssertEqual(pack.manifest.inputs.map(\.path),CandidateContract.sourcePaths)
        XCTAssertEqual(pack.manifest.artifacts.map(\.path),CandidateContract.publicArtifacts)
        XCTAssertThrowsError(try ResourceContract.decode(ResourceManifest.self,pack.manifestBytes))
        XCTAssertEqual(ResourcePreset.baseline.schemas,["paia_a1","paia_resource_secondary"])
        XCTAssertEqual(try ResourceContract.decode(CandidateManifest.self,pack.manifestBytes),pack.manifest)
    }
    func testUnknownDuplicateAndUnsafeManifestFieldsAreRejected()throws {
        let (_,pack)=try fixture()
        var object=try XCTUnwrap(JSONSerialization.jsonObject(with:pack.manifestBytes) as? [String:Any])
        object["unknown"]=true
        let encoder:JSONSerialization.WritingOptions=[.sortedKeys,.withoutEscapingSlashes]
        XCTAssertThrowsError(try ResourceContract.decode(CandidateManifest.self,JSONSerialization.data(withJSONObject:object,options:encoder)))
        var inputs=Dictionary(uniqueKeysWithValues:pack.manifest.inputs.map{($0.path,pack.files[$0.path]!)})
        let artifacts=Dictionary(uniqueKeysWithValues:pack.manifest.artifacts.map{($0.path,pack.files[$0.path]!)})
        inputs["templates/../foreign.yaml"]=Data([1])
        XCTAssertThrowsError(try CandidateManifest(generation:pack.manifest.generation,inputs:inputs,artifacts:artifacts))
        let duplicate=Data(("{\"format\":2,"+String(decoding:pack.manifestBytes.dropFirst(),as:UTF8.self)).utf8)
        XCTAssertThrowsError(try ResourceContract.decode(CandidateManifest.self,duplicate))
    }
    func testSnapshotIsolationAndClosedDirectories()throws {
        let (url,pack)=try fixture(),snapshot=try CandidateResourceSnapshot(pack);defer{snapshot.close()}
        let extra=url.appendingPathComponent("build/unlisted.bin");try Data([1]).write(to:extra)
        XCTAssertThrowsError(try VerifiedCandidatePack(directory:ResourceDirectory(url),expected:pack.reference))
        XCTAssertNoThrow(try snapshot.verify())
        try Data([2]).write(to:snapshot.directory.appendingPathComponent("build/paia_candidate.table.bin"))
        XCTAssertThrowsError(try snapshot.verify())
    }
    func testSpecialLinkedAndOversizedFilesAreRefused()throws {
        for kind in 0..<4 {
            let (url,pack)=try fixture(),path=url.appendingPathComponent("build/paia_candidate.table.bin"),held=url.appendingPathComponent("held")
            try FileManager.default.moveItem(at:path,to:held)
            if kind==0{try FileManager.default.createSymbolicLink(at:path,withDestinationURL:held)}
            else if kind==1{XCTAssertEqual(link(held.path,path.path),0)}
            else if kind==2{XCTAssertEqual(mkfifo(path.path,0o600),0)}
            else{try Data(repeating:0,count:ResourceContract.maximumFile+1).write(to:path)}
            // Check the file itself, not only the deliberately added root entry.
            XCTAssertThrowsError(try VerifiedCandidatePack.read("build/paia_candidate.table.bin",from:ResourceDirectory(url)))
            XCTAssertThrowsError(try VerifiedCandidatePack(directory:ResourceDirectory(url),expected:pack.reference))
        }
    }
    func testDerivedBindingAndUnchangedPublicBytesAreMandatory()throws {
        let (_,base)=try fixture()
        let binding=try CandidatePersonalBinding(base:base.reference,authoritySHA:String(repeating:"a",count:64),revision:1,tiers:["pin"])
        let inputs=Dictionary(uniqueKeysWithValues:base.manifest.inputs.map{($0.path,base.files[$0.path]!)})
        var artifacts=Dictionary(uniqueKeysWithValues:base.manifest.artifacts.map{($0.path,base.files[$0.path]!)})
        for path in binding.extraArtifacts{artifacts[path]=Data(("SIMULATED "+path).utf8)}
        func derived()throws->VerifiedCandidatePack {
            let directory=try ResourceDirectory(root()),manifest=try CandidateManifest(generation:UUID().uuidString.lowercased(),inputs:inputs,artifacts:artifacts,personal:binding)
            try VerifiedCandidatePack.write(manifest:manifest,files:inputs.merging(artifacts){_,b in b},to:directory)
            XCTAssertThrowsError(try VerifiedCandidatePack(directory:directory,expected:manifest.reference))
            return try VerifiedCandidatePack(directory:directory,expected:manifest.reference,personal:binding)
        }
        XCTAssertNoThrow(try derived().validateDerived(from:base,binding:binding))
        artifacts["build/paia_candidate_flypy_ascii.schema.yaml"]=Data("changed but coherently hashed".utf8)
        XCTAssertThrowsError(try derived().validateDerived(from:base,binding:binding))
        let wrong=try CandidatePersonalBinding(base:base.reference,authoritySHA:String(repeating:"b",count:64),revision:1,tiers:["pin"])
        XCTAssertThrowsError(try derived().validateDerived(from:base,binding:wrong))
    }
}
