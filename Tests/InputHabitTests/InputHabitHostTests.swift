#if os(macOS)
import XCTest
import AppKit
import IMKHost
import IMKTestClient
import EngineBridge
import SessionCore
import SettingsCore

final class InputHabitHostTests:XCTestCase {
    static var environment:ResearchLabEnvironment!
    override class func setUp(){super.setUp();do{environment=try ResearchLabEnvironment()}catch{XCTFail("Verified habits engine startup failed: \(error)")}}
    @MainActor func key(_ text:String="",_ code:UInt16=0)throws->NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[],timestamp:0,windowNumber:0,context:nil,characters:text,charactersIgnoringModifiers:text,isARepeat:false,keyCode:code))
    }
    @MainActor func client(_ id:String)->PAIAIMKTestClient {
        _=NSApplication.shared;let c=PAIAIMKTestClient(text:"prefix");c.applicationIdentifier=id;return c
    }
    @MainActor func workspace() -> IMKWorkspace {
        IMKWorkspace(resourceDescription:"Explicit research qualification",makeSession:{try Self.environment.runtime.makeSession(schema:$0.schema)})
    }
    @MainActor func activate(_ d:IMKControllerDriver,_ c:PAIAIMKTestClient)throws {
        XCTAssertEqual(d.activate(try XCTUnwrap(IMKTextInputBridge(c))),.ready)
    }
    @MainActor func action(_ kind:InputHabitActionKind,_ d:IMKControllerDriver)throws {
        d.performInputHabitMenuAction(try XCTUnwrap(d.inputHabitMenuAction(kind)))
    }
    @MainActor func testTwoApplicationModesNeverChangeOtherComposition()throws {
        let w=workspace();defer{w.close()};var cfg=LabConfiguration();cfg.initialModes=["dev.paia.a":.literal,"dev.paia.b":.chinese];try w.applyConfiguration(cfg)
        let a=client("dev.paia.a"),b=client("dev.paia.b"),da=w.makeDriver(hide:{},present:{_,_,_ in}),db=w.makeDriver(hide:{},present:{_,_,_ in})
        try activate(db,b);for c in "nihao"{XCTAssertTrue(db.handle(try key(String(c)),client:b))}
        let snapshot=try XCTUnwrap(db.coordinator.snapshot),marked=b.view.string
        try activate(da,a);XCTAssertTrue(da.usesLiteralMode);XCTAssertFalse(da.handle(try key("R"),client:a));a.view.insertText("R",replacementRange:a.view.selectedRange())
        XCTAssertFalse(da.handle(try key("ü"),client:a));a.view.insertText("ü",replacementRange:a.view.selectedRange())
        XCTAssertEqual(a.applicationIdentifierCalls,1);XCTAssertEqual(a.insertCalls,0)
        XCTAssertEqual(db.coordinator.snapshot?.inputGeneration,snapshot.inputGeneration);XCTAssertEqual(b.view.string,marked)
        var changed=cfg;changed.initialModes["dev.paia.b"] = .literal
        XCTAssertThrowsError(try w.applyConfiguration(changed));XCTAssertEqual(w.configuration,cfg)
        XCTAssertTrue(db.handle(try key(" ",49),client:b));XCTAssertEqual(b.view.string,"prefix你好");XCTAssertEqual(b.insertCalls,1)
        print("HABIT_APPLICATION_NATIVE two actual engine/NSTextView owners; composing client unchanged; app ID read once per activation")
    }
    @MainActor func testExplicitActivationModeSurvivesPassthroughAndUnrelatedRetirement()throws {
        let w=workspace();defer{w.close()};let c=client("dev.paia.default"),d=w.makeDriver(hide:{},present:{_,_,_ in})
        try activate(d,c);try action(.literal,d)
        for text in ["a","b"]{XCTAssertFalse(d.handle(try key(text),client:c));c.view.insertText(text,replacementRange:c.view.selectedRange())}
        XCTAssertTrue(d.usesLiteralMode);XCTAssertEqual(c.applicationIdentifierCalls,1)
        try w.withIdleAccess{w.personalAuthorityChanged()}
        XCTAssertFalse(d.handle(try key("c"),client:c));c.view.insertText("c",replacementRange:c.view.selectedRange())
        XCTAssertTrue(d.usesLiteralMode);XCTAssertEqual(c.applicationIdentifierCalls,1)
        try action(.chinese,d);XCTAssertFalse(d.usesLiteralMode)
        for ch in "nihao"{XCTAssertTrue(d.handle(try key(String(ch)),client:c))};XCTAssertTrue(d.handle(try key(" ",49),client:c))
        XCTAssertEqual(c.view.string,"prefixabc你好");XCTAssertEqual(c.insertCalls,1)
        try action(.literal,d);d.deactivate(client:c);try activate(d,c);XCTAssertFalse(d.usesLiteralMode)
    }
    @MainActor func testForeignDriverAndStaleMenusCannotChangeModeOrOpenPalette()throws {
        let w=workspace();defer{w.close()};var palettes=0
        let a=client("dev.paia.a"),b=client("dev.paia.b")
        let da=w.makeDriver(hide:{},present:{_,_,_ in},showCharacters:{palettes+=1}),db=w.makeDriver(hide:{},present:{_,_,_ in},showCharacters:{palettes+=1})
        try activate(da,a);try activate(db,b)
        for kind in [InputHabitActionKind.literal,.characters] {db.performInputHabitMenuAction(try XCTUnwrap(da.inputHabitMenuAction(kind)))}
        XCTAssertFalse(db.usesLiteralMode);XCTAssertEqual(palettes,0)
        let old=try XCTUnwrap(da.inputHabitMenuAction(.characters));XCTAssertTrue(da.handle(try key("n"),client:a));da.performInputHabitMenuAction(old)
        XCTAssertNil(da.inputHabitMenuAction(.characters));XCTAssertEqual(palettes,0);XCTAssertEqual(a.insertCalls,0)
    }
    @MainActor func testSystemPaletteIsOnceOnlyAndNeverAnInputEffect()throws {
        let w=workspace();defer{w.close()};var palettes=0,reenter:(()->Void)?
        let c=client("dev.paia.a"),d=w.makeDriver(hide:{},present:{_,_,_ in},showCharacters:{palettes+=1;reenter?()})
        try activate(d,c);let menu=try XCTUnwrap(d.inputHabitMenuAction(.characters));reenter={[weak d] in d?.performInputHabitMenuAction(menu)}
        d.performInputHabitMenuAction(menu);d.performInputHabitMenuAction(menu)
        XCTAssertEqual(palettes,1);XCTAssertEqual(c.insertCalls,0);XCTAssertEqual(c.markCalls,0);XCTAssertEqual(c.view.string,"prefix")
        XCTAssertEqual(c.documentLengthCalls,0);XCTAssertEqual(c.reads.count,0)
        print("HABIT_CHARACTER_ENTRY production action gate with SIMULATED system-palette callback; no IME insertion; actual OS panel untested")
    }
    @MainActor func testPaletteRefusesTargetMutationOrReentrantActivationDuringHide()throws {
        for mutation in 0..<3 {
            let w=workspace();defer{w.close()};var palettes=0,onHide:(()->Void)?
            let a=client("dev.paia.a"),b=client("dev.paia.b"),d=w.makeDriver(hide:{let f=onHide;onHide=nil;f?()},present:{_,_,_ in},showCharacters:{palettes+=1})
            try activate(d,a);let menu=try XCTUnwrap(d.inputHabitMenuAction(.characters))
            onHide={
                if mutation==0{a.view.setSelectedRange(NSRange(location:0,length:0))}
                else if mutation==1{a.view.setMarkedText("foreign",selectedRange:NSRange(location:7,length:0),replacementRange:NSRange(location:6,length:0))}
                else{_ = d.activate(IMKTextInputBridge(b)!)}
            }
            d.performInputHabitMenuAction(menu);XCTAssertEqual(palettes,0);XCTAssertEqual(a.insertCalls,0);XCTAssertEqual(b.insertCalls,0)
        }
    }
    @MainActor func testApplicationIdentityGetterCannotPublishAfterLifecycleReentry()throws {
        for operation in 0..<5 {
            var made=0;let a=client("dev.paia.a"),b=client("dev.paia.b")
            let d=IMKControllerDriver(makeSession:{made+=1;return try? Self.environment.runtime.makeSession(schema:"paia_b1_full_ascii")},initialLiteral:{$0=="dev.paia.a"},hide:{},present:{_,_,_ in})
            defer{d.close()}
            a.onApplicationIdentifier={
                switch operation {case 0:_ = d.activate(IMKTextInputBridge(b)!);case 1:d.finish(client:a);case 2:d.deactivate(client:a);case 3:d.close();default:_ = d.handle(try! self.key("n"),client:a)}
            }
            XCTAssertEqual(d.activate(try XCTUnwrap(IMKTextInputBridge(a))),.superseded)
            XCTAssertEqual(made,operation==0 ? 1:0);XCTAssertFalse(d.usesLiteralMode)
            XCTAssertEqual(a.insertCalls,0);XCTAssertEqual(a.markCalls,0);XCTAssertEqual(b.insertCalls,0)
            if operation==0{XCTAssertTrue(d.handle(try key("n"),client:b));XCTAssertEqual(d.coordinator.snapshot?.sourceText,"n");XCTAssertGreaterThan(b.markCalls,0);XCTAssertEqual(a.markCalls,0)}
        }
    }
    @MainActor func testDirectUmlautIsNotSilentlyNormalizedInAnyInputState()throws {
        let w=workspace();defer{w.close()};let c=client("dev.paia.a"),d=w.makeDriver(hide:{},present:{_,_,_ in})
        try activate(d,c);XCTAssertFalse(d.handle(try key("ü"),client:c));c.view.insertText("ü",replacementRange:c.view.selectedRange())
        XCTAssertTrue(d.handle(try key("n"),client:c));let before=try XCTUnwrap(d.coordinator.snapshot),mark=c.view.string
        XCTAssertTrue(d.handle(try key("ü"),client:c));XCTAssertEqual(c.view.string,mark)
        XCTAssertEqual(d.coordinator.snapshot?.sourceText,before.sourceText);XCTAssertEqual(d.coordinator.snapshot?.caretUTF8,before.caretUTF8)
        XCTAssertEqual(c.insertCalls,0);XCTAssertTrue(d.handle(try key("",53),client:c))
        try action(.literal,d)
        for text in ["ü","u\u{308}"]{XCTAssertFalse(d.handle(try key(text),client:c));c.view.insertText(text,replacementRange:c.view.selectedRange())}
        XCTAssertTrue(c.view.string.utf8.elementsEqual("prefixüüu\u{308}".utf8));XCTAssertEqual(c.insertCalls,0)
    }
    @MainActor func testNativePreferencesKeepPolicyAndAppRulesInOneExplicitSave()throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("paia-habit-ui-"+UUID().uuidString)
        let store=try SettingsStore(directory:root)
        let w=IMKWorkspace(settingsStore:store,resourceDescription:"Explicit policy test",makeSession:{try Self.environment.runtime.makeSession(schema:$0.schema)})
        defer{w.close();try? FileManager.default.removeItem(at:root)}
        _=NSApplication.shared;let preferences=IMKPreferencesController(workspace:w);defer{preferences.close()}
        preferences.fuzzy.state = .on
        XCTAssertTrue(NSApp.sendAction(preferences.fuzzy.action!,to:preferences.fuzzy.target,from:preferences.fuzzy))
        XCTAssertTrue(w.configuration.fuzzyInitials);XCTAssertNil(try store.snapshot())
        preferences.applicationID.stringValue="dev.paia.explicit";preferences.applicationMode.selectItem(at:2)
        XCTAssertTrue(NSApp.sendAction(preferences.applyApplication.action!,to:preferences.applyApplication.target,from:preferences.applyApplication))
        XCTAssertEqual(w.configuration.initialModes["dev.paia.explicit"],.literal);XCTAssertNil(try store.snapshot())
        XCTAssertTrue(NSApp.sendAction(preferences.settings.saveButton.action!,to:preferences.settings.saveButton.target,from:preferences.settings.saveButton))
        XCTAssertEqual(try store.snapshot()?.values,w.configuration.preferences)
        let before=try Data(contentsOf:root.appendingPathComponent("settings.json"))
        preferences.spelling.selectItem(at:1)
        XCTAssertTrue(NSApp.sendAction(preferences.spelling.action!,to:preferences.spelling.target,from:preferences.spelling))
        XCTAssertEqual(w.configuration.spelling,.flypy);XCTAssertFalse(preferences.correction.isEnabled)
        XCTAssertEqual(try Data(contentsOf:root.appendingPathComponent("settings.json")),before)
    }

}
#endif
