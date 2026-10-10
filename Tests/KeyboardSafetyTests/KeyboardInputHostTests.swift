#if os(macOS)
import XCTest
import AppKit
import EngineBridge
import NativeHost
import SessionCore

final class KeyboardInputHostTests:XCTestCase {
    static var environment:ResearchLabEnvironment!
    static var preparedApplication=false
    override class func setUp(){super.setUp();do{environment=try ResearchLabEnvironment()}catch{XCTFail("B8 host startup: \(error)")}}
    @MainActor func make()throws->(NativeLabController,LabWindow){
        _=NSApplication.shared;let c=NativeLabController(runtime:try XCTUnwrap(Self.environment?.runtime))
        let w=LabWindow(contentRect:NSRect(x:0,y:0,width:1040,height:820),styleMask:[.titled,.closable],backing:.buffered,defer:false)
        w.isReleasedWhenClosed=false;try c.attach(to:w)
        if !Self.preparedApplication{XCTAssertTrue(NSApp.setActivationPolicy(.regular));NSApp.finishLaunching();Self.preparedApplication=true}
        NSApp.activate(ignoringOtherApps:true);w.makeKeyAndOrderFront(nil);XCTAssertTrue(w.makeFirstResponder(c.editor))
        let deadline=Date(timeIntervalSinceNow:3)
        while !w.isKeyWindow && Date()<deadline{if let e=NSApp.nextEvent(matching:.any,until:Date(timeIntervalSinceNow:0.05),inMode:.default,dequeue:true){NSApp.sendEvent(e)};NSApp.updateWindows();w.makeKey()}
        XCTAssertTrue(w.isKeyWindow);return(c,w)
    }
    @MainActor func key(_ text:String,_ view:NSTextView,code:UInt16=0)throws {
        view.keyDown(with:try XCTUnwrap(NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[],timestamp:0,windowNumber:view.window?.windowNumber ?? 0,context:nil,characters:text,charactersIgnoringModifiers:text,isARepeat:false,keyCode:code)))
    }
    @MainActor func type(_ raw:String,_ view:NSTextView)throws{for c in raw{try key(String(c),view)}}
    @MainActor func trace(_ kind:String,_ c:NativeLabController,_ before:CandidateSnapshot,_ original:String,_ event:String)throws {
        let after=c.editor.dispatcher?.session.snapshot
        let value:[String:Any]=["kind":kind,"eventScalars":event.unicodeScalars.map{$0.value},"beforeRaw":before.rawASCII,"beforeCaret":before.caretUTF8,"beforeDocumentScalars":original.unicodeScalars.map{$0.value},"afterRaw":after?.rawASCII ?? "<inactive>","afterCaret":after?.caretUTF8 ?? -1,"afterDocumentScalars":c.editor.string.unicodeScalars.map{$0.value},"markedLocation":c.editor.markedRange().location,"markedLength":c.editor.markedRange().length,"insertCount":c.editor.dispatcher?.insertCount ?? -1]
        print("B8_OBSERVATION "+String(decoding:try JSONSerialization.data(withJSONObject:value,options:[.sortedKeys]),as:UTF8.self))
    }
    @MainActor func testMiddlePunctuationPreservesDocumentMarkedTextAndRaw()throws {
        for chinese in [false,true] {for punctuation in [",","."] {
            let(c,w)=try make();defer{w.close()};var config=LabConfiguration();config.chinesePunctuation=chinese;try c.applyConfiguration(config)
            c.editor.string="prefix|";c.editor.setSelectedRange(NSRange(location:7,length:0));c.editor.renew()
            try type("nihao",c.editor);for _ in 0..<3{try key("",c.editor,code:123)}
            let host=try XCTUnwrap(c.editor.dispatcher),before=try XCTUnwrap(host.session.snapshot),text=c.editor.string,mark=c.editor.markedRange(),selection=c.editor.selectedRange()
            XCTAssertEqual(before.caretUTF8,2);try key(punctuation,c.editor);try trace("APPKIT_HOST_MIDDLE",c,before,text,punctuation)
            XCTAssertEqual(Array(c.editor.string.utf8),Array(text.utf8));XCTAssertEqual(c.editor.markedRange(),mark);XCTAssertEqual(c.editor.selectedRange(),selection)
            XCTAssertEqual(host.session.snapshot?.rawASCII,before.rawASCII);XCTAssertEqual(host.session.snapshot?.caretUTF8,before.caretUTF8)
            XCTAssertEqual(host.session.snapshot?.inputGeneration,before.inputGeneration);XCTAssertEqual(host.insertCount,0);XCTAssertTrue(host.isCurrentTarget)
        }}
    }
    @MainActor func testNonASCIISingleAndMultipleScalarsNeverOverwriteOwnedMarkedText()throws {
        for (raw,event) in [("l","ü"),("n","ü"),("l","u\u{308}"),("nihao","👩🏽‍💻"),("nihao","ｑ")] {
            let(c,w)=try make();defer{w.close()};try type(raw,c.editor)
            let host=try XCTUnwrap(c.editor.dispatcher),before=try XCTUnwrap(host.session.snapshot),text=c.editor.string,mark=c.editor.markedRange(),selection=c.editor.selectedRange()
            // One complete NSEvent, never the UTF-8 byte helper used for ASCII raw input.
            try key(event,c.editor);try trace("APPKIT_HOST_NONASCII",c,before,text,event)
            XCTAssertEqual(Array(c.editor.string.utf8),Array(text.utf8));XCTAssertEqual(c.editor.markedRange(),mark);XCTAssertEqual(c.editor.selectedRange(),selection)
            XCTAssertEqual(host.session.snapshot?.rawASCII,before.rawASCII);XCTAssertEqual(host.session.snapshot?.caretUTF8,before.caretUTF8)
            XCTAssertEqual(host.session.snapshot?.inputGeneration,before.inputGeneration);XCTAssertEqual(host.insertCount,0);XCTAssertTrue(host.isCurrentTarget)
        }
    }
}
#endif
