#if os(macOS)
import XCTest
import AppKit
import EngineBridge
import IMKHost
import IMKTestClient
import SessionCore
import TextBoundary
import NativeHost

final class ContextIMKTests:XCTestCase {
    static var environment:LabEnvironment!
    override class func setUp(){super.setUp();do{environment=try LabEnvironment()}catch{XCTFail("Verified context fixture startup failed: \(error)")}}
    @MainActor final class Authority {
        var epoch:UInt64=1,read=true,replace=true,endpoint=true
        var onRead:(()->Void)?
    }
    @MainActor final class Rig {
        let client:PAIAIMKTestClient,driver:IMKControllerDriver,bridge:IMKTextInputBridge,authority=Authority()
        init(_ text:String="a你好b",selection:NSRange?=NSRange(location:1,length:2),qualified:Bool=true,hide:@escaping()->Void={},present:@escaping(ContextEditState,NSRect)->Bool={_,_ in true})throws {
            client=PAIAIMKTestClient(text:text);if let selection=selection{client.view.setSelectedRange(selection)}
            let client=self.client,authority=self.authority
            bridge=try XCTUnwrap(IMKTextInputBridge(client,qualifiedContext:qualified ? {
                let callback=authority.onRead;authority.onRead=nil;callback?()
                return ContextAuthority(permissionEpoch:authority.epoch,documentRevision:UInt64(client.contextRevision),canRead:authority.read,canReplace:authority.replace,cheapReliableLength:authority.endpoint)
            }:nil))
            driver=IMKControllerDriver(makeSession:{try? ContextIMKTests.environment.runtime.makeSession()},hide:hide,present:{_,_,_ in},presentContext:present)
            _=driver.activate(bridge)
        }
        func close(){driver.close()}
    }
    @MainActor func event(_ text:String="",code:UInt16=0,modifiers:NSEvent.ModifierFlags=[],repeatKey:Bool=false)throws->NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:modifiers,timestamp:0,windowNumber:0,context:nil,characters:text,charactersIgnoringModifiers:text,isARepeat:repeatKey,keyCode:code))
    }
    @MainActor func key(_ r:Rig,_ text:String="",_ code:UInt16=0)throws {XCTAssertTrue(r.driver.handle(try event(text,code:code),client:r.client))}
    @MainActor func begin(_ r:Rig,_ kind:ContextEditKind = .selectedText)throws->ContextEditState {
        r.driver.performContextMenuAction(try XCTUnwrap(r.driver.contextMenuAction(kind:kind)))
        return try XCTUnwrap(r.driver.contextEdit)
    }
    @MainActor func replaceDraft(_ text:String,_ r:Rig)throws {
        let count=try XCTUnwrap(r.driver.contextEdit).draft.count;try key(r,"",115)
        for _ in 0..<count{try key(r,"",117)};for c in text{try key(r,String(c))}
        XCTAssertEqual(r.driver.contextEdit?.draft.utf8.map{$0},Array(text.utf8))
    }
    @MainActor func review(_ r:Rig)throws->ContextEditState {
        let state=try XCTUnwrap(r.driver.contextEdit);r.driver.reviewContext(token:state.token)
        let reviewed=try XCTUnwrap(r.driver.contextEdit);XCTAssertTrue(reviewed.reviewed);return reviewed
    }
    @MainActor func testUnknownBridgeHasNoContextReadsOrCapabilityUpgrade()throws {
        _=NSApplication.shared;let r=try Rig("",selection:nil,qualified:false);defer{r.close()}
        XCTAssertNil(r.driver.contextMenuAction(kind:.knownCharacter));XCTAssertNil(r.driver.contextMenuAction(kind:.selectedText))
        XCTAssertEqual(r.client.documentLengthCalls,0);XCTAssertEqual(r.client.reads.count,0)
        for c in "nihao"{try key(r,String(c))};try key(r," ",49)
        XCTAssertEqual(r.client.view.string,"你好");XCTAssertEqual(r.client.insertCalls,1);XCTAssertEqual(r.client.documentLengthCalls,0)
        // This client declares a synthetic bundle identifier and implements every
        // public selector; neither fact authorizes context on the default bridge.
        XCTAssertFalse(r.bridge.offersContext)
        let prefixed=try Rig("existing",selection:nil,qualified:false);defer{prefixed.close()}
        try key(prefixed,"n");XCTAssertEqual(prefixed.client.lastGeometryIndex,1)
        try key(prefixed,"",53);XCTAssertEqual(prefixed.client.lastGeometryIndex,0)
        // The older owned-lab dispatcher is not a C3 adapter and cannot ignore
        // the newly explicit range in a reviewedEdit effect.
        let session=try Self.environment.runtime.makeSession();_=try session.refresh()
        let view=NSTextView();view.string="original";view.setSelectedRange(NSRange(location:8,length:0))
        let dispatcher=HostDispatcher(client:view,session:session)
        let edit=try session.commitReviewedEdit("X",replacing:NSRange(location:0,length:1),binding:try XCTUnwrap(session.idleExpressionBinding))
        XCTAssertFalse(dispatcher.apply(edit));XCTAssertEqual(dispatcher.insertCount,0);XCTAssertEqual(view.string,"original");XCTAssertThrowsError(try session.refresh())
    }
    @MainActor func testSelectionReviewLongerShorterAndEmptyUseOneReservedEffect()throws {
        _=NSApplication.shared
        for replacement in ["x","代码𠀀e\u{301}👩🏽‍💻",""] {
            let r=try Rig();defer{r.close()};let initial=try begin(r)
            XCTAssertEqual(initial.capture.original,"你好");XCTAssertEqual(r.client.lastGeometryIndex,0);XCTAssertEqual(r.client.markCalls,0);XCTAssertEqual(r.client.insertCalls,0)
            XCTAssertEqual(r.client.reads.count,4);XCTAssertEqual(r.client.documentLengthCalls,6)
            try replaceDraft(replacement,r);let preview=try review(r)
            r.driver.applyContext(token:preview.token);r.driver.applyContext(token:preview.token)
            XCTAssertEqual(r.client.view.string,"a"+replacement+"b");XCTAssertEqual(r.client.insertCalls,1);XCTAssertEqual(r.client.markCalls,0)
            XCTAssertEqual((r.client.writes.firstObject as? NSValue)?.rangeValue,NSRange(location:1,length:2));XCTAssertNil(r.driver.coordinator.session)
            XCTAssertEqual(r.client.view.selectedRange(),NSRange(location:1+replacement.utf16.count,length:0))
            XCTAssertEqual(r.client.reads.count,10);XCTAssertEqual(r.client.documentLengthCalls,15)
        }
    }
    @MainActor func testContextualKnownCharacterEmptyEndAndJoiningRefusal()throws {
        _=NSApplication.shared
        for source in ["","你好"] {
            let r=try Rig(source,selection:nil);defer{r.close()};_=try begin(r,.knownCharacter)
            try replaceDraft("U+20000",r);let preview=try review(r);XCTAssertEqual(preview.character?.identifier,"U+20000")
            r.driver.applyContext(token:preview.token);XCTAssertEqual(r.client.view.string,source+"𠀀");XCTAssertEqual(r.client.insertCalls,1)
        }
        let r=try Rig("ᄀ",selection:nil);defer{r.close()};_=try begin(r,.knownCharacter);try replaceDraft("U+1161",r)
        r.driver.reviewContext(token:r.driver.contextEdit!.token);XCTAssertFalse(r.driver.contextEdit!.reviewed);XCTAssertEqual(r.client.insertCalls,0)
    }
    @MainActor func testDraftKeysHaveZeroContextReadsAndC2DoesNotGrantC3()throws {
        _=NSApplication.shared;let r=try Rig();defer{r.close()};r.authority.replace=false;_=try begin(r)
        let reads=r.client.reads.count,lengths=r.client.documentLengthCalls,revision=r.client.contextRevision
        XCTAssertFalse(r.driver.isIdleForManagement);XCTAssertNil(r.driver.retainedMenuAction(arm:true))
        try replaceDraft("literal correction",r);try key(r,"",123);try key(r,"",124)
        XCTAssertEqual(r.client.reads.count,reads);XCTAssertEqual(r.client.documentLengthCalls,lengths);XCTAssertEqual(r.client.contextRevision,revision)
        let preview=try review(r);XCTAssertFalse(preview.capture.canReplace);r.driver.applyContext(token:preview.token)
        XCTAssertEqual(r.client.insertCalls,0);XCTAssertEqual(r.client.view.string,"a你好b")
        r.driver.cancelContext(token:preview.token);XCTAssertTrue(r.driver.isIdleForManagement)
        for unavailable in 0..<2 {
            let q=try Rig();defer{q.close()};if unavailable==0{q.authority.read=false}else{q.authority.endpoint=false}
            q.driver.performContextMenuAction(try XCTUnwrap(q.driver.contextMenuAction(kind:.selectedText)))
            XCTAssertNil(q.driver.contextEdit);XCTAssertEqual(q.client.documentLengthCalls,0);XCTAssertEqual(q.client.reads.count,0)
        }
        // A metadata callback can revoke read authority without a lifecycle event.
        // The following body read must not happen under the former permission.
        for stage in 0..<2 {
            let q=try Rig();defer{q.close()}
            if stage==0{q.client.onLength={q.authority.read=false}}else{q.authority.onRead={q.client.onMarkedRange={q.authority.read=false}}}
            q.driver.performContextMenuAction(try XCTUnwrap(q.driver.contextMenuAction(kind:.selectedText)))
            XCTAssertNil(q.driver.contextEdit);XCTAssertEqual(q.client.reads.count,0)
            if stage==1{XCTAssertEqual(q.client.documentLengthCalls,0)}
        }
    }
    @MainActor func testRawMalformedActualRangeAndTruncatedResponsesRefuse()throws {
        _=NSApplication.shared
        for fault in 1...5 {
            let r=try Rig("abc",selection:NSRange(location:0,length:3));defer{r.close()}
            if fault==5{r.client.truncateReads=true}else{r.client.contextReadFault=fault}
            r.driver.performContextMenuAction(try XCTUnwrap(r.driver.contextMenuAction(kind:.selectedText)))
            XCTAssertNil(r.driver.contextEdit);XCTAssertEqual(r.client.insertCalls,0);XCTAssertEqual(r.client.view.string,"abc")
        }
    }
    @MainActor func testUnicodeNeighborhoodAndActualSurrogateExpansion()throws {
        _=NSApplication.shared
        for text in ["👩🏽‍💻X𠀀","e\u{301}X你好",String(repeating:"q",count:400)+"\nX尾"] {
            let r=try Rig(text,selection:(text as NSString).range(of:"X"));defer{r.close()};_=try begin(r)
            try replaceDraft("Y",r);let preview=try review(r);r.driver.applyContext(token:preview.token)
            XCTAssertEqual(r.client.view.string,text.replacingOccurrences(of:"X",with:"Y"));XCTAssertEqual(r.client.insertCalls,1)
        }
        let base="𠀀"+String(repeating:"a",count:254)+"\nX尾",selection=("𠀀"+String(repeating:"a",count:254)+"\nX尾" as NSString).range(of:"X")
        let r=try Rig(base,selection:selection);defer{r.close()};_=try begin(r)
        XCTAssertTrue(r.client.reads.compactMap{$0 as? NSValue}.contains(where:{$0.rangeValue.location==1 || $0.rangeValue.location==0 || $0.rangeValue.location==2}))
        for text in ["🇦X🇧","\rX\n"] {
            let q=try Rig(text,selection:(text as NSString).range(of:"X"));defer{q.close()};_=try begin(q);try replaceDraft("",q)
            q.driver.reviewContext(token:q.driver.contextEdit!.token);XCTAssertFalse(q.driver.contextEdit!.reviewed);XCTAssertEqual(q.client.insertCalls,0)
        }
    }
    @MainActor func testEveryCaptureGetterAndGeometryReentryCancelsWithoutRetarget()throws {
        _=NSApplication.shared
        for callback in 0..<6 {
            let r=try Rig();defer{r.close()};let cancel={r.driver.close()}
            switch callback {case 0:r.client.onSelectedRange=cancel;case 1:r.client.onMarkedRange=cancel;case 2:r.client.onLength=cancel;case 3:r.client.onRead=cancel;case 4:r.client.onGeometry=cancel;default:r.authority.onRead=cancel}
            r.driver.performContextMenuAction(try XCTUnwrap(r.driver.contextMenuAction(kind:.selectedText)))
            XCTAssertNil(r.driver.contextEdit);XCTAssertNil(r.driver.coordinator.session);XCTAssertEqual(r.client.insertCalls,0);XCTAssertEqual(r.client.markCalls,0)
        }
    }
    @MainActor func testChangedSelectionBytesDocumentRevisionAndPermissionInvalidateApply()throws {
        _=NSApplication.shared
        for variant in 0..<5 {
            let r=try Rig();defer{r.close()};_=try begin(r);try replaceDraft("new",r);let preview=try review(r)
            let oldRevision=r.client.contextRevision
            switch variant {
            case 0:r.client.view.setSelectedRange(NSRange(location:0,length:1))
            case 1:r.client.view.string="a你号b";r.client.view.setSelectedRange(NSRange(location:1,length:2));XCTAssertGreaterThan(r.client.contextRevision,oldRevision)
            case 2:r.authority.epoch+=1
            case 3:r.authority.replace=false
            default:r.client.onLength={r.client.view.string="a你号b";r.client.view.setSelectedRange(NSRange(location:1,length:2))}
            }
            let before=r.client.view.string;r.driver.applyContext(token:preview.token);r.driver.applyContext(token:preview.token)
            XCTAssertEqual(r.client.insertCalls,0);if variant != 4{XCTAssertEqual(r.client.view.string,before)};XCTAssertNil(r.driver.contextEdit)
        }
        let distant=String(repeating:"q",count:600)+"\n你好尾",q=try Rig(distant,selection:NSRange(location:601,length:2));defer{q.close()}
        _=try begin(q);try replaceDraft("new",q);let preview=try review(q),oldRevision=q.client.contextRevision
        q.client.view.textStorage?.replaceCharacters(in:NSRange(location:0,length:1),with:"z")
        q.client.view.setSelectedRange(NSRange(location:601,length:2));XCTAssertGreaterThan(q.client.contextRevision,oldRevision)
        q.driver.applyContext(token:preview.token);XCTAssertEqual(q.client.insertCalls,0)
    }
    @MainActor func testWriteReentryIgnoredRangeAndUnknownReadbackNeverReplay()throws {
        _=NSApplication.shared
        for variant in 0..<6 {
            let r=try Rig();defer{r.close()};_=try begin(r);let issued=variant==5 ? "":"new";try replaceDraft(issued,r);let preview=try review(r),owner=r.driver.coordinator
            let other=PAIAIMKTestClient(text:"other")
            if variant==0{r.client.onInsert={r.driver.applyContext(token:preview.token)}}
            if variant==1{r.client.onInsert={_ = r.driver.activate(IMKTextInputBridge(other)!)}}
            if variant==2 || variant==5{r.client.onInsert={r.client.truncateReads=true}}
            if variant==3{r.client.ignoreReplacementRange=true}
            if variant==4{r.client.onInsert={r.client.view.string="wrong";r.client.view.setSelectedRange(NSRange(location:4,length:0))}}
            r.driver.applyContext(token:preview.token);r.driver.applyContext(token:preview.token)
            XCTAssertEqual(r.client.insertCalls,1);XCTAssertEqual(other.insertCalls,0);XCTAssertEqual(r.client.markCalls,0)
            if variant==0{XCTAssertEqual(r.client.view.string,"anewb");XCTAssertEqual(owner.outcome,.ready)}
            else{XCTAssertEqual(owner.outcome,.outcomeUnknown);XCTAssertEqual(owner.recovery?.issuedText,issued);XCTAssertEqual(owner.recovery?.preedit,"你好");XCTAssertTrue(owner.recovery?.hasContent==true);if variant==5{XCTAssertTrue(owner.recovery!.inspectionText.contains("Empty replacement: deletion"))}}
        }
    }
    @MainActor func testCancelLifecycleAndModifiedKeysNeverLeaveSelectionSessionForC0()throws {
        _=NSApplication.shared
        for ending in 0..<6 {
            let r=try Rig();defer{r.close()};let captured=try begin(r),owner=r.driver.coordinator
            XCTAssertFalse(owner.process(.text("x"),client:r.client));XCTAssertNil(r.driver.retainedMenuAction(arm:true))
            switch ending {
            case 0:r.driver.cancelContext(token:captured.token)
            case 1:r.driver.finish(client:r.client)
            case 2:r.driver.deactivate(client:r.client)
            case 3:r.driver.close()
            case 4:r.driver.revokeContextAccess()
            default:XCTAssertFalse(r.driver.handle(try event("c",modifiers:[.command]),client:r.client))
            }
            XCTAssertNil(owner.session);r.driver.applyContext(token:captured.token)
            _=r.driver.handle(try event("x"),client:r.client)
            XCTAssertEqual(r.client.view.string,"a你好b");XCTAssertEqual(r.client.insertCalls,0);XCTAssertEqual(r.client.markCalls,0)
        }
        let idle=try Rig("",selection:nil);defer{idle.close()};let captured=try begin(idle,.knownCharacter);idle.driver.cancelContext(token:captured.token)
        for c in "nihao"{try key(idle,String(c))};try key(idle," ",49);XCTAssertEqual(idle.client.view.string,"你好")
    }
    @MainActor func testStaleMenusEditedReviewFailedPresentationAndRepeatedReturn()throws {
        _=NSApplication.shared
        let refused=try Rig();defer{refused.close()};let old=try XCTUnwrap(refused.driver.contextMenuAction(kind:.selectedText))
        XCTAssertFalse(refused.driver.handle(try event("x"),client:refused.client))
        refused.client.view.setSelectedRange(NSRange(location:0,length:1));refused.driver.performContextMenuAction(old)
        XCTAssertNil(refused.driver.contextEdit);XCTAssertEqual(refused.client.reads.count,0);XCTAssertEqual(refused.client.documentLengthCalls,0)
        let r=try Rig();defer{r.close()};let menu=try XCTUnwrap(r.driver.contextMenuAction(kind:.selectedText));_=try begin(r);try replaceDraft("new",r);let preview=try review(r)
        try key(r,"x");XCTAssertFalse(r.driver.contextEdit!.reviewed);r.driver.applyContext(token:preview.token);XCTAssertEqual(r.client.insertCalls,0)
        r.driver.performContextMenuAction(menu);XCTAssertFalse(r.driver.contextEdit!.reviewed)
        XCTAssertTrue(r.driver.handle(try event("\r",code:36,repeatKey:true),client:r.client));XCTAssertFalse(r.driver.contextEdit!.reviewed)
        let latest=try review(r);r.driver.cancelContext(token:latest.token);r.driver.applyContext(token:latest.token);XCTAssertEqual(r.client.insertCalls,0)
        let refusedInputs:[(String,UInt16)]=[("\t",48),("\u{1}",0),(String(repeating:"x",count:1025),0)]
        for (text,code) in refusedInputs {
            let blocked=try Rig();defer{blocked.close()};_=try begin(blocked);let oldReview=try review(blocked)
            try key(blocked,text,code);XCTAssertFalse(blocked.driver.contextEdit!.reviewed);XCTAssertNotNil(blocked.driver.contextEdit!.notice)
            blocked.driver.applyContext(token:oldReview.token);XCTAssertEqual(blocked.client.insertCalls,0)
        }
        weak var target:IMKControllerDriver?
        let q=try Rig(present:{state,_ in if state.reviewed{target?.applyContext(token:state.token);return false};return true});target=q.driver;defer{q.close()}
        _=try begin(q);try replaceDraft("new",q);q.driver.reviewContext(token:q.driver.contextEdit!.token)
        XCTAssertNil(q.driver.contextEdit);XCTAssertEqual(q.client.insertCalls,0)
    }
    @MainActor func testActualNonKeyPanelFullOriginalReplacementAndOverflowTail()throws {
        _=NSApplication.shared;let panel=ContextEditPanel(),screen=NSRect(x:0,y:0,width:1200,height:900)
        let original="原文"+String(repeating:"世界",count:250)+"末",r=try Rig(original,selection:NSRange(location:0,length:original.utf16.count),hide:{panel.orderOut(nil)},present:{state,rect in panel.show(state,below:rect,screen:screen)})
        defer{r.close();panel.orderOut(nil)}
        let window=NSWindow(contentRect:NSRect(x:40,y:60,width:640,height:240),styleMask:[.titled],backing:.buffered,defer:false);window.isReleasedWhenClosed=false;window.contentView=r.client.view;window.makeKeyAndOrderFront(nil);window.makeFirstResponder(r.client.view);defer{window.close()}
        // AppKit focus can move the selection, so the explicit authored selection
        // is restored before activating/capturing the same protocol adapter.
        r.client.view.setSelectedRange(NSRange(location:0,length:original.utf16.count));_=r.driver.activate(r.bridge);_=try begin(r)
        try key(r,"",119);try key(r,"终");let preview=try review(r);panel.displayIfNeeded()
        XCTAssertTrue(panel.isVisible);XCTAssertFalse(panel.isKeyWindow);XCTAssertFalse(panel.canBecomeKey);XCTAssertTrue(window.firstResponder===r.client.view)
        XCTAssertEqual(panel.displayedOriginal,original);XCTAssertEqual(panel.displayedReplacement,original+"终")
        XCTAssertGreaterThan(panel.textView.bounds.height,panel.scroll.contentSize.height)
        let view=try XCTUnwrap(panel.contentView)
        func capture(_ key:String)throws {let bitmap=try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in:view.bounds));view.cacheDisplay(in:view.bounds,to:bitmap);if let path=ProcessInfo.processInfo.environment[key]{try XCTUnwrap(bitmap.representation(using:.png,properties:[:])).write(to:URL(fileURLWithPath:path),options:.atomic)}}
        try capture("PAIA_CONTEXT_CAPTURE")
        for _ in 0..<40{panel.scrollReview(1,token:preview.token)}
        XCTAssertGreaterThan(panel.scroll.contentView.bounds.minY,0)
        let manager=try XCTUnwrap(panel.textView.layoutManager),container=try XCTUnwrap(panel.textView.textContainer)
        XCTAssertEqual(NSMaxRange(manager.glyphRange(forBoundingRect:panel.textView.visibleRect,in:container)),manager.numberOfGlyphs)
        try capture("PAIA_CONTEXT_CAPTURE_TAIL")
        r.driver.applyContext(token:preview.token);XCTAssertEqual(r.client.insertCalls,1);XCTAssertFalse(panel.isVisible);XCTAssertEqual(r.client.view.string,original+"终")
        let next=try Rig("next文字",selection:NSRange(location:4,length:2));defer{next.close()};_=try begin(next);let newer=try review(next)
        for reentry in 1...5 {
            var callbacks=0
            let obsolete=panel.show(preview,below:NSRect(x:200,y:400,width:1,height:22),screen:screen,isCurrent:{
                callbacks+=1
                if callbacks==reentry{XCTAssertTrue(panel.show(newer,below:NSRect(x:200,y:400,width:1,height:22),screen:screen))}
                return true
            })
            XCTAssertFalse(obsolete);XCTAssertEqual(panel.renderedToken,newer.token);XCTAssertEqual(panel.displayedOriginal,"文字");XCTAssertTrue(panel.textView.string.hasSuffix("文字"))
        }
        print("IMK_CONTEXT_NATIVE ENGINE_NATIVE + APPKIT_HOST; authored qualified adapter; 12 tests; no installed or live-client claim")
    }
}
#endif
