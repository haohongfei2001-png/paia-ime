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
            XCTAssertNil(update.commit);XCTAssertTrue(update.handled)
            XCTAssertEqual(after.rawASCII,before.rawASCII);XCTAssertEqual(after.caretUTF8,before.caretUTF8)
            XCTAssertEqual(after.inputGeneration,before.inputGeneration);XCTAssertEqual(after.rows.map{$0.ref},before.rows.map{$0.ref})
        }}}}
    }
}
