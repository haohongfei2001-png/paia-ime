#if os(macOS)
import XCTest
import AppKit
import ResourceCore
import SettingsCore
import LexiconCore
import ExpressionCore
import IMKHost
import IMKTestClient
import EngineBridge
import SessionCore

final class ProductCandidateTests:XCTestCase {
    static let exact="  明确保存的原话 👩🏽‍💻 e\u{301}\r\n完整结尾。  "
    func required(_ key:String)throws->String {try XCTUnwrap(ProcessInfo.processInfo.environment[key],"Explicit isolated product test setup required")}
    func bundle()throws->Bundle {try XCTUnwrap(Bundle(url:URL(fileURLWithPath:required("PAIA_CANDIDATE_BUNDLE"))))}
    func authorities(_ parent:URL)throws->[String:Data] {
        let root=parent.appendingPathComponent(ProductDataRoot.leaf);var result=[String:Data]()
        for path in [".layout","settings/.slot","personal/.slot","expressions/.slot","settings/.initialized","personal/.initialized","expressions/.initialized","settings/settings.json","personal/lexicon.json","expressions/expressions.json"] {
            let file=root.appendingPathComponent(path);if FileManager.default.fileExists(atPath:file.path){result[path]=try Data(contentsOf:file)}
        };return result
    }
    @MainActor func event(_ text:String="",code:UInt16=0,modifiers:NSEvent.ModifierFlags=[])throws->NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:modifiers,timestamp:0,windowNumber:0,context:nil,characters:text,charactersIgnoringModifiers:text,isARepeat:false,keyCode:code))
    }
    @MainActor func activate(_ driver:IMKControllerDriver,_ client:PAIAIMKTestClient)throws {
        XCTAssertEqual(driver.activate(try XCTUnwrap(IMKTextInputBridge(client))),.ready)
    }
    @MainActor func type(_ raw:String,_ driver:IMKControllerDriver,_ client:PAIAIMKTestClient)throws {
        for character in raw{XCTAssertTrue(driver.handle(try event(String(character)),client:client))}
    }
    @MainActor func commit(_ raw:String,_ text:String,workspace:IMKWorkspace)throws {
        let client=PAIAIMKTestClient(text:"prefix👩🏽‍💻"),driver=workspace.makeDriver(hide:{},present:{_,_,_ in});defer{driver.close()}
        try activate(driver,client);try type(raw,driver,client)
        for _ in 0..<410 {
            let snapshot=try XCTUnwrap(driver.coordinator.snapshot)
            if let row=snapshot.rows.first(where:{$0.text.utf8.elementsEqual(text.utf8)}) {
                driver.choose(row.ref);driver.choose(row.ref)
                XCTAssertEqual(client.view.string,"prefix👩🏽‍💻"+text);XCTAssertEqual(client.insertCalls,1);XCTAssertEqual(client.documentLengthCalls,0);return
            }
            if !snapshot.hasMore{break};XCTAssertTrue(driver.handle(try event(code:121),client:client))
        }
        XCTFail("Authored candidate missing");throw ResourceError.probe
    }
    @MainActor func testSaveRestartDeleteAndNativeOwnerStage()throws {
        _=NSApplication.shared;let stage=try required("PAIA_PRODUCT_STAGE"),parent=URL(fileURLWithPath:try required("PAIA_PRODUCT_PARENT"))
        XCTAssertTrue(["public","save","restore","delete","deleted"].contains(stage))
        let environment=try IMKServiceEnvironment(environment:[:],preflight:true,isolatedDataParent:parent,applicationBundle:bundle());defer{environment.close()}
        let candidate=try XCTUnwrap(environment.candidate),stores=try XCTUnwrap(environment.productStores),workspace=environment.workspace
        let preferences=IMKPreferencesController(workspace:workspace);defer{preferences.close()}
        XCTAssertTrue(stores.unavailable.isEmpty);XCTAssertEqual(RimeRuntime.startupAttempts,1);XCTAssertEqual(environment.runtime.deploymentCalls,0)
        let initial=try authorities(parent)
        if stage=="public" {
            XCTAssertFalse(candidate.personalActive);var count=0
            for spelling in LabSpelling.allCases {for traditional in [false,true] {for punctuation in [false,true] {for fuzzy in [false,true] {for correction in (spelling == .full ? [true,false]:[true]) {
                var c=LabConfiguration();c.spelling=spelling;c.traditional=traditional;c.chinesePunctuation=punctuation;c.fuzzyInitials=fuzzy;c.fullPinyinCorrection=correction
                try preferences.applyConfiguration(c)
                try commit(spelling == .full ? "shurufa":"uurufa",traditional ? "輸入法":"输入法",workspace:workspace);count+=1
            }}}}}
            XCTAssertEqual(count,32);XCTAssertEqual(try authorities(parent),initial)
            try preferences.applyConfiguration(LabConfiguration())
            let driver=workspace.makeDriver(hide:{},present:{_,_,_ in},presentRepair:{_,_ in true}),other=workspace.makeDriver(hide:{},present:{_,_,_ in})
            let a=PAIAIMKTestClient(text:""),b=PAIAIMKTestClient(text:"");defer{driver.close();other.close()}
            try activate(driver,a);try activate(other,b);try type("nihao",other,b)
            XCTAssertThrowsError(try preferences.applyConfiguration(LabConfiguration()))
            XCTAssertThrowsError(try workspace.saveExpression("blocked",aliases:[],catalogRevision:0))
            XCTAssertEqual(try authorities(parent),initial);XCTAssertEqual(b.insertCalls,0)
            XCTAssertTrue(other.handle(try event("\u{1b}",code:53),client:b))
            let action=try XCTUnwrap(driver.retainedMenuAction(arm:true));driver.performRetainedMenuAction(action)
            try type("nihaoshijie",driver,a)
            for text in ["你好","世界"] {
                let session=try XCTUnwrap(driver.coordinator.session),choice=try XCTUnwrap(session.repairChoices().rows.first{$0.anchor.text==text})
                // Drive actual visible rows; ranking need not place a confirmed
                // prefix on the first page of a longer sentence.
                var selected=false
                for _ in 0..<410 {
                    let visible=try XCTUnwrap(driver.coordinator.snapshot)
                    if let row=visible.rows.first(where:{$0.text==choice.anchor.text}){driver.choose(row.ref);selected=true;break}
                    if !visible.hasMore{break};XCTAssertTrue(driver.handle(try event(code:121),client:a))
                }
                XCTAssertTrue(selected)
            }
            XCTAssertEqual(a.insertCalls,0)
            XCTAssertTrue(driver.handle(try event(code:123,modifiers:[.option]),client:a))
            for _ in 0..<3 where driver.repair?.target.index != 0{XCTAssertTrue(driver.handle(try event(code:123,modifiers:[.option]),client:a))}
            let target=try XCTUnwrap(driver.repair);XCTAssertEqual(target.target.index,0)
            driver.searchRepair(token:target.token)
            let alternatives=try XCTUnwrap(driver.repair),replacement=try XCTUnwrap(alternatives.rows.firstIndex{$0.surface=="拟好"})
            for _ in 0..<410 where driver.repair!.page<replacement/5{XCTAssertTrue(driver.handle(try event(code:121),client:a))}
            XCTAssertEqual(driver.repair?.page,replacement/5)
            XCTAssertTrue(driver.handle(try event(String(replacement%5+1)),client:a));let reviewed=try XCTUnwrap(driver.repair);XCTAssertNotNil(reviewed.proposal)
            driver.applyRepair(token:reviewed.token);driver.applyRepair(token:reviewed.token)
            XCTAssertNil(driver.repair);XCTAssertEqual(a.insertCalls,0)
            driver.performRetainedMenuAction(try XCTUnwrap(driver.retainedMenuAction(arm:false)))
            XCTAssertEqual(a.view.string,"拟好世界");XCTAssertEqual(a.insertCalls,1)
            let mixedClient=PAIAIMKTestClient(text:"prefix"),mixed=workspace.makeDriver(hide:{},present:{_,_,_ in});defer{mixed.close()}
            try activate(mixed,mixedClient);try type("nihao",mixed,mixedClient)
            mixed.performMixedMenuAction(try XCTUnwrap(mixed.mixedMenuAction(.begin)))
            let chinese=try XCTUnwrap(mixed.coordinator.snapshot?.rows.first{$0.text=="你好"});mixed.choose(chinese.ref)
            mixed.performMixedMenuAction(try XCTUnwrap(mixed.mixedMenuAction(.literal)))
            XCTAssertTrue(mixed.handle(try event("RAG👩🏽‍💻"),client:mixedClient))
            let mixedCommit=try XCTUnwrap(mixed.mixedMenuAction(.commit));mixed.performMixedMenuAction(mixedCommit);mixed.performMixedMenuAction(mixedCommit)
            XCTAssertEqual(mixedClient.view.string,"prefix你好RAG👩🏽‍💻");XCTAssertEqual(mixedClient.insertCalls,1)
            XCTAssertEqual(try authorities(parent),initial)
            print("PRODUCT_PUBLIC_NATIVE host_schema_commits=32 repaired_commit=1 mixed_commit=1 authority_bytes_unchanged=true")
        } else if stage=="save" {
            var c=LabConfiguration();c.spelling = .flypy;c.traditional=true;c.chinesePunctuation=true;c.fuzzyInitials=true;c.initialModes=["dev.paia.literal-sample":.literal]
            try preferences.applyConfiguration(c)
            XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(preferences.settings.saveButton.action),to:preferences.settings.saveButton.target,from:preferences.settings.saveButton))
            XCTAssertEqual(try stores.settings?.snapshot()?.values,c.preferences)
            preferences.openTerms(nil);let manager=try XCTUnwrap(preferences.terms)
            for (surface,reading,pin) in [("候选工程样例","hou xuan gong cheng yang li",false),("专用候选样例","zhuan yong hou xuan yang li",true)] {
                XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(manager.newButton.action),to:manager.newButton.target,from:manager.newButton))
                manager.surface.stringValue=surface;manager.reading.stringValue=reading;manager.pin.state=pin ? .on:.off
                XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(manager.addButton.action),to:manager.addButton.target,from:manager.addButton))
            }
            XCTAssertEqual(try stores.personal?.snapshot().activeTerms.count,2);XCTAssertTrue(candidate.pendingRestart)
            _=try workspace.saveExpression(Self.exact,aliases:["localq"],catalogRevision:0)
            XCTAssertEqual(workspace.expressionCatalog?.search("localq").first?.record.exactText,Self.exact)
        } else if stage=="restore" || stage=="delete" {
            XCTAssertTrue(candidate.personalActive);XCTAssertFalse(candidate.personalPreparationFailed)
            XCTAssertEqual(workspace.configuration.spelling,.flypy);XCTAssertTrue(workspace.configuration.traditional)
            XCTAssertEqual(workspace.configuration.initialModes,["dev.paia.literal-sample":.literal])
            try commit("uurufa","輸入法",workspace:workspace)
            let literalClient=PAIAIMKTestClient(text:""),literal=workspace.makeDriver(hide:{},present:{_,_,_ in});defer{literal.close()}
            literalClient.applicationIdentifier="dev.paia.literal-sample";try activate(literal,literalClient)
            XCTAssertFalse(literal.handle(try event("n"),client:literalClient));XCTAssertEqual(literalClient.insertCalls,0);literal.close()
            try preferences.applyConfiguration(LabConfiguration())
            let overlay=try environment.makeSession(workspace.configuration);defer{overlay.end()}
            XCTAssertFalse(overlay.canRetainForRepair);XCTAssertFalse(overlay.canUseMixed)
            try commit("houxuangongchengyangli","候选工程样例",workspace:workspace)
            try commit("zhuanyonghouxuanyangli","专用候选样例",workspace:workspace)
            if stage=="restore" {
                let client=PAIAIMKTestClient(text:"original"),driver=workspace.makeDriver(hide:{},present:{_,_,_ in},presentRecall:{_,_ in true});defer{driver.close()}
                try activate(driver,client);XCTAssertTrue(driver.handle(try event(" ",code:49,modifiers:[.option]),client:client))
                let list=try XCTUnwrap(driver.recall),row=try XCTUnwrap(list.rows.first);driver.reviewExpression(row.ref,token:list.token)
                let review=try XCTUnwrap(driver.recall);driver.acceptExpression(token:review.token);driver.acceptExpression(token:review.token)
                XCTAssertEqual(client.view.string,"original"+Self.exact);XCTAssertEqual(client.insertCalls,1)
                XCTAssertEqual(try authorities(parent),initial)
            } else {
                try workspace.withIdleAccess {
                    let store=try XCTUnwrap(stores.personal)
                    for term in try store.snapshot().activeTerms{try store.setDeleted(id:term.id,deleted:true,expectedRevision:store.snapshot().revision)}
                    workspace.personalAuthorityChanged()
                }
                XCTAssertTrue(candidate.pendingRestart);XCTAssertThrowsError(try overlay.refresh())
                let plain=try environment.makeSession(workspace.configuration);defer{plain.end()}
                XCTAssertTrue(plain.canRetainForRepair);XCTAssertTrue(plain.canUseMixed)
                try commit("shurufa","输入法",workspace:workspace)
                let document=try XCTUnwrap(stores.expressions?.snapshot()),record=try XCTUnwrap(document.records.first)
                _=try workspace.deleteExpression(record,catalogRevision:document.revision)
            }
        } else {
            XCTAssertFalse(candidate.personalActive);XCTAssertEqual(try stores.personal?.snapshot().activeTerms.count,0)
            XCTAssertEqual(try stores.personal?.snapshot().terms.filter{$0.isDeleted && $0.noRelearn}.count,2)
            XCTAssertTrue(workspace.expressionCatalog?.search("localq").isEmpty==true)
            try preferences.applyConfiguration(LabConfiguration());try commit("nihao","你好",workspace:workspace)
            XCTAssertEqual(try authorities(parent),initial)
        }
        let files=try FileManager.default.subpathsOfDirectory(atPath:candidate.snapshot.userDirectory.path)
        XCTAssertFalse(files.contains{$0.hasPrefix("build/") || $0.contains("userdb") || $0.hasSuffix(".table.bin") || $0.hasSuffix(".prism.bin")})
        print("PRODUCT_RESTART_STAGE \(stage) ENGINE_NATIVE + APPKIT_HOST main_attempts=1 deployments=0")
    }
    @MainActor func testOptionalStoreAndPersonalPreparationFaultStage()throws {
        _=NSApplication.shared;let stage=try required("PAIA_PRODUCT_STAGE"),parent=URL(fileURLWithPath:try required("PAIA_PRODUCT_PARENT"))
        XCTAssertTrue(["bad_settings","missing_personal","second_writer","helper_failure","changed_authority","replaced_root"].contains(stage))
        let seed=ProductStores(parent:parent);XCTAssertTrue(seed.unavailable.isEmpty)
        _=try seed.settings!.save(SettingsValues(),expectedRevision:0)
        _=try seed.personal!.add(surface:"故障自造词",reading:"gu zhang zi zao ci",pin:true,expectedRevision:0)
        _=try seed.expressions!.saveExact(Self.exact,aliases:["localq"],expectedRevision:0)
        if stage != "second_writer"{seed.close()};defer{seed.close()}
        let root=parent.appendingPathComponent(ProductDataRoot.leaf)
        if stage=="bad_settings"{try Data("invalid authored fault".utf8).write(to:root.appendingPathComponent("settings/settings.json"))}
        if stage=="missing_personal"{try FileManager.default.removeItem(at:root.appendingPathComponent("personal/lexicon.json"))}
        let before=try authorities(parent)
        if ["helper_failure","changed_authority","replaced_root"].contains(stage) {
            let stores=ProductStores(parent:parent);defer{stores.close()};let bundle=try bundle(),resources=try XCTUnwrap(bundle.resourceURL),executable=try XCTUnwrap(bundle.executableURL)
            let components=try CandidateComponents(library:resources.appendingPathComponent("Engine/librime.1.dylib"),extensionLibrary:resources.appendingPathComponent("Engine/paia-g01.dylib"),helper:executable.deletingLastPathComponent().appendingPathComponent("paia-resources"),extensionSHA:XCTUnwrap(bundle.object(forInfoDictionaryKey:"PAIACandidateExtensionSHA") as? String),helperSHA:XCTUnwrap(bundle.object(forInfoDictionaryKey:"PAIAResourceHelperSHA") as? String))
            let reference=ResourceReference(generation:try XCTUnwrap(bundle.object(forInfoDictionaryKey:"PAIACandidateGeneration") as? String),manifestSHA:try XCTUnwrap(bundle.object(forInfoDictionaryKey:"PAIACandidateManifestSHA") as? String))
            var changed=false
            let failure:((URL,[String],URL,TimeInterval)throws->Data)?=stage=="helper_failure" ? {exe,_,home,_ in
                XCTAssertEqual(RimeRuntime.startupAttempts,0)
                return try ResourceHelper.run(executable:exe,arguments:["authored-invalid-operation"],home:home,timeout:5)
            }:nil
            let candidate=try CandidateEnvironment(pack:resources.appendingPathComponent("CandidatePack"),reference:reference,components:components,personalStore:stores.personal,helperRun:failure,beforeAuthorityCheck:{
                XCTAssertEqual(RimeRuntime.startupAttempts,0);changed=true
                if stage=="replaced_root" {
                    try FileManager.default.moveItem(at:root,to:parent.appendingPathComponent("retained-original"))
                    try FileManager.default.createDirectory(at:root,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
                } else if stage=="changed_authority" {
                    let store=try XCTUnwrap(stores.personal),document=try store.snapshot()
                    try store.setDeleted(id:XCTUnwrap(document.activeTerms.first).id,deleted:true,expectedRevision:document.revision)
                }
            });defer{_ = candidate.runtime.close()}
            XCTAssertFalse(candidate.personalActive);XCTAssertTrue(candidate.personalPreparationFailed)
            XCTAssertEqual(changed,stage != "helper_failure")
            let workspace=IMKWorkspace(resourceDescription:candidate.status,supportsSpellingPolicies:true,makeSession:{try candidate.makeSession(configuration:$0)});defer{workspace.close()}
            try commit("nihao","你好",workspace:workspace)
            if stage=="helper_failure"{XCTAssertEqual(try authorities(parent),before)}
            if stage=="changed_authority"{XCTAssertEqual(try stores.personal?.snapshot().activeTerms.count,0)}
            if stage=="replaced_root"{XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath:root.path).isEmpty)}
        } else {
            let environment=try IMKServiceEnvironment(environment:[:],preflight:true,isolatedDataParent:parent,applicationBundle:bundle());defer{environment.close()}
            let stores=try XCTUnwrap(environment.productStores)
            if stage=="bad_settings"{XCTAssertNil(stores.settings);XCTAssertNotNil(stores.personal);XCTAssertNotNil(stores.expressions)}
            if stage=="missing_personal"{XCTAssertNil(stores.personal);XCTAssertNotNil(stores.settings);XCTAssertNotNil(stores.expressions)}
            if stage=="second_writer"{XCTAssertNil(stores.root);XCTAssertFalse(environment.candidate!.personalActive)}
            try commit("nihao","你好",workspace:environment.workspace);XCTAssertEqual(try authorities(parent),before)
        }
        XCTAssertEqual(RimeRuntime.startupAttempts,1)
        print("PRODUCT_FAULT_STAGE \(stage) ENGINE_NATIVE + APPKIT_HOST public_input_preserved=true main_attempts=1")
    }
    @MainActor func testMissingCandidateMetadataCannotEnterResearchLane()throws {
        let parent=try CandidateProductScratch.create();defer{try? FileManager.default.removeItem(at:parent)}
        let app=parent.appendingPathComponent("missing.app"),contents=app.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at:contents,withIntermediateDirectories:true)
        let info:[String:Any]=["CFBundleIdentifier":"dev.paia.ime.candidate","CFBundlePackageType":"APPL","CFBundleExecutable":"PAIAInputMethod","CFBundleVersion":"1"]
        try PropertyListSerialization.data(fromPropertyList:info,format:.xml,options:0).write(to:contents.appendingPathComponent("Info.plist"))
        let missing=try XCTUnwrap(Bundle(url:app)),verified=try bundle(),resources=try XCTUnwrap(verified.resourceURL)
        // All research arguments are reachable authored resources. A dispatch
        // regression must cross the native entry, not merely fail missing env.
        let research=["PAIA_IMK_RESEARCH":"1","PAIA_B1_RESEARCH":"1",
            "PAIA_RIME_LIBRARY":resources.appendingPathComponent("Engine/librime.1.dylib").path,
            "PAIA_G01_LIBRARY":resources.appendingPathComponent("Engine/paia-g01.dylib").path,
            "PAIA_B1_SHARED":resources.appendingPathComponent("CandidatePack/templates").path,
            "PAIA_B1_REVISION":"authored-metadata-routing-negative"]
        XCTAssertThrowsError(try IMKServiceEnvironment(environment:research,preflight:true,isolatedDataParent:parent,applicationBundle:missing))
        XCTAssertEqual(RimeRuntime.startupAttempts,0);XCTAssertFalse(FileManager.default.fileExists(atPath:parent.appendingPathComponent(ProductDataRoot.leaf).path))
        print("PRODUCT_METADATA_NEGATIVE main_attempts=0 no_research_fallback=true")
    }
    @MainActor func testG01OnlyTableNeverAdvertisesMixedInput()throws {
        let path=URL(fileURLWithPath:try required("PAIA_CANDIDATE_G01_ONLY")),user=try CandidateProductScratch.create();defer{try? FileManager.default.removeItem(at:user)}
        let runtime=try RimeRuntime(library:path.deletingLastPathComponent().appendingPathComponent("librime.1.dylib").path,shared:required("PAIA_CANDIDATE_SOURCES"),isolatedUser:user.path,dictionaryRevision:"authored-g01-only-negative",g01Library:path.path);defer{_ = runtime.close()}
        XCTAssertTrue(runtime.repairExtensionLoaded);XCTAssertFalse(runtime.mixedExtensionLoaded)
        let session=try runtime.makeSession(deferredCommit:true);defer{session.end()};_=try session.refresh()
        XCTAssertTrue(session.canRetainForRepair);XCTAssertFalse(session.canUseMixed);XCTAssertFalse(session.canBeginMixed)
        XCTAssertThrowsError(try session.beginMixed(binding:XCTUnwrap(session.idleExpressionBinding)))
        for c in "nihao"{_=try session.process(.text(String(c)))}
        let choice=try XCTUnwrap(session.repairChoices().rows.first{$0.anchor.text=="你好"});XCTAssertNil(try session.selectForRepair(choice).commit)
        let effect=try XCTUnwrap(session.commitEngineComposition().commit);XCTAssertEqual(effect.text,"你好");XCTAssertTrue(session.reserve(effect));XCTAssertFalse(session.reserve(effect))
        print("PRODUCT_G01_ONLY_NATIVE repair=true mixed=false actual_commit=1")
    }
}
#endif
