#if os(macOS)
import XCTest
import AppKit
import NativeHost
import EngineBridge
final class NativeControlTests:XCTestCase {
    static var environment:ResearchLabEnvironment!
    override class func setUp(){super.setUp();do{environment=try ResearchLabEnvironment()}catch{XCTFail("B1 native startup: \(error)")}}
    @MainActor func make()throws->(NativeLabController,LabWindow){
        _=NSApplication.shared
        let runtime=try XCTUnwrap(Self.environment?.runtime)
        let c=NativeLabController(runtime:runtime)
        let w=LabWindow(contentRect:NSRect(x:0,y:0,width:1040,height:720),styleMask:[.titled,.closable,.resizable],backing:.buffered,defer:false)
        w.isReleasedWhenClosed=false;try c.attach(to:w);w.makeKey();XCTAssertTrue(w.makeFirstResponder(c.editor));return(c,w)
    }
    @MainActor func key(_ text:String,_ view:LabTextView,keyCode:UInt16=0)throws {
        let event=try XCTUnwrap(NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[],timestamp:0,windowNumber:view.window?.windowNumber ?? 0,context:nil,characters:text,charactersIgnoringModifiers:text,isARepeat:false,keyCode:keyCode))
        view.keyDown(with:event)
    }
    @MainActor func type(_ text:String,_ view:LabTextView)throws {for c in text{try key(String(c),view,keyCode:c==" " ? 49:0)}}
    @MainActor func configurationAction(_ c:NativeLabController){NSApp.sendAction(c.spelling.action!,to:c.spelling.target,from:c.spelling)}
    @MainActor func heldSentence(_ c:NativeLabController)throws {
        c.hold.performClick(nil);XCTAssertTrue(c.configuration.deferredCommit)
        try type("nihaoshurufashijie",c.editor);try key(" ",c.editor,keyCode:49)
        XCTAssertTrue(c.editor.hasMarkedText());XCTAssertTrue(c.repairButton.isEnabled)
    }
    @MainActor func preview(_ c:NativeLabController,_ w:LabWindow)throws->NSButton {
        let mark=c.editor.markedRange(),selection=c.editor.selectedRange(),document=c.editor.string
        var transitions=[String]();let originalFocus=w.beforeFocusChange
        w.beforeFocusChange={responder in
            let name=responder.map{String(describing:Swift.type(of:$0))} ?? "nil"
            let delegate=(responder as? NSTextView)?.delegate.map{String(describing:Swift.type(of:$0))} ?? "none"
            transitions.append("to="+name+" delegate="+delegate+" suspended=\(c.editor.dispatcher?.isInspectorSuspended ?? false) marked=\(c.editor.markedRange())")
            originalFocus?(responder)
        }
        defer{w.beforeFocusChange=originalFocus}
        c.repairButton.performClick(nil);XCTAssertTrue(c.inspectorVisible,c.status.stringValue+" | "+transitions.joined(separator:"; "))
        XCTAssertEqual(c.editor.markedRange(),mark);XCTAssertEqual(c.editor.selectedRange(),selection);XCTAssertEqual(c.editor.string,document)
        XCTAssertTrue(c.editor.dispatcher?.isInspectorSuspended==true)
        let targets=c.targetStack.arrangedSubviews.compactMap{$0 as? NSButton}
        let target=try XCTUnwrap(targets.first(where:{$0.title.hasPrefix("输入法 ")}));target.performClick(nil)
        XCTAssertTrue(w.makeFirstResponder(c.rawField));c.rawField.stringValue="daimashencha"
        XCTAssertTrue(w.makeFirstResponder(c.surfaceField));c.surfaceField.stringValue="代码审查"
        XCTAssertEqual(c.editor.markedRange(),mark);XCTAssertEqual(c.editor.selectedRange(),selection);XCTAssertEqual(c.editor.string,document)
        c.controlTextDidChange(Notification(name:NSControl.textDidChangeNotification,object:c.surfaceField))
        c.previewButton.performClick(nil)
        XCTAssertEqual(c.previewLabel.stringValue,"你好代码审查世界",c.status.stringValue)
        return try XCTUnwrap(c.acceptStack.arrangedSubviews.first as? NSButton)
    }
    @MainActor func testSixSchemaControlsProduceNativeCandidatesAndCommits()throws {
        for (index,raw) in [(0,"shurufa"),(1,"uurufa"),(2,"uurufa")] {
            for traditional in [false,true] {
                let(c,w)=try make();defer{w.close()}
                c.spelling.selectItem(at:index);c.script.selectItem(at:traditional ? 1:0);configurationAction(c)
                try type(raw,c.editor);XCTAssertFalse(c.editor.dispatcher!.session.snapshot!.rows.isEmpty)
                try key(" ",c.editor,keyCode:49)
                XCTAssertEqual(c.editor.string,traditional ? "輸入法":"输入法");XCTAssertEqual(c.editor.dispatcher?.insertCount,1)
            }
        }
    }
    @MainActor func testLiteralAndPunctuationControlsHaveActualSemantics()throws {
        let(c,w)=try make();defer{w.close()}
        c.literal.performClick(nil);XCTAssertTrue(c.configuration.literal)
        try type("RAG user_id /tmp/a 3.14 12:34 𠀀 e\u{301} 👩🏽‍💻",c.editor)
        XCTAssertEqual(c.editor.string,"RAG user_id /tmp/a 3.14 12:34 𠀀 e\u{301} 👩🏽‍💻")
        c.literal.performClick(nil);c.punctuation.performClick(nil)
        try type(",?!;",c.editor);XCTAssertTrue(c.editor.string.hasSuffix("，？！；"))
        try type(" 3.14 12:34",c.editor);XCTAssertTrue(c.editor.string.hasSuffix(" 3.14 12:34"))
        let(d,x)=try make();defer{x.close()};d.punctuation.performClick(nil)
        try type("nihao,",d.editor);XCTAssertEqual(d.editor.string,"你好，");XCTAssertEqual(d.editor.dispatcher?.insertCount,1)
    }
    @MainActor func testRepairControlFocusPreviewAcceptAndSingleCommit()throws {
        let(c,w)=try make();defer{w.close()};try heldSentence(c)
        let original=c.editor.string,host=try XCTUnwrap(c.editor.dispatcher)
        let accept=try preview(c,w);XCTAssertEqual(c.editor.string,original);XCTAssertEqual(host.insertCount,0)
        accept.performClick(nil);XCTAssertFalse(c.inspectorVisible);XCTAssertTrue(host.isCurrentTarget)
        XCTAssertEqual(host.insertCount,0);XCTAssertTrue(c.editor.hasMarkedText())
        c.commitButton.performClick(nil);XCTAssertEqual(c.editor.string,"你好代码审查世界");XCTAssertEqual(host.insertCount,1)
        accept.performClick(nil);c.commitButton.performClick(nil);XCTAssertEqual(host.insertCount,1)
    }
    @MainActor func testOldAcceptCancelModeAndTypingCannotRetarget()throws {
        let(c,w)=try make();defer{w.close()};try heldSentence(c)
        XCTAssertFalse(c.spelling.isEnabled);c.spelling.selectItem(at:1);configurationAction(c);XCTAssertEqual(c.configuration.spelling,.full)
        let original=c.editor.string;let old=try preview(c,w)
        c.cancelRepairButton.performClick(nil);XCTAssertEqual(c.editor.string,original);old.performClick(nil);XCTAssertEqual(c.editor.string,original)
        let second=try preview(c,w);XCTAssertTrue(w.makeFirstResponder(c.editor));try type("n",c.editor)
        let changed=c.editor.string;second.performClick(nil);XCTAssertEqual(c.editor.string,changed)
        XCTAssertEqual(c.editor.dispatcher?.insertCount,0)
    }
    @MainActor func testUnrelatedFocusAndTargetChangesRejectRepair()throws {
        let(c,w)=try make();defer{w.close()};try heldSentence(c);let accept=try preview(c,w)
        let unrelated=NSTextField();c.root.addArrangedSubview(unrelated);XCTAssertTrue(w.makeFirstResponder(unrelated))
        accept.performClick(nil);XCTAssertEqual(c.editor.dispatcher?.insertCount,0);XCTAssertFalse(c.inspectorVisible)
        XCTAssertThrowsError(try c.editor.dispatcher!.session.refresh())
        let(d,x)=try make();defer{x.close()};try heldSentence(d);let other=try preview(d,x)
        d.editor.string="externally changed target";other.performClick(nil)
        XCTAssertEqual(d.editor.string,"externally changed target");XCTAssertEqual(d.editor.dispatcher?.insertCount,0)
        XCTAssertFalse(d.inspectorVisible);XCTAssertTrue(d.acceptStack.arrangedSubviews.isEmpty)
    }
    @MainActor func testOldTargetAndCandidateControlsHoldDisplayedIdentity()throws {
        let(c,w)=try make();defer{w.close()};try heldSentence(c)
        c.repairButton.performClick(nil)
        let oldTarget=try XCTUnwrap(c.targetStack.arrangedSubviews.first as? NSButton)
        let oldAccept=try preview(c,w)
        let raw=c.rawField.stringValue,surface=c.surfaceField.stringValue
        oldTarget.performClick(nil)
        XCTAssertEqual(c.rawField.stringValue,raw);XCTAssertEqual(c.surfaceField.stringValue,surface)
        XCTAssertTrue(c.acceptStack.arrangedSubviews.first===oldAccept)
        c.previewButton.performClick(nil)
        let newAccept=try XCTUnwrap(c.acceptStack.arrangedSubviews.first as? NSButton)
        oldAccept.performClick(nil);XCTAssertTrue(c.acceptStack.arrangedSubviews.first===newAccept);XCTAssertTrue(c.inspectorVisible)
        c.cancelRepairButton.performClick(nil)
        let(d,x)=try make();defer{x.close()};try type("nihao",d.editor)
        let snapshot=try XCTUnwrap(d.editor.dispatcher?.session.snapshot)
        d.editor.candidates.show(snapshot,below:NSRect(x:10,y:100,width:100,height:20),screen:NSRect(x:0,y:0,width:1000,height:800))
        let stack=try XCTUnwrap(d.editor.candidates.contentView?.subviews.first as? NSStackView)
        let oldCandidate=try XCTUnwrap(stack.arrangedSubviews.first as? NSButton)
        d.cancelCompositionButton.performClick(nil);d.spelling.selectItem(at:1);configurationAction(d)
        oldCandidate.performClick(nil);XCTAssertEqual(d.editor.string,"");XCTAssertEqual(d.editor.dispatcher?.insertCount,0)
    }
    @MainActor func testNestedForeignOrNilFocusFailsClosed()throws {
        for useNil in [false,true] {
            let(c,w)=try make();try heldSentence(c);c.repairButton.performClick(nil);XCTAssertTrue(c.inspectorVisible)
            let foreign=NSTextField();c.root.addArrangedSubview(foreign)
            let original=w.beforeFocusChange;var injected=false
            defer{w.beforeFocusChange=original;w.close()}
            w.beforeFocusChange={responder in
                original?(responder)
                if responder===c.surfaceField && !injected {injected=true;_ = w.makeFirstResponder(useNil ? nil:foreign)}
            }
            _ = w.makeFirstResponder(c.surfaceField)
            XCTAssertTrue(injected);XCTAssertFalse(c.inspectorVisible);XCTAssertEqual(c.editor.dispatcher?.insertCount,0)
            XCTAssertEqual(w.focusTransitionDepth,0);XCTAssertNil(w.primaryFocusRequest)
            XCTAssertThrowsError(try c.editor.dispatcher!.session.refresh())
        }
    }
    @MainActor func testNativeLayoutCapture()throws {
        guard ProcessInfo.processInfo.environment["PAIA_CAPTURE_LAYOUT"]=="1" else{throw XCTSkip("Optional synthetic-view capture not requested")}
        let(c,w)=try make();defer{w.close()};try heldSentence(c);c.repairButton.performClick(nil)
        XCTAssertTrue(c.inspectorVisible,c.status.stringValue)
        w.orderFront(nil);c.root.layoutSubtreeIfNeeded();c.root.displayIfNeeded()
        let bitmap=try XCTUnwrap(c.root.bitmapImageRepForCachingDisplay(in:c.root.bounds))
        c.root.cacheDisplay(in:c.root.bounds,to:bitmap)
        let data=try XCTUnwrap(bitmap.representation(using:.png,properties:[:]))
        let directory=URL(fileURLWithPath:FileManager.default.currentDirectoryPath).appendingPathComponent("evidence/b1-run")
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        try data.write(to:directory.appendingPathComponent("native-controls.png"))
        // Deliberate test-only capture of this authored synthetic document, never a desktop screenshot.
        let encoded=data.base64EncodedString();var offset=encoded.startIndex;var index=0
        while offset<encoded.endIndex {let end=encoded.index(offset,offsetBy:3000,limitedBy:encoded.endIndex) ?? encoded.endIndex;print("PAIA_B1_IMAGE_\(index):"+encoded[offset..<end]);offset=end;index+=1}
    }
    @MainActor func testNativeControlAccessibilityAndWindowDeactivation()throws {
        let(c,w)=try make();defer{w.close()}
        XCTAssertEqual(c.spelling.accessibilityLabel(),"Spelling system")
        XCTAssertEqual(c.rawField.accessibilityLabel(),"Replacement raw spelling")
        XCTAssertFalse(c.repairButton.keyEquivalent.isEmpty);XCTAssertFalse(c.commitButton.keyEquivalent.isEmpty)
        try heldSentence(c);let accept=try preview(c,w);w.resignKey();accept.performClick(nil)
        XCTAssertEqual(c.editor.dispatcher?.insertCount,0);XCTAssertFalse(c.inspectorVisible)
    }
}
#endif
