#if os(macOS)
import XCTest
import AppKit
import IMKHost
import IMKTestClient
import EngineBridge
import SessionCore

final class QualificationHostTests:XCTestCase {
    @MainActor func event(_ text:String,code:UInt16=0)throws->NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[],timestamp:0,windowNumber:0,context:nil,characters:text,charactersIgnoringModifiers:text,isARepeat:false,keyCode:code))
    }
    @MainActor func type(_ raw:String,_ driver:IMKControllerDriver,_ client:PAIAIMKTestClient)throws {
        for character in raw {XCTAssertTrue(driver.handle(try event(String(character)),client:client))}
    }
    @MainActor func testBoundedStrongCorpusControllerReplay()throws {
        let e=ProcessInfo.processInfo.environment
        guard e["PAIA_B1_RESEARCH"]=="1",let shared=e["PAIA_QUALIFICATION_SHARED"],let user=e["PAIA_QUALIFICATION_HOST_USER"] else{throw XCTSkip("Explicit native qualification host lane not selected")}
        _=NSApplication.shared
        let runtime=try RimeRuntime(library:XCTUnwrap(e["PAIA_RIME_LIBRARY"]),shared:shared,isolatedUser:user,dictionaryRevision:XCTUnwrap(e["PAIA_B1_REVISION"]),precompiled:true)
        defer{runtime.close()}
        var episodes=0,inserts=0
        for schema in LabConfiguration.researchSchemas {
            try autoreleasepool {
                let driver=IMKControllerDriver(makeSession:{try? runtime.makeSession(schema:schema,chinesePunctuation:schema.contains("_punct"))},hide:{},present:{_,_,_ in})
                defer{driver.close()}
                let a=PAIAIMKTestClient(text:"prefix𠀀e\u{301}👩🏽‍💻"),b=PAIAIMKTestClient(text:"other")
                let prefix=a.view.string,raw=schema.contains("_full_") ? "shurufa":"uurufa",expected=schema.contains("_traditional_") ? "輸入法":"输入法"
                XCTAssertEqual(driver.activate(try XCTUnwrap(IMKTextInputBridge(a))),.ready)
                XCTAssertTrue(try XCTUnwrap(driver.coordinator.session).learningDisabled)
                try type(raw,driver,a)
                let ref=try XCTUnwrap(driver.coordinator.snapshot?.rows.first?.ref)
                XCTAssertEqual(driver.coordinator.snapshot?.rows.first?.text,expected)
                XCTAssertTrue(a.view.hasMarkedText());driver.choose(ref)
                XCTAssertEqual(a.view.string,prefix+expected);XCTAssertEqual(a.insertCalls,1)
                driver.choose(ref);XCTAssertEqual(a.insertCalls,1)
                XCTAssertFalse(driver.handle(try event("\r",code:36),client:a))
                try type(raw,driver,a)
                let composition=a.view.string
                driver.finish(client:b);driver.deactivate(client:b)
                XCTAssertEqual(a.view.string,composition);XCTAssertEqual(b.view.string,"other");XCTAssertEqual(a.insertCalls,1)
                XCTAssertTrue(driver.handle(try event("\r",code:36),client:a))
                XCTAssertEqual(a.view.string,prefix+expected+raw);XCTAssertEqual(a.insertCalls,2)
                driver.finish(client:a);XCTAssertEqual(a.insertCalls,2)
                XCTAssertEqual(driver.activate(try XCTUnwrap(IMKTextInputBridge(b))),.ready)
                driver.choose(ref);XCTAssertEqual(b.view.string,"other");XCTAssertEqual(b.insertCalls,0)
                try type(schema.contains("_full_") ? "shi":"ui",driver,b)
                let page=try XCTUnwrap(driver.coordinator.snapshot),old=try XCTUnwrap(page.rows.first?.ref)
                XCTAssertTrue(page.hasMore);XCTAssertTrue(driver.handle(try event("",code:121),client:b))
                XCTAssertEqual(driver.coordinator.snapshot?.pageIndex,page.pageIndex+1)
                let before=b.view.string;driver.choose(old);XCTAssertEqual(b.view.string,before);XCTAssertEqual(b.insertCalls,0)
                let current=try XCTUnwrap(driver.coordinator.snapshot?.rows.first)
                driver.choose(current.ref);XCTAssertEqual(b.view.string,"other"+current.text);XCTAssertEqual(b.insertCalls,1)
                driver.choose(current.ref);XCTAssertEqual(b.insertCalls,1)
                let c=PAIAIMKTestClient(text:"")
                XCTAssertEqual(driver.activate(try XCTUnwrap(IMKTextInputBridge(c))),.ready)
                try type(raw,driver,c)
                c.onInsert={c.view.setMarkedText("foreign",selectedRange:NSRange(location:7,length:0),replacementRange:NSRange(location:NSNotFound,length:0))}
                XCTAssertTrue(driver.handle(try event("\r",code:36),client:c))
                XCTAssertEqual(driver.coordinator.outcome,.outcomeUnknown);XCTAssertEqual(c.view.string,raw+"foreign");XCTAssertEqual(c.insertCalls,1)
                driver.finish(client:c);driver.deactivate(client:c)
                XCTAssertEqual(c.insertCalls,1);XCTAssertTrue(c.view.hasMarkedText())
                c.onInsert=nil
                for client in [a,b,c] {
                    XCTAssertEqual(client.documentLengthCalls,0)
                    for range in client.reads.compactMap({($0 as? NSValue)?.rangeValue}){XCTAssertLessThanOrEqual(range.length,16384)}
                }
                inserts+=a.insertCalls+b.insertCalls+c.insertCalls;episodes+=1
            }
        }
        XCTAssertEqual(episodes,32);XCTAssertEqual(inserts,128);XCTAssertEqual(runtime.deploymentCalls,0)
        XCTAssertEqual(runtime.diagnostics.liveSessions,0)
        XCTAssertEqual(runtime.diagnostics.sessionsCreated,runtime.diagnostics.sessionsDestroyed)
        print("APPKIT_HOST qualification episodes=\(episodes) insertCalls=\(inserts); real production controller and NSTextView-backed authored IMK client; installed=false")
    }
}
#endif
