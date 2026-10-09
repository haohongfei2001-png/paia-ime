#if os(macOS)
import XCTest
import AppKit
import EngineBridge
import NativeHost
import SessionCore
// Run separately from EngineTests, because librime has one process-global lifecycle owner.
final class AppKitHostTests:XCTestCase {
    static var lab:LabEnvironment!
    override class func setUp() {super.setUp();do {lab=try LabEnvironment()} catch {XCTFail("APPKIT_HOST startup failed: \(error)")}}
    @MainActor func testNativeMarkedThenSingleCommitAcrossUnicodePrefixes() throws {
        _=NSApplication.shared
        for prefix in ["","中文","𠀀","e\u{301}","👩🏽‍💻","\r\n","A👨‍👩‍👧‍👦Z"] {
            let client=NSTextView(frame:NSRect(x:0,y:0,width:600,height:200))
            client.string=prefix;client.setSelectedRange(NSRange(location:prefix.utf16.count,length:0))
            let session=try Self.lab.runtime.makeSession(),host=HostDispatcher(client:client,session:session)
            defer{host.invalidate()}
            for c in "nihao".utf8 {XCTAssertTrue(host.apply(try session.process(.code(Int32(c)))))}
            XCTAssertTrue(client.hasMarkedText());XCTAssertEqual(client.markedRange().location,prefix.utf16.count)
            let u=try session.process(.space);XCTAssertTrue(host.apply(u))
            XCTAssertEqual(client.string,prefix+"你好");XCTAssertFalse(client.hasMarkedText())
            XCTAssertFalse(host.apply(u));XCTAssertEqual(host.insertCount,1)
        }
    }
    @MainActor func testCancelAndStaleTargetCannotWrite() throws {
        _=NSApplication.shared
        let client=NSTextView();client.string="existing👩🏽‍💻";client.setSelectedRange(NSRange(location:client.string.utf16.count,length:0))
        let session=try Self.lab.runtime.makeSession(),host=HostDispatcher(client:client,session:session)
        for c in "nihao".utf8 {_=host.apply(try session.process(.code(Int32(c))))}
        _=host.apply(try session.process(.escape));XCTAssertEqual(client.string,"existing👩🏽‍💻")
        for c in "nihao".utf8 {_=host.apply(try session.process(.code(Int32(c))))}
        let commit=try session.process(.space);host.invalidate()
        XCTAssertFalse(host.apply(commit));XCTAssertEqual(client.string,"existing👩🏽‍💻");XCTAssertEqual(host.insertCount,0)
    }
    @MainActor func testHostSelectionAndFocusChangesRejectEffects() throws {
        _=NSApplication.shared
        let window=NSWindow(contentRect:NSRect(x:0,y:0,width:500,height:200),styleMask:[.titled],backing:.buffered,defer:false)
        let client=NSTextView(frame:NSRect(x:0,y:0,width:200,height:100)),other=NSTextView(frame:NSRect(x:210,y:0,width:200,height:100))
        window.contentView?.addSubview(client);window.contentView?.addSubview(other);window.makeFirstResponder(client)
        let s=try Self.lab.runtime.makeSession(),host=HostDispatcher(client:client,session:s)
        for c in "nihao".utf8 {_=host.apply(try s.process(.code(Int32(c))))}
        let u=try s.process(.space);window.makeFirstResponder(other)
        XCTAssertFalse(host.apply(u));XCTAssertEqual(host.insertCount,0)
        let client2=NSTextView();let s2=try Self.lab.runtime.makeSession(),host2=HostDispatcher(client:client2,session:s2)
        for c in "nihao".utf8 {_=host2.apply(try s2.process(.code(Int32(c))))}
        let u2=try s2.process(.space);client2.string="externally changed"
        XCTAssertFalse(host2.apply(u2));XCTAssertEqual(client2.string,"externally changed")
    }
    @MainActor func testUnhandledEngineCommitAndPreeditCaret() throws {
        _=NSApplication.shared
        let client=NSTextView(),s=try Self.lab.runtime.makeSession()
        let host=HostDispatcher(client:client,session:s);defer{host.invalidate()}
        for c in "nihao".utf8 {_=host.apply(try s.process(.code(Int32(c))))}
        _=host.apply(try s.process(.code(0xff51)))
        XCTAssertEqual(client.selectedRange().location,client.markedRange().location+s.snapshot!.selectedRangeUTF16.location)
        _=host.apply(try s.process(.code(0xff57)))
        let u=try s.process(.code(44));XCTAssertTrue(host.apply(u));XCTAssertEqual(client.string,"你好")
        XCTAssertFalse(u.handled);XCTAssertEqual(host.insertCount,1)
    }
    @MainActor func testWindowResignKeyInvalidatesAndOldButtonKeepsItsSnapshot() throws {
        _=NSApplication.shared
        let window=NSWindow(contentRect:NSRect(x:0,y:0,width:500,height:200),styleMask:[.titled],backing:.buffered,defer:false)
        window.isReleasedWhenClosed=false
        let client=NSTextView(frame:NSRect(x:0,y:0,width:300,height:100));window.contentView?.addSubview(client)
        window.makeKey();window.makeFirstResponder(client)
        let s=try Self.lab.runtime.makeSession(),host=HostDispatcher(client:client,session:s)
        for c in "nihao".utf8 {_=host.apply(try s.process(.code(Int32(c))))}
        let panel=CandidatePanel();defer{panel.orderOut(nil);window.close()}
        let old=s.snapshot!,rect=NSRect(x:100,y:200,width:100,height:20),screen=NSRect(x:0,y:0,width:800,height:600)
        panel.show(old,below:rect,screen:screen)
        let stack=try XCTUnwrap(panel.contentView?.subviews.first as? NSStackView)
        let button=try XCTUnwrap(stack.arrangedSubviews.first as? NSButton)
        _=host.apply(try s.process(.code(0xff08)))
        panel.show(s.snapshot!,below:rect,screen:screen)
        var clicked:CandidateRef?
        panel.choose={clicked=$0};button.performClick(nil)
        XCTAssertEqual(clicked,old.rows[0].ref)
        XCTAssertThrowsError(try s.select(try XCTUnwrap(clicked)))
        window.resignKey();XCTAssertFalse(host.isCurrentTarget)
        XCTAssertThrowsError(try s.process(.code(97)))
    }
    @MainActor func testExistingHostMarkedTextIsNeverAdoptedOrCleared() throws {
        _=NSApplication.shared
        for attemptApply in [false,true] {
            let client=NSTextView();client.string="prefix👩🏽‍💻";client.setSelectedRange(NSRange(location:client.string.utf16.count,length:0))
            client.setMarkedText("外部e\u{301}",selectedRange:NSRange(location:2,length:0),replacementRange:NSRange(location:NSNotFound,length:0))
            let text=client.string,marked=client.markedRange(),selection=client.selectedRange()
            let session=try Self.lab.runtime.makeSession(),update=try session.refresh(),host=HostDispatcher(client:client,session:session)
            XCTAssertFalse(host.isCurrentTarget);XCTAssertThrowsError(try session.refresh())
            if attemptApply{XCTAssertFalse(host.apply(update))}
            host.invalidate()
            XCTAssertEqual(client.string,text);XCTAssertEqual(client.markedRange(),marked);XCTAssertEqual(client.selectedRange(),selection)
            XCTAssertTrue(client.hasMarkedText());XCTAssertEqual(host.insertCount,0)
        }
    }
    @MainActor func testRenewDoesNotInvokeFactoryForUnownedMark() throws {
        _=NSApplication.shared
        let client=LabTextView();var calls=0
        client.makeSession={calls+=1;return try? HostDispatcher(client:client,session:Self.lab.runtime.makeSession())}
        defer{client.makeSession=nil;client.dispatcher?.invalidate()}
        client.setMarkedText("外部👩🏽‍💻",selectedRange:NSRange(location:2,length:0),replacementRange:NSRange(location:NSNotFound,length:0))
        let text=client.string,marked=client.markedRange(),selection=client.selectedRange()
        client.renew();XCTAssertEqual(calls,0);XCTAssertNil(client.dispatcher)
        XCTAssertEqual(client.string,text);XCTAssertEqual(client.markedRange(),marked);XCTAssertEqual(client.selectedRange(),selection)
        client.unmarkText();client.renew();XCTAssertEqual(calls,1);XCTAssertTrue(client.dispatcher?.isCurrentTarget==true)
        client.dispatcher?.invalidate();XCTAssertEqual(client.string,text)
    }
    @MainActor func testReturnConsumesOnceAndReplacesSelectedGrapheme() throws {
        _=NSApplication.shared
        let client=NSTextView();client.string="A👩🏽‍💻B";client.setSelectedRange(NSRange(location:1,length:"👩🏽‍💻".utf16.count))
        let session=try Self.lab.runtime.makeSession(),host=HostDispatcher(client:client,session:session);defer{host.invalidate()}
        for c in "nihao".utf8 {_=host.apply(try session.process(.code(Int32(c))))}
        let u=try session.process(.returnKey);XCTAssertTrue(u.handled);XCTAssertTrue(host.apply(u))
        XCTAssertEqual(client.string,"AnihaoB");XCTAssertEqual(host.insertCount,1)
        XCTAssertFalse(try session.process(.returnKey).handled)
    }
}
#endif
