#if os(macOS)
import XCTest
import AppKit
import NativeHost
import EngineBridge
import SessionCore
import TextBoundary
import SettingsCore

final class CharacterHostTests:XCTestCase {
    static var environment:ResearchLabEnvironment!
    static var preparedApplication=false
    override class func setUp(){super.setUp();do{environment=try ResearchLabEnvironment()}catch{XCTFail("B7 native startup: \(error)")}}
    @MainActor func make()throws->(NativeLabController,LabWindow){
        _=NSApplication.shared
        let c=NativeLabController(runtime:try XCTUnwrap(Self.environment?.runtime))
        let w=LabWindow(contentRect:NSRect(x:0,y:0,width:1040,height:820),styleMask:[.titled,.closable],backing:.buffered,defer:false)
        w.isReleasedWhenClosed=false;try c.attach(to:w)
        if !Self.preparedApplication {XCTAssertTrue(NSApp.setActivationPolicy(.regular));NSApp.finishLaunching();Self.preparedApplication=true}
        NSApp.activate(ignoringOtherApps:true);w.makeKeyAndOrderFront(nil);XCTAssertTrue(w.makeFirstResponder(c.editor))
        let deadline=Date(timeIntervalSinceNow:3)
        while !w.isKeyWindow && Date()<deadline {
            if let event=NSApp.nextEvent(matching:.any,until:Date(timeIntervalSinceNow:0.05),inMode:.default,dequeue:true){NSApp.sendEvent(event)}
            NSApp.updateWindows();w.makeKey()
        }
        XCTAssertTrue(w.isKeyWindow,"A real key synthetic host is required before interaction checks")
        return(c,w)
    }
    @MainActor func send(_ control:NSControl)throws{XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(control.action),to:control.target,from:control))}
    @MainActor func key(_ text:String,_ view:NSTextView,code:UInt16=0)throws {
        view.keyDown(with:try XCTUnwrap(NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[],timestamp:0,windowNumber:view.window?.windowNumber ?? 0,context:nil,characters:text,charactersIgnoringModifiers:text,isARepeat:false,keyCode:code)))
    }
    @MainActor func type(_ text:String,_ view:NSTextView)throws{for c in text{try key(String(c),view)}}
    @MainActor func preview(_ c:NativeLabController,_ input:String)throws->NSButton {
        if !c.characterInspectorVisible{try send(c.characterButton)}
        XCTAssertTrue(c.characterInspectorVisible);c.characterField.stringValue=input;try send(c.characterPreviewButton)
        return try XCTUnwrap(c.characterActionStack.arrangedSubviews.first as? NSButton)
    }
    @MainActor func seed(_ c:NativeLabController,_ text:String,caret:Int?=nil){c.editor.string=text;c.editor.setSelectedRange(NSRange(location:caret ?? text.utf16.count,length:0));c.editor.renew()}
    @MainActor func capture(_ c:NativeLabController)throws {
        let view=c.root;view.layoutSubtreeIfNeeded();view.displayIfNeeded()
        let bitmap=try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in:view.bounds));view.cacheDisplay(in:view.bounds,to:bitmap)
        let data=try XCTUnwrap(bitmap.representation(using:.png,properties:[:]))
        let directory=URL(fileURLWithPath:FileManager.default.currentDirectoryPath).appendingPathComponent("evidence/b7-run")
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true);try data.write(to:directory.appendingPathComponent("unicode-preview.png"))
        let encoded=data.base64EncodedString();var offset=encoded.startIndex,index=0
        while offset<encoded.endIndex{let end=encoded.index(offset,offsetBy:3000,limitedBy:encoded.endIndex) ?? encoded.endIndex;FileHandle.standardError.write(Data(("PAIA_B7_IMAGE_\(index):"+encoded[offset..<end]+"\n").utf8));offset=end;index+=1}
    }
    @MainActor func testExplicitSupplementaryScalarPreviewCommitAndNormalEngineContinue()throws {
        let(c,w)=try make();defer{w.close()};let prefix="A👩🏽‍💻";seed(c,prefix)
        let host=try XCTUnwrap(c.editor.dispatcher),generation=host.session.snapshot?.inputGeneration
        let insert=try preview(c,"U+20000")
        XCTAssertEqual(Array(c.editor.string.utf8),Array(prefix.utf8));XCTAssertEqual(host.insertCount,0)
        XCTAssertEqual(host.session.snapshot?.inputGeneration,generation)
        XCTAssertTrue(c.characterPreviewLabel.stringValue.contains("U+20000"));XCTAssertTrue(c.characterPreviewLabel.stringValue.contains("missing-glyph"))
        XCTAssertTrue(w.firstResponder===c.characterField);XCTAssertTrue(w.isKeyWindow)
        try capture(c);try send(insert)
        XCTAssertEqual(c.editor.string.unicodeScalars.map{$0.value},prefix.unicodeScalars.map{$0.value}+[0x20000])
        XCTAssertEqual(c.editor.selectedRange(),NSRange(location:prefix.utf16.count+2,length:0));XCTAssertEqual(host.insertCount,1)
        XCTAssertFalse(c.inspectorVisible);XCTAssertEqual(c.characterField.stringValue,"");XCTAssertEqual(c.characterPreviewLabel.stringValue,"")
        XCTAssertTrue(w.firstResponder===c.editor);XCTAssertTrue(w.isKeyWindow)
        try send(insert);XCTAssertEqual(host.insertCount,1)
        try type("nihao",c.editor);try key(" ",c.editor,code:49)
        XCTAssertEqual(c.editor.string,prefix+"𠀀你好");XCTAssertEqual(host.insertCount,2);XCTAssertFalse(c.editor.hasMarkedText())
    }
    @MainActor func testExactCharacterAcrossModesAndLiteralRenewal()throws {
        var count=0
        for spelling in LabSpelling.allCases {for traditional in [false,true] {for punctuation in [false,true] {for literal in [false,true] {
            let(c,w)=try make();defer{w.close()};var config=LabConfiguration();config.spelling=spelling;config.traditional=traditional;config.chinesePunctuation=punctuation;config.literal=literal
            try c.applyConfiguration(config)
            if literal{try type("A",c.editor);XCTAssertFalse(c.editor.dispatcher?.isCurrentTarget ?? true)}
            let insert=try preview(c,"±"),host=try XCTUnwrap(c.editor.dispatcher);try send(insert)
            XCTAssertEqual(c.configuration,config);XCTAssertEqual(c.editor.string,literal ? "A±":"±");XCTAssertEqual(host.insertCount,1)
            XCTAssertTrue(w.firstResponder===c.editor);XCTAssertTrue(w.isKeyWindow);count+=1
        }}}}
        XCTAssertEqual(count,24);print("B7_APPKIT_HOST 24 spelling/script/punctuation/literal configurations; no quality claim")
    }
    @MainActor func testCancelInvalidInputFieldChangesAndOldActionsDoNotInsert()throws {
        let(c,w)=try make();defer{w.close()};seed(c,"prefix")
        let old=try preview(c,"U+0041"),host=try XCTUnwrap(c.editor.dispatcher)
        c.characterField.stringValue="U+00B1";try send(old);XCTAssertTrue(c.characterActionStack.arrangedSubviews.isEmpty);XCTAssertEqual(c.editor.string,"prefix")
        let current=try preview(c,"U+00B1");try send(old);XCTAssertTrue(c.characterActionStack.arrangedSubviews.first===current)
        c.characterField.stringValue="U+202E";try send(c.characterPreviewButton);XCTAssertTrue(c.characterActionStack.arrangedSubviews.isEmpty)
        c.characterField.setMarkedText("U+0041",selectedRange:NSRange(location:6,length:0),replacementRange:NSRange(location:NSNotFound,length:0))
        try send(c.characterPreviewButton);XCTAssertTrue(c.characterActionStack.arrangedSubviews.isEmpty);c.characterField.unmarkText()
        _ = try preview(c,"U+212B");c.characterField.stringValue="Å"
        c.textDidChange(Notification(name:NSText.didChangeNotification,object:c.characterField));XCTAssertTrue(c.characterActionStack.arrangedSubviews.isEmpty)
        let cancelled=try preview(c,"U+212B");try send(c.characterCancelButton);try send(cancelled);try send(current)
        XCTAssertEqual(c.editor.string,"prefix");XCTAssertEqual(host.insertCount,0);XCTAssertFalse(c.inspectorVisible);XCTAssertTrue(w.firstResponder===c.editor)
        let next=try preview(c,"Å");c.characterField.stringValue="Å";try send(next)
        XCTAssertEqual(c.editor.string,"prefix");XCTAssertEqual(host.insertCount,0)
    }
    @MainActor func testCaretOnlySelectionRefusalAndNativeRangeNormalization()throws {
        do {
            let(c,w)=try make();defer{w.close()};seed(c,"abc")
            c.editor.setSelectedRange(NSRange(location:0,length:1));XCTAssertEqual(c.editor.selectedRange(),NSRange(location:0,length:1))
            try send(c.characterButton);XCTAssertFalse(c.inspectorVisible);XCTAssertEqual(c.editor.string,"abc")
        }
        // AppKit normalizes these requests before our controller can observe them.
        // Pure tests exercise refusal of the original invalid ranges; native tests
        // verify the actual observable safe range and never forge NSTextView state.
        for (text,requested) in [("𠀀",[NSRange(location:1,length:0)]),("e\u{301}",[NSRange(location:1,length:0)]),("👩🏽‍💻",[NSRange(location:2,length:0)]),("abcd",[NSRange(location:0,length:0),NSRange(location:3,length:0)])] {
            let(c,w)=try make();defer{w.close()};seed(c,text)
            XCTAssertFalse(TextBoundary.validSingleCaret(requested,in:text))
            c.editor.selectedRanges=requested.map{NSValue(range:$0)}
            let observed=c.editor.selectedRanges.map{$0.rangeValue}
            XCTAssertNotEqual(observed,requested);XCTAssertTrue(TextBoundary.validSingleCaret(observed,in:text))
            try send(c.characterButton);XCTAssertTrue(c.characterInspectorVisible)
            XCTAssertEqual(Array(c.editor.string.utf8),Array(text.utf8));XCTAssertEqual(c.editor.dispatcher?.insertCount,0)
            try send(c.characterCancelButton);XCTAssertFalse(c.inspectorVisible)
        }
        let(c,w)=try make();defer{w.close()};seed(c,"abcd");let insert=try preview(c,"U+0041")
        c.editor.setSelectedRange(NSRange(location:1,length:1));try send(insert)
        XCTAssertEqual(c.editor.string,"abcd");XCTAssertFalse(c.inspectorVisible)
    }
    @MainActor func testCompositionForeignMarksRepairAndClosedWindowRefuseOpening()throws {
        let(c,w)=try make();defer{w.close()};try type("ni",c.editor)
        let before=c.editor.string;try send(c.characterButton);XCTAssertFalse(c.characterInspectorVisible);XCTAssertEqual(c.editor.string,before)
        try key("\u{1b}",c.editor,code:53)
        var hold=LabConfiguration();hold.deferredCommit=true;try c.applyConfiguration(hold);try type("nihao",c.editor);try key(" ",c.editor,code:49);try send(c.repairButton)
        XCTAssertTrue(c.inspectorVisible);try send(c.characterButton);XCTAssertFalse(c.characterInspectorVisible);try send(c.cancelRepairButton);try key("\u{1b}",c.editor,code:53)
        c.editor.setMarkedText("外部",selectedRange:NSRange(location:2,length:0),replacementRange:NSRange(location:NSNotFound,length:0));let foreign=c.editor.string
        try send(c.characterButton);XCTAssertFalse(c.characterInspectorVisible);XCTAssertEqual(c.editor.string,foreign);XCTAssertTrue(c.editor.hasMarkedText())
        w.close();try send(c.characterButton);XCTAssertFalse(c.characterInspectorVisible)
    }
    @MainActor func testSharedModeSettingsAndRepairBarriersIncludeDirectActions()throws {
        let(c,w)=try make();defer{w.close()}
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("paia-b7-settings-"+UUID().uuidString)
        defer{try? FileManager.default.removeItem(at:root)}
        let store=try SettingsStore(directory:root);defer{store.close()};let settings=SettingsController(lab:c,store:store);settings.restoreAtStartup()
        var config=LabConfiguration();config.spelling = .flypy;config.traditional=true;try c.applyConfiguration(config)
        let insert=try preview(c,"U+00B1"),host=try XCTUnwrap(c.editor.dispatcher),binding=host.session.idleCharacterBinding
        XCTAssertFalse(c.spelling.isEnabled);XCTAssertFalse(settings.saveButton.isEnabled);XCTAssertFalse(settings.defaultsButton.isEnabled)
        XCTAssertThrowsError(try c.applyConfiguration(LabConfiguration()))
        c.spelling.selectItem(at:0);try send(c.spelling)
        for button in [settings.saveButton,settings.defaultsButton,settings.verifyButton,c.repairButton,c.previewButton,c.cancelRepairButton]{try send(button)}
        XCTAssertNil(try store.snapshot());XCTAssertEqual(c.configuration,config);XCTAssertTrue(c.characterInspectorVisible)
        XCTAssertEqual(host.session.idleCharacterBinding,binding);XCTAssertTrue(c.characterActionStack.arrangedSubviews.first===insert)
        try send(insert);XCTAssertEqual(c.editor.string,"±");XCTAssertEqual(host.insertCount,1)
    }
    @MainActor func testTargetChangesAndForeignFocusInvalidatePreview()throws {
        for kind in 0..<7 {
            let(c,w)=try make();defer{w.close()};seed(c,"Å")
            let insert=try preview(c,"U+0041"),host=try XCTUnwrap(c.editor.dispatcher)
            switch kind {
            case 0:c.editor.string="Å";c.editor.setSelectedRange(NSRange(location:1,length:0))
            case 1:c.editor.setSelectedRange(NSRange(location:0,length:0))
            case 2:let foreign=NSTextView(frame:.zero);c.root.addArrangedSubview(foreign);XCTAssertTrue(w.makeFirstResponder(foreign))
            case 3:XCTAssertTrue(w.makeFirstResponder(nil))
            case 4:c.editor.renew()
            case 5:w.resignKey()
            default:NotificationCenter.default.post(name:NSApplication.didResignActiveNotification,object:NSApp)
            }
            let before=Array(c.editor.string.utf8);try send(insert)
            XCTAssertEqual(Array(c.editor.string.utf8),before);XCTAssertEqual(host.insertCount,0);XCTAssertFalse(c.inspectorVisible)
        }
    }
    @MainActor func testCancelRevokesAcceptanceBeforeRestoringFocus()throws {
        for repair in [false,true] {
            let(c,w)=try make();defer{w.close()}
            let old:NSButton,cancel:NSButton
            if repair {
                var config=LabConfiguration();config.deferredCommit=true;try c.applyConfiguration(config)
                try type("nihao",c.editor);try key(" ",c.editor,code:49);try send(c.repairButton)
                c.rawField.stringValue="nihao";c.surfaceField.stringValue="你好";try send(c.previewButton)
                old=try XCTUnwrap(c.acceptStack.arrangedSubviews.first as? NSButton);cancel=c.cancelRepairButton
            }else{seed(c,"prefix");old=try preview(c,"U+0041");cancel=c.characterCancelButton}
            let host=try XCTUnwrap(c.editor.dispatcher),before=Array(c.editor.string.utf8),snapshot=host.session.snapshot,original=w.beforeFocusChange
            var injected=false
            w.beforeFocusChange={responder in
                original?(responder);guard responder===c.editor,!injected else{return};injected=true
                try? self.send(old)
                // Neither a retained action nor a newly requested preview can revive cancellation.
                try? self.send(repair ? c.previewButton:c.characterPreviewButton);try? self.send(old)
            }
            try send(cancel);w.beforeFocusChange=original;XCTAssertTrue(injected)
            XCTAssertEqual(Array(c.editor.string.utf8),before);XCTAssertEqual(host.insertCount,0)
            XCTAssertEqual(host.session.snapshot?.inputGeneration,snapshot?.inputGeneration)
            XCTAssertFalse(c.inspectorVisible);XCTAssertTrue(w.firstResponder===c.editor)
            try send(old);XCTAssertEqual(host.insertCount,0)
        }
    }
    @MainActor func testContextJoiningScalarIsRefusedBeforeInsertion()throws {
        let(c,w)=try make();defer{w.close()};seed(c,"🇧")
        try send(c.characterButton);XCTAssertTrue(c.characterInspectorVisible)
        c.characterField.stringValue="U+1F1E6";try send(c.characterPreviewButton)
        XCTAssertTrue(c.characterActionStack.arrangedSubviews.isEmpty);XCTAssertEqual(c.editor.string,"🇧")
        XCTAssertEqual(c.editor.dispatcher?.insertCount,0);try send(c.characterCancelButton)
    }
    @MainActor func testFocusRestorationReentrancyCannotChangeOrRepeatInsert()throws {
        for kind in 0..<4 {
            let(c,w)=try make();defer{w.close()};seed(c,"prefix")
            let insert=try preview(c,"U+0041"),host=try XCTUnwrap(c.editor.dispatcher),original=w.beforeFocusChange
            var injected=false
            w.beforeFocusChange={ responder in
                original?(responder)
                guard responder===c.editor,!injected else{return};injected=true
                switch kind {
                case 0:c.characterField.stringValue="U+0042"
                case 1:try? self.send(c.characterCancelButton)
                case 2:try? self.send(insert)
                default:c.editor.string="changed";c.editor.setSelectedRange(NSRange(location:7,length:0))
                }
            }
            try send(insert);XCTAssertTrue(injected);w.beforeFocusChange=original
            XCTAssertEqual(c.editor.string,kind==2 ? "prefixA":(kind==3 ? "changed":"prefix"))
            XCTAssertEqual(host.insertCount,kind==2 ? 1:0);XCTAssertFalse(c.inspectorVisible)
            try send(insert);XCTAssertEqual(host.insertCount,kind==2 ? 1:0)
        }
    }
}
#endif
