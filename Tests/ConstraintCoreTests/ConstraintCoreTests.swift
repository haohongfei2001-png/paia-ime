import XCTest
import ConstraintCore
import SessionCore
final class ConstraintCoreTests:XCTestCase {
    func testLeaseBindsRequestSessionGenerationDictionaryAndTarget() throws {
        var core=SessionCore(dictionaryRevision:"A")
        _ = try core.receive(EngineValue(raw:"ni",preedit:"你",caretUTF8:2))
        let lease=RepairLease(snapshot:core.snapshot!,revision:"A",request:3)
        XCTAssertTrue(lease.matches(core.snapshot,revision:"A",request:3))
        XCTAssertFalse(lease.matches(core.snapshot,revision:"B",request:3))
        XCTAssertFalse(lease.matches(core.snapshot,revision:"A",request:4))
        var other=SessionCore(dictionaryRevision:"A");_ = try other.receive(EngineValue(raw:"ni",preedit:"你",caretUTF8:2))
        XCTAssertFalse(lease.matches(other.snapshot,revision:"A",request:3))
        _ = try core.receive(EngineValue(raw:"ni",preedit:"你",caretUTF8:2))
        XCTAssertFalse(lease.matches(core.snapshot,revision:"A",request:3))
        core.invalidate();XCTAssertFalse(lease.matches(core.snapshot,revision:"A",request:3))
    }
    func testRawBytesNeverUseDisplayedGraphemeLength() throws {
        try RawAnchor(bytes:0..<5,text:"👩🏽‍💻",engineIndex:2).validate(in:"emoji")
        XCTAssertThrowsError(try RawAnchor(bytes:0..<6,text:"e\u{301}",engineIndex:0).validate(in:"emoji"))
        XCTAssertThrowsError(try RawAnchor(bytes:0..<1,text:"𠀀",engineIndex:0).validate(in:"𠀀"))
    }
}
