import XCTest
import Foundation
import TextBoundary
import SessionCore

final class ContextCoreTests:XCTestCase {
    func evidence(_ text:String,_ selection:NSRange)throws->ContextEvidence {
        let request=try ContextBudget.request(selection:selection,length:text.utf16.count)
        let units=Array(text.utf16)[request.location..<(request.location+request.length)]
        return try ContextEvidence(read:BoundedTextRead(requested:request,actual:request,units:Array(units)),selection:selection,documentLength:text.utf16.count)
    }
    func testRawUTF16AndFiniteActualRangeValidation()throws {
        let malformed:[[UInt16]]=[[0xD800],[0xDC00],[0xD800,65],[65,0xDFFF]]
        for units in malformed {
            XCTAssertThrowsError(try BoundedTextRead(requested:NSRange(location:0,length:units.count),actual:NSRange(location:0,length:units.count),units:units))
        }
        let pair=try BoundedTextRead(requested:NSRange(location:0,length:2),actual:NSRange(location:0,length:2),units:[0xD840,0xDC00]);XCTAssertEqual(pair.text,"𠀀")
        for actual in [NSRange(location:NSNotFound,length:2),NSRange(location:Int.max-1,length:3),NSRange(location:3,length:2),NSRange(location:0,length:1)] {
            XCTAssertThrowsError(try BoundedTextRead(requested:NSRange(location:0,length:2),actual:actual,units:[65,66]))
        }
        XCTAssertThrowsError(try ContextBudget.request(selection:NSRange(location:0,length:1025),length:1025))
        XCTAssertThrowsError(try ContextBudget.request(selection:NSRange(location:Int.max,length:1),length:Int.max))
    }
    func testEmptyDocumentEndpointAndShiftedReadback()throws {
        let empty=try evidence("",NSRange(location:0,length:0)),insert=try empty.replacing(with:"𠀀")
        XCTAssertEqual(insert.documentLength,2);XCTAssertEqual(insert.caret,NSRange(location:2,length:0));XCTAssertEqual(insert.expected.text,"𠀀")
        let original=try evidence("left你好right",NSRange(location:4,length:2))
        for replacement in ["x","中文𠀀",""] {
            let result=try original.replacing(with:replacement)
            XCTAssertEqual(result.expected.text,"left"+replacement+"right");XCTAssertEqual(result.caret.location,4+replacement.utf16.count)
            XCTAssertEqual(result.expected.requested.length,result.expected.actual.length)
        }
    }
    func testSelectionAndReplacementJoinsRespectGraphemes()throws {
        for (text,selection) in [("e\u{301}",NSRange(location:0,length:1)),("👩🏽‍💻",NSRange(location:0,length:2)),("\r\n",NSRange(location:1,length:0)),("🇦🇧",NSRange(location:2,length:0))] {
            XCTAssertThrowsError(try evidence(text,selection))
        }
        for text in ["🇦X🇧","\rX\n"] {
            let range=(text as NSString).range(of:"X");XCTAssertThrowsError(try evidence(text,range).replacing(with:""))
        }
        XCTAssertThrowsError(try evidence("aXb",NSRange(location:1,length:1)).replacing(with:"\u{301}"))
        XCTAssertNoThrow(try evidence("a👩🏽‍💻b",NSRange(location:1,length:"👩🏽‍💻".utf16.count)).replacing(with:"e\u{301}"))
        XCTAssertThrowsError(try evidence("ᄀX",NSRange(location:1,length:1)).replacing(with:"ᅡ"))
    }
    func testFiniteHaloCannotInventLeftResetOrRightEndpoint()throws {
        for text in [String(repeating:"🇦",count:200)+"X", "a"+String(repeating:"\u{301}",count:400)+"X",String(repeating:"👩\u{200D}",count:150)+"👩X"] {
            XCTAssertThrowsError(try evidence(text,NSRange(location:text.utf16.count-1,length:1)))
        }
        let text=String(repeating:"z",count:400)+"\n你好X",range=NSRange(location:text.utf16.count-1,length:1)
        XCTAssertNoThrow(try evidence(text,range).replacing(with:"Y"))
        let clipped=try BoundedTextRead(requested:NSRange(location:0,length:3),actual:NSRange(location:0,length:2),units:[65,66])
        XCTAssertThrowsError(try ContextEvidence(read:clipped,selection:NSRange(location:1,length:1),documentLength:3))
        // A LF within the selected span is not a retained-left reset.
        let units=Array((String(repeating:"z",count:300)+"\nX").utf16)
        XCTAssertThrowsError(try evidence(String(decoding:units,as:UTF16.self),NSRange(location:299,length:3)))
    }
    func testExactUnitsDoNotUseCanonicalStringEquality()throws {
        let a=try evidence("é",NSRange(location:0,length:1)),b=try evidence("e\u{301}",NSRange(location:0,length:2))
        XCTAssertEqual(a.original,b.original);XCTAssertFalse(a.exactlyMatches(b))
        XCTAssertThrowsError(try a.replacing(with:"\0"))
    }
    func testKnownCharacterRemainsStandaloneInCapturedContext()throws {
        for (source,code) in [("ᄀ","U+1161"),("🇦","U+1F1E7")] {
            let e=try evidence(source,NSRange(location:source.utf16.count,length:0))
            XCTAssertThrowsError(try e.replacing(with:KnownCharacter(code).text))
        }
        XCTAssertEqual(try evidence("你好",NSRange(location:2,length:0)).replacing(with:KnownCharacter("U+20000").text).expected.text,"你好𠀀")
    }
    func testReviewedDeletionUsesOneEffectAndCannotReplay()throws {
        var core=SessionCore(dictionaryRevision:"authored-context-fixture")
        _=try core.receive(EngineValue(raw:"",preedit:"",caretUTF8:0));let binding=try XCTUnwrap(core.idleExpressionBinding)
        let update=try core.commitReviewedEdit("",replacing:NSRange(location:3,length:2),binding:binding),effect=try XCTUnwrap(update.commit)
        XCTAssertEqual(effect.origin,.reviewedEdit);XCTAssertEqual(effect.text,"");XCTAssertEqual(effect.replacementUTF16,NSRange(location:3,length:2))
        XCTAssertThrowsError(try core.commitReviewedEdit("again",replacing:NSRange(location:3,length:2),binding:binding))
        XCTAssertTrue(core.reserve(effect));XCTAssertFalse(core.reserve(effect))
        XCTAssertThrowsError(try core.commitReviewedEdit("again",replacing:NSRange(location:3,length:2),binding:binding))
        core.invalidate();XCTAssertFalse(core.reserve(effect))
    }
}
