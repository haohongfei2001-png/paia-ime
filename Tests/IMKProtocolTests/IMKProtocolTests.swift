#if os(macOS)
import XCTest
import AppKit
import InputMethodKit
import EngineBridge
import SessionCore
import IMKHost
import IMKTestClient

final class IMKProtocolTests:XCTestCase {
    static var lab:LabEnvironment!
    override class func setUp(){super.setUp();do{lab=try LabEnvironment()}catch{XCTFail("ENGINE_NATIVE verified fixture startup failed")}}
    @MainActor func activate(_ client:PAIAIMKTestClient,_ owner:IMKSessionCoordinator)throws {
        XCTAssertTrue(owner.activate(try XCTUnwrap(IMKTextInputBridge(client)),makeSession:{try? Self.lab.runtime.makeSession()}))
    }
    @MainActor func type(_ raw:String,_ client:PAIAIMKTestClient,_ owner:IMKSessionCoordinator){
        for c in raw {XCTAssertTrue(owner.process(.text(String(c)),client:client))}
    }
    @MainActor func event(_ text:String,code:UInt16=0,modifiers:NSEvent.ModifierFlags=[] )throws->NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:modifiers,timestamp:0,windowNumber:0,context:nil,characters:text,charactersIgnoringModifiers:text,isARepeat:false,keyCode:code))
    }
    @MainActor func testRealProtocolMarkedCandidateCommitOnceAndBoundedReads()throws {
        _=NSApplication.shared
        let client=PAIAIMKTestClient(text:"prefix👩🏽‍💻"),owner=IMKSessionCoordinator();defer{owner.retire()}
        let start=client.view.string.utf16.count;try activate(client,owner);type("nihao",client,owner)
        let snapshot=try XCTUnwrap(owner.snapshot),candidate=try XCTUnwrap(snapshot.rows.first)
        XCTAssertEqual(candidate.text,"你好");XCTAssertTrue(client.view.hasMarkedText())
        XCTAssertTrue(owner.choose(candidate.ref,client:client));XCTAssertEqual(client.view.string,"prefix👩🏽‍💻你好")
        XCTAssertEqual(owner.insertCount,1);XCTAssertEqual(client.insertCalls,1);XCTAssertFalse(client.view.hasMarkedText())
        XCTAssertFalse(owner.choose(candidate.ref,client:client));XCTAssertEqual(client.insertCalls,1)
        XCTAssertEqual(client.documentLengthCalls,0)
        for range in client.reads.compactMap({($0 as? NSValue)?.rangeValue}) {XCTAssertEqual(range.location,start);XCTAssertLessThanOrEqual(range.length,16384)}
        for range in client.writes.compactMap({($0 as? NSValue)?.rangeValue}) {XCTAssertEqual(range.location,start);XCTAssertNotEqual(range.location,NSNotFound)}
        print("IMK_PROTOCOL real librime + actual NSTextView-backed IMKTextInput bridge; no IMKServer or installed input source")
    }
    @MainActor func testRawLifecycleFlushIsOnceAndDoesNotTargetAnotherClient()throws {
        _=NSApplication.shared
        let a=PAIAIMKTestClient(text:"A"),b=PAIAIMKTestClient(text:"B"),owner=IMKSessionCoordinator();defer{owner.retire()}
        try activate(a,owner);type("nihao",a,owner)
        XCTAssertFalse(owner.finish(client:b));XCTAssertEqual(b.view.string,"B");XCTAssertEqual(a.insertCalls,0)
        XCTAssertTrue(owner.finish(client:a));XCTAssertEqual(a.view.string,"Anihao");XCTAssertEqual(a.insertCalls,1)
        XCTAssertFalse(owner.finish(client:a));owner.deactivate(client:a);XCTAssertEqual(a.insertCalls,1)
        try activate(b,owner);type("shi",b,owner);let before=b.view.string
        owner.deactivate(client:a);XCTAssertEqual(b.view.string,before);XCTAssertNotNil(owner.session)
        owner.deactivate(client:b);XCTAssertEqual(b.view.string,"Bshi");XCTAssertEqual(b.insertCalls,1)
    }
    @MainActor func testForeignMarkAndInitialSelectionAreNeverAdopted()throws {
        _=NSApplication.shared
        for foreignMark in [false,true] {
            let client=PAIAIMKTestClient(text:"existing"),owner=IMKSessionCoordinator();defer{owner.retire()}
            if foreignMark{client.view.setMarkedText("foreign",selectedRange:NSRange(location:7,length:0),replacementRange:NSRange(location:NSNotFound,length:0))}
            else{client.view.setSelectedRange(NSRange(location:1,length:3))}
            let before=client.view.string;var factories=0
            XCTAssertFalse(owner.activate(try XCTUnwrap(IMKTextInputBridge(client)),makeSession:{factories+=1;return try? Self.lab.runtime.makeSession()}))
            XCTAssertEqual(factories,0);XCTAssertEqual(client.view.string,before);XCTAssertEqual(client.markCalls,0);XCTAssertEqual(client.insertCalls,0)
        }
    }
    @MainActor func testUnicodeCommitsAndUnsupportedTextKeepExactComposition()throws {
        _=NSApplication.shared
        for (raw,expected) in [("kuo","𠀀"),("emoji","👩🏽‍💻"),("accent","e\u{301}")] {
            let client=PAIAIMKTestClient(text:""),owner=IMKSessionCoordinator();defer{owner.retire()};try activate(client,owner);type(raw,client,owner)
            XCTAssertTrue(owner.process(.space,client:client));XCTAssertEqual(client.view.string.utf8.map{$0},expected.utf8.map{$0});XCTAssertEqual(client.insertCalls,1)
        }
        let client=PAIAIMKTestClient(text:""),owner=IMKSessionCoordinator();defer{owner.retire()};try activate(client,owner);type("nihao",client,owner)
        XCTAssertTrue(owner.process(.code(0xff51),client:client));let before=try XCTUnwrap(owner.snapshot),text=client.view.string,mark=client.view.markedRange(),selection=client.view.selectedRange(),calls=client.markCalls
        for unsupported in [",","。","👩🏽‍💻","ｑ"] {
            XCTAssertTrue(owner.process(.text(unsupported),client:client));XCTAssertEqual(owner.snapshot?.inputGeneration,before.inputGeneration)
            XCTAssertEqual(owner.snapshot?.rows.map{$0.ref},before.rows.map{$0.ref});XCTAssertEqual(client.view.string,text);XCTAssertEqual(client.view.markedRange(),mark);XCTAssertEqual(client.view.selectedRange(),selection)
            XCTAssertEqual(client.markCalls,calls);XCTAssertEqual(client.insertCalls,0);XCTAssertNotNil(owner.notice)
        }
    }
    @MainActor func testUnknownInsertOutcomeNeverReplaysOrClearsForeignMark()throws {
        _=NSApplication.shared
        let client=PAIAIMKTestClient(text:""),owner=IMKSessionCoordinator();try activate(client,owner);type("nihao",client,owner)
        client.onInsert={client.view.setMarkedText("foreign",selectedRange:NSRange(location:7,length:0),replacementRange:NSRange(location:NSNotFound,length:0))}
        let writes=client.markCalls
        XCTAssertTrue(owner.process(.returnKey,client:client));XCTAssertEqual(client.insertCalls,1);XCTAssertEqual(client.markCalls,writes)
        XCTAssertEqual(client.view.string,"nihaoforeign");XCTAssertTrue(client.view.hasMarkedText());XCTAssertNil(owner.session)
        XCTAssertEqual(owner.outcome,.outcomeUnknown);XCTAssertEqual(owner.recovery?.raw,"nihao");XCTAssertEqual(owner.recovery?.issuedText,"nihao")
        XCTAssertFalse(owner.finish(client:client));owner.deactivate(client:client);XCTAssertEqual(client.insertCalls,1);XCTAssertTrue(client.view.hasMarkedText())
    }
    @MainActor func testEveryClientReadAndWriteCallbackCanRetireWithoutFurtherMutation()throws {
        _=NSApplication.shared
        for phase in 0..<5 {
            let client=PAIAIMKTestClient(text:""),owner=IMKSessionCoordinator();try activate(client,owner);type("ni",client,owner)
            let original=client.view.string,markCalls=client.markCalls
            let callback={_ = owner.process(.text("x"),client:client)}
            switch phase {case 0:client.onSelectedRange=callback;case 1:client.onMarkedRange=callback;case 2:client.onRead=callback;case 3:client.onMark=callback;default:client.onInsert=callback}
            XCTAssertTrue(owner.process(phase==4 ? .returnKey:.text("h"),client:client));XCTAssertNil(owner.session)
            XCTAssertLessThanOrEqual(client.insertCalls,1);XCTAssertLessThanOrEqual(client.markCalls,markCalls+(phase==3 ? 1:0))
            if phase<3{XCTAssertEqual(client.view.string,original)}
            XCTAssertNotNil(owner.recovery);XCTAssertFalse(owner.finish(client:client))
        }
    }
    @MainActor func testTruncatedReadAndSelectionChangeStopWithoutCleanup()throws {
        _=NSApplication.shared
        for truncate in [false,true] {
            let client=PAIAIMKTestClient(text:"prefix"),owner=IMKSessionCoordinator();try activate(client,owner);type("nihao",client,owner)
            if truncate{client.truncateReads=true}else{client.view.setSelectedRange(NSRange(location:0,length:0))}
            let before=client.view.string,marks=client.markCalls
            XCTAssertTrue(owner.process(.space,client:client));XCTAssertEqual(client.view.string,before);XCTAssertEqual(client.markCalls,marks);XCTAssertEqual(client.insertCalls,0)
            XCTAssertEqual(owner.outcome,.ownershipLost);XCTAssertEqual(owner.recovery?.raw,"nihao")
        }
    }
    @MainActor func testIdlePassThroughAndActivationIsolation()throws {
        _=NSApplication.shared
        let a=PAIAIMKTestClient(text:""),b=PAIAIMKTestClient(text:""),owner=IMKSessionCoordinator();defer{owner.retire()};try activate(a,owner)
        for key:InputKey in [.returnKey,.space,.escape,.code(0xff51),.text("👩🏽‍💻")] {
            XCTAssertFalse(owner.process(key,client:a));XCTAssertNil(owner.session)
            a.view.insertText("X",replacementRange:NSRange(location:NSNotFound,length:0));try activate(a,owner)
        }
        type("nihao",a,owner);let old=try XCTUnwrap(owner.snapshot).rows[0].ref,oldText=a.view.string
        try activate(b,owner);type("shi",b,owner)
        XCTAssertFalse(owner.choose(old,client:b));XCTAssertFalse(owner.process(.returnKey,client:a));XCTAssertEqual(a.view.string,oldText);XCTAssertEqual(a.insertCalls,0)
        XCTAssertTrue(owner.process(.space,client:b));XCTAssertEqual(b.insertCalls,1)
    }
    @MainActor func testFirstAndAppendedMarkedWriteUnknownRetainsAcceptedRaw()throws {
        _=NSApplication.shared
        for before in ["","ni"] {
            let client=PAIAIMKTestClient(text:""),owner=IMKSessionCoordinator();try activate(client,owner);type(before,client,owner)
            client.onMark={client.truncateReads=true}
            XCTAssertTrue(owner.process(.text("h"),client:client));XCTAssertEqual(owner.outcome,.outcomeUnknown)
            XCTAssertEqual(owner.recovery?.raw,before+"h");XCTAssertEqual(client.insertCalls,0);XCTAssertNil(owner.session)
        }
    }
    @MainActor func testIdleModifierReleaseAllowsNextEventAtChangedCaret()throws {
        _=NSApplication.shared
        let client=PAIAIMKTestClient(text:"prefix"),owner=IMKSessionCoordinator();defer{owner.retire()};try activate(client,owner)
        XCTAssertTrue(owner.releaseIdle(client:client));XCTAssertNil(owner.session)
        client.view.setSelectedRange(NSRange(location:0,length:0));try activate(client,owner);type("nihao",client,owner)
        XCTAssertTrue(owner.process(.space,client:client));XCTAssertEqual(client.view.string,"你好prefix")
    }
    @MainActor func testSharedControllerDriverRebindsAfterActualIdleHostEdit()throws {
        _=NSApplication.shared
        let client=PAIAIMKTestClient(text:""),driver=IMKControllerDriver(makeSession:{try? Self.lab.runtime.makeSession()},hide:{},present:{_,_,_ in})
        defer{driver.close()};driver.activate(try XCTUnwrap(IMKTextInputBridge(client)))
        XCTAssertFalse(driver.handle(try event("👩🏽‍💻"),client:client))
        client.view.insertText("👩🏽‍💻",replacementRange:NSRange(location:NSNotFound,length:0))
        for c in "nihao"{XCTAssertTrue(driver.handle(try event(String(c)),client:client))}
        XCTAssertTrue(driver.handle(try event(" ",code:49),client:client));XCTAssertEqual(client.view.string,"👩🏽‍💻你好")
        XCTAssertFalse(driver.handle(try event("x",modifiers:[.command]),client:client))
        client.view.setSelectedRange(NSRange(location:0,length:0))
        XCTAssertTrue(driver.handle(try event("n"),client:client));XCTAssertEqual(driver.coordinator.snapshot?.rawASCII,"n")
    }
    @MainActor func testControllerNestedModifierNeverEscapesDuringInsert()throws {
        _=NSApplication.shared
        let client=PAIAIMKTestClient(text:""),driver=IMKControllerDriver(makeSession:{try? Self.lab.runtime.makeSession()},hide:{},present:{_,_,_ in})
        defer{driver.close()};driver.activate(try XCTUnwrap(IMKTextInputBridge(client)))
        for c in "nihao"{XCTAssertTrue(driver.handle(try event(String(c)),client:client))}
        let nested=try event("\u{7f}",code:51,modifiers:[.command]);var nestedConsumed=false
        client.onInsert={nestedConsumed=driver.handle(nested,client:client)}
        XCTAssertTrue(driver.handle(try event("\r",code:36),client:client));XCTAssertTrue(nestedConsumed)
        XCTAssertEqual(client.view.string,"nihao");XCTAssertEqual(client.insertCalls,1)
    }
    @MainActor func testPresentationTakeoverCannotOverwriteNewActivation()throws {
        _=NSApplication.shared
        let a=PAIAIMKTestClient(text:"A"),b=PAIAIMKTestClient(text:"B")
        weak var target:IMKControllerDriver?;var takeover=false
        let bridge=try XCTUnwrap(IMKTextInputBridge(b))
        let driver=IMKControllerDriver(makeSession:{try? Self.lab.runtime.makeSession()},hide:{if takeover{takeover=false;target?.activate(bridge)}},present:{_,_,_ in});target=driver
        defer{driver.close()}
        takeover=true;driver.activate(try XCTUnwrap(IMKTextInputBridge(a)))
        XCTAssertFalse(driver.handle(try event("n"),client:a));XCTAssertTrue(driver.handle(try event("n"),client:b))
        XCTAssertEqual(a.view.string,"A");XCTAssertEqual(driver.coordinator.snapshot?.rawASCII,"n")
        driver.finish(client:b);driver.activate(try XCTUnwrap(IMKTextInputBridge(a)))
        takeover=true;driver.deactivate(client:a)
        XCTAssertTrue(driver.handle(try event("h"),client:b));XCTAssertEqual(driver.coordinator.snapshot?.rawASCII,"h")
    }
    @MainActor func testGeometryFailureDoesNotReuseCacheAfterOwnershipLoss()throws {
        _=NSApplication.shared
        let client=PAIAIMKTestClient(text:""),bridge=try XCTUnwrap(IMKTextInputBridge(client));var shows=0,hides=0
        let driver=IMKControllerDriver(makeSession:{try? Self.lab.runtime.makeSession()},hide:{hides+=1},present:{_,_,_ in shows+=1})
        defer{driver.close()};driver.activate(bridge)
        XCTAssertTrue(driver.handle(try event("n"),client:client));XCTAssertGreaterThan(shows,0)
        client.invalidGeometry=true;let before=shows
        XCTAssertTrue(driver.handle(try event("i"),client:client));XCTAssertGreaterThan(shows,before,"Verified target may retain its recent rectangle")
        client.onGeometry={client.view.setSelectedRange(NSRange(location:0,length:0))};let validShows=shows,priorHides=hides
        XCTAssertTrue(driver.handle(try event("h"),client:client));XCTAssertEqual(shows,validShows);XCTAssertGreaterThan(hides,priorHides)
        XCTAssertNil(driver.coordinator.session);XCTAssertEqual(driver.coordinator.outcome,.ownershipLost)
    }
}
#endif
