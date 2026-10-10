import XCTest
import Foundation
import ResourceCore

final class InputMethodLaunchTests:XCTestCase {
    func testOrdinaryAppKitArgumentsPreserveTheExistingServicePath()throws {
        for arguments in [[],["-NSDocumentRevisionsDebugMode","YES"],["-authored-launch-argument","value"]] {
            let parsed=try InputMethodLaunchArguments(arguments)
            XCTAssertFalse(parsed.preflight);XCTAssertNil(parsed.isolatedParent)
        }
    }
    func testOnlySupportedPreflightFormsAreAcceptedWithoutFilesystemWork()throws {
        let simple=try InputMethodLaunchArguments(["--preflight"])
        XCTAssertTrue(simple.preflight);XCTAssertNil(simple.isolatedParent)
        let path="/__paia_authored_absent_"+UUID().uuidString.lowercased()
        XCTAssertFalse(FileManager.default.fileExists(atPath:path))
        let isolated=try InputMethodLaunchArguments(["--preflight","--isolated-parent",path])
        XCTAssertTrue(isolated.preflight);XCTAssertEqual(isolated.isolatedParent?.path,path)
        XCTAssertFalse(FileManager.default.fileExists(atPath:path))
    }
    func testMalformedOwnedFlagsNeverBecomeOrdinaryServiceArguments()throws {
        for arguments in [["--isolated-parent"],["--isolated-parent","/authored"],["--preflight","--isolated-parent"],
                          ["--preflight","--isolated-parent",""],["--preflight","--isolated-parent","relative"],
                          ["--preflight","--isolated-parent","/bad\0path"],["--preflight","--preflight"],
                          ["--preflight","extra"],["other","--preflight"],["--preflight=1"],
                          ["--isolated-parent=/authored"],["--preflight-typo"],
                          ["--preflight","--isolated-parent","/authored","--isolated-parent","/other"]] {
            XCTAssertThrowsError(try InputMethodLaunchArguments(arguments))
        }
    }
}
