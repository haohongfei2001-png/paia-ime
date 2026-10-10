#if os(macOS)
import XCTest
import AppKit
import NativeHost
import EngineBridge
import SettingsCore

final class SettingsRecoveryHostTests:XCTestCase {
    static var environment:ResearchLabEnvironment!
    override class func setUp(){super.setUp();do{environment=try ResearchLabEnvironment()}catch{XCTFail("B5 native startup: \(error)")}}
    @MainActor func make(_ fault:SettingsTestFault,seed:Bool=false)throws->(NativeLabController,LabWindow,SettingsStore,SettingsController,URL){
        _=NSApplication.shared
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent("paia-b5-host-"+UUID().uuidString)
        if seed{let initial=try SettingsStore(directory:directory);_ = try initial.save(SettingsValues(),expectedRevision:0);initial.close()}
        let store=try SettingsStore(directory:directory,fault:fault),lab=NativeLabController(runtime:try XCTUnwrap(Self.environment?.runtime))
        let window=LabWindow(contentRect:NSRect(x:0,y:0,width:1100,height:830),styleMask:[.titled,.closable,.resizable],backing:.buffered,defer:false)
        window.isReleasedWhenClosed=false;try lab.attach(to:window);window.orderFront(nil);window.makeKey();XCTAssertTrue(window.makeFirstResponder(lab.editor))
        let controller=SettingsController(lab:lab,store:store);controller.restoreAtStartup();return(lab,window,store,controller,directory)
    }
    @MainActor func key(_ text:String,_ view:NSTextView,code:UInt16=0)throws {
        let event=try XCTUnwrap(NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[],timestamp:0,windowNumber:view.window?.windowNumber ?? 0,context:nil,characters:text,charactersIgnoringModifiers:text,isARepeat:false,keyCode:code));view.keyDown(with:event)
    }
    @MainActor func type(_ raw:String,_ view:NSTextView)throws{for c in raw{try key(String(c),view,code:c==" " ? 49:0)}}
    @MainActor func send(_ button:NSButton){XCTAssertTrue(NSApp.sendAction(button.action!,to:button.target,from:button))}
    @MainActor func capture(_ lab:NativeLabController,name:String)throws {
        lab.root.layoutSubtreeIfNeeded();lab.root.displayIfNeeded()
        let bitmap=try XCTUnwrap(lab.root.bitmapImageRepForCachingDisplay(in:lab.root.bounds));lab.root.cacheDisplay(in:lab.root.bounds,to:bitmap)
        let data=try XCTUnwrap(bitmap.representation(using:.png,properties:[:]))
        let output=URL(fileURLWithPath:FileManager.default.currentDirectoryPath).appendingPathComponent("evidence/b5-run")
        try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true);try data.write(to:output.appendingPathComponent(name+".png"))
        let encoded=data.base64EncodedString();var offset=encoded.startIndex,index=0
        while offset<encoded.endIndex{let end=encoded.index(offset,offsetBy:3000,limitedBy:encoded.endIndex) ?? encoded.endIndex;FileHandle.standardError.write(Data(("PAIA_B5_\(name)_IMAGE_\(index):"+encoded[offset..<end]+"\n").utf8));offset=end;index+=1}
    }
    @MainActor func testPublishedVerificationKeepsCurrentModeSessionAndCommitIdentity()throws {
        let(lab,window,store,settings,directory)=try make(.afterPublication);defer{window.close();store.close();try? FileManager.default.removeItem(at:directory)}
        var attempted=LabConfiguration();attempted.spelling = .flypy;attempted.traditional=true;try lab.applyConfiguration(attempted)
        send(settings.saveButton);XCTAssertFalse(settings.saveButton.isEnabled);XCTAssertTrue(settings.verifyButton.isEnabled);XCTAssertTrue(store.hasUnverifiedSave)
        let file=directory.appendingPathComponent("settings.json"),published=try Data(contentsOf:file)
        try lab.applyConfiguration(LabConfiguration());let host=try XCTUnwrap(lab.editor.dispatcher)
        try type("nihao",lab.editor);XCTAssertFalse(settings.verifyButton.isEnabled);let marked=lab.editor.string,range=lab.editor.markedRange()
        send(settings.verifyButton);XCTAssertTrue(store.hasUnverifiedSave);XCTAssertEqual(lab.editor.string,marked);XCTAssertEqual(lab.editor.markedRange(),range);XCTAssertEqual(try Data(contentsOf:file),published)
        try key(" ",lab.editor,code:49);XCTAssertEqual(lab.editor.string,"你好");XCTAssertEqual(host.insertCount,1);XCTAssertTrue(settings.verifyButton.isEnabled)
        let generation=host.session.snapshot?.inputGeneration,key=host.session.key
        send(settings.verifyButton);XCTAssertFalse(settings.verifyButton.isEnabled);XCTAssertTrue(settings.saveButton.isEnabled);XCTAssertFalse(store.hasUnverifiedSave)
        XCTAssertEqual(try store.snapshot()?.revision,1);XCTAssertEqual(try store.snapshot()?.values,attempted.preferences)
        XCTAssertEqual(lab.configuration,LabConfiguration());XCTAssertTrue(lab.editor.dispatcher===host);XCTAssertEqual(host.session.key,key);XCTAssertEqual(host.session.snapshot?.inputGeneration,generation)
        XCTAssertEqual(try Data(contentsOf:file),published);XCTAssertTrue(settings.status.stringValue.contains("save verified"))
        send(settings.verifyButton);XCTAssertEqual(try Data(contentsOf:file),published);XCTAssertEqual(host.insertCount,1)
        try capture(lab,name:"verified-save")
        try type("nihao ",lab.editor);XCTAssertEqual(lab.editor.string,"你好你好");XCTAssertEqual(host.insertCount,2);XCTAssertEqual(try Data(contentsOf:file),published)
        send(settings.saveButton);XCTAssertEqual(try store.snapshot()?.revision,2);XCTAssertEqual(try store.snapshot()?.values,LabConfiguration().preferences)
    }
    @MainActor func testPreviousEmptyAndExistingStateRequireANewExplicitSave()throws {
        for seed in [false,true] {
            let(lab,window,store,settings,directory)=try make(.beforePublication,seed:seed);defer{window.close();store.close();try? FileManager.default.removeItem(at:directory)}
            let file=directory.appendingPathComponent("settings.json"),before=try? Data(contentsOf:file)
            var next=LabConfiguration();next.traditional=true;try lab.applyConfiguration(next)
            send(settings.saveButton);XCTAssertFalse(settings.saveButton.isEnabled);XCTAssertTrue(settings.verifyButton.isEnabled)
            let host=try XCTUnwrap(lab.editor.dispatcher);send(settings.verifyButton)
            XCTAssertEqual(try? Data(contentsOf:file),before);XCTAssertEqual(try store.snapshot()?.revision,seed ? 1:nil)
            XCTAssertEqual(lab.configuration,next);XCTAssertTrue(lab.editor.dispatcher===host);XCTAssertTrue(settings.status.stringValue.contains("Previous saved state verified"))
            send(settings.verifyButton);XCTAssertEqual(try? Data(contentsOf:file),before)
            try type("nihao ",lab.editor);XCTAssertEqual(lab.editor.string,"你好");XCTAssertEqual(host.insertCount,1);XCTAssertEqual(try? Data(contentsOf:file),before)
            send(settings.saveButton);XCTAssertEqual(try store.snapshot()?.revision,seed ? 2:1);XCTAssertEqual(try store.snapshot()?.values,next.preferences)
        }
    }
    @MainActor func testForeignMarkRepairAndClosedWindowCannotResolvePendingSave()throws {
        let(lab,window,store,settings,directory)=try make(.afterPublication);defer{window.close();store.close();try? FileManager.default.removeItem(at:directory)}
        send(settings.saveButton);let file=directory.appendingPathComponent("settings.json"),bytes=try Data(contentsOf:file)
        var held=LabConfiguration();held.deferredCommit=true;try lab.applyConfiguration(held)
        try type("nihaoshurufashijie ",lab.editor);lab.repairButton.performClick(nil);XCTAssertTrue(lab.inspectorVisible)
        let original=lab.editor.string;send(settings.verifyButton);XCTAssertEqual(lab.editor.string,original);XCTAssertTrue(store.hasUnverifiedSave);XCTAssertEqual(try Data(contentsOf:file),bytes)
        lab.cancelRepairButton.performClick(nil);lab.cancelCompositionButton.performClick(nil)
        var literal=LabConfiguration();literal.literal=true;try lab.applyConfiguration(literal)
        lab.editor.setMarkedText("外部👩🏽‍💻",selectedRange:NSRange(location:2,length:0),replacementRange:NSRange(location:NSNotFound,length:0));lab.editor.didChangeState?()
        let text=lab.editor.string,mark=lab.editor.markedRange();XCTAssertFalse(settings.verifyButton.isEnabled)
        send(settings.verifyButton);XCTAssertEqual(lab.editor.string,text);XCTAssertEqual(lab.editor.markedRange(),mark);XCTAssertTrue(store.hasUnverifiedSave)
        lab.editor.unmarkText();lab.editor.string="";try lab.applyConfiguration(LabConfiguration())
        window.close();XCTAssertTrue(lab.isClosed);send(settings.verifyButton);send(settings.saveButton)
        XCTAssertTrue(store.hasUnverifiedSave);XCTAssertEqual(try Data(contentsOf:file),bytes);XCTAssertEqual(lab.editor.string,"")
    }
    @MainActor func testCorruptOutcomeStaysBlockedWhileNativeInputContinues()throws {
        let(lab,window,store,settings,directory)=try make(.afterPublication);defer{window.close();store.close();try? FileManager.default.removeItem(at:directory)}
        send(settings.saveButton);let file=directory.appendingPathComponent("settings.json"),corrupt=Data("synthetic-corrupt-outcome".utf8);try corrupt.write(to:file)
        send(settings.verifyButton);XCTAssertTrue(store.hasUnverifiedSave);XCTAssertFalse(settings.saveButton.isEnabled);XCTAssertTrue(settings.status.stringValue.contains("cannot be verified"))
        send(settings.verifyButton);send(settings.saveButton);XCTAssertEqual(try Data(contentsOf:file),corrupt)
        let host=try XCTUnwrap(lab.editor.dispatcher);try type("nihao ",lab.editor);XCTAssertEqual(lab.editor.string,"你好");XCTAssertEqual(host.insertCount,1)
        XCTAssertFalse(settings.saveButton.isEnabled);XCTAssertTrue(settings.verifyButton.isEnabled);XCTAssertEqual(try Data(contentsOf:file),corrupt)
        try capture(lab,name:"blocked-save")
    }
    @MainActor func testChangedAuthorityBeforeSaveDoesNotOfferVerification()throws {
        let(lab,window,store,settings,directory)=try make(.afterPublication,seed:true);defer{window.close();store.close();try? FileManager.default.removeItem(at:directory)}
        let file=directory.appendingPathComponent("settings.json"),foreign=try SettingsCodec.encode(SettingsDocument(revision:2,values:SettingsValues()))
        try foreign.write(to:file);send(settings.saveButton)
        XCTAssertFalse(store.hasUnverifiedSave);XCTAssertFalse(settings.saveButton.isEnabled);XCTAssertFalse(settings.verifyButton.isEnabled)
        XCTAssertTrue(settings.status.stringValue.contains("without a verifiable attempt"));send(settings.verifyButton)
        XCTAssertEqual(try Data(contentsOf:file),foreign);try type("nihao ",lab.editor);XCTAssertEqual(lab.editor.string,"你好")
        XCTAssertFalse(settings.verifyButton.isEnabled);XCTAssertEqual(try Data(contentsOf:file),foreign)
    }
    @MainActor func testUnavailableStartupDoesNotOfferVerificationOrCreateStore()throws {
        _=NSApplication.shared
        let lab=NativeLabController(runtime:try XCTUnwrap(Self.environment?.runtime)),window=LabWindow(contentRect:NSRect(x:0,y:0,width:1000,height:800),styleMask:[.titled],backing:.buffered,defer:false)
        window.isReleasedWhenClosed=false;try lab.attach(to:window);defer{window.close()}
        let settings=SettingsController(lab:lab,store:nil);settings.restoreAtStartup();XCTAssertFalse(settings.verifyButton.isEnabled)
        send(settings.verifyButton);send(settings.saveButton);XCTAssertFalse(settings.saveButton.isEnabled);XCTAssertFalse(settings.verifyButton.isEnabled);XCTAssertEqual(lab.configuration,LabConfiguration())
    }
}
#endif
