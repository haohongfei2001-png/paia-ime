#if os(macOS)
import XCTest
import Foundation
import EngineBridge
import ConstraintCore

// Separate filtered test process: closing the only runtime cannot invalidate
// unrelated tests. All words/resources are the explicit authored A2 fixture.
final class ConstraintCloseTests:XCTestCase {
    func testPendingExportedTrialClosesOnceAndFailedPrepareExportsNothing()throws {
        let env=ProcessInfo.processInfo.environment
        let user=FileManager.default.temporaryDirectory.appendingPathComponent("paia-g01-close-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:user,withIntermediateDirectories:false)
        defer{try? FileManager.default.removeItem(at:user)}
        let runtime=try RimeRuntime(library:XCTUnwrap(env["PAIA_RIME_LIBRARY"]),shared:XCTUnwrap(env["PAIA_A2_SHARED"]),isolatedUser:user.path,
            dictionaryRevision:XCTUnwrap(env["PAIA_A2_REVISION"]),g01Library:XCTUnwrap(env["PAIA_G01_LIBRARY"]))
        defer{runtime.close()}
        let session=try runtime.makeSession(deferredCommit:true)
        for byte in "nihaoshijie".utf8{XCTAssertNil(try session.process(.code(Int32(byte))).commit)}
        for text in ["你好","世界"] {
            let choice=try XCTUnwrap(session.repairChoices().rows.first{$0.anchor.text==text})
            XCTAssertNil(try session.selectForRepair(choice).commit)
        }
        let beforeFailure=runtime.diagnostics
        XCTAssertThrowsError(try session.prepareRepair(target:XCTUnwrap(session.repairAnchors().targets.first),replacementRaw:"nihao",surface:"不存在的自造候选")) {error in
            guard let failure=error as? ConstraintError,case .native(_,let examined)=failure else{XCTFail("Expected actual bounded native-search refusal");return}
            XCTAssertGreaterThan(examined,0)
        }
        XCTAssertEqual(runtime.diagnostics,beforeFailure)
        let proposal=try session.prepareRepair(target:XCTUnwrap(session.repairAnchors().targets.first),replacementRaw:"nihao",surface:"拟好")
        XCTAssertEqual(runtime.diagnostics.liveSessions,2);XCTAssertEqual(runtime.diagnostics.sessionsCreated,2)
        XCTAssertTrue(runtime.close())
        let closed=runtime.diagnostics
        XCTAssertEqual(closed.liveSessions,0);XCTAssertEqual(closed.sessionsCreated,2);XCTAssertEqual(closed.sessionsDestroyed,2)
        proposal.cancel();proposal.cancel();session.end();XCTAssertTrue(runtime.close())
        XCTAssertEqual(runtime.diagnostics,closed)
        XCTAssertThrowsError(try session.applyRepair(proposal))
        XCTAssertEqual(runtime.diagnostics,closed)
        print("ENGINE_NATIVE G01 pending-trial runtime close created=2 destroyed=2 failed_prepare_exports=0 late_cancel_noop=true")
    }
}
#endif
