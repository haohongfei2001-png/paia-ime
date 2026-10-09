import XCTest
import EngineBridge
import SessionCore
final class EngineTests:XCTestCase {
    static var lab:LabEnvironment!
    override class func setUp() {super.setUp();do {lab=try LabEnvironment()} catch {XCTFail("ENGINE_NATIVE startup failed: \(error)")}}
    func make() throws -> InputSession {guard let lab=Self.lab else {throw EngineError.closed};return try lab.runtime.makeSession()}
    func type(_ raw:String,_ session:InputSession) throws {
        for c in raw.utf8 {_=try session.process(.code(Int32(c)))}
    }
    func testRealRawMarkedCandidateEngineSelectionCommitOnce() throws {
        let s=try make();defer{s.end()}
        try type("nihao",s)
        let snapshot=try XCTUnwrap(s.snapshot)
        XCTAssertEqual(snapshot.rawASCII,"nihao");XCTAssertFalse(snapshot.preedit.isEmpty)
        XCTAssertEqual(snapshot.rows.first?.text,"你好")
        let update=try s.select(snapshot.rows[0].ref)
        XCTAssertEqual(update.commit?.text,"你好")
        XCTAssertTrue(s.reserve(try XCTUnwrap(update.commit)))
        XCTAssertFalse(s.reserve(try XCTUnwrap(update.commit)))
        XCTAssertNil(try s.refresh().commit)
        XCTAssertThrowsError(try s.select(snapshot.rows[0].ref))
    }
    func testDigitsUseShownSecondCandidateAndInvalidDigitsPreserve() throws {
        let s=try make();defer{s.end()};try type("nihao",s)
        let original=try XCTUnwrap(s.snapshot)
        XCTAssertTrue(try s.process(.number(9)).handled)
        XCTAssertEqual(s.snapshot?.inputGeneration,original.inputGeneration)
        let expected=original.rows[1].text
        let chosen=try s.process(.number(2))
        XCTAssertEqual(chosen.commit?.text,expected)
        XCTAssertTrue(s.reserve(try XCTUnwrap(chosen.commit)))
    }
    func testBackspaceCaretForwardDeleteAndLiteralReturn() throws {
        let s=try make();defer{s.end()};try type("nihao",s)
        _=try s.process(.code(0xff08));XCTAssertEqual(s.snapshot?.rawASCII,"niha")
        _=try s.process(.code(0xff51));XCTAssertEqual(s.snapshot?.caretUTF8,3)
        _=try s.process(.code(0xffff));XCTAssertEqual(s.snapshot?.rawASCII,"nih")
        let u=try s.process(.returnKey);XCTAssertTrue(u.handled);XCTAssertEqual(u.commit?.text,"nih")
        XCTAssertTrue(s.reserve(try XCTUnwrap(u.commit)))
        XCTAssertFalse(try s.process(.returnKey).handled)
    }
    func testEmptyShortcutsEscapeAndSessionLifetime() throws {
        let s=try make()
        for key:InputKey in [.returnKey,.space,.number(1),.escape,.command,.code(0xff09),.code(0xff51)] {XCTAssertFalse(try s.process(key).handled)}
        try type("nihao",s);let ref=s.snapshot!.rows[0].ref
        _=try s.process(.command);XCTAssertEqual(s.snapshot?.rows[0].ref,ref)
        _=try s.process(.escape);XCTAssertEqual(s.snapshot?.rawASCII,"");XCTAssertNil(try s.refresh().commit)
        s.end();s.end();XCTAssertThrowsError(try s.select(ref));XCTAssertThrowsError(try s.process(.code(97)))
    }
    func testPageSelectionUsesCurrentPageMapping() throws {
        let s=try make();defer{s.end()};try type("ni",s)
        let first=try XCTUnwrap(s.snapshot);XCTAssertTrue(first.hasMore)
        _=try s.process(.code(0xff56))
        let next=try XCTUnwrap(s.snapshot);XCTAssertGreaterThan(next.pageIndex,first.pageIndex)
        XCTAssertThrowsError(try s.select(first.rows[0].ref))
        let u=try s.process(.number(1));XCTAssertEqual(u.commit?.text,next.rows[0].text)
        XCTAssertTrue(s.reserve(try XCTUnwrap(u.commit)))
    }
    func testUnicodeCandidatesPassThroughRealEngine() throws {
        for (raw,expected) in [("kuo","𠀀"),("emoji","👩🏽‍💻"),("accent","e\u{301}")] {
            let s=try make();defer{s.end()};try type(raw,s)
            XCTAssertEqual(s.snapshot?.rows.first?.text,expected)
            let u=try s.process(.space);XCTAssertEqual(u.commit?.text,expected)
            XCTAssertTrue(s.reserve(try XCTUnwrap(u.commit)))
        }
    }
    func testUnhandledPunctuationStillDrainsEngineCommit() throws {
        let s=try make();defer{s.end()};try type("nihao",s)
        let u=try s.process(.code(44))
        XCTAssertFalse(u.handled)
        XCTAssertEqual(u.commit?.text,"你好")
        XCTAssertTrue(s.reserve(try XCTUnwrap(u.commit)))
        try type("nihao",s);XCTAssertEqual(s.snapshot?.rawASCII,"nihao")
    }
    func testPendingCommitRefusesKeyBeforeEngineMutation() throws {
        let s=try make();defer{s.end()};try type("nihao",s)
        let u=try s.process(.space)
        XCTAssertThrowsError(try s.process(.code(97)))
        XCTAssertTrue(s.reserve(try XCTUnwrap(u.commit)))
        XCTAssertEqual(try s.refresh().snapshot?.rawASCII,"")
    }
    func testConcurrentShortLivedSessionsRemainIsolated() throws {
        let runtime=Self.lab!.runtime,lock=NSLock()
        var errors:[String]=[]
        DispatchQueue.concurrentPerform(iterations:16) { _ in
            do {
                let s=try runtime.makeSession();defer{s.end()}
                for c in "nihao".utf8 {_=try s.process(.code(Int32(c)))}
                let u=try s.process(.space)
                guard let effect=u.commit,effect.text=="你好",s.reserve(effect) else {throw EngineError.closed}
                guard try s.refresh().commit==nil else {throw EngineError.closed}
            } catch {lock.lock();errors.append("isolated session failed");lock.unlock()}
        }
        XCTAssertEqual(errors,[])
    }
    func testIndependentSessionsAndNoUserDictionary() throws {
        let a=try make(),b=try make();defer{a.end();b.end()}
        try type("nihao",a);try type("shi",b)
        XCTAssertThrowsError(try b.select(a.snapshot!.rows[0].ref))
        XCTAssertEqual(a.snapshot?.rawASCII,"nihao");XCTAssertEqual(b.snapshot?.rawASCII,"shi")
        let contents=FileManager.default.enumerator(atPath:Self.lab.temporaryDirectory.path)?.allObjects as? [String] ?? []
        XCTAssertFalse(contents.contains(where:{$0.contains("userdb")}))
    }
}
