#if os(macOS)
import XCTest
import AppKit
import EngineBridge
import IMKHost
import IMKTestClient
import SessionCore

final class IMKRepairTests:XCTestCase {
    static var environment:ResearchLabEnvironment!
    override class func setUp(){super.setUp();do{environment=try ResearchLabEnvironment()}catch{XCTFail("Verified repair research startup failed: \(error)")}}
    @MainActor final class Rig {
        let driver:IMKControllerDriver,client:PAIAIMKTestClient
        init(schema:String="paia_a1",hide:@escaping()->Void={},present:@escaping(SegmentRepairState,NSRect)->Bool={_,_ in true})throws {
            client=PAIAIMKTestClient(text:"existing👩🏽‍💻")
            driver=IMKControllerDriver(makeSession:{try? IMKRepairTests.environment.runtime.makeSession(schema:schema)},hide:hide,present:{_,_,_ in},presentRepair:present)
            XCTAssertEqual(driver.activate(try XCTUnwrap(IMKTextInputBridge(client))),.ready)
        }
        func close(){driver.close()}
    }
    @MainActor func event(_ text:String="",code:UInt16=0,modifiers:NSEvent.ModifierFlags=[],repeatKey:Bool=false)throws->NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:modifiers,timestamp:0,windowNumber:0,context:nil,characters:text,charactersIgnoringModifiers:text,isARepeat:repeatKey,keyCode:code))
    }
    @MainActor func key(_ r:Rig,_ text:String="",_ code:UInt16=0,_ modifiers:NSEvent.ModifierFlags=[])throws {
        XCTAssertTrue(r.driver.handle(try event(text,code:code,modifiers:modifiers),client:r.client))
    }
    @MainActor func arm(_ r:Rig)throws {r.driver.performRetainedMenuAction(try XCTUnwrap(r.driver.retainedMenuAction(arm:true)));XCTAssertTrue(r.driver.coordinator.session?.isRetainedComposition==true)}
    @MainActor func type(_ raw:String,_ r:Rig)throws {for c in raw{try key(r,String(c))}}
    @MainActor func confirm(_ words:[String],_ r:Rig)throws {
        for word in words {
            var found=false
            for _ in 0..<100 {
                let snapshot=try XCTUnwrap(r.driver.coordinator.snapshot)
                if let row=snapshot.rows.first(where:{$0.text.utf8.elementsEqual(word.utf8)}) {r.driver.choose(row.ref);found=true;break}
                if !snapshot.hasMore{break};try key(r,"",121)
            }
            XCTAssertTrue(found,"Real candidate missing: "+word);if !found{throw EngineError.closed}
        }
        XCTAssertEqual(r.client.insertCalls,0)
    }
    @MainActor func target(_ index:Int,_ r:Rig)throws->SegmentRepairState {
        try key(r,"",123,[.option])
        for _ in 0..<260 {
            let state=try XCTUnwrap(r.driver.repair);if state.target.index==index{return state}
            try key(r,"",state.target.index>index ? 123:124,[.option])
        }
        throw EngineError.closed
    }
    @MainActor func replaceDraft(_ text:String,_ r:Rig)throws {
        let count=try XCTUnwrap(r.driver.repair).replacementRaw.utf8.count;try key(r,"",115)
        for _ in 0..<count{try key(r,"",117)};try type(text,r)
        XCTAssertEqual(r.driver.repair?.replacementRaw,text)
    }
    @MainActor func review(_ surface:String,_ r:Rig)throws->SegmentRepairState {
        let state=try XCTUnwrap(r.driver.repair);r.driver.searchRepair(token:state.token)
        let list=try XCTUnwrap(r.driver.repair),index=try XCTUnwrap(list.rows.firstIndex(where:{$0.surface.utf8.elementsEqual(surface.utf8)}))
        while r.driver.repair!.page<index/5{try key(r,"",121)}
        let visible=try XCTUnwrap(r.driver.repair)
        XCTAssertTrue(r.driver.handle(try event(String(index%5+1)),client:r.client))
        XCTAssertNotEqual(visible.token,r.driver.repair?.token)
        let result=try XCTUnwrap(r.driver.repair);XCTAssertNotNil(result.proposal);return result
    }
    @MainActor func commit(_ expected:String,_ r:Rig)throws {
        let action=try XCTUnwrap(r.driver.retainedMenuAction(arm:false));r.driver.performRetainedMenuAction(action)
        r.driver.performRetainedMenuAction(action)
        XCTAssertEqual(r.client.view.string,"existing👩🏽‍💻"+expected);XCTAssertEqual(r.client.insertCalls,1);XCTAssertNil(r.driver.coordinator.session)
        XCTAssertEqual(r.client.documentLengthCalls,0)
    }
    @MainActor func testFrontMiddleEndInsertDeleteResegmentUnicodeAndLongSuffixThroughIMK()throws {
        _=NSApplication.shared
        let cases:[(String,[String],Int,String,String,String)]=[
            ("nihaoshijieni",["你好","世界","你"],0,"nihao","拟好","拟好世界你"),
            ("nihaonihaoshijie",["你好","你好","世界"],1,"nihao","你号","你好你号世界"),
            ("nihaoshijieni",["你好","世界","你"],2,"ni","泥","你好世界泥"),
            ("nishijieni",["你","世界","你"],0,"nihao","你好","你好世界你"),
            ("nihaoshijieni",["你好","世界","你"],0,"ni","你","你世界你"),
            ("nihaoshijieni",["你好","世界","你"],1,"","","你好你"),
            ("nihaoshijieni",["你好","世界","你"],1,"shijieni","世界泥","你好世界泥你"),
            ("nihaoemojikuo",["你好","👩🏽‍💻","𠀀"],1,"accent","e\u{301}","你好e\u{301}𠀀"),
            ("nihao"+String(repeating:"shijie",count:128)+"ni",["你好"]+Array(repeating:"世界",count:128)+["你"],0,"nihao","拟好","拟好"+String(repeating:"世界",count:128)+"你")]
        for (raw,words,index,replacement,surface,expected) in cases {
            let r=try Rig();defer{r.close()};try arm(r);try type(raw,r);try confirm(words,r)
            let marks=r.client.markCalls,original=r.client.view.string,generation=r.driver.coordinator.snapshot?.inputGeneration
            _ = try target(index,r);try replaceDraft(replacement,r);let state=try review(surface,r)
            XCTAssertEqual(r.client.markCalls,marks);XCTAssertEqual(r.client.view.string,original);XCTAssertEqual(r.driver.coordinator.snapshot?.inputGeneration,generation)
            XCTAssertEqual(state.proposal?.preview.utf8.map{$0},Array(expected.utf8))
            r.driver.applyRepair(token:state.token);XCTAssertEqual(r.client.insertCalls,0);XCTAssertNil(r.driver.repair)
            let after=r.client.markCalls;r.driver.applyRepair(token:state.token);XCTAssertEqual(r.client.markCalls,after)
            try commit(expected,r)
        }
        print("IMK_REPAIR cases=9; real first/middle/last/insert/delete/resegment/Unicode/128-word suffix; zero inserts before explicit engine commit")
    }
    @MainActor func testFullInitialsFlypyNaturalAndTraditionalUseSameIssuedRepairPath()throws {
        _=NSApplication.shared
        let cases=[("full","nihaoshurufashijie","daimashencha"),("full","nhsrfshijie","dmsc"),("flypy","nihcuurufauijp","ddmaufia"),("natural","nihkuurufauijx","dlmaufia")]
        for (spelling,raw,replacement) in cases {for traditional in [false,true] {for punctuation in [false,true] {
            let schema="paia_b1_"+spelling+(traditional ? "_traditional":"")+(punctuation ? "_punct":"_ascii")
            let r=try Rig(schema:schema);defer{r.close()};try arm(r);try type(raw,r)
            try confirm(["你好",traditional ? "輸入法":"输入法","世界"],r);_ = try target(1,r);try replaceDraft(replacement,r)
            let surface=traditional ? "代碼審查":"代码审查",state=try review(surface,r)
            r.driver.applyRepair(token:state.token);try commit("你好"+surface+"世界",r)
        }}}
        print("IMK_REPAIR spelling-script-punctuation combinations=16")
    }
    @MainActor func testOneArmRetiresAfterReturnEscapeCommitAndModifierFinish()throws {
        _=NSApplication.shared
        for ending in 0..<7 {
            let r=try Rig();defer{r.close()};try arm(r);try type("nihao",r);try confirm(["你好"],r)
            let old=try XCTUnwrap(r.driver.coordinator.session)
            if ending==0{try key(r,"\r",36);XCTAssertEqual(r.client.view.string,"existing👩🏽‍💻nihao")}
            if ending==1{try key(r,"",53);XCTAssertEqual(r.client.view.string,"existing👩🏽‍💻")}
            if ending==2{try commit("你好",r)}
            if ending==3{XCTAssertFalse(r.driver.handle(try event("c",modifiers:[.command]),client:r.client));XCTAssertEqual(r.client.view.string,"existing👩🏽‍💻nihao")}
            if ending==4{r.driver.finish(client:r.client);XCTAssertEqual(r.client.view.string,"existing👩🏽‍💻nihao")}
            if ending==5{r.driver.deactivate(client:r.client);XCTAssertEqual(r.client.view.string,"existing👩🏽‍💻nihao")}
            if ending==6 {
                let before=r.client.view.string,marks=r.client.markCalls;r.driver.close()
                XCTAssertEqual(r.client.view.string,before);XCTAssertEqual(r.client.markCalls,marks);XCTAssertEqual(r.client.insertCalls,0)
                XCTAssertThrowsError(try old.refresh());let next=PAIAIMKTestClient(text:"")
                XCTAssertEqual(r.driver.activate(try XCTUnwrap(IMKTextInputBridge(next))),.ready);XCTAssertFalse(r.driver.coordinator.session!.isRetainedComposition)
                for c in "nihao"{XCTAssertTrue(r.driver.handle(try event(String(c)),client:next))}
                XCTAssertTrue(r.driver.handle(try event(" ",code:49),client:next));XCTAssertEqual(next.view.string,"你好");XCTAssertEqual(next.insertCalls,1);continue
            }
            XCTAssertThrowsError(try old.refresh());XCTAssertNil(r.driver.coordinator.session)
            if ending==5{XCTAssertEqual(r.driver.activate(try XCTUnwrap(IMKTextInputBridge(r.client))),.ready)}
            let previous=r.client.insertCalls;try type("nihao",r);XCTAssertFalse(r.driver.coordinator.session!.isRetainedComposition)
            try key(r," ",49);XCTAssertEqual(r.client.insertCalls,previous+1)
        }
    }
    @MainActor func testPartialUnarmedUnsupportedKeysAndConflictDoNotChangeComposition()throws {
        _=NSApplication.shared;let r=try Rig();defer{r.close()}
        try type("nihao",r);let text=r.client.view.string,marks=r.client.markCalls,generation=r.driver.coordinator.snapshot?.inputGeneration
        try key(r,"",123,[.option]);XCTAssertNil(r.driver.repair);XCTAssertEqual(r.client.view.string,text);XCTAssertEqual(r.client.markCalls,marks);XCTAssertEqual(r.driver.coordinator.snapshot?.inputGeneration,generation)
        try key(r,"",53);try arm(r);try type("nihaoshijieni",r)
        let partial=r.client.view.string;try key(r,"",123,[.option]);XCTAssertNil(r.driver.repair);XCTAssertEqual(r.client.view.string,partial)
        try confirm(["你好","世界","你"],r);let before=r.client.view.string,held=r.driver.coordinator.snapshot?.inputGeneration
        for c in [",",".","!",":","A"]{try key(r,c);XCTAssertEqual(r.driver.coordinator.snapshot?.inputGeneration,held);XCTAssertEqual(r.client.view.string,before)}
        _ = try target(1,r);try replaceDraft("zz",r);r.driver.searchRepair(token:r.driver.repair!.token)
        XCTAssertTrue(r.driver.repair?.searched==true);XCTAssertTrue(r.driver.repair?.complete==true);XCTAssertTrue(r.driver.repair?.rows.isEmpty==true)
        try key(r,"",53);XCTAssertNil(r.driver.repair);XCTAssertEqual(r.client.view.string,before);XCTAssertEqual(r.client.insertCalls,0)
        XCTAssertTrue(r.driver.handle(try event("",code:53,repeatKey:true),client:r.client));XCTAssertEqual(r.client.view.string,before)
        try commit("你好世界你",r)
    }
    @MainActor func testStaleMenuRowsDraftAndReviewCannotApplyToNewerTarget()throws {
        _=NSApplication.shared;let r=try Rig();defer{r.close()}
        let armAction=try XCTUnwrap(r.driver.retainedMenuAction(arm:true));try type("n",r);r.driver.performRetainedMenuAction(armAction);XCTAssertFalse(r.driver.coordinator.session!.isRetainedComposition)
        try key(r,"",53);try arm(r);try type("nihaoshijieni",r);try confirm(["你好","世界","你"],r)
        let commitAction=try XCTUnwrap(r.driver.retainedMenuAction(arm:false));_ = try target(0,r);let oldList=try XCTUnwrap(r.driver.repair)
        r.driver.searchRepair(token:oldList.token);let list=try XCTUnwrap(r.driver.repair);try key(r,"x")
        r.driver.reviewRepair(row:0,token:list.token);XCTAssertNil(r.driver.repair?.proposal);r.driver.performRetainedMenuAction(commitAction);XCTAssertEqual(r.client.insertCalls,0)
        try replaceDraft("nihao",r);let review=try self.review("拟好",r),before=r.client.view.string,marks=r.client.markCalls
        r.driver.cancelRepair(token:review.token);r.driver.applyRepair(token:review.token);XCTAssertEqual(r.client.markCalls,marks);XCTAssertEqual(r.client.view.string,before)
        let b=PAIAIMKTestClient(text:"other");XCTAssertEqual(r.driver.activate(try XCTUnwrap(IMKTextInputBridge(b))),.ready)
        r.driver.performRetainedMenuAction(armAction);r.driver.performRetainedMenuAction(commitAction);r.driver.applyRepair(token:review.token)
        XCTAssertEqual(b.insertCalls,0);XCTAssertEqual(b.markCalls,0);XCTAssertEqual(r.client.view.string,before)
    }
    @MainActor func testFailedPresentationAndGeometryReentryNeverAuthorizeApply()throws {
        _=NSApplication.shared
        for variant in 0..<3 {
            weak var targetDriver:IMKControllerDriver?
            let r=try Rig(present:{state,_ in
                if state.proposal != nil {targetDriver?.applyRepair(token:state.token);return variant != 0};return true
            });targetDriver=r.driver;defer{r.close()};try arm(r);try type("nihaoshijieni",r);try confirm(["你好","世界","你"],r);_ = try target(0,r)
            if variant==1{r.client.onGeometry={r.driver.close()}}
            let before=r.client.view.string,marks=r.client.markCalls
            r.driver.searchRepair(token:r.driver.repair!.token)
            if let state=r.driver.repair,!state.rows.isEmpty{r.driver.reviewRepair(row:0,token:state.token)}
            XCTAssertEqual(r.client.markCalls,marks);XCTAssertEqual(r.client.insertCalls,0);XCTAssertEqual(r.client.view.string,before)
            if variant==0 || variant==1{XCTAssertNil(r.driver.repair)}
        }
    }
    @MainActor func testApplyAndCommitReentryOrUnknownReadbackNeverReplay()throws {
        _=NSApplication.shared
        for variant in 0..<4 {
            let r=try Rig();defer{r.close()};try arm(r);try type("nihaoshijieni",r);try confirm(["你好","世界","你"],r);_ = try target(0,r)
            let state=try review("拟好",r),b=PAIAIMKTestClient(text:"other")
            if variant==0{r.client.onMark={r.driver.applyRepair(token:state.token)}}
            if variant==1{r.client.onMark={_ = r.driver.activate(try! XCTUnwrap(IMKTextInputBridge(b)))}}
            r.driver.applyRepair(token:state.token);XCTAssertEqual(r.client.insertCalls,0);XCTAssertEqual(b.insertCalls,0)
            if variant==1 {XCTAssertNil(r.driver.repair);continue}
            let action=try XCTUnwrap(r.driver.retainedMenuAction(arm:false))
            if variant==2{r.client.onInsert={r.driver.performRetainedMenuAction(action)}}
            if variant==3{r.client.onInsert={r.client.truncateReads=true}}
            r.driver.performRetainedMenuAction(action);let marks=r.client.markCalls
            r.driver.performRetainedMenuAction(action);r.driver.applyRepair(token:state.token)
            XCTAssertEqual(r.client.insertCalls,1);XCTAssertEqual(r.client.markCalls,marks)
            if variant==3{XCTAssertEqual(r.driver.coordinator.outcome,.outcomeUnknown);XCTAssertNotNil(r.driver.recovery?.issuedText)}
        }
    }
    @MainActor func testRealNonKeyPanelFullReviewTailAndCancellation()throws {
        let app=NSApplication.shared;_ = app.setActivationPolicy(.accessory);let panel=SegmentRepairPanel(),screen=try XCTUnwrap(NSScreen.main).visibleFrame
        let r=try Rig(hide:{panel.orderOut(nil)},present:{state,rect in panel.show(state,below:rect,screen:screen)});defer{r.close();panel.orderOut(nil)}
        let window=NSWindow(contentRect:NSRect(x:40,y:60,width:640,height:240),styleMask:[.titled],backing:.buffered,defer:false);window.isReleasedWhenClosed=false;window.contentView=r.client.view;window.makeKeyAndOrderFront(nil);window.makeFirstResponder(r.client.view);defer{window.close()}
        try arm(r);let tail=String(repeating:"世界",count:200)+"你"
        try type("nihao"+String(repeating:"shijie",count:200)+"ni",r);try confirm(["你好"]+Array(repeating:"世界",count:200)+["你"],r);_ = try target(0,r)
        let state=try review("拟好",r);panel.displayIfNeeded()
        XCTAssertTrue(panel.isVisible);XCTAssertFalse(panel.canBecomeKey);XCTAssertFalse(panel.isKeyWindow);XCTAssertTrue(window.firstResponder===r.client.view)
        XCTAssertEqual(panel.displayedOriginal,"你好"+tail);XCTAssertEqual(panel.displayedPreview,"拟好"+tail);XCTAssertTrue(panel.textView.string.hasSuffix("拟好"+tail))
        let view=try XCTUnwrap(panel.contentView)
        func capture(_ key:String)throws {let bitmap=try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in:view.bounds));view.cacheDisplay(in:view.bounds,to:bitmap);if let path=ProcessInfo.processInfo.environment[key]{try XCTUnwrap(bitmap.representation(using:.png,properties:[:])).write(to:URL(fileURLWithPath:path),options:.atomic)}}
        try capture("PAIA_REPAIR_CAPTURE")
        XCTAssertGreaterThan(panel.textView.bounds.height,panel.scroll.contentSize.height)
        for _ in 0..<30{panel.scrollReview(1,token:state.token)}
        XCTAssertGreaterThan(panel.scroll.contentView.bounds.minY,0)
        let manager=try XCTUnwrap(panel.textView.layoutManager),container=try XCTUnwrap(panel.textView.textContainer)
        XCTAssertEqual(NSMaxRange(manager.glyphRange(forBoundingRect:panel.textView.visibleRect,in:container)),manager.numberOfGlyphs)
        try capture("PAIA_REPAIR_CAPTURE_TAIL")
        let before=r.client.view.string;r.driver.cancelRepair(token:state.token);XCTAssertFalse(panel.isVisible);XCTAssertEqual(r.client.view.string,before);XCTAssertEqual(r.client.insertCalls,0)
        _ = try target(0,r);let applied=try review("拟好",r);r.driver.applyRepair(token:applied.token)
        XCTAssertFalse(panel.isVisible);XCTAssertNil(r.driver.repair);XCTAssertEqual(r.client.insertCalls,0)
        // Ownership loss while editing must also retire the old panel/proposal.
        _ = try target(0,r);XCTAssertTrue(panel.isVisible)
        r.client.view.setSelectedRange(NSRange(location:0,length:0));let foreign=r.client.view.string
        try key(r,"x");XCTAssertNil(r.driver.repair);XCTAssertFalse(panel.isVisible);XCTAssertEqual(r.client.view.string,foreign)
        print("IMK_REPAIR_NATIVE ENGINE_NATIVE + APPKIT_HOST; actual non-key review and complete tail; authored protocol clients only")
    }
}
#endif
