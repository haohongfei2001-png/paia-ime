#if os(macOS)
import XCTest
import AppKit
import EngineBridge
import NativeHost
import SessionCore

@MainActor private final class EffectProbeView:NSTextView {
    var afterInsert:(()->Void)?,beforeMarked:(()->Void)?,afterMarked:(()->Void)?
    var insertCalls=0,markCalls=0,unmarkCalls=0
    override func insertText(_ insertString:Any,replacementRange:NSRange){insertCalls+=1;super.insertText(insertString,replacementRange:replacementRange);afterInsert?()}
    override func setMarkedText(_ value:Any,selectedRange:NSRange,replacementRange:NSRange){markCalls+=1;beforeMarked?();super.setMarkedText(value,selectedRange:selectedRange,replacementRange:replacementRange);afterMarked?()}
    override func unmarkText(){unmarkCalls+=1;super.unmarkText()}
}
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
    @MainActor func key(_ text:String,_ view:NSTextView,code:UInt16=0,modifiers:NSEvent.ModifierFlags=[])throws {
        view.keyDown(with:try XCTUnwrap(NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:modifiers,timestamp:0,windowNumber:view.window?.windowNumber ?? 0,context:nil,characters:text,charactersIgnoringModifiers:text,isARepeat:false,keyCode:code)))
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
    @MainActor func capture(_ label:String,_ c:NativeLabController)throws {
        let view=c.root;view.layoutSubtreeIfNeeded();view.displayIfNeeded()
        let bitmap=try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in:view.bounds));view.cacheDisplay(in:view.bounds,to:bitmap)
        let data=try XCTUnwrap(bitmap.representation(using:.png,properties:[:])),directory=URL(fileURLWithPath:FileManager.default.currentDirectoryPath).appendingPathComponent("evidence/b8-run")
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true);try data.write(to:directory.appendingPathComponent(label+".png"))
        let encoded=data.base64EncodedString();var offset=encoded.startIndex,index=0
        while offset<encoded.endIndex{let end=encoded.index(offset,offsetBy:3000,limitedBy:encoded.endIndex) ?? encoded.endIndex;FileHandle.standardError.write(Data(("PAIA_B8_\(label)_IMAGE_\(index):"+encoded[offset..<end]+"\n").utf8));offset=end;index+=1}
    }
    @MainActor func testRefusalIsVisibleAndDoesNotApplyOrRewriteMarkedText()throws {
        let(c,w)=try make();defer{w.close()};try type("nihao",c.editor);for _ in 0..<3{try key("",c.editor,code:123)}
        let host=try XCTUnwrap(c.editor.dispatcher),before=try XCTUnwrap(host.session.snapshot),text=Array(c.editor.string.utf8)
        var edits=0
        let token=NotificationCenter.default.addObserver(forName:NSTextStorage.didProcessEditingNotification,object:c.editor.textStorage,queue:.main){_ in MainActor.assumeIsolated{edits+=1}}
        defer{NotificationCenter.default.removeObserver(token)}
        try key(",",c.editor);XCTAssertEqual(c.editor.lastInputRefusal,.textBeforeRawSuffix)
        XCTAssertTrue(c.status.stringValue.contains("Composition unchanged"));XCTAssertTrue(c.status.stringValue.contains("Return"))
        try capture("middle-refusal",c)
        try key("ü",c.editor);XCTAssertEqual(c.editor.lastInputRefusal,.unsupportedTextDuringComposition)
        try capture("unicode-refusal",c)
        XCTAssertTrue(c.status.stringValue.contains("not supported"));XCTAssertEqual(edits,0)
        XCTAssertEqual(Array(c.editor.string.utf8),text);XCTAssertEqual(host.session.snapshot?.inputGeneration,before.inputGeneration)
        let refusal=try host.session.process(.text("ｑ"));XCTAssertFalse(host.apply(refusal));XCTAssertTrue(host.isCurrentTarget);XCTAssertEqual(edits,0)
        try key("",c.editor,code:119);try key(" ",c.editor,code:49)
        XCTAssertEqual(host.insertCount,1);XCTAssertFalse(c.editor.hasMarkedText())
        XCTAssertEqual(c.status.stringValue,"");XCTAssertNil(c.editor.lastInputRefusal)
    }
    @MainActor func testIdleLiteralAndPhysicalControlPathsRemainDistinct()throws {
        for literal in [false,true] {
            let(c,w)=try make();defer{w.close()};var config=LabConfiguration();config.literal=literal;try c.applyConfiguration(config)
            for text in ["ü","中","𠀀","u\u{308}","👩🏽‍💻","ｑ","（"] {
                c.editor.string="prefix|";c.editor.setSelectedRange(NSRange(location:7,length:0));c.editor.renew()
                try key(text,c.editor);XCTAssertEqual(Array(c.editor.string.utf8),Array(("prefix|"+text).utf8));XCTAssertNil(c.editor.lastInputRefusal)
            }
        }
        let(c,w)=try make();defer{w.close()};c.editor.dispatcher?.invalidate()
        c.editor.dispatcher=HostDispatcher(client:c.editor,session:try Self.environment.runtime.makeSession(schema:LabConfiguration().schema))
        XCTAssertNil(c.editor.dispatcher?.session.snapshot);try key("ｑ",c.editor);XCTAssertEqual(c.editor.string,"ｑ")
        c.editor.string="";c.editor.setSelectedRange(NSRange(location:0,length:0));c.editor.renew();try type("nihao",c.editor)
        try key("",c.editor,code:123);XCTAssertEqual(c.editor.dispatcher?.session.snapshot?.caretUTF8,4)
        try key("",c.editor,code:51);XCTAssertEqual(c.editor.dispatcher?.session.snapshot?.rawASCII,"niho")
        try key("\r",c.editor,code:36);XCTAssertEqual(c.editor.string,"niho");XCTAssertFalse(c.editor.hasMarkedText())
    }
    @MainActor func testRefusalCallbackCannotResumeTheOldEvent()throws {
        for kind in 0..<4 {
            let(c,w)=try make();defer{w.close()};try type("nihao",c.editor)
            let host=try XCTUnwrap(c.editor.dispatcher),original=c.editor.didRefuseInput;var calls=0
            c.editor.didRefuseInput={ reason in
                original?(reason);calls+=1
                switch kind {
                case 0:try? self.key("\u{1b}",c.editor,code:53)
                case 1:try? self.key("a",c.editor)
                case 2:c.editor.string="external";c.editor.setSelectedRange(NSRange(location:8,length:0))
                default:let other=NSTextView(frame:.zero);c.root.addArrangedSubview(other);_ = w.makeFirstResponder(other)
                }
            }
            try key("ü",c.editor);XCTAssertEqual(calls,1);XCTAssertEqual(host.insertCount,0)
            switch kind {
            case 0:XCTAssertEqual(c.editor.string,"");XCTAssertEqual(host.session.snapshot?.rawASCII,"")
            case 1:XCTAssertEqual(host.session.snapshot?.rawASCII,"nihaoa");XCTAssertEqual(c.editor.string,host.session.snapshot?.preedit)
            case 2:XCTAssertEqual(c.editor.string,"external");XCTAssertEqual(c.status.stringValue,"")
            default:XCTAssertEqual(c.editor.string,"");XCTAssertFalse(host.isCurrentTarget)
            }
            XCTAssertFalse(c.editor.string.contains("ü"))
        }
    }
    @MainActor func testApplyStopsAfterInsertionLosesOwnershipAndNeverReplays()throws {
        for kind in 0..<4 {
            let(_,w)=try make();defer{w.close()}
            let root=NSView(frame:NSRect(x:0,y:0,width:600,height:250)),view=EffectProbeView(frame:NSRect(x:0,y:0,width:280,height:200)),other=NSTextView(frame:NSRect(x:300,y:0,width:280,height:200))
            root.addSubview(view);root.addSubview(other);w.contentView=root;XCTAssertTrue(w.makeFirstResponder(view))
            let session=try Self.environment.runtime.makeSession(schema:LabConfiguration().schema),host=HostDispatcher(client:view,session:session)
            for b in "nihao".utf8{XCTAssertTrue(host.apply(try session.process(.code(Int32(b)))))}
            let update=try session.process(.space);var countsAtCallback=(0,0),called=false
            view.afterInsert={
                called=true;countsAtCallback=(view.markCalls,view.unmarkCalls)
                switch kind {
                case 0:host.invalidate()
                case 1:_ = w.makeFirstResponder(other)
                case 2:_ = try? session.process(.text("a"))
                default:view.removeFromSuperview()
                }
            }
            XCTAssertFalse(host.apply(update));XCTAssertTrue(called);XCTAssertEqual(host.insertCount,1);XCTAssertEqual(view.insertCalls,1)
            XCTAssertEqual(view.markCalls,countsAtCallback.0);XCTAssertEqual(view.unmarkCalls,countsAtCallback.1)
            XCTAssertFalse(host.apply(update));XCTAssertEqual(view.insertCalls,1);view.afterInsert=nil;host.invalidate()
        }
    }
    @MainActor func testNestedMarkApplicationIsRejectedBeforeRecursion()throws {
        let(_,w)=try make();defer{w.close()};let view=EffectProbeView(frame:NSRect(x:0,y:0,width:400,height:200));w.contentView=view;XCTAssertTrue(w.makeFirstResponder(view))
        let session=try Self.environment.runtime.makeSession(schema:LabConfiguration().schema),host=HostDispatcher(client:view,session:session);defer{host.invalidate()}
        let update=try session.process(.text("n"));var nested:Bool?,once=false
        view.beforeMarked={guard !once else{return};once=true;nested=host.apply(update)}
        XCTAssertTrue(host.apply(update));XCTAssertEqual(nested,false);XCTAssertEqual(view.markCalls,1);XCTAssertEqual(view.string,update.snapshot?.preedit)
        view.beforeMarked=nil
        let cancelled=try session.process(.escape);var capturedUnmarks=0
        view.afterMarked={capturedUnmarks=view.unmarkCalls;host.invalidate()}
        XCTAssertFalse(host.apply(cancelled));XCTAssertEqual(view.unmarkCalls,capturedUnmarks);view.afterMarked=nil
    }

    @MainActor func testNoAppKitPunctuationFallbackAfterNativeWriteLosesFocus()throws {
        let(c,w)=try make();defer{w.close()};try type("nihao",c.editor)
        let host=try XCTUnwrap(c.editor.dispatcher),other=NSTextView(frame:.zero);c.root.addArrangedSubview(other)
        var injected=false
        let token=NotificationCenter.default.addObserver(forName:NSTextStorage.didProcessEditingNotification,object:c.editor.textStorage,queue:.main){_ in MainActor.assumeIsolated {
            guard !injected else{return};injected=true;_ = w.makeFirstResponder(other)
        }}
        defer{NotificationCenter.default.removeObserver(token)}
        try key(",",c.editor);XCTAssertTrue(injected);XCTAssertTrue(w.firstResponder===other)
        XCTAssertEqual(host.insertCount,1);XCTAssertFalse(host.isCurrentTarget)
        XCTAssertFalse(c.editor.string.contains(","));XCTAssertEqual(other.string,"")
        let after=Array(c.editor.string.utf8);try key(",",c.editor)
        XCTAssertEqual(Array(c.editor.string.utf8),after);XCTAssertEqual(other.string,"")
    }

    @MainActor func testCancellationDoesNotUnmarkANewerNativeOwner()throws {
        let(_,w)=try make();defer{w.close()}
        let view=EffectProbeView(frame:NSRect(x:0,y:0,width:400,height:200));w.contentView=view;XCTAssertTrue(w.makeFirstResponder(view))
        let session=try Self.environment.runtime.makeSession(schema:LabConfiguration().schema),host=HostDispatcher(client:view,session:session)
        XCTAssertTrue(host.apply(try session.process(.text("n"))));XCTAssertTrue(view.hasMarkedText())
        var foreignBytes=[UInt8](),foreignMark=NSRange(),foreignSelection=NSRange(),foreignUnmarks=0,called=false
        view.afterMarked={
            view.afterMarked=nil;called=true
            let foreign="外部👩🏽‍💻"
            view.setMarkedText(foreign,selectedRange:NSRange(location:(foreign as NSString).length,length:0),replacementRange:NSRange(location:NSNotFound,length:0))
            foreignBytes=Array(view.string.utf8);foreignMark=view.markedRange();foreignSelection=view.selectedRange();foreignUnmarks=view.unmarkCalls
        }
        host.invalidate();XCTAssertTrue(called)
        XCTAssertEqual(Array(view.string.utf8),foreignBytes);XCTAssertEqual(view.markedRange(),foreignMark);XCTAssertEqual(view.selectedRange(),foreignSelection)
        XCTAssertTrue(view.hasMarkedText());XCTAssertEqual(view.unmarkCalls,foreignUnmarks)
        XCTAssertFalse(host.isCurrentTarget);XCTAssertThrowsError(try session.process(.text("a")))
        host.invalidate();XCTAssertEqual(view.unmarkCalls,foreignUnmarks);XCTAssertEqual(view.markedRange(),foreignMark)
    }

    @MainActor func testOptionCancellationDoesNotResumeAfterFocusChanges()throws {
        let(c,w)=try make();defer{w.close()};c.editor.string="keepword";c.editor.setSelectedRange(NSRange(location:8,length:0));c.editor.renew();try type("n",c.editor)
        let old=try XCTUnwrap(c.editor.dispatcher),other=NSTextView(frame:.zero);c.root.addArrangedSubview(other)
        var called=false
        let token=NotificationCenter.default.addObserver(forName:NSTextStorage.didProcessEditingNotification,object:c.editor.textStorage,queue:.main){_ in MainActor.assumeIsolated {
            guard !called else{return};called=true;_ = w.makeFirstResponder(other)
        }}
        defer{NotificationCenter.default.removeObserver(token)}
        try key("\u{7f}",c.editor,code:51,modifiers:[.option])
        XCTAssertTrue(called);XCTAssertTrue(w.firstResponder===other);XCTAssertFalse(old.isCurrentTarget)
        XCTAssertEqual(c.editor.string,"keepword");XCTAssertEqual(other.string,"")
    }

    @MainActor func testRenewDoesNotReplaceADispatcherInstalledDuringFactoryCallback()throws {
        let(c,w)=try make();defer{w.close()}
        let newer=HostDispatcher(client:c.editor,session:try Self.environment.runtime.makeSession(schema:LabConfiguration().schema))
        let obsolete=HostDispatcher(client:c.editor,session:try Self.environment.runtime.makeSession(schema:LabConfiguration().schema))
        c.editor.makeSession={c.editor.dispatcher=newer;return obsolete}
        c.editor.renew();XCTAssertTrue(c.editor.dispatcher===newer)
        obsolete.invalidate();newer.invalidate();c.editor.makeSession=nil
    }

}
#endif
