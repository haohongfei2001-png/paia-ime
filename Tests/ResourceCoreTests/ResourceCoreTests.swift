import XCTest
import Foundation
import Darwin
import ResourceCore

// SIMULATED file/store protocol tests. Fake binary bytes and no-op probe here
// are never represented as native compiler or engine validation.
final class ResourceCoreTests:XCTestCase {
    private var roots=[URL]()
    func root()throws->URL {let p=FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("paia-resource-test-"+UUID().uuidString);try FileManager.default.createDirectory(at:p,withIntermediateDirectories:false);roots.append(p);return p}
    override func tearDown(){for p in roots{try? FileManager.default.removeItem(at:p)};super.tearDown()}
    func pack(_ preset:ResourcePreset = .baseline)throws->(VerifiedResourcePack,URL) {
        let path=try root();var files=Dictionary(uniqueKeysWithValues:preset.requiredArtifacts.map{($0,Data(("SIMULATED "+$0+UUID().uuidString).utf8))})
        files["default.yaml"]=preset.sources["default.yaml"]
        let manifest=try ResourceManifest(generation:UUID().uuidString.lowercased(),preset:preset,artifacts:files)
        try VerifiedResourcePack.write(manifest:manifest,files:files,to:ResourceDirectory(path))
        return (try VerifiedResourcePack(directory:ResourceDirectory(path),expected:manifest.reference),path)
    }
    func storePath()throws->URL {try root().appendingPathComponent("store")}
    func noProbe(_ value:ResourceSnapshot)throws {try value.verify()}
    func generation(_ path:URL,_ reference:ResourceReference)->URL {path.appendingPathComponent("generations").appendingPathComponent(reference.generation)}
    func replaceManifest(_ path:URL,_ change:(inout [String:Any])->Void)throws->ResourceReference {
        let file=path.appendingPathComponent("manifest.json");var object=try JSONSerialization.jsonObject(with:Data(contentsOf:file)) as! [String:Any]
        change(&object);let bytes=try JSONSerialization.data(withJSONObject:object,options:[.sortedKeys,.withoutEscapingSlashes]);try bytes.write(to:file)
        return ResourceReference(generation:object["generation"] as! String,manifestSHA:ResourceContract.digest(bytes))
    }
    func testTwoSchemaContractAndCanonicalManifestAreClosed()throws {
        let (value,path)=try pack();XCTAssertEqual(value.manifest.schemas.count,2)
        XCTAssertEqual(try ResourceContract.decode(ResourceManifest.self,value.manifestBytes),value.manifest)
        let mutations:[([String:Any])->[String:Any]] = [
            {var x=$0;x["unknown"]=1;return x},
            {var x=$0;x["format"]=2;return x},
            {var x=$0;x["schemas"]=["paia_a1"];return x},
            {var x=$0;x["contract"]="other";return x},
            {var x=$0;x["engineSHA"]=String(repeating:"0",count:64);return x},
            {var x=$0;x["headerSHA"]=String(repeating:"0",count:64);return x},
            {var x=$0;x["provenance"]="licensed because hashed";return x}
        ]
        for mutate in mutations {
            try value.manifestBytes.write(to:path.appendingPathComponent("manifest.json"))
            let ref=try replaceManifest(path){$0=mutate($0)}
            XCTAssertThrowsError(try VerifiedResourcePack(directory:ResourceDirectory(path),expected:ref))
        }
        var duplicate=Data("{\"format\":1,".utf8);duplicate.append(value.manifestBytes.dropFirst())
        XCTAssertThrowsError(try ResourceContract.decode(ResourceManifest.self,duplicate))
        XCTAssertThrowsError(try ResourceContract.decode(ResourceManifest.self,Data(repeating:32,count:ResourceContract.maximumJSON+1)))
    }
    func testMissingSecondSchemaAndEveryArtifactFaultRejects()throws {
        for kind in ["missing-second","empty","truncated","changed","extra-script","omitted-declaration","wrong-source","duplicate-path","traversal"] {
            let (value,path)=try pack();var expected=value.reference
            let file=path.appendingPathComponent("build/paia_resource_secondary.schema.yaml")
            if kind=="missing-second"{try FileManager.default.removeItem(at:file)}
            if kind=="empty"{try Data().write(to:file)}
            if kind=="truncated"{try Data([1]).write(to:file)}
            if kind=="changed"{var bytes=try Data(contentsOf:file);bytes[0]^=1;try bytes.write(to:file)}
            if kind=="extra-script"{try Data("untrusted".utf8).write(to:path.appendingPathComponent("code.lua"))}
            if kind=="omitted-declaration"{expected=try replaceManifest(path){var rows=$0["artifacts"] as! [[String:Any]];rows.removeLast();$0["artifacts"]=rows}}
            if kind=="wrong-source"{expected=try replaceManifest(path){$0["inputs"]=[]}}
            if ["duplicate-path","traversal"].contains(kind){expected=try replaceManifest(path){var rows=$0["artifacts"] as! [[String:Any]];rows[0]["path"]=kind=="traversal" ? "../private":"default.yaml";$0["artifacts"]=rows}}
            XCTAssertThrowsError(try VerifiedResourcePack(directory:ResourceDirectory(path),expected:expected),kind)
        }
    }
    func testSpecialFilesAndOversizedArtifactDoNotFollowOrBlock()throws {
        for kind in ["symlink","hardlink","fifo","oversized","manifest-link","root-link"] {
            let (value,path)=try pack(),outside=try root().appendingPathComponent("outside")
            try Data("untouched".utf8).write(to:outside)
            let file=path.appendingPathComponent(kind=="manifest-link" ? "manifest.json":"build/paia_a1.table.bin")
            if kind=="root-link" {
                let link=try root().appendingPathComponent("link");try FileManager.default.createSymbolicLink(at:link,withDestinationURL:path)
                XCTAssertThrowsError(try ResourceDirectory(link));continue
            }
            try FileManager.default.removeItem(at:file)
            if kind=="symlink" || kind=="manifest-link"{try FileManager.default.createSymbolicLink(at:file,withDestinationURL:outside)}
            if kind=="hardlink"{try FileManager.default.linkItem(at:outside,to:file)}
            if kind=="fifo"{XCTAssertEqual(mkfifo(file.path,0o600),0)}
            if kind=="oversized"{FileManager.default.createFile(atPath:file.path,contents:nil);let handle=try FileHandle(forWritingTo:file);try handle.truncate(atOffset:UInt64(ResourceContract.maximumFile+1));try handle.close()}
            XCTAssertThrowsError(try VerifiedResourcePack(directory:ResourceDirectory(path),expected:value.reference),kind)
            XCTAssertEqual(try Data(contentsOf:outside),Data("untouched".utf8))
        }
    }
    func testPublishCurrentFallbackAndNextPublicationPreservesVerifiedGood()throws {
        let path=try storePath(),store=try ResourceStore(directory:path,create:true);defer{store.close()}
        let (a,_)=try pack(),(b,_)=try pack(.extended),(c,_)=try pack()
        XCTAssertEqual(try store.publish(a,expectedRevision:0,probe:noProbe).index.current,a.reference)
        let second=try store.publish(b,expectedRevision:1,probe:noProbe).index
        XCTAssertEqual(second.lastGood,a.reference);XCTAssertEqual(second.current,b.reference)
        let catalog=try ResourceCatalog(directory:path),selected=try catalog.select(probe:noProbe)
        XCTAssertEqual(selected.reason,.current);XCTAssertEqual(selected.snapshot.pack.reference,b.reference);selected.snapshot.close()
        try Data("corrupt".utf8).write(to:generation(path,b.reference).appendingPathComponent("build/paia_a1.table.bin"))
        let recovered=try catalog.select(probe:noProbe);XCTAssertEqual(recovered.reason,.lastGood);XCTAssertEqual(recovered.snapshot.pack.reference,a.reference);recovered.snapshot.close()
        let third=try store.publish(c,expectedRevision:2,probe:noProbe).index
        XCTAssertEqual(third.lastGood,a.reference);XCTAssertEqual(third.current,c.reference)
        XCTAssertNotEqual(a.reference.generation,c.reference.generation);XCTAssertEqual(a.manifest.dictionaryRevision,c.manifest.dictionaryRevision)
    }
    func testAllPublicationFaultPointsPreserveOldAndUnknownDoesNotRetry()throws {
        for fault in [ResourcePublicationFault.beforeGenerationRename,.afterGenerationRename,.beforeIndexRename,.afterIndexRename] {
            let path=try storePath(),initial=try ResourceStore(directory:path,create:true),(a,_)=try pack(),(b,_)=try pack(.extended)
            _=try initial.publish(a,expectedRevision:0,probe:noProbe);initial.close()
            let store=try ResourceStore(directory:path,fault:fault);defer{store.close()}
            XCTAssertThrowsError(try store.publish(b,expectedRevision:1,probe:noProbe))
            let catalog=try ResourceCatalog(directory:path),index=try XCTUnwrap(catalog.index())
            XCTAssertEqual(index.current,fault == .afterIndexRename ? b.reference:a.reference)
            XCTAssertNoThrow(try catalog.pack(a.reference))
            if fault == .afterIndexRename {
                XCTAssertEqual(index.lastGood,a.reference)
                let before=try Data(contentsOf:path.appendingPathComponent("index.json"))
                XCTAssertThrowsError(try store.publish(b,expectedRevision:1,probe:noProbe))
                XCTAssertEqual(try Data(contentsOf:path.appendingPathComponent("index.json")),before)
            }
        }
    }
    func testProbeFailureAndBadBothNeverMutateIndex()throws {
        let path=try storePath(),store=try ResourceStore(directory:path,create:true);defer{store.close()}
        let (a,_)=try pack(),(b,_)=try pack(.extended)
        _=try store.publish(a,expectedRevision:0,probe:noProbe)
        let index=try Data(contentsOf:path.appendingPathComponent("index.json"))
        XCTAssertThrowsError(try store.publish(b,expectedRevision:1){if $0.pack.manifest.preset == .extended{throw ResourceError.probe}})
        XCTAssertEqual(try Data(contentsOf:path.appendingPathComponent("index.json")),index)
        _=try store.publish(b,expectedRevision:1,probe:noProbe)
        let prior=try Data(contentsOf:path.appendingPathComponent("index.json"))
        for reference in [a.reference,b.reference]{try Data().write(to:generation(path,reference).appendingPathComponent("build/paia_a1.prism.bin"))}
        var probes=0;XCTAssertThrowsError(try ResourceCatalog(directory:path).select{_ in probes+=1})
        XCTAssertEqual(probes,0);XCTAssertEqual(try Data(contentsOf:path.appendingPathComponent("index.json")),prior)
    }
    func testOneWriterStaleRevisionAndReplacedAuthorityRefuse()throws {
        let path=try storePath(),store=try ResourceStore(directory:path,create:true);defer{store.close()}
        XCTAssertThrowsError(try ResourceStore(directory:path))
        let (value,_)=try pack();XCTAssertThrowsError(try store.publish(value,expectedRevision:9,probe:noProbe))
        let lock=path.appendingPathComponent(".writer.lock"),moved=path.appendingPathComponent("old-lock")
        try FileManager.default.moveItem(at:lock,to:moved);try Data().write(to:lock)
        XCTAssertThrowsError(try store.publish(value,expectedRevision:0,probe:noProbe))
        XCTAssertFalse(FileManager.default.fileExists(atPath:path.appendingPathComponent("index.json").path))
    }
    func testPrivateSnapshotSurvivesPublicMutationAndRootIdentityMovesRefuse()throws {
        let (value,path)=try pack(),copy=try ResourceSnapshot(value);defer{copy.close()}
        let file=path.appendingPathComponent("build/paia_a1.table.bin")
        try Data("changed".utf8).write(to:file);XCTAssertNoThrow(try copy.verify())
        XCTAssertThrowsError(try VerifiedResourcePack(directory:ResourceDirectory(path),expected:value.reference))
        let owner=try ResourceDirectory(path),moved=try root().appendingPathComponent("moved")
        try FileManager.default.moveItem(at:path,to:moved);try FileManager.default.createDirectory(at:path,withIntermediateDirectories:false)
        XCTAssertThrowsError(try owner.read("manifest.json"))
    }
    func testReadOnlyCatalogRefusesCorruptIndexAndUnreferencedGeneration()throws {
        let path=try storePath(),store=try ResourceStore(directory:path,create:true);defer{store.close()}
        let (value,_)=try pack();_ = try store.publish(value,expectedRevision:0,probe:noProbe)
        let file=path.appendingPathComponent("index.json");try Data("broken".utf8).write(to:file)
        let before=try Data(contentsOf:file);XCTAssertThrowsError(try ResourceCatalog(directory:path).select(probe:noProbe));XCTAssertEqual(try Data(contentsOf:file),before)
        XCTAssertTrue(FileManager.default.fileExists(atPath:generation(path,value.reference).path))
    }
}
