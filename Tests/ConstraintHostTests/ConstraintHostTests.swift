#if os(macOS)
import XCTest
import AppKit
import EngineBridge
import NativeHost
import ConstraintCore
final class ConstraintHostTests:XCTestCase {
    static var runtime:RimeRuntime!
    static var user:URL!
    override class func setUp() {
        super.setUp()
        do {
            let env=ProcessInfo.processInfo.environment
            user=FileManager.default.temporaryDirectory.appendingPathComponent("paia-a2-host-"+UUID().uuidString)
            try FileManager.default.createDirectory(at:user,withIntermediateDirectories:true)
            runtime=try RimeRuntime(library:env["PAIA_RIME_LIBRARY"]!,shared:env["PAIA_A2_SHARED"]!,isolatedUser:user.path,
                                   dictionaryRevision:env["PAIA_A2_REVISION"]!,g01Library:env["PAIA_G01_LIBRARY"]!)
        } catch {XCTFail("APPKIT_HOST A2 startup: \(error)")}
    }
    override class func tearDown(){runtime=nil;if let user=user {try? FileManager.default.removeItem(at:user)};super.tearDown()}
    @MainActor func testRepairUpdatesMarkedTextThenOneRealCommit() throws {
        _=NSApplication.shared
        let client=NSTextView();let prefix="A👩🏽‍💻𠀀e\u{301}"
        client.string=prefix;client.setSelectedRange(NSRange(location:prefix.utf16.count,length:0))
        let s=try Self.runtime.makeSession(deferredCommit:true),host=HostDispatcher(client:client,session:s);defer{host.invalidate()}
        for b in "nihaoshijieni".utf8 {XCTAssertTrue(host.apply(try s.process(.code(Int32(b)))))}
        for word in ["你好","世界","你"] {
            let choice=try XCTUnwrap(s.repairChoices(limit:128).rows.first(where:{$0.anchor.text==word}))
            XCTAssertTrue(host.apply(try s.selectForRepair(choice)))
        }
        XCTAssertTrue(client.hasMarkedText());XCTAssertEqual(host.insertCount,0)
        let p=try s.prepareRepair(target:try s.repairAnchors().targets[1],replacementRaw:"nihao",surface:"拟好")
        XCTAssertEqual(host.insertCount,0)
        let preview=try s.applyRepair(p);XCTAssertNil(preview.commit);XCTAssertTrue(host.apply(preview))
        XCTAssertEqual(client.markedRange().location,prefix.utf16.count);XCTAssertTrue(client.string.hasPrefix(prefix))
        let final=try s.commitEngineComposition();XCTAssertTrue(host.apply(final))
        XCTAssertEqual(client.string,prefix+"你好拟好你");XCTAssertEqual(host.insertCount,1)
        XCTAssertFalse(host.apply(final));XCTAssertFalse(client.hasMarkedText())
    }
    @MainActor func testDelayedRepairCannotWriteChangedTarget() throws {
        _=NSApplication.shared
        let client=NSTextView();client.string="existing";client.setSelectedRange(NSRange(location:8,length:0))
        let s=try Self.runtime.makeSession(deferredCommit:true),host=HostDispatcher(client:client,session:s)
        for b in "nihaoshijieni".utf8 {_=host.apply(try s.process(.code(Int32(b))))}
        for word in ["你好","世界","你"] {
            let c=try XCTUnwrap(s.repairChoices(limit:128).rows.first(where:{$0.anchor.text==word}));_=host.apply(try s.selectForRepair(c))
        }
        let proposal=try s.prepareRepair(target:try s.repairAnchors().targets[0],replacementRaw:"nihao",surface:"拟好")
        client.string="new target";let preview=try s.applyRepair(proposal)
        XCTAssertFalse(host.apply(preview));XCTAssertEqual(client.string,"new target");XCTAssertEqual(host.insertCount,0)
        XCTAssertThrowsError(try s.commitEngineComposition())
    }
}
#endif
