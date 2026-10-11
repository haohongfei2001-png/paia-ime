#if os(macOS)
import XCTest
import Foundation
import ResourceCore
import SettingsCore
import EngineBridge
@testable import IMKHost

// Explicit authored save using N+1 production stores. Real N consumption is
// tested afterward in a separate frozen original XCTest process and app entry.
final class ExplicitCompatibleSaveTests:XCTestCase {
    @MainActor func testAdvanceExistingSettingsRevisionWithoutChangingFormatContract()throws {
        let parent=try XCTUnwrap(ProcessInfo.processInfo.environment["PAIA_RELEASE_PARENT"])
        let lease=try ExistingProductLease(parent:URL(fileURLWithPath:parent));defer{lease.close()}
        let before=try lease.bytes(),old=try XCTUnwrap(lease.settings.snapshot())
        let next=try lease.settings.save(old.values,expectedRevision:old.revision)
        let after=try lease.bytes()
        XCTAssertEqual(next.revision,old.revision+1);XCTAssertEqual(next.values,old.values)
        XCTAssertNotEqual(after.settings,before.settings);XCTAssertEqual(after.personal,before.personal);XCTAssertEqual(after.expressions,before.expressions)
        XCTAssertEqual(RimeRuntime.startupAttempts,0)
        print("RELEASE_EXPLICIT_SAVE SIMULATED production_store revision=\(old.revision)->\(next.revision) main_attempts=0")
    }
}
#endif
