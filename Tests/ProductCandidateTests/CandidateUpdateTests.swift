#if os(macOS)
import XCTest
import AppKit
import Darwin
import ResourceCore
import SettingsCore
import LexiconCore
import ExpressionCore
import IMKHost
import IMKTestClient
import EngineBridge
import SessionCore

extension ProductCandidateTests {
    func updateInputs()throws->(Bundle,URL,ResourceReference,CandidateComponents,CandidateSourcePolicy) {
        let app=try bundle(),(directory,reference,components)=try CandidateUpdate.bundleInputs(app)
        let policy=try CandidateSourcePolicy(bundle:VerifiedCandidatePack(directory:ResourceDirectory(directory),expected:reference),expectedBundle:reference)
        return (app,directory,reference,components,policy)
    }
    @MainActor func testCandidateUpdateAndCurrentPersonalAuthorityStage()throws {
        _=NSApplication.shared
        let stage=try required("PAIA_UPDATE_STAGE"),parent=URL(fileURLWithPath:try required("PAIA_PRODUCT_PARENT"))
        let (app,_,_,components,policy)=try updateInputs();defer{components.close()}
        let catalogURL=parent.appendingPathComponent(CandidateUpdate.catalogLeaf),catalog=try CandidateResourceCatalog(directory:catalogURL,policy:policy)
        let priorAuthority=try authorities(parent)
        if ["both","missing_index"].contains(stage) {
            XCTAssertThrowsError(try IMKServiceEnvironment(environment:[:],preflight:true,isolatedDataParent:parent,applicationBundle:app))
            XCTAssertEqual(RimeRuntime.startupAttempts,0);XCTAssertEqual(try authorities(parent),priorAuthority)
            print("CANDIDATE_UPDATE_STAGE \(stage) refused main_attempts=0 bundled_fallback=false");return
        }
        let index=try catalog.index()
        let service=try IMKServiceEnvironment(environment:[:],preflight:true,isolatedDataParent:parent,applicationBundle:app);defer{service.close()}
        let selected=try XCTUnwrap(service.candidate),stores=try XCTUnwrap(service.productStores),before=try authorities(parent)
        if stage != "active_publication"{XCTAssertEqual(before,priorAuthority)}
        XCTAssertEqual(RimeRuntime.startupAttempts,1);XCTAssertEqual(service.runtime.deploymentCalls,0)
        let fallback=["fallback","semantic","wrong_prism","personal_fallback"].contains(stage)
        XCTAssertEqual(selected.publicSelectionReason,fallback ? .lastGood:.current)
        XCTAssertEqual(selected.publicReference,fallback ? index.lastGood:index.current)
        let baseline=fallback || stage=="active_publication"
        XCTAssertEqual(selected.publicPreset,baseline ? .baseline:.updated)
        var config=LabConfiguration();config.chinesePunctuation=true
        try service.workspace.applyConfiguration(config)
        if ["personal_updated","personal_fallback"].contains(stage) {
            XCTAssertTrue(selected.personalActive);XCTAssertFalse(selected.personalPreparationFailed)
            let binding=try XCTUnwrap(selected.snapshot.pack.manifest.personal)
            XCTAssertEqual(binding.base,selected.publicReference)
            XCTAssertEqual(binding.authoritySHA,LexiconCodec.digest(try XCTUnwrap(stores.personal).exportData()))
            XCTAssertEqual(service.workspace.configuration.initialModes,[:]) // Applied in memory only.
            XCTAssertEqual(try stores.settings?.snapshot()?.values.initialModes,["dev.paia.literal-sample":.literal])
            try commit("houxuangongchengyangli","候选工程样例",workspace:service.workspace)
            try commit("zhuanyonghouxuanyangli","专用候选样例",workspace:service.workspace)
            XCTAssertEqual(service.workspace.expressionCatalog?.search("localq").first?.record.exactText,Self.exact)
        } else {XCTAssertFalse(selected.personalActive)}
        if stage=="active_publication" {
            let driver=service.workspace.makeDriver(hide:{},present:{_,_,_ in}),client=PAIAIMKTestClient(text:"held👩🏽‍💻")
            defer{driver.close()};try activate(driver,client);try type("n",driver,client)
            let snapshot=try XCTUnwrap(driver.coordinator.snapshot),revision=service.runtime.dictionaryRevision
            XCTAssertThrowsError(try CandidateUpdate.publish(bundle:app,preset:.updated,parent:parent,expectedRevision:index.revision,create:false)){error in if case ResourceError.busy=error{}else{XCTFail("Active process accepted resource publication")}}
            XCTAssertEqual(try catalog.index(),index)
            let helper=try XCTUnwrap(app.executableURL).deletingLastPathComponent().appendingPathComponent("paia-resources")
            let receipt=try ResourceHelper.run(executable:helper,arguments:["candidate-publish","updated",String(index.revision),"existing",parent.path],home:parent,timeout:120)
            let next=try ResourceContract.decode(CandidateResourceIndex.self,receipt);try next.validate(policy:policy)
            XCTAssertEqual(next.revision,index.revision+1);XCTAssertEqual(next.lastGood,index.current)
            XCTAssertEqual(service.runtime.dictionaryRevision,revision)
            XCTAssertEqual(driver.coordinator.snapshot?.inputGeneration,snapshot.inputGeneration);XCTAssertEqual(driver.coordinator.snapshot?.rawASCII,snapshot.rawASCII);XCTAssertEqual(driver.coordinator.snapshot?.rows.map(\.ref),snapshot.rows.map(\.ref));XCTAssertEqual(client.insertCalls,0)
            try type("i",driver,client)
            let row=try XCTUnwrap(driver.coordinator.snapshot?.rows.first{$0.text=="呢"});driver.choose(row.ref);driver.choose(row.ref)
            XCTAssertEqual(client.insertCalls,1);XCTAssertEqual(client.view.string,"held👩🏽‍💻呢")
            XCTAssertEqual(selected.publicReference,index.current);try selected.snapshot.verify()
        } else {
            try commit(baseline ? "ni":CandidateSourcePolicy.updateRaw,baseline ? "呢":CandidateSourcePolicy.updateSurface,workspace:service.workspace)
        }
        if stage=="deleted" {
            let personal=try XCTUnwrap(stores.personal).snapshot()
            XCTAssertTrue(personal.activeTerms.isEmpty);XCTAssertEqual(personal.terms.filter{$0.isDeleted && $0.noRelearn}.count,2)
            XCTAssertTrue(service.workspace.expressionCatalog?.search("localq").isEmpty==true)
        }
        XCTAssertEqual(try authorities(parent),before)
        let publicPack=try catalog.pack(fallback ? XCTUnwrap(index.lastGood):catalog.index().current)
        XCTAssertNil(publicPack.manifest.personal)
        for text in ["候选工程样例","专用候选样例",Self.exact] {XCTAssertTrue(publicPack.files.values.allSatisfy{$0.range(of:Data(text.utf8))==nil})}
        let files=try FileManager.default.subpathsOfDirectory(atPath:selected.snapshot.userDirectory.path)
        XCTAssertFalse(files.contains{$0.hasPrefix("build/") || $0.contains("userdb") || $0.hasSuffix(".table.bin") || $0.hasSuffix(".prism.bin")})
        print("CANDIDATE_UPDATE_STAGE \(stage) ENGINE_NATIVE + APPKIT_HOST selected=\(selected.publicSelectionReason.rawValue)/\(selected.publicPreset.rawValue) personal=\(selected.personalActive) main_attempts=1 deployments=0 authority_bytes_unchanged=true")
    }
    func testCandidateUpdateMarkerRejectsCoherentOldCompiledArtifacts()throws {
        let (_,_,_,components,policy)=try updateInputs();defer{components.close()}
        let parent=URL(fileURLWithPath:try required("PAIA_PRODUCT_PARENT")),catalog=try CandidateResourceCatalog(directory:parent.appendingPathComponent(CandidateUpdate.catalogLeaf),policy:policy),index=try catalog.index()
        let base=try catalog.pack(XCTUnwrap(index.lastGood)),updated=try catalog.pack(index.current)
        let artifacts=Dictionary(uniqueKeysWithValues:base.manifest.artifacts.map{($0.path,base.files[$0.path]!)})
        let inputs=policy.sources(.updated),manifest=try CandidateManifest(generation:UUID().uuidString.lowercased(),inputs:inputs,artifacts:artifacts)
        let root=try CandidateCompiler.scratch();defer{try? FileManager.default.removeItem(at:root)}
        let owner=try ResourceDirectory(root),target=try owner.createDirectory("coherent")
        try VerifiedCandidatePack.write(manifest:manifest,files:inputs.merging(artifacts){_,b in b},to:target)
        let wrong=try VerifiedCandidatePack(directory:target,expected:manifest.reference),snapshot=try CandidateResourceSnapshot(wrong);defer{snapshot.close()}
        XCTAssertEqual(try policy.admitSourceIdentity(wrong),.updated)
        // Existing 32-policy smoke does not discriminate this single authored row.
        XCTAssertNoThrow(try CandidateHelper.probe(snapshot,components:components,timeout:120))
        XCTAssertThrowsError(try CandidateHelper.probeUpdate(snapshot,preset:.updated,components:components))
        let correct=try CandidateResourceSnapshot(updated);defer{correct.close()}
        XCTAssertNoThrow(try CandidateHelper.probeUpdate(correct,preset:.updated,components:components))
        let old=try CandidateResourceSnapshot(base);defer{old.close()}
        XCTAssertNoThrow(try CandidateHelper.probeUpdate(old,preset:.baseline,components:components))
        let isolated=try CandidateResourceStore(directory:root.appendingPathComponent("store"),policy:policy,create:true);defer{isolated.close()}
        XCTAssertThrowsError(try isolated.publish(wrong,expectedRevision:0){snapshot,preset in try CandidateHelper.probeUpdate(snapshot,preset:preset,components:components)})
        XCTAssertFalse(FileManager.default.fileExists(atPath:root.appendingPathComponent("store/index.json").path));XCTAssertEqual(RimeRuntime.startupAttempts,0)
        print("CANDIDATE_UPDATE_MARKER_NATIVE coherent_old_binary_refused=true source_identity_alone_insufficient=true updated_commits=8 baseline_commits=8 exhaustive_negatives=16 publisher_main_attempts=0")
    }
    func testCandidateUpdateHelperFaultsAreReapedBeforeRecordedFallback()throws {
        let (_,_,_,components,policy)=try updateInputs();defer{components.close()}
        let parent=URL(fileURLWithPath:try required("PAIA_PRODUCT_PARENT")),catalog=try CandidateResourceCatalog(directory:parent.appendingPathComponent(CandidateUpdate.catalogLeaf),policy:policy),index=try catalog.index()
        for fault in ["crash","timeout","malformed","wrong-receipt"] {
            let root=try CandidateCompiler.scratch();defer{try? FileManager.default.removeItem(at:root)}
            let helper=root.appendingPathComponent("paia-resources"),pidFile=root.appendingPathComponent("pid")
            let command:String
            switch fault {
            case "crash":command="kill -KILL $$"
            case "timeout":command="trap '' TERM; while :; do :; done"
            case "malformed":command="printf 'invalid\\n'"
            default:
                let wrong=CandidateUpdateProbeReceipt(reference:try XCTUnwrap(index.lastGood),preset:.baseline)
                command="printf '%s\\n' '"+String(decoding:try ResourceContract.encode(wrong),as:UTF8.self)+"'"
            }
            try Data(("#!/bin/sh\necho $$ > '"+pidFile.path+"'\n"+command+"\n").utf8).write(to:helper)
            XCTAssertEqual(chmod(helper.path,0o700),0)
            var calls=0
            let selected=try catalog.select{snapshot,preset in
                calls+=1
                if snapshot.pack.reference==index.current {
                    let output=try ResourceHelper.run(executable:helper,arguments:[],home:root,timeout:1)
                    guard try ResourceContract.decode(CandidateUpdateProbeReceipt.self,output)==CandidateUpdateProbeReceipt(reference:snapshot.pack.reference,preset:preset) else{throw ResourceError.probe}
                } else {
                    let pid=try XCTUnwrap(Int32(String(decoding:Data(contentsOf:pidFile),as:UTF8.self).trimmingCharacters(in:.whitespacesAndNewlines)))
                    XCTAssertEqual(kill(pid,0),-1);XCTAssertEqual(errno,ESRCH)
                    try CandidateHelper.probe(snapshot,components:components,timeout:120)
                    try CandidateHelper.probeUpdate(snapshot,preset:preset,components:components)
                }
            }
            defer{selected.snapshot.close()};XCTAssertEqual(calls,2);XCTAssertEqual(selected.reason,.lastGood);XCTAssertEqual(selected.snapshot.pack.reference,index.lastGood)
        }
        XCTAssertEqual(RimeRuntime.startupAttempts,0)
        print("CANDIDATE_UPDATE_HELPER_FAULTS faults=4 reaped_before_fallback=true ENGINE_NATIVE fallback_probe main_attempts=0")
    }
    @MainActor func testCandidateCatalogOnlyMetadataNeverEntersResearchLane()throws {
        let parent=try CandidateProductScratch.create();defer{try? FileManager.default.removeItem(at:parent)}
        let app=parent.appendingPathComponent("incomplete.app"),contents=app.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at:contents,withIntermediateDirectories:true)
        let info:[String:Any]=["CFBundleIdentifier":"dev.paia.authored.incomplete","CFBundlePackageType":"APPL","CFBundleExecutable":"PAIAInputMethod","CFBundleVersion":"1","PAIACandidateResourceCatalog":CandidateUpdate.catalogContract]
        try PropertyListSerialization.data(fromPropertyList:info,format:.xml,options:0).write(to:contents.appendingPathComponent("Info.plist"))
        let incomplete=try XCTUnwrap(Bundle(url:app)),verified=try bundle(),resources=try XCTUnwrap(verified.resourceURL)
        let research=["PAIA_IMK_RESEARCH":"1","PAIA_B1_RESEARCH":"1",
            "PAIA_RIME_LIBRARY":resources.appendingPathComponent("Engine/librime.1.dylib").path,
            "PAIA_G01_LIBRARY":resources.appendingPathComponent("Engine/paia-g01.dylib").path,
            "PAIA_B1_SHARED":resources.appendingPathComponent("CandidatePack/templates").path,
            "PAIA_B1_REVISION":"authored-catalog-routing-negative"]
        XCTAssertThrowsError(try IMKServiceEnvironment(environment:research,preflight:true,isolatedDataParent:parent,applicationBundle:incomplete))
        XCTAssertEqual(RimeRuntime.startupAttempts,0);XCTAssertFalse(FileManager.default.fileExists(atPath:parent.appendingPathComponent(ProductDataRoot.leaf).path))
        print("CANDIDATE_CATALOG_METADATA_NEGATIVE main_attempts=0 no_research_fallback=true")
    }
    @MainActor func testCandidateUpdateLateNativeFailureNeverRetries()throws {
        let (app,directory,reference,components,_)=try updateInputs();defer{components.close()}
        let parent=URL(fileURLWithPath:try required("PAIA_PRODUCT_PARENT")),before=try authorities(parent),stores=ProductStores(parent:parent);defer{stores.close()}
        XCTAssertEqual(try authorities(parent),before)
        XCTAssertFalse(try XCTUnwrap(stores.personal).snapshot().activeTerms.isEmpty)
        var changed=false
        XCTAssertThrowsError(try CandidateEnvironment(pack:directory,reference:reference,components:components,personalStore:stores.personal,catalog:parent.appendingPathComponent(CandidateUpdate.catalogLeaf),beforeAuthorityCheck:{
            XCTAssertEqual(RimeRuntime.startupAttempts,0);changed=true
            try FileManager.default.removeItem(at:components.library)
        }))
        XCTAssertTrue(changed);XCTAssertEqual(RimeRuntime.startupAttempts,1);XCTAssertEqual(try authorities(parent),before)
        let (again,ref,parts)=try CandidateUpdate.bundleInputs(app);defer{parts.close()}
        let snapshot=try CandidateResourceSnapshot(VerifiedCandidatePack(directory:ResourceDirectory(again),expected:ref));defer{snapshot.close()}
        XCTAssertThrowsError(try RimeRuntime(candidate:snapshot,components:parts));XCTAssertEqual(RimeRuntime.startupAttempts,1)
        print("CANDIDATE_UPDATE_LATE_NATIVE main_attempts=1 no_in_process_fallback=true")
    }
}
#endif
