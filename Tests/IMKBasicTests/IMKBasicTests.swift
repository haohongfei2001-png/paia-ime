#if os(macOS)
import XCTest
import AppKit
import IMKHost
import IMKTestClient
import NativeHost
import EngineBridge
import SessionCore
import SettingsCore
import LexiconCore

final class IMKBasicTests:XCTestCase {
    @MainActor func key(_ text:String,code:UInt16=0,modifiers:NSEvent.ModifierFlags=[])throws->NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:modifiers,timestamp:0,windowNumber:0,context:nil,characters:text,charactersIgnoringModifiers:text,isARepeat:false,keyCode:code))
    }
    @MainActor func send(_ button:NSButton){XCTAssertTrue(NSApp.sendAction(button.action!,to:button.target,from:button))}
    @MainActor func type(_ text:String,_ driver:IMKControllerDriver,_ client:PAIAIMKTestClient)throws {
        for character in text {XCTAssertTrue(driver.handle(try key(String(character)),client:client))}
    }
    @MainActor func activate(_ driver:IMKControllerDriver,_ client:PAIAIMKTestClient)throws {
        XCTAssertEqual(driver.activate(try XCTUnwrap(IMKTextInputBridge(client))),.ready)
    }
    @MainActor func testResearchModesSettingsAndPersonalTermsThroughIMKDriver()throws {
        var variables=ProcessInfo.processInfo.environment
        guard let stage=variables["PAIA_IMK_BASIC_STAGE"],let selected=variables["PAIA_B3_STORE"],let personalPath=variables["PAIA_B2_STORE"] else{throw XCTSkip("Explicit unbundled IMK basic-controls lane not selected")}
        _=NSApplication.shared
        if NSApp.activationPolicy() != .accessory{_ = NSApp.setActivationPolicy(.accessory)}
        variables["PAIA_IMK_RESEARCH"]="1";variables["PAIA_B3_SETTINGS"]="0"
        if stage.hasPrefix("authority_"){variables["PAIA_B2_STORE"]=personalPath+"-"+stage}
        if stage=="controls" || stage.hasPrefix("authority_") {
            let seed=try LexiconStore(directory:URL(fileURLWithPath:variables["PAIA_B2_STORE"]!));defer{seed.close()}
            _ = try seed.add(surface:"原生显式甲",reading:"yuan sheng xian shi jia",pin:true,expectedRevision:0)
        }
        let environment=try IMKServiceEnvironment(environment:variables);defer{environment.close()}
        let fault:SettingsTestFault?=stage=="verify_previous" ? .beforePublication:stage=="verify_published" ? .afterPublication:stage=="verify_unresolved" ? .afterInitialization:nil
        let directory=URL(fileURLWithPath:stage.hasPrefix("verify_") ? selected+"-"+stage:selected)
        let store=try SettingsStore(directory:directory,fault:fault);defer{store.close()}
        var rejectFlypy=stage=="restore_failed",dirtyFlypy=false
        var preparedCallback:(()->Void)?,dirtySession:InputSession?
        let workspace=IMKWorkspace(settingsStore:store,personalStore:environment.personal?.store,resourceDescription:environment.workspace.resourceDescription,makeSession:{configuration in
            if rejectFlypy && configuration.spelling == .flypy{throw EngineError.closed}
            let session=try environment.makeSession(configuration)
            if dirtyFlypy && configuration.spelling == .flypy{_ = try session.process(.text("n"));dirtySession=session}
            let callback=preparedCallback;preparedCallback=nil;callback?()
            return session
        },disablePersonal:{environment.personal?.disableOverlayUntilRestart()})
        let preferences=IMKPreferencesController(workspace:workspace);defer{preferences.close();workspace.close()}
        var hideCallback:(()->Void)?
        let driver=workspace.makeDriver(hide:{let callback=hideCallback;hideCallback=nil;callback?()},present:{_,_,_ in})
        let other=workspace.makeDriver(hide:{},present:{_,_,_ in})
        let a=PAIAIMKTestClient(text:""),b=PAIAIMKTestClient(text:"")
        defer{driver.close();other.close()}
        let file=directory.appendingPathComponent("settings.json"),before=try? Data(contentsOf:file)
        if stage=="controls" {
            preferences.show();preferences.openTerms(nil)
            let terms=try XCTUnwrap(preferences.terms),personal=try XCTUnwrap(environment.personal),authority=try XCTUnwrap(personal.store)
            try activate(driver,a);try type("yuanshengxianshijia",driver,a)
            XCTAssertEqual(driver.coordinator.snapshot?.rows.first?.text,"原生显式甲")
            XCTAssertTrue(driver.handle(try key("\u{1b}",code:53),client:a))
            var cases=0
            for spelling in LabSpelling.allCases {for traditional in [false,true]{for literal in [false,true]{for punctuation in [false,true]{
                var c=LabConfiguration();c.spelling=spelling;c.traditional=traditional;c.literal=literal;c.chinesePunctuation=punctuation
                try preferences.applyConfiguration(c);a.view.string="";a.view.setSelectedRange(NSRange(location:0,length:0));try activate(driver,a)
                if literal {
                    let inserts=a.insertCalls
                    for text in ["RAG ","𠀀","e\u{301}","👩🏽‍💻"] {
                        XCTAssertFalse(driver.handle(try key(text),client:a))
                        // Model the receiving host's ordinary text-system action
                        // after IMK returned false; this is not an IME insert path.
                        a.view.insertText(text,replacementRange:a.view.selectedRange())
                    }
                    XCTAssertEqual(a.view.string,"RAG 𠀀e\u{301}👩🏽‍💻");XCTAssertEqual(a.insertCalls,inserts)
                    for (text,code) in [("\r",UInt16(36)),("\t",UInt16(48)),("",UInt16(123))]{XCTAssertFalse(driver.handle(try key(text,code:code),client:a))}
                } else {
                    let inserts=a.insertCalls
                    try type(spelling == .full ? "shurufa":"uurufa",driver,a)
                    XCTAssertTrue(driver.handle(try key(" ",code:49),client:a));XCTAssertEqual(a.insertCalls,inserts+1)
                    let punct=try key(",");if !driver.handle(punct,client:a){a.view.insertText(",",replacementRange:a.view.selectedRange())}
                    XCTAssertEqual(a.view.string,(traditional ? "輸入法":"输入法")+(punctuation ? "，":","))
                }
                XCTAssertEqual(try? Data(contentsOf:file),before);cases+=1
            }}}};XCTAssertEqual(cases,24)
            // Idle mode failures preserve the existing engine and configuration.
            try preferences.applyConfiguration(LabConfiguration());try activate(driver,a)
            let old=try XCTUnwrap(driver.coordinator.session),original=workspace.configuration
            var flypy=original;flypy.spelling = .flypy;rejectFlypy=true
            XCTAssertThrowsError(try preferences.applyConfiguration(flypy));XCTAssertTrue(driver.coordinator.session===old);XCTAssertEqual(workspace.configuration,original);XCTAssertNoThrow(try old.refresh())
            rejectFlypy=false;dirtyFlypy=true;XCTAssertThrowsError(try preferences.applyConfiguration(flypy))
            XCTAssertTrue(driver.coordinator.session===old);XCTAssertThrowsError(try XCTUnwrap(dirtySession).refresh());dirtyFlypy=false
            // Any client's actual composition blocks settings and already-open manager actions.
            try activate(other,b);try type("nihao",other,b)
            let mark=b.view.string,range=b.view.markedRange(),generation=other.coordinator.snapshot?.inputGeneration,revision=try authority.snapshot().revision
            send(preferences.settings.saveButton);send(preferences.settings.defaultsButton)
            XCTAssertThrowsError(try preferences.applyConfiguration(flypy));terms.surface.stringValue="阻止写入";terms.reading.stringValue="zu zhi xie ru";send(terms.addButton)
            XCTAssertEqual(try authority.snapshot().revision,revision);XCTAssertNil(try? Data(contentsOf:file))
            XCTAssertEqual(b.view.string,mark);XCTAssertEqual(b.view.markedRange(),range);XCTAssertEqual(other.coordinator.snapshot?.inputGeneration,generation)
            XCTAssertTrue(other.handle(try key(" ",code:49),client:b));XCTAssertEqual(b.view.string,"你好")
            // Nested mutation from a client getter cannot enter the global gate.
            a.onSelectedRange={XCTAssertThrowsError(try workspace.applyConfiguration(flypy))}
            XCTAssertTrue(driver.handle(try key("n"),client:a));XCTAssertEqual(workspace.configuration,original)
            XCTAssertTrue(driver.handle(try key("\u{1b}",code:53),client:a))
            // Callback during staging causes an abort, with no fabricated engine key.
            preparedCallback={XCTAssertFalse(driver.handle(try! self.key("x"),client:a))}
            XCTAssertThrowsError(try preferences.applyConfiguration(flypy));XCTAssertEqual(workspace.configuration,original);XCTAssertNil(driver.coordinator.session)
            try activate(driver,a)
            hideCallback={XCTAssertThrowsError(try workspace.applyConfiguration(original));XCTAssertEqual(other.activate(try! XCTUnwrap(IMKTextInputBridge(b))),.superseded)}
            try preferences.applyConfiguration(flypy);XCTAssertEqual(workspace.configuration,flypy)
            try preferences.applyConfiguration(original);try activate(driver,a);try activate(other,b)
            let ownedA=try XCTUnwrap(driver.coordinator.session),ownedB=try XCTUnwrap(other.coordinator.session)
            terms.surface.stringValue="原生新词乙";terms.reading.stringValue="yuan sheng xin ci yi";send(terms.addButton)
            XCTAssertTrue(personal.pendingRestart);XCTAssertThrowsError(try ownedA.refresh());XCTAssertThrowsError(try ownedB.refresh())
            XCTAssertEqual(try authority.snapshot().revision,revision+1)
            // Import preview is immutable, but a later Apply must reacquire global idle.
            let source=try LexiconStore(directory:directory.appendingPathComponent("import-source"));defer{source.close()}
            _ = try source.add(surface:"明确导入丙",reading:"ming que dao ru bing",expectedRevision:0)
            let chosen=directory.appendingPathComponent("chosen.json");try SelectedLexiconFile.write(source.exportData(),to:chosen)
            try terms.previewSelectedFile(chosen);let apply=try XCTUnwrap(terms.importActions.arrangedSubviews.first as? NSButton)
            try activate(other,b);try type("nihao",other,b);let prior=try authority.snapshot().revision
            send(apply);XCTAssertEqual(try authority.snapshot().revision,prior)
            XCTAssertThrowsError(try terms.writeSelectedExport(directory.appendingPathComponent("blocked-export.json")))
            XCTAssertTrue(other.handle(try key("\u{1b}",code:53),client:b));send(apply);XCTAssertEqual(try authority.snapshot().revision,prior+1)
            send(apply);XCTAssertEqual(try authority.snapshot().revision,prior+1)
            // Edit/pin/delete/tombstone-restore use the same guarded manager.
            let row=try XCTUnwrap(terms.rows.arrangedSubviews.first as? NSButton);send(row)
            terms.pin.state = .on;let edit=try XCTUnwrap(terms.actions.arrangedSubviews.first as? NSButton);send(edit)
            let edited=try authority.snapshot();XCTAssertTrue(edited.terms[0].explicitPin)
            send(try XCTUnwrap(terms.rows.arrangedSubviews.first as? NSButton))
            let remove=try XCTUnwrap(terms.actions.arrangedSubviews.last as? NSButton);send(remove)
            XCTAssertTrue(try authority.snapshot().terms[0].isDeleted)
            send(try XCTUnwrap(terms.rows.arrangedSubviews.first as? NSButton));send(try XCTUnwrap(terms.actions.arrangedSubviews.last as? NSButton))
            XCTAssertFalse(try authority.snapshot().terms[0].isDeleted)
            let restoredRevision=try authority.snapshot().revision;send(remove);send(edit);XCTAssertEqual(try authority.snapshot().revision,restoredRevision)
            // A retained framework controller that has closed is no longer a management owner.
            let closed=workspace.makeDriver(hide:{},present:{_,_,_ in}),c=PAIAIMKTestClient(text:"")
            try activate(closed,c);closed.close();XCTAssertTrue(workspace.isIdle);try preferences.applyConfiguration(original)
            let uncertain=workspace.makeDriver(hide:{},present:{_,_,_ in}),u=PAIAIMKTestClient(text:"")
            try activate(uncertain,u);u.onMark={u.view.string="foreign"}
            XCTAssertTrue(uncertain.handle(try key("n"),client:u));XCTAssertEqual(uncertain.coordinator.outcome,.outcomeUnknown)
            XCTAssertFalse(workspace.isIdle);uncertain.close();XCTAssertTrue(workspace.isIdle)
            let foreign=u.view.string;try preferences.applyConfiguration(original);XCTAssertEqual(u.view.string,foreign)
            // Actual shared settings buttons; normal IMK input never saves.
            send(preferences.settings.saveButton);let saved=try Data(contentsOf:file)
            try activate(driver,a);try type("nihao",driver,a);XCTAssertTrue(driver.handle(try key(" ",code:49),client:a));XCTAssertEqual(try Data(contentsOf:file),saved)
            preferences.show();preferences.root.layoutSubtreeIfNeeded();preferences.root.displayIfNeeded()
            let bitmap=try XCTUnwrap(preferences.root.bitmapImageRepForCachingDisplay(in:preferences.root.bounds));preferences.root.cacheDisplay(in:preferences.root.bounds,to:bitmap)
            let png=try XCTUnwrap(bitmap.representation(using:.png,properties:[:])),encoded=Array(png.base64EncodedString())
            for i in stride(from:0,to:encoded.count,by:1800){print("PAIA_IMK_SETTINGS_IMAGE_\(i/1800):\(String(encoded[i..<min(i+1800,encoded.count)]))")}
            print("IMK_BASIC 24 real resource/mode combinations; two-client management gate; staged failure and reentry; explicit overlay/store/import actions; no installation")
        } else if stage=="save" {
            var c=LabConfiguration();c.spelling = .flypy;c.traditional=true;c.chinesePunctuation=true
            try preferences.applyConfiguration(c);send(preferences.settings.saveButton);XCTAssertEqual(try store.snapshot()?.values,c.preferences)
        } else if stage=="restore" {
            XCTAssertEqual(workspace.configuration.spelling,.flypy);XCTAssertTrue(workspace.configuration.traditional);XCTAssertTrue(workspace.configuration.chinesePunctuation)
            try activate(driver,a);try type("uurufa",driver,a);XCTAssertTrue(driver.handle(try key(" ",code:49),client:a));XCTAssertTrue(driver.handle(try key(","),client:a));XCTAssertEqual(a.view.string,"輸入法，");XCTAssertEqual(try Data(contentsOf:file),before)
        } else if stage=="restore_failed" {
            XCTAssertEqual(workspace.configuration,LabConfiguration());XCTAssertTrue(preferences.settings.status.stringValue.contains("Saved mode unavailable"))
            try activate(driver,a);try type("nihao",driver,a);XCTAssertTrue(driver.handle(try key(" ",code:49),client:a));XCTAssertEqual(a.view.string,"你好");XCTAssertEqual(try Data(contentsOf:file),before)
        } else if stage=="authority_oversized" {
            let personal=try XCTUnwrap(environment.personal);XCTAssertFalse(personal.pendingRestart)
            preferences.show();preferences.openTerms(nil);let manager=try XCTUnwrap(preferences.terms)
            try activate(driver,a);let old=try XCTUnwrap(driver.coordinator.session)
            try Data(repeating:32,count:LexiconRules.maximumBytes+1).write(to:URL(fileURLWithPath:variables["PAIA_B2_STORE"]!).appendingPathComponent("lexicon.json"))
            manager.surface.stringValue="拒绝过大权威";manager.reading.stringValue="ju jue guo da quan wei";send(manager.addButton)
            XCTAssertTrue(personal.pendingRestart);XCTAssertThrowsError(try old.refresh());XCTAssertTrue(manager.status.stringValue.contains("authority unavailable"))
        } else if stage=="authority_changed" {
            let personal=try XCTUnwrap(environment.personal);XCTAssertFalse(personal.pendingRestart)
            try activate(driver,a);let old=try XCTUnwrap(driver.coordinator.session)
            try Data("authored corrupt authority".utf8).write(to:URL(fileURLWithPath:variables["PAIA_B2_STORE"]!).appendingPathComponent("lexicon.json"))
            preferences.show();preferences.openTerms(nil)
            XCTAssertNil(preferences.terms);XCTAssertTrue(personal.pendingRestart);XCTAssertThrowsError(try old.refresh())
            try activate(driver,a);try type("nihao",driver,a);XCTAssertTrue(driver.handle(try key(" ",code:49),client:a));XCTAssertEqual(a.view.string,"你好")
        } else if stage.hasPrefix("verify_") {
            var c=LabConfiguration();c.spelling = .natural;try preferences.applyConfiguration(c)
            send(preferences.settings.saveButton);let bytes=try? Data(contentsOf:file)
            XCTAssertTrue(store.hasUnverifiedSave);XCTAssertFalse(preferences.settings.saveButton.isEnabled)
            try preferences.applyConfiguration(LabConfiguration());let mode=workspace.configuration
            send(preferences.settings.verifyButton);XCTAssertEqual(workspace.configuration,mode);XCTAssertEqual(try? Data(contentsOf:file),bytes)
            if stage=="verify_unresolved"{XCTAssertTrue(store.hasUnverifiedSave);XCTAssertFalse(preferences.settings.saveButton.isEnabled)}
            else{XCTAssertFalse(store.hasUnverifiedSave);XCTAssertTrue(preferences.settings.saveButton.isEnabled);XCTAssertEqual(try store.snapshot()?.values,stage=="verify_published" ? c.preferences:nil)}
            try activate(driver,a);try type("nihao",driver,a);XCTAssertTrue(driver.handle(try key(" ",code:49),client:a));XCTAssertEqual(a.view.string,"你好");XCTAssertEqual(try? Data(contentsOf:file),bytes)
        } else {XCTFail("Unknown explicit test stage")}
        XCTAssertEqual(a.documentLengthCalls,0);XCTAssertEqual(b.documentLengthCalls,0)
        print("IMK_BASIC_STAGE \(stage) ENGINE_NATIVE + APPKIT_HOST; authored stores and NSTextView protocol fixtures only")
    }
}
#endif
