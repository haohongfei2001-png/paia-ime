import XCTest
@testable import SessionCore
import TextBoundary
final class SessionCoreTests:XCTestCase {
    func testUTF8UTF16AndGraphemeBoundaries() throws {
        for text in ["中文","𠀀","e\u{301}","👩🏽‍💻","\r\n","A👨‍👩‍👧‍👦Z"] {
            for index in Array(text.indices) + [text.endIndex] {
                let byte=text.utf8.distance(from:text.utf8.startIndex,to:index.samePosition(in:text.utf8)!)
                XCTAssertEqual(try TextBoundary.utf16Offset(in:text,utf8:byte),index.utf16Offset(in:text))
            }
            XCTAssertEqual(try TextBoundary.range(in:text,startUTF8:0,endUTF8:text.utf8.count),NSRange(location:0,length:text.utf16.count))
        }
        XCTAssertThrowsError(try TextBoundary.utf16Offset(in:"𠀀",utf8:1))
        XCTAssertThrowsError(try TextBoundary.utf16Offset(in:"e\u{301}",utf8:1))
        XCTAssertThrowsError(try TextBoundary.utf16Offset(in:"👩🏽‍💻",utf8:4))
        XCTAssertFalse(TextBoundary.validGraphemeRange(NSRange(location:1,length:1),in:"𠀀"))
        XCTAssertFalse(TextBoundary.validGraphemeRange(NSRange(location:0,length:1),in:"e\u{301}"))
        XCTAssertFalse(TextBoundary.validGraphemeRange(NSRange(location:Int.max,length:1),in:"x"))
    }
    func testCandidateGenerationAndTargetInvalidation() throws {
        var core=SessionCore(dictionaryRevision:"fixture-1")
        let v=EngineValue(raw:"ni",preedit:"ni",caretUTF8:2,candidates:["你"])
        let first=try core.receive(v).snapshot!.rows[0].ref
        try core.validate(first)
        _=try core.receive(v)
        XCTAssertThrowsError(try core.validate(first))
        let latest=core.snapshot!.rows[0].ref
        core.invalidate();XCTAssertThrowsError(try core.validate(latest))
    }
    func testSingleCommitReservationAndUnknownNoReplay() throws {
        var core=SessionCore(dictionaryRevision:"fixture-1")
        let effect=try core.receive(EngineValue(raw:"",preedit:"",caretUTF8:0,commit:"你好")).commit!
        XCTAssertThrowsError(try core.receive(EngineValue(raw:"a",preedit:"a",caretUTF8:1)))
        XCTAssertTrue(core.reserve(effect))
        XCTAssertFalse(core.reserve(effect))
        var other=SessionCore(dictionaryRevision:"fixture-1")
        XCTAssertFalse(other.reserve(effect))
        core.invalidate();XCTAssertFalse(core.reserve(effect))
    }
    func testRejectInvalidEngineBoundariesAndNoFabricatedSpan() throws {
        var core=SessionCore(dictionaryRevision:"fixture-1")
        XCTAssertThrowsError(try core.receive(EngineValue(raw:"x",preedit:"𠀀",caretUTF8:1,preeditCaretUTF8:1)))
        XCTAssertNil(try core.receive(EngineValue(raw:"x",preedit:"x",caretUTF8:1,candidates:["𠀀"])).snapshot!.rows[0].ref.rawSpanUTF8)
    }
}
