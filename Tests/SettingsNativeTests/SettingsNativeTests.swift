#if os(macOS)
import XCTest
import AppKit
import NativeHost
import EngineBridge
import SettingsCore
import LexiconCore

final class SettingsNativeTests:XCTestCase {
    @MainActor func key(_ text:String,_ view:NSTextView,code:UInt16=0)throws {
        let event=try XCTUnwrap(NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[],timestamp:0,windowNumber:view.window?.windowNumber ?? 0,context:nil,characters:text,charactersIgnoringModifiers:text,isARepeat:false,keyCode:code));view.keyDown(with:event)
    }
    @MainActor func type(_ raw:String,_ view:NSTextView)throws {for c in raw{try key(String(c),view,code:c==" " ? 49:0)}}
    @MainActor func send(_ button:NSButton){XCTAssertTrue(NSApp.sendAction(button.action!,to:button.target,from:button))}
    @MainActor func testFreshProcessSettingsStage()throws {
        _=NSApplication.shared
        let variables=ProcessInfo.processInfo.environment
        guard let stage=variables["PAIA_B3_TEST_STAGE"],let selected=variables["PAIA_B3_STORE"],let personalPath=variables["PAIA_B2_STORE"] else{throw XCTSkip("Explicit B3 synthetic stage not selected")}
        let directory=URL(fileURLWithPath:stage=="personal_corrupt" ? selected+"-personal":selected),personalURL=URL(fileURLWithPath:personalPath),file=directory.appendingPathComponent("settings.json")
        if stage=="controls" {let terms=try LexiconStore(directory:personalURL);_ = try terms.add(surface:"设置测例甲",reading:"she zhi ce li jia",expectedRevision:0);terms.close()}
        if stage=="settings_corrupt"{try Data("synthetic-corrupt-settings".utf8).write(to:file)}
        if stage=="settings_missing"{try FileManager.default.removeItem(at:file)}
        if stage=="personal_corrupt"{try Data("synthetic-corrupt-personal-authority".utf8).write(to:personalURL.appendingPathComponent("lexicon.json"));let saved=try SettingsStore(directory:directory);_ = try saved.save(SettingsValues(),expectedRevision:0);saved.close()}
        let environment=try PersonalLabEnvironment(environment:variables);defer{_ = environment.runtime.close();environment.store?.close()}
        if stage=="overlay_disabled"{environment.disableOverlayUntilRestart()}
        var rejectFlypy=stage=="restore_failed",dirtyFlypy=false
        var rejected:InputSession?
        let lab=NativeLabController(runtime:environment.runtime,configuredSession:{configuration in
            if rejectFlypy && configuration.spelling == .flypy {throw EngineError.closed}
            let session=try environment.makeSession(configuration:configuration)
            if dirtyFlypy && configuration.spelling == .flypy {_ = try session.process(.code(110));rejected=session}
            return session
        })
        let window=LabWindow(contentRect:NSRect(x:0,y:0,width:1100,height:830),styleMask:[.titled,.closable,.resizable],backing:.buffered,defer:false);window.isReleasedWhenClosed=false
        try lab.attach(to:window);window.orderFront(nil);window.makeKey();XCTAssertTrue(window.makeFirstResponder(lab.editor));defer{window.close()}
        let store=try? SettingsStore(directory:directory,fault:stage=="save_unknown" ? .afterPublication:nil);defer{store?.close()}
        let settings=SettingsController(lab:lab,store:store);settings.restoreAtStartup()
        let before=try? Data(contentsOf:file)
        if stage=="controls" {
            XCTAssertNotNil(store);XCTAssertNil(before)
            var count=0
            for spelling in LabSpelling.allCases {for traditional in [false,true]{for literal in [false,true]{for punctuation in [false,true]{
                lab.editor.string="";var next=LabConfiguration();next.spelling=spelling;next.traditional=traditional;next.literal=literal;next.chinesePunctuation=punctuation
                try lab.applyConfiguration(next);XCTAssertEqual(lab.configuration,next)
                if literal{try type("RAG 𠀀 e\u{301} 👩🏽‍💻",lab.editor);XCTAssertEqual(lab.editor.string,"RAG 𠀀 e\u{301} 👩🏽‍💻")}
                else{try type(spelling == .full ? "shurufa":"uurufa",lab.editor);try key(" ",lab.editor,code:49);try key(",",lab.editor);XCTAssertEqual(lab.editor.string,(traditional ? "輸入法":"输入法")+(punctuation ? "，":","))}
                XCTAssertEqual(try? Data(contentsOf:file),before);count+=1
            }}}};XCTAssertEqual(count,24)
            lab.editor.string="";try lab.applyConfiguration(LabConfiguration());let old=try XCTUnwrap(lab.editor.dispatcher)
            rejectFlypy=true;lab.spelling.selectItem(at:1);XCTAssertTrue(NSApp.sendAction(lab.spelling.action!,to:lab.spelling.target,from:lab.spelling))
            XCTAssertEqual(lab.configuration.spelling,.full);XCTAssertEqual(lab.spelling.indexOfSelectedItem,0);XCTAssertTrue(lab.editor.dispatcher===old);XCTAssertNoThrow(try old.session.refresh())
            rejectFlypy=false;dirtyFlypy=true;lab.spelling.selectItem(at:1)
            XCTAssertTrue(NSApp.sendAction(lab.spelling.action!,to:lab.spelling.target,from:lab.spelling))
            XCTAssertNotNil(rejected);XCTAssertThrowsError(try rejected!.refresh());XCTAssertTrue(lab.editor.dispatcher===old);XCTAssertEqual(lab.configuration.spelling,.full);dirtyFlypy=false
            try type("nihao",lab.editor);XCTAssertTrue(lab.hasComposition);XCTAssertFalse(settings.saveButton.isEnabled)
            let marked=lab.editor.string,range=lab.editor.markedRange(),generation=old.session.snapshot?.inputGeneration
            send(settings.saveButton);send(settings.defaultsButton)
            XCTAssertEqual(lab.editor.string,marked);XCTAssertEqual(lab.editor.markedRange(),range);XCTAssertEqual(old.session.snapshot?.inputGeneration,generation);XCTAssertNil(try? Data(contentsOf:file))
            try key(" ",lab.editor,code:49);XCTAssertEqual(lab.editor.string,"你好");XCTAssertEqual(old.insertCount,1)
            rejectFlypy=false;var held=LabConfiguration();held.traditional=true;held.deferredCommit=true;try lab.applyConfiguration(held);lab.editor.string=""
            try type("nihaoshurufashijie",lab.editor);try key(" ",lab.editor,code:49);lab.repairButton.performClick(nil);XCTAssertTrue(lab.inspectorVisible)
            let original=lab.editor.string;send(settings.saveButton);send(settings.defaultsButton);XCTAssertEqual(lab.editor.string,original);XCTAssertNil(try? Data(contentsOf:file));lab.cancelRepairButton.performClick(nil)
            lab.cancelCompositionButton.performClick(nil);send(settings.defaultsButton);XCTAssertEqual(lab.configuration,LabConfiguration())
            send(settings.saveButton);XCTAssertNotNil(try store?.snapshot());let savedBytes=try Data(contentsOf:file)
            try type("nihao",lab.editor);try key(" ",lab.editor,code:49);XCTAssertEqual(try Data(contentsOf:file),savedBytes)
            if variables["PAIA_CAPTURE_B3_LAYOUT"]=="1" {
                XCTAssertTrue(lab.editor.string.hasSuffix("你好"));lab.editor.scrollRangeToVisible(NSRange(location:lab.editor.string.utf16.count,length:0))
                lab.root.layoutSubtreeIfNeeded();lab.editor.needsDisplay=true;lab.root.displayIfNeeded()
                let bitmap=try XCTUnwrap(lab.root.bitmapImageRepForCachingDisplay(in:lab.root.bounds));lab.root.cacheDisplay(in:lab.root.bounds,to:bitmap)
                let png=try XCTUnwrap(bitmap.representation(using:.png,properties:[:])),encoded=png.base64EncodedString();var offset=encoded.startIndex,index=0
                let output=URL(fileURLWithPath:FileManager.default.currentDirectoryPath).appendingPathComponent("evidence/b3-run");try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true);try png.write(to:output.appendingPathComponent("settings-controls.png"))
                while offset<encoded.endIndex{let end=encoded.index(offset,offsetBy:3000,limitedBy:encoded.endIndex) ?? encoded.endIndex;FileHandle.standardError.write(Data(("PAIA_B3_IMAGE_\(index):"+encoded[offset..<end]+"\n").utf8));offset=end;index+=1}
            }
            let beforeClose=try Data(contentsOf:file);window.close();XCTAssertTrue(lab.isClosed)
            send(settings.saveButton);send(settings.defaultsButton);XCTAssertThrowsError(try lab.applyConfiguration(LabConfiguration()));XCTAssertNil(lab.editor.makeSession?())
            XCTAssertEqual(try Data(contentsOf:file),beforeClose)
        } else if stage=="save" {
            var next=LabConfiguration();next.spelling = .flypy;next.traditional=true;next.chinesePunctuation=true;next.deferredCommit=true
            try lab.applyConfiguration(next);send(settings.saveButton);XCTAssertEqual(try store?.snapshot()?.values,next.preferences)
        } else if stage=="restore" {
            XCTAssertEqual(lab.configuration.spelling,.flypy);XCTAssertTrue(lab.configuration.traditional);XCTAssertTrue(lab.configuration.chinesePunctuation);XCTAssertFalse(lab.configuration.deferredCommit)
            try type("uurufa",lab.editor);try key(" ",lab.editor,code:49);try key(",",lab.editor);XCTAssertEqual(lab.editor.string,"輸入法，");XCTAssertEqual(try? Data(contentsOf:file),before)
        } else if stage=="restore_failed" {
            XCTAssertEqual(lab.configuration,LabConfiguration());XCTAssertTrue(settings.status.stringValue.contains("Saved mode unavailable"))
            try type("nihao",lab.editor);try key(" ",lab.editor,code:49);XCTAssertEqual(lab.editor.string,"你好");XCTAssertEqual(try? Data(contentsOf:file),before)
        } else if stage=="save_unknown" {
            send(settings.saveButton);XCTAssertFalse(settings.saveButton.isEnabled);XCTAssertTrue(settings.status.stringValue.contains("not confirmed"))
            let published=try Data(contentsOf:file);send(settings.saveButton)
            try type("uurufa",lab.editor);try key(" ",lab.editor,code:49);XCTAssertEqual(lab.editor.string,"輸入法")
            XCTAssertFalse(settings.saveButton.isEnabled);XCTAssertEqual(try Data(contentsOf:file),published)
        } else if stage=="overlay_disabled" {
            XCTAssertTrue(environment.pendingRestart);try lab.applyConfiguration(LabConfiguration());XCTAssertTrue(lab.editor.dispatcher!.session.supportsRepair)
            try type("nihao",lab.editor);try key(" ",lab.editor,code:49);XCTAssertEqual(lab.editor.string,"你好");XCTAssertEqual(try? Data(contentsOf:file),before)
        } else if ["settings_corrupt","settings_missing"].contains(stage) {
            XCTAssertNil(store);XCTAssertFalse(settings.saveButton.isEnabled);XCTAssertEqual(lab.configuration,LabConfiguration())
            try type("nihao",lab.editor);try key(" ",lab.editor,code:49);send(settings.saveButton);send(settings.defaultsButton)
            XCTAssertEqual(lab.editor.string,"你好");XCTAssertEqual(try? Data(contentsOf:file),before)
        } else if stage=="personal_corrupt" {
            XCTAssertTrue(environment.authorityUnavailable);XCTAssertTrue(environment.resources.overlaySchemas.isEmpty)
            try type("nihao",lab.editor);try key(" ",lab.editor,code:49);XCTAssertEqual(lab.editor.string,"你好");XCTAssertTrue(lab.editor.dispatcher!.session.supportsRepair)
        } else{XCTFail("Unknown stage")}
        print("B3_APPKIT_HOST stage=\(stage); synthetic fixtures only; no input history persisted")
    }
}
#endif
