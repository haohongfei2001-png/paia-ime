#if os(macOS)
import XCTest
import AppKit
import EngineBridge
import IMKHost
import IMKTestClient
import SessionCore
import NativeHost

final class MixedIMKTests:XCTestCase {
    // A separate test filter/process owns this runtime; don't initialize two in one process.
    static var environment:ResearchLabEnvironment!
    override class func setUp(){super.setUp();do{environment=try ResearchLabEnvironment()}catch{XCTFail("Verified mixed host startup failed: \(error)")}}
    @MainActor final class Rig {
        let client=PAIAIMKTestClient(text:"prefix👩🏽‍💻"),driver:IMKControllerDriver
        init()throws {
            _=NSApplication.shared
            driver=IMKControllerDriver(makeSession:{try? MixedIMKTests.environment.runtime.makeSession(schema:"paia_b1_full_ascii")},hide:{},present:{_,_,_ in})
            XCTAssertEqual(driver.activate(try XCTUnwrap(IMKTextInputBridge(client))),.ready)
        }
    }
    @MainActor func event(_ text:String="",_ code:UInt16=0,_ modifiers:NSEvent.ModifierFlags=[])throws->NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:modifiers,timestamp:0,windowNumber:0,context:nil,characters:text,charactersIgnoringModifiers:text,isARepeat:false,keyCode:code))
    }
    @MainActor func key(_ r:Rig,_ text:String="",_ code:UInt16=0,_ modifiers:NSEvent.ModifierFlags=[])throws {XCTAssertTrue(r.driver.handle(try event(text,code,modifiers),client:r.client))}
    @MainActor func menu(_ r:Rig,_ kind:MixedActionKind)throws {r.driver.performMixedMenuAction(try XCTUnwrap(r.driver.mixedMenuAction(kind)))}
    @MainActor func choose(_ r:Rig,_ text:String)throws {
        for _ in 0..<13 {
            let snapshot=try XCTUnwrap(r.driver.coordinator.snapshot)
            if let row=snapshot.rows.first(where:{$0.text==text}){r.driver.choose(row.ref);return}
            if !snapshot.hasMore{break};try key(r,"",121)
        }
        XCTFail("Real host candidate unavailable: "+text);throw EngineError.closed
    }
    @MainActor func composed(_ r:Rig,_ literal:String="data 3.14")throws {
        // Begin with an ordinary live Pinyin composition, then explicitly adopt it.
        for c in "nihao"{try key(r,String(c))}
        try menu(r,.begin);try key(r,"",115);try key(r,"",124);try key(r,"",124)
        try key(r,"l",37,[.option]);XCTAssertTrue(r.driver.coordinator.session?.mixedLiteralIntent==true)
        for c in literal{try key(r,String(c),c==" " ? 49:0)}
        try key(r,"l",37,[.option]);try choose(r,"好");try key(r,"",48);try choose(r,"你")
        XCTAssertEqual(r.client.insertCalls,0);XCTAssertEqual(r.driver.coordinator.snapshot?.sourceText,"ni"+literal+"hao")
    }
    @MainActor func testActualMenusLiteralToggleCandidatesAndOneNativeHostEffect()throws {
        let r=try Rig();defer{r.driver.close()};try composed(r)
        XCTAssertEqual(r.client.view.string,"prefix👩🏽‍💻你data 3.14好")
        let action=try XCTUnwrap(r.driver.mixedMenuAction(.commit));r.driver.performMixedMenuAction(action);r.driver.performMixedMenuAction(action)
        XCTAssertEqual(r.client.insertCalls,1);XCTAssertEqual(r.client.view.string,"prefix👩🏽‍💻你data 3.14好");XCTAssertFalse(r.client.view.hasMarkedText())
        XCTAssertEqual(r.client.documentLengthCalls,0)
        print("MIXED_IMK_NATIVE ENGINE_NATIVE + APPKIT_HOST; adopted ordinary source, production menu-action dispatch and Option-L, real selection and one insert")
    }
    @MainActor func testReturnAndLifecycleKeepEntireMixedSourceAtFrontAndMiddle()throws {
        for middle in [false,true] {
            let r=try Rig();defer{r.driver.close()};try composed(r,"RAG")
            try key(r,"",115);if middle{try key(r,"",124)}
            try key(r,"\r",36);r.driver.finish(client:r.client)
            XCTAssertEqual(r.client.insertCalls,1);XCTAssertEqual(r.client.view.string,"prefix👩🏽‍💻niRAGhao")
        }
    }
    @MainActor func testChangedTargetPreservesWholeSourceAndStalesCommitMenu()throws {
        let r=try Rig();defer{r.driver.close()};try composed(r,"RAG")
        let action=try XCTUnwrap(r.driver.mixedMenuAction(.commit))
        r.client.view.setSelectedRange(NSRange(location:0,length:0));let before=r.client.view.string
        r.driver.performMixedMenuAction(action)
        XCTAssertEqual(r.client.insertCalls,0);XCTAssertEqual(r.client.view.string,before)
        XCTAssertNil(r.driver.coordinator.session);XCTAssertEqual(r.driver.recovery?.raw,"niRAGhao")
    }
    @MainActor func testReentrantCommitCannotCreateSecondEffect()throws {
        let r=try Rig();defer{r.driver.close()};try composed(r,"RAG")
        let action=try XCTUnwrap(r.driver.mixedMenuAction(.commit));r.client.onInsert={r.driver.performMixedMenuAction(action)}
        r.driver.performMixedMenuAction(action);r.driver.performMixedMenuAction(action)
        XCTAssertEqual(r.client.insertCalls,1);XCTAssertEqual(r.client.view.string,"prefix👩🏽‍💻你RAG好")
    }
    @MainActor func testUnknownInsertOutcomeKeepsFullMixedRecoveryWithoutRetry()throws {
        let r=try Rig();defer{r.driver.close()};try composed(r,"RAG")
        let action=try XCTUnwrap(r.driver.mixedMenuAction(.commit))
        r.client.onInsert={r.client.truncateReads=true}
        r.driver.performMixedMenuAction(action);r.driver.performMixedMenuAction(action);r.driver.finish(client:r.client)
        XCTAssertEqual(r.client.insertCalls,1);XCTAssertEqual(r.client.view.string,"prefix👩🏽‍💻你RAG好")
        XCTAssertNil(r.driver.coordinator.session);XCTAssertEqual(r.driver.recovery?.raw,"niRAGhao")
        XCTAssertEqual(r.driver.recovery?.issuedText,"你RAG好")
    }
    @MainActor func test128WordSuffixThroughSameMarkedHostAndFullSourceReturn()throws {
        let r=try Rig();defer{r.driver.close()};try composed(r,"RAG");try key(r,"",119)
        try key(r,String(repeating:"shijie",count:128))
        for _ in 0..<128{try choose(r,"世界")}
        let source="niRAGhao"+String(repeating:"shijie",count:128)
        XCTAssertEqual(r.driver.coordinator.snapshot?.sourceText,source)
        XCTAssertEqual(r.client.view.string,"prefix👩🏽‍💻你RAG好"+String(repeating:"世界",count:128));XCTAssertEqual(r.client.insertCalls,0)
        try key(r,"",115);try key(r,"\r",36)
        XCTAssertEqual(r.client.insertCalls,1);XCTAssertEqual(r.client.view.string,"prefix👩🏽‍💻"+source)
        XCTAssertEqual(r.client.documentLengthCalls,0)
        print("MIXED_IMK_LONG 128 genuine suffix selections; full marked source preserved; one Return effect; no visible-latency claim")
    }
    @MainActor func testBoundedCandidatePresentationDoesNotClaimCompleteExhaustion()throws {
        // SIMULATED rows for presentation semantics only, not native decoding.
        _=NSApplication.shared;var core=SessionCore(dictionaryRevision:"synthetic-display-check")
        let span=MixedSpan(source:"ni",origin:.spelling),draft=try MixedDraft(spans:[span],caretUTF8:2)
        let row=MixedCandidateValue(text:"simulated row",coverage:0..<2),panel=CandidatePanel();defer{panel.orderOut(nil)}
        for complete in [false,true] {
            let snapshot=try XCTUnwrap(core.receiveMixed(draft,owner:UUID(),span:span.id,projection:1,rows:[row],complete:complete).snapshot)
            panel.show(snapshot,below:NSRect(x:100,y:400,width:1,height:20),screen:NSRect(x:0,y:0,width:800,height:600))
            let label=try XCTUnwrap(panel.contentView?.subviews.compactMap{$0 as? NSTextField}.first)
            XCTAssertEqual(label.stringValue,complete ? "Page 1 · End of candidates":"Page 1 · Shown candidate limit reached; search incomplete")
        }
    }
}
#endif
