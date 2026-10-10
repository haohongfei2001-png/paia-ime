#if os(macOS)
import XCTest
import AppKit
import Darwin
import ResourceCore
import EngineBridge
import IMKHost
import IMKTestClient
import LexiconCore

final class ResourceIMKTests:XCTestCase {
    private var roots=[URL]()
    func root()throws->URL {let p=FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("paia-resource-native-"+UUID().uuidString);try FileManager.default.createDirectory(at:p,withIntermediateDirectories:false);roots.append(p);return p}
    override func tearDown(){for p in roots{try? FileManager.default.removeItem(at:p)};super.tearDown()}
    func required(_ key:String)throws->String {try XCTUnwrap(ProcessInfo.processInfo.environment[key],"Required native resource fixture: "+key)}
    func helper()throws->URL {URL(fileURLWithPath:try required("PAIA_RESOURCE_HELPER"))}
    func library()throws->URL {URL(fileURLWithPath:try required("PAIA_RIME_LIBRARY"))}
    func probe(_ snapshot:ResourceSnapshot)throws {try ResourceHelper.probe(snapshot,library:library(),helper:helper(),helperSHA:required("PAIA_RESOURCE_HELPER_SHA"))}
    func storeCopy()throws->URL {
        let p=try root().appendingPathComponent("store")
        try FileManager.default.copyItem(at:URL(fileURLWithPath:required("PAIA_RESOURCE_TEST_STORE")),to:p);return p
    }
    func corrupt(_ store:URL,_ reference:ResourceReference,coherent:Bool=false,secondOnly:Bool=false)throws {
        let directory=store.appendingPathComponent("generations").appendingPathComponent(reference.generation)
        let pack=try VerifiedResourcePack(directory:ResourceDirectory(directory),expected:reference)
        let name=secondOnly ? "build/paia_resource_secondary.schema.yaml":"build/paia_a1.table.bin"
        let data=Data("deliberately unusable authored fixture artifact".utf8);try data.write(to:directory.appendingPathComponent(name))
        if coherent {
            var files=pack.files;files[name]=data
            let manifest=try ResourceManifest(generation:reference.generation,preset:pack.manifest.preset,artifacts:files)
            try ResourceContract.encode(manifest).write(to:directory.appendingPathComponent("manifest.json"))
            let old=try XCTUnwrap(ResourceCatalog(directory:store).index())
            let next=ResourceIndex(revision:old.revision,current:try manifest.reference,lastGood:old.lastGood)
            try ResourceContract.encode(next).write(to:store.appendingPathComponent("index.json"))
        }
    }
    @MainActor func testStartupAndRecoveryStage()throws {
        _=NSApplication.shared
        let stage=try required("PAIA_RESOURCE_STAGE")
        let shared=["active_publication","after_publication"].contains(stage)
        let path=try (shared ? URL(fileURLWithPath:required("PAIA_RESOURCE_ACTIVE_STORE")):storeCopy())
        let catalog=try ResourceCatalog(directory:path),original=try XCTUnwrap(catalog.index())
        let prior=try XCTUnwrap(original.lastGood)
        if ["fallback","both","semantic"].contains(stage){try corrupt(path,original.current,coherent:stage=="semantic")}
        if stage=="both"{try corrupt(path,prior)}
        var environment=ProcessInfo.processInfo.environment
        environment["PAIA_RESOURCE_ROOT"]=path.path;environment["PAIA_IMK_RESEARCH"]="0";environment["PAIA_B1_RESEARCH"]="0";environment["PAIA_B2_RESEARCH"]="0";environment["PAIA_B3_SETTINGS"]="0";environment.removeValue(forKey:"PAIA_C_STORE")
        if stage=="both" {
            XCTAssertThrowsError(try IMKServiceEnvironment(environment:environment));XCTAssertEqual(RimeRuntime.startupAttempts,0)
            print("RESOURCE_IMK_STAGE both zero main engine entries; no client or host write")
            return
        }
        if stage=="late_failure" {
            let copy=try root().appendingPathComponent("librime.1.16.0.dylib");try FileManager.default.copyItem(at:library(),to:copy)
            XCTAssertThrowsError(try PublicResourceEnvironment(store:path,bundle:nil,bundleReference:nil,library:copy,helper:helper(),helperSHA:required("PAIA_RESOURCE_HELPER_SHA"),probeOverride:{snapshot in
                try ResourceHelper.probe(snapshot,library:copy,helper:self.helper(),helperSHA:self.required("PAIA_RESOURCE_HELPER_SHA"))
                try FileManager.default.removeItem(at:copy)
            }))
            XCTAssertEqual(RimeRuntime.startupAttempts,1)
            let user=try root();XCTAssertThrowsError(try RimeRuntime(library:library().path,shared:user.path,isolatedUser:user.path,dictionaryRevision:"must-not-retry",precompiled:true))
            XCTAssertEqual(RimeRuntime.startupAttempts,1)
            print("RESOURCE_IMK_STAGE late_failure main entry once; no in-process fallback")
            return
        }
        guard ["current","fallback","semantic","active_publication","after_publication"].contains(stage) else{XCTFail("Unknown required stage");return}
        let service=try IMKServiceEnvironment(environment:environment);defer{service.close()}
        let selected=try XCTUnwrap(service.publicResources),manifest=selected.selection.snapshot.pack.manifest
        XCTAssertEqual(RimeRuntime.startupAttempts,1);XCTAssertEqual(service.runtime.deploymentCalls,0);XCTAssertNil(service.personal)
        XCTAssertEqual(selected.selection.reason,["fallback","semantic"].contains(stage) ? .lastGood:.current)
        XCTAssertEqual(selected.selection.snapshot.pack.reference,["fallback","semantic"].contains(stage) ? prior:original.current)
        if stage=="after_publication"{XCTAssertEqual(manifest.preset,.baseline)}
        let privatePack=try ResourceDirectory(selected.selection.snapshot.directory)
        let before=Dictionary(uniqueKeysWithValues:try manifest.artifacts.map{($0.path,try privatePack.readPath($0.path))})
        let driver=service.workspace.makeDriver(hide:{},present:{_,_,_ in}),client=PAIAIMKTestClient(text:"Existing𠀀")
        defer{driver.close()};XCTAssertEqual(driver.activate(try XCTUnwrap(IMKTextInputBridge(client))),.ready)
        func key(_ text:String,_ code:UInt16=0)throws->NSEvent {try XCTUnwrap(NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[],timestamp:0,windowNumber:0,context:nil,characters:text,charactersIgnoringModifiers:text,isARepeat:false,keyCode:code))}
        let raw=stage=="active_publication" ? "nihao":manifest.preset.probeRaw
        let expected=stage=="active_publication" ? "你好":manifest.preset.probeText
        for character in raw.prefix(2){XCTAssertTrue(driver.handle(try key(String(character)),client:client))}
        let session=try XCTUnwrap(driver.coordinator.session),held=try XCTUnwrap(session.snapshot)
        if stage=="active_publication" {
            let personal=try root().appendingPathComponent("personal"),authority=try LexiconStore(directory:personal)
            let id=try authority.add(surface:"SyntheticDeletedResourceWord",reading:"ce shi",expectedRevision:0)
            try authority.setDeleted(id:id,deleted:true,expectedRevision:1)
            let bytes=try authority.exportData();authority.close()
            let result=try ResourceHelper.run(executable:helper(),arguments:["publish",path.path,"baseline",try library().path,String(original.revision),"existing"],home:root(),timeout:120)
            let published=try ResourceContract.decode(ResourceIndex.self,result)
            XCTAssertNotEqual(published.current,original.current)
            XCTAssertEqual(service.runtime.dictionaryRevision,manifest.dictionaryRevision)
            XCTAssertEqual(session.snapshot?.inputGeneration,held.inputGeneration);XCTAssertEqual(session.snapshot?.rawASCII,held.rawASCII)
            XCTAssertEqual(client.insertCalls,0);XCTAssertEqual(try Data(contentsOf:personal.appendingPathComponent("lexicon.json")),bytes)
            let new=try ResourceCatalog(directory:path).pack(published.current)
            XCTAssertTrue(new.files.values.allSatisfy{$0.range(of:Data("SyntheticDeletedResourceWord".utf8))==nil})
        }
        for character in raw.dropFirst(2){XCTAssertTrue(driver.handle(try key(String(character)),client:client))}
        XCTAssertEqual(session.snapshot?.rows.first?.text,expected)
        XCTAssertTrue(driver.handle(try key(" ",49),client:client));XCTAssertEqual(client.insertCalls,1);XCTAssertEqual(client.view.string,"Existing𠀀"+expected)
        XCTAssertNil(try session.refresh().commit);XCTAssertEqual(service.runtime.deploymentCalls,0)
        XCTAssertEqual(try manifest.artifacts.map{try privatePack.readPath($0.path)},manifest.artifacts.map{before[$0.path]!})
        let user=selected.selection.snapshot.userDirectory
        let descendants=(FileManager.default.enumerator(atPath:user.path)?.allObjects as? [String]) ?? []
        XCTAssertFalse(descendants.contains{$0.hasPrefix("build/") || $0.contains("userdb") || $0.hasSuffix(".table.bin") || $0.hasSuffix(".prism.bin")},"Precompiled startup must not create compiled/userdb artifacts: \(descendants)")
        try selected.selection.snapshot.verify()
        print("RESOURCE_IMK_STAGE \(stage) ENGINE_NATIVE + APPKIT_HOST; selected=\(selected.selection.reason.rawValue); once commit; zero deploy; fixture only")
    }
    func testHelperFailuresAreReapedBeforeNativeFallback()throws {
        let path=try storeCopy(),catalog=try ResourceCatalog(directory:path),index=try XCTUnwrap(catalog.index())
        for fault in ["crash","timeout","malformed","wrong-receipt"] {
            let directory=try root(),fake=directory.appendingPathComponent("paia-resources")
            let command:String
            switch fault {
            case "crash":command="kill -KILL $$"
            case "timeout":command="trap '' TERM; while :; do :; done"
            case "malformed":command="printf 'invalid\\n'"
            default:
                var receipt=try JSONSerialization.jsonObject(with:ResourceContract.encode(ResourceProbeReceipt(catalog.pack(index.current).manifest))) as! [String:Any]
                receipt["deployments"]=1
                let data=try JSONSerialization.data(withJSONObject:receipt,options:[.sortedKeys,.withoutEscapingSlashes])
                command="printf '%s\\n' '"+String(decoding:data,as:UTF8.self)+"'"
            }
            let script=Data(("#!/bin/sh\n"+command+"\n").utf8);try script.write(to:fake);XCTAssertEqual(chmod(fake.path,0o700),0)
            var attempts=0
            let selected=try catalog.select{snapshot in
                attempts+=1
                if snapshot.pack.reference==index.current{try ResourceHelper.probe(snapshot,library:self.library(),helper:fake,helperSHA:ResourceContract.digest(script),timeout:0.1)}
                else{try self.probe(snapshot)}
            }
            XCTAssertEqual(attempts,2);XCTAssertEqual(selected.reason,.lastGood);selected.snapshot.close()
        }
        XCTAssertEqual(RimeRuntime.startupAttempts,0)
        print("RESOURCE_HELPER_FAULTS crash/timeout/malformed/wrong receipt rejected and reaped; real native fallback; no main runtime consumed")
    }
    func testNativeMissingSecondSchemaRejectsWholePublication()throws {
        let path=try storeCopy(),catalog=try ResourceCatalog(directory:path),index=try XCTUnwrap(catalog.index())
        let original=try catalog.pack(index.current);var files=original.files
        files["build/paia_resource_secondary.schema.yaml"]=Data("schema: broken\n".utf8)
        let manifest=try ResourceManifest(generation:UUID().uuidString.lowercased(),preset:original.manifest.preset,artifacts:files)
        let directory=try root();try VerifiedResourcePack.write(manifest:manifest,files:files,to:ResourceDirectory(directory))
        let broken=try VerifiedResourcePack(directory:ResourceDirectory(directory),expected:manifest.reference)
        let store=try ResourceStore(directory:path);defer{store.close()}
        XCTAssertThrowsError(try store.publish(broken,expectedRevision:index.revision,probe:probe))
        XCTAssertEqual(try catalog.index(),index);XCTAssertEqual(RimeRuntime.startupAttempts,0)
        print("RESOURCE_ALL_SCHEMA_NATIVE invalid second compiled schema rejected; prior index retained")
    }
}
#endif
