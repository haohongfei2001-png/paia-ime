import XCTest
import TextBoundary
import SessionCore

final class CharacterCoreTests:XCTestCase {
    func testExactScalarIdentityAndReadableIdentifiers()throws {
        for (input,code) in [("U+20000",UInt32(0x20000)),("u+00b1",0xB1),("±",0xB1),("U+4E2D",0x4E2D),("A",0x41),("U+1F469",0x1F469),("U+212B",0x212B),("Å",0xC5)] {
            let value=try KnownCharacter(input);XCTAssertEqual(value.scalar.value,code)
            XCTAssertEqual(value.text.unicodeScalars.map{$0.value},[code]);XCTAssertTrue(value.identifier.hasPrefix("U+"));XCTAssertFalse(value.name.isEmpty)
        }
        XCTAssertEqual(try KnownCharacter("𠀀").text.utf16.count,2)
        XCTAssertNotEqual(try KnownCharacter("Å"),try KnownCharacter("Å"))
        XCTAssertEqual(try KnownCharacter("U+000041").identifier,"U+0041")
    }
    func testMalformedInvisibleAndUnsupportedValuesAreRefused() {
        for input in ["","20000"," U+0041","U+0041 ","U+","U+GG","U+-1","U+110000","U+D800","U+0000041","U+00\n41","ab","e\u{301}","👩🏽‍💻","U+0000","U+000A","U+007F","U+009F","U+0020","U+00A0","U+0301","U+200B","U+200D","U+202E","U+2066","U+FE0F","U+E000","U+0378","U+FDD0","U+10FFFF","U+2800","U+1D159","U+1F3FB","U+FF9E"] {XCTAssertThrowsError(try KnownCharacter(input),input)}
    }
    func testInsertedScalarMustKeepItsOwnGraphemeBoundaries()throws {
        XCTAssertTrue(try KnownCharacter("U+20000").canInsert(at:NSRange(location:1,length:0),in:"AB"))
        XCTAssertFalse(try KnownCharacter("U+1F1E6").canInsert(at:NSRange(location:2,length:0),in:"🇧"))
        XCTAssertFalse(try KnownCharacter("U+1161").canInsert(at:NSRange(location:1,length:0),in:"ᄀ"))
        XCTAssertFalse(try KnownCharacter("A").canInsert(at:NSRange(location:0,length:0),in:"\u{301}"))
        XCTAssertFalse(try KnownCharacter("A").canInsert(at:NSRange(location:1,length:0),in:"𠀀"))
        XCTAssertFalse(try KnownCharacter("A").canInsert(at:NSRange(location:0,length:1),in:"A"))
    }
    func testInitializedIdleBindingAndSingleReservation()throws {
        var core=SessionCore(dictionaryRevision:"b7-synthetic-state")
        XCTAssertNil(core.idleCharacterBinding)
        _ = try core.receive(EngineValue(raw:"",preedit:"",caretUTF8:0))
        let binding=try XCTUnwrap(core.idleCharacterBinding),value=try KnownCharacter("U+20000")
        let update=try core.commitKnownCharacter(value,binding:binding),effect=try XCTUnwrap(update.commit)
        XCTAssertEqual(effect.text.unicodeScalars.map{$0.value},[0x20000]);if case .literal=effect.origin {}else{XCTFail("Expected explicit literal origin")}
        XCTAssertTrue(update.handled);XCTAssertTrue(try XCTUnwrap(update.snapshot).rows.isEmpty)
        XCTAssertNil(core.idleCharacterBinding);XCTAssertThrowsError(try core.commitKnownCharacter(value,binding:binding))
        XCTAssertTrue(core.reserve(effect));XCTAssertFalse(core.reserve(effect))
        XCTAssertThrowsError(try core.commitKnownCharacter(value,binding:binding))
        let next=try XCTUnwrap(core.idleCharacterBinding)
        let other=try XCTUnwrap(core.commitKnownCharacter(KnownCharacter("U+212B"),binding:next).commit)
        XCTAssertEqual(other.text.unicodeScalars.map{$0.value},[0x212B]);core.invalidate();XCTAssertFalse(core.reserve(other));XCTAssertNil(core.idleCharacterBinding)
    }
    func testCompositionAndForeignBindingsNeverClearOrCommit()throws {
        var a=SessionCore(dictionaryRevision:"b7-a"),b=SessionCore(dictionaryRevision:"b7-b")
        _ = try a.receive(EngineValue(raw:"",preedit:"",caretUTF8:0));_ = try b.receive(EngineValue(raw:"",preedit:"",caretUTF8:0))
        let old=try XCTUnwrap(a.idleCharacterBinding),foreign=try XCTUnwrap(b.idleCharacterBinding),value=try KnownCharacter("±")
        XCTAssertThrowsError(try a.commitKnownCharacter(value,binding:foreign))
        _ = try a.receive(EngineValue(raw:"ni",preedit:"ni",caretUTF8:2,candidates:["你"]))
        XCTAssertNil(a.idleCharacterBinding);XCTAssertThrowsError(try a.commitKnownCharacter(value,binding:old));XCTAssertEqual(a.snapshot?.rawASCII,"ni")
        XCTAssertEqual(a.snapshot?.rows.first?.text,"你")
        a.invalidate();XCTAssertThrowsError(try a.commitKnownCharacter(value,binding:old))
    }
}
