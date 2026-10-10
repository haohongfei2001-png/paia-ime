import XCTest
import EngineBridge
import SessionCore

// Real pinned engine, separate process from the native host class.
final class KeyboardBridgeTests:XCTestCase {
    static var environment:ResearchLabEnvironment!
    override class func setUp(){super.setUp();do{environment=try ResearchLabEnvironment()}catch{XCTFail("B8 bridge startup: \(error)")}}
    func testMiddlePunctuationDoesNotDiscardTheUncommittedRightSide()throws {
        for (spelling,raw) in [(LabSpelling.full,"nihao"),(.flypy,"nihc"),(.natural,"nihk")] {for traditional in [false,true] {for chinese in [false,true] {for code:Int32 in [44,46] {
            var config=LabConfiguration();config.spelling=spelling;config.traditional=traditional;config.chinesePunctuation=chinese
            let s=try Self.environment.runtime.makeSession(schema:config.schema,chinesePunctuation:chinese);defer{s.end()}
            for byte in raw.utf8{_ = try s.process(.code(Int32(byte)))}
            for _ in 2..<raw.utf8.count{_ = try s.process(.code(0xff51))}
            let before=try XCTUnwrap(s.snapshot);XCTAssertEqual(before.rawASCII,raw);XCTAssertEqual(before.caretUTF8,2)
            let update=try s.process(.code(code)),after=try XCTUnwrap(s.snapshot)
            let observation:[String:Any]=["kind":"ENGINE_NATIVE","schema":config.schema,"chinesePunctuation":chinese,"key":code,"beforeRaw":before.rawASCII,"beforeCaret":before.caretUTF8,"afterRaw":after.rawASCII,"afterCaret":after.caretUTF8,"handled":update.handled,"commit":update.commit?.text ?? ""]
            print("B8_OBSERVATION "+String(decoding:try JSONSerialization.data(withJSONObject:observation,options:[.sortedKeys]),as:UTF8.self))
            // Until a complete compound-insertion contract exists, a visible refusal must
            // leave the entire composition intact; silently dropping suffix is forbidden.
            XCTAssertNil(update.commit);XCTAssertTrue(update.handled);XCTAssertEqual(update.refusal,.textBeforeRawSuffix)
            XCTAssertEqual(after.rawASCII,before.rawASCII);XCTAssertEqual(after.caretUTF8,before.caretUTF8)
            XCTAssertEqual(after.inputGeneration,before.inputGeneration);XCTAssertEqual(after.rows.map{$0.ref},before.rows.map{$0.ref})
        }}}}
    }
    func same(_ a:CandidateSnapshot,_ b:CandidateSnapshot,file:StaticString=#filePath,line:UInt=#line){
        XCTAssertEqual(a.session,b.session,file:file,line:line);XCTAssertEqual(a.targetEpoch,b.targetEpoch,file:file,line:line)
        XCTAssertEqual(a.inputGeneration,b.inputGeneration,file:file,line:line);XCTAssertEqual(a.rawASCII,b.rawASCII,file:file,line:line)
        XCTAssertEqual(a.preedit,b.preedit,file:file,line:line);XCTAssertEqual(a.caretUTF8,b.caretUTF8,file:file,line:line)
        XCTAssertEqual(a.selectedRangeUTF16,b.selectedRangeUTF16,file:file,line:line);XCTAssertEqual(a.rows.map{$0.ref},b.rows.map{$0.ref},file:file,line:line)
        XCTAssertEqual(a.rows.map{$0.text},b.rows.map{$0.text},file:file,line:line);XCTAssertEqual(a.pageIndex,b.pageIndex,file:file,line:line)
        XCTAssertEqual(a.highlighted,b.highlighted,file:file,line:line);XCTAssertEqual(a.hasMore,b.hasMore,file:file,line:line)
    }
    func testTextRefusalIsAnExactNoOpAtStartMiddleAndInConfirmedComposition()throws {
        for held in [false,true] {for caret in [0,2] {
            let s=try Self.environment.runtime.makeSession(schema:LabConfiguration().schema,deferredCommit:held);defer{s.end()}
            for b in "nihao".utf8{_ = try s.process(.code(Int32(b)))}
            if held{XCTAssertNil(try s.process(.space).commit)}
            _ = try s.process(.code(0xff50));for _ in 0..<caret{_ = try s.process(.code(0xff53))}
            let before=try XCTUnwrap(s.snapshot);XCTAssertEqual(before.caretUTF8,caret)
            let timing=s.lastTiming
            let punctuation=(33...126).filter{!(97...122).contains($0) && !(48...57).contains($0) && $0 != 39}.map{String(Unicode.Scalar($0)!)}
            for text in punctuation {
                let update=try s.process(.text(text));XCTAssertEqual(update.refusal,.textBeforeRawSuffix);XCTAssertTrue(update.handled);XCTAssertNil(update.commit)
                same(try XCTUnwrap(update.snapshot),before);same(try XCTUnwrap(s.snapshot),before)
                XCTAssertEqual(s.lastTiming.engineNanoseconds,timing.engineNanoseconds);XCTAssertEqual(s.lastTiming.copyNanoseconds,timing.copyNanoseconds)
            }
            for text in ["ü","中","𠀀","u\u{308}","👩🏽‍💻","ｑ","（","", "\u{1}"] {
                let update=try s.process(.text(text));XCTAssertEqual(update.refusal,.unsupportedTextDuringComposition);XCTAssertNil(update.commit);same(try XCTUnwrap(s.snapshot),before)
            }
            let literal=try s.process(.returnKey);XCTAssertEqual(literal.commit?.text,"nihao");XCTAssertTrue(s.reserve(try XCTUnwrap(literal.commit)))
        }}
    }
    func testSupportedSpellingControlsDelimiterAndExplicitSelectionRemainRealEngineOperations()throws {
        let s=try Self.environment.runtime.makeSession(schema:LabConfiguration().schema);defer{s.end()}
        for text in ["ü","ｑ","（","u\u{308}"] {let u=try s.process(.text(text));XCTAssertFalse(u.handled);XCTAssertNil(u.refusal);XCTAssertNil(u.commit)}
        for c in "xi'an"{_ = try s.process(.text(String(c)))}
        XCTAssertEqual(s.snapshot?.rawASCII,"xi'an")
        _ = try s.process(.code(0xff51));_ = try s.process(.text("v"));XCTAssertEqual(s.snapshot?.rawASCII,"xi'avn")
        _ = try s.process(.code(0xff08));XCTAssertEqual(s.snapshot?.rawASCII,"xi'an")
        let literal=try s.process(.returnKey);XCTAssertEqual(literal.commit?.text,"xi'an");XCTAssertTrue(s.reserve(try XCTUnwrap(literal.commit)))
        for c in "nihao"{_ = try s.process(.text(String(c)))}
        let before=try XCTUnwrap(s.snapshot),candidate=before.rows[0]
        XCTAssertEqual(try s.process(.text("ü")).refusal,.unsupportedTextDuringComposition)
        let selected=try s.select(candidate.ref);XCTAssertEqual(selected.commit?.text,candidate.text)
        XCTAssertThrowsError(try s.process(.text("ü")),"Pending effect is not an eligible refusal state")
        XCTAssertTrue(s.reserve(try XCTUnwrap(selected.commit)));XCTAssertFalse(s.reserve(try XCTUnwrap(selected.commit)))
        for c in "nv"{_ = try s.process(.text(String(c)))}
        XCTAssertEqual(s.snapshot?.rawASCII,"nv");_ = try s.process(.escape);XCTAssertEqual(s.snapshot?.rawASCII,"")
    }

}
