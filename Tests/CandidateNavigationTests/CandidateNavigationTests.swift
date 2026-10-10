#if os(macOS)
import XCTest
import AppKit
import NativeHost
import EngineBridge
import SessionCore

final class CandidateNavigationTests:XCTestCase {
    @MainActor func descendants(_ view:NSView)->[NSView] {[view]+view.subviews.flatMap{descendants($0)}}
    static var environment:ResearchLabEnvironment!
    override class func setUp(){super.setUp();do{environment=try ResearchLabEnvironment()}catch{XCTFail("B4 native startup: \(error)")}}
    @MainActor func make()throws->(NativeLabController,LabWindow){
        _=NSApplication.shared
        let controller=NativeLabController(runtime:try XCTUnwrap(Self.environment?.runtime))
        let window=LabWindow(contentRect:NSRect(x:0,y:0,width:1040,height:720),styleMask:[.titled,.closable],backing:.buffered,defer:false)
        window.isReleasedWhenClosed=false;try controller.attach(to:window);window.orderFront(nil);window.makeKey()
        XCTAssertTrue(window.makeFirstResponder(controller.editor));return(controller,window)
    }
    @MainActor func key(_ text:String,_ view:NSTextView,code:UInt16=0)throws {
        let event=try XCTUnwrap(NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[],timestamp:0,windowNumber:view.window?.windowNumber ?? 0,context:nil,characters:text,charactersIgnoringModifiers:text,isARepeat:false,keyCode:code));view.keyDown(with:event)
    }
    @MainActor func type(_ text:String,_ view:NSTextView)throws{for c in text{try key(String(c),view)}}
    @MainActor func rows(_ panel:CandidatePanel)throws->[NSButton]{descendants(try XCTUnwrap(panel.contentView)).compactMap{$0 as? NSButton}.sorted{$0.tag<$1.tag}}
    @MainActor func assertPresentation(_ controller:NativeLabController,_ window:LabWindow)throws {
        let snapshot=try XCTUnwrap(controller.editor.dispatcher?.session.snapshot),panel=controller.editor.candidates
        XCTAssertFalse(snapshot.rows.isEmpty);XCTAssertTrue(panel.isVisible);XCTAssertFalse(panel.canBecomeKey);XCTAssertTrue(window.firstResponder===controller.editor)
        let buttons=try rows(panel);XCTAssertEqual(buttons.count,snapshot.rows.count)
        XCTAssertEqual(buttons.filter{$0.title.hasPrefix("▶ ")}.count,1)
        XCTAssertEqual(buttons.filter{($0.accessibilityValue() as? String)=="selected"}.count,1)
        for (i,button) in buttons.enumerated(){
            XCTAssertTrue(button.title.hasSuffix("\(i+1). \(snapshot.rows[i].text)"));XCTAssertEqual(button.title.hasPrefix("▶ "),i==snapshot.highlighted)
            XCTAssertEqual(button.accessibilityLabel(),"Candidate \(i+1), \(snapshot.rows[i].text)");XCTAssertTrue(button.refusesFirstResponder)
            XCTAssertEqual(button.font?.fontDescriptor,NSFont.systemFont(ofSize:16,weight:i==snapshot.highlighted ? .semibold:.regular).fontDescriptor)
        }
        let label=try XCTUnwrap(descendants(try XCTUnwrap(panel.contentView)).compactMap{$0 as? NSTextField}.first)
        XCTAssertEqual(label.stringValue,"Page \(snapshot.pageIndex+1) · \(snapshot.hasMore ? "More candidates":"End of candidates")")
    }
    @MainActor func capture(_ panel:CandidatePanel,name:String)throws {
        let view=try XCTUnwrap(panel.contentView);view.layoutSubtreeIfNeeded();view.displayIfNeeded()
        let bitmap=try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in:view.bounds));view.cacheDisplay(in:view.bounds,to:bitmap)
        XCTAssertEqual(try XCTUnwrap(bitmap.colorAt(x:0,y:0)).alphaComponent,1,accuracy:0.001)
        let data=try XCTUnwrap(bitmap.representation(using:.png,properties:[:]))
        let directory=URL(fileURLWithPath:FileManager.default.currentDirectoryPath).appendingPathComponent("evidence/b4-run")
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true);try data.write(to:directory.appendingPathComponent(name+".png"))
        let encoded=data.base64EncodedString();var offset=encoded.startIndex,index=0
        while offset<encoded.endIndex{let end=encoded.index(offset,offsetBy:3000,limitedBy:encoded.endIndex) ?? encoded.endIndex;FileHandle.standardError.write(Data(("PAIA_B4_\(name)_IMAGE_\(index):"+encoded[offset..<end]+"\n").utf8));offset=end;index+=1}
    }
    @MainActor func testEngineHighlightMatchesVisibleRowAndSpaceCommitsOnce()throws {
        let(c,w)=try make();defer{w.close()};try type("shi",c.editor)
        let host=try XCTUnwrap(c.editor.dispatcher),first=try XCTUnwrap(host.session.snapshot)
        XCTAssertGreaterThan(first.rows.count,1);try assertPresentation(c,w)
        try key("\u{F701}",c.editor,code:125);let down=try XCTUnwrap(host.session.snapshot)
        XCTAssertEqual(down.highlighted,first.highlighted+1);XCTAssertEqual(host.insertCount,0);try assertPresentation(c,w)
        try capture(c.editor.candidates,name:"highlighted-second")
        try key("\u{F700}",c.editor,code:126);XCTAssertEqual(host.session.snapshot?.highlighted,first.highlighted);try assertPresentation(c,w)
        try key("\u{F701}",c.editor,code:125);let current=try XCTUnwrap(host.session.snapshot),chosen=current.rows[current.highlighted].text
        try key(" ",c.editor,code:49);XCTAssertEqual(c.editor.string,chosen);XCTAssertEqual(host.insertCount,1)
        XCTAssertFalse(c.editor.hasMarkedText());XCTAssertFalse(c.editor.candidates.isVisible)
        try key(" ",c.editor,code:49);XCTAssertEqual(host.insertCount,1);XCTAssertEqual(c.editor.string,chosen+" ")
    }
    @MainActor func testPagesDigitsAndOldRenderedButtonCannotRetarget()throws {
        let(c,w)=try make();defer{w.close()};try type("shi",c.editor)
        let host=try XCTUnwrap(c.editor.dispatcher),first=try XCTUnwrap(host.session.snapshot),old=try XCTUnwrap(try rows(c.editor.candidates).first)
        XCTAssertTrue(first.hasMore);try key("\u{F72D}",c.editor,code:121)
        let next=try XCTUnwrap(host.session.snapshot);XCTAssertEqual(next.pageIndex,first.pageIndex+1);XCTAssertEqual(host.insertCount,0);try assertPresentation(c,w)
        try capture(c.editor.candidates,name:"next-page")
        let document=c.editor.string,generation=next.inputGeneration
        old.performClick(nil);XCTAssertTrue(w.firstResponder===c.editor);XCTAssertEqual(host.insertCount,0);XCTAssertEqual(c.editor.string,document);XCTAssertEqual(host.session.snapshot?.inputGeneration,generation)
        try assertPresentation(c,w)
        try key("\u{F72C}",c.editor,code:116);XCTAssertEqual(host.session.snapshot?.pageIndex,first.pageIndex);try assertPresentation(c,w)
        try key("\u{F72D}",c.editor,code:121);let current=try XCTUnwrap(host.session.snapshot);XCTAssertGreaterThan(current.rows.count,1)
        let expected=current.rows[1].text;try key("2",c.editor)
        XCTAssertEqual(c.editor.string,expected);XCTAssertEqual(host.insertCount,1);XCTAssertFalse(c.editor.candidates.isVisible)
        old.performClick(nil);XCTAssertEqual(host.insertCount,1);XCTAssertEqual(c.editor.string,expected)
    }
    @MainActor func testDisplayedButtonCommitsItsOwnRowOnceWithoutFocusTransfer()throws {
        let(c,w)=try make();defer{w.close()};try type("shi",c.editor)
        let host=try XCTUnwrap(c.editor.dispatcher),snapshot=try XCTUnwrap(host.session.snapshot),buttons=try rows(c.editor.candidates)
        XCTAssertGreaterThan(buttons.count,1);let button=buttons[1],expected=snapshot.rows[1].text
        button.performClick(nil);XCTAssertEqual(c.editor.string,expected);XCTAssertEqual(host.insertCount,1)
        XCTAssertTrue(w.firstResponder===c.editor);XCTAssertFalse(c.editor.candidates.isVisible)
        button.performClick(nil);XCTAssertEqual(c.editor.string,expected);XCTAssertEqual(host.insertCount,1)
    }
    @MainActor func testCancelFocusAndModeHidePanelAndInvalidateOldClicks()throws {
        let(c,w)=try make();defer{w.close()};try type("shi",c.editor)
        let cancelled=try XCTUnwrap(try rows(c.editor.candidates).first)
        try key("\u{1b}",c.editor,code:53);XCTAssertFalse(c.editor.candidates.isVisible);cancelled.performClick(nil);XCTAssertEqual(c.editor.string,"");XCTAssertFalse(c.editor.candidates.isVisible)
        try type("shi",c.editor);let unfocused=try XCTUnwrap(try rows(c.editor.candidates).first)
        XCTAssertTrue(w.makeFirstResponder(nil));XCTAssertFalse(c.editor.candidates.isVisible);unfocused.performClick(nil);XCTAssertEqual(c.editor.string,"")
        XCTAssertTrue(w.makeFirstResponder(c.editor));try type("shi",c.editor);let oldMode=try XCTUnwrap(try rows(c.editor.candidates).first)
        try key("\u{1b}",c.editor,code:53);var next=LabConfiguration();next.spelling = .flypy;try c.applyConfiguration(next)
        XCTAssertFalse(c.editor.candidates.isVisible);oldMode.performClick(nil);XCTAssertEqual(c.editor.string,"");XCTAssertEqual(c.editor.dispatcher?.insertCount,0)
        try c.applyConfiguration(LabConfiguration());try type("shi",c.editor)
        let deactivated=try XCTUnwrap(try rows(c.editor.candidates).first);XCTAssertTrue(c.editor.candidates.isVisible)
        w.resignKey();XCTAssertFalse(c.editor.candidates.isVisible);deactivated.performClick(nil)
        XCTAssertEqual(c.editor.string,"");XCTAssertEqual(c.editor.dispatcher?.insertCount,0);XCTAssertFalse(c.editor.candidates.isVisible)

    }
    @MainActor func testBoundedRepeatNavigationDoesNotCommitOrLoseFocus()throws {
        let(c,w)=try make();defer{w.close()};try type("shi",c.editor);let host=try XCTUnwrap(c.editor.dispatcher)
        let panels=NSApp.windows.filter{$0 is CandidatePanel}.count
        for _ in 0..<40 {
            try key("\u{F701}",c.editor,code:125);try assertPresentation(c,w)
            try key("\u{F700}",c.editor,code:126);try assertPresentation(c,w)
            try key("\u{F72D}",c.editor,code:121);try assertPresentation(c,w)
            try key("\u{F72C}",c.editor,code:116);try assertPresentation(c,w)
        }
        XCTAssertEqual(host.insertCount,0);XCTAssertTrue(c.editor.hasMarkedText());XCTAssertEqual(host.session.snapshot?.rawASCII,"shi")
        XCTAssertEqual(NSApp.windows.filter{$0 is CandidatePanel}.count,panels);XCTAssertEqual(descendants(try XCTUnwrap(c.editor.candidates.contentView)).filter{$0 is NSScrollView}.count,1);XCTAssertEqual(try rows(c.editor.candidates).count,host.session.snapshot?.rows.count)
        print("B4_APPKIT_HOST bounded 160 navigation actions; not endurance or visible-latency evidence")
    }
    @MainActor func testUnicodeAndEndPagePresentationUsesSnapshotText()throws {
        _=NSApplication.shared
        // SIMULATED Unicode snapshot checks presentation only; never presented as engine output.
        var core=SessionCore(dictionaryRevision:"b4-synthetic-presentation")
        let text=["𠀀","e\u{301}","👩🏽‍💻","多码点後綴"]
        let update=try core.receive(EngineValue(raw:"shi",preedit:"shi",caretUTF8:3,candidates:text,page:2,highlighted:2,hasMore:false))
        let panel=CandidatePanel();defer{panel.orderOut(nil)}
        panel.show(try XCTUnwrap(update.snapshot),below:NSRect(x:10,y:30,width:100,height:20),screen:NSRect(x:0,y:0,width:800,height:600))
        let buttons=try rows(panel);for i in text.indices{XCTAssertTrue(buttons[i].title.hasSuffix(text[i]))};XCTAssertTrue(buttons[2].title.hasPrefix("▶ "))
        let label=try XCTUnwrap(descendants(try XCTUnwrap(panel.contentView)).compactMap{$0 as? NSTextField}.first)
        XCTAssertEqual(label.stringValue,"Page 3 · End of candidates");XCTAssertTrue(NSRect(x:0,y:0,width:800,height:600).contains(panel.frame))
    }
}
#endif
