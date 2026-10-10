import XCTest
@testable import SessionCore
final class MixedDraftTests:XCTestCase {
    // SIMULATED values only. UUIDs here are not native phonetic proof or decoder evidence.
    func testInteriorLiteralSplitsBothRawSidesWithoutSelectingChinese()throws {
        let draft=try MixedDraft(spans:[MixedSpan(source:"nihao",origin:.spelling)],caretUTF8:2)
        let next=try draft.replacing(2..<2,with:"RAG",literal:true)
        XCTAssertEqual(next.spans.map(\.source),["ni","RAG","hao"]);XCTAssertEqual(next.source,"niRAGhao")
        XCTAssertEqual(next.display,"niRAGhao");XCTAssertEqual(next.caretUTF8,5);XCTAssertFalse(next.isResolved)
        XCTAssertEqual(draft.source,"nihao");XCTAssertEqual(Set(next.spans.map(\.id)).count,3)
    }
    func testRightThenLeftConfirmationPreservesWholeSourceAndLiteral()throws {
        var draft=try MixedDraft(spans:[MixedSpan(source:"ni",origin:.spelling),MixedSpan(source:"RAG",origin:.literal),MixedSpan(source:"hao",origin:.spelling)])
        draft=try draft.confirming(draft.spans[2].id,coverage:0..<3,surface:"好",proof:UUID())
        draft=try draft.confirming(draft.spans[0].id,coverage:0..<2,surface:"你",proof:UUID())
        XCTAssertEqual(draft.source,"niRAGhao");XCTAssertEqual(draft.display,"你RAG好");XCTAssertTrue(draft.isResolved)
        XCTAssertEqual(try draft.displayCaretUTF16,1)
        XCTAssertThrowsError(try draft.movingCaret(to:1)) // no invented Chinese/Pinyin interior map
        let reopened=try draft.reopening(draft.spans[0].id)
        XCTAssertEqual(try reopened.movingCaret(to:1).displayCaretUTF16,1);XCTAssertEqual(reopened.display,"niRAG好")
    }
    func testLiteralGraphemesPreserveExactUTF8AndDeleteWholeEmoji()throws {
        var draft=try MixedDraft(spans:[MixedSpan(source:"e",origin:.literal)],caretUTF8:1)
        draft=try draft.replacing(1..<1,with:"\u{301}",literal:true)
        XCTAssertTrue(draft.source.utf8.elementsEqual("e\u{301}".utf8));XCTAssertEqual(draft.spans.count,1)
        let offset=draft.source.utf8.count
        draft=try draft.replacing(offset..<offset,with:"👩🏽‍💻",literal:true)
        XCTAssertThrowsError(try draft.movingCaret(to:offset+4))
        let deleted=try draft.replacing(offset..<draft.source.utf8.count,with:"",literal:true)
        XCTAssertTrue(deleted.source.utf8.elementsEqual("e\u{301}".utf8))
    }
    func testCrossOriginGraphemeAndPartialConfirmedEditFailUnchanged()throws {
        let raw=try MixedDraft(spans:[MixedSpan(source:"e",origin:.spelling)],caretUTF8:1)
        XCTAssertThrowsError(try raw.replacing(1..<1,with:"\u{301}",literal:true));XCTAssertEqual(raw.source,"e")
        let chosen=try MixedDraft(spans:[MixedSpan(source:"nihao",origin:.engine(surface:"你好",proof:UUID()))],caretUTF8:5)
        XCTAssertThrowsError(try chosen.replacing(2..<2,with:"RAG",literal:true))
        XCTAssertThrowsError(try chosen.replacing(4..<5,with:"",literal:true));XCTAssertEqual(chosen.source,"nihao")
    }
    func testRemovingLiteralMergesRawAndStalesOldSpanIdentity()throws {
        let draft=try MixedDraft(spans:[MixedSpan(source:"ni",origin:.spelling),MixedSpan(source:"RAG",origin:.literal),MixedSpan(source:"hao",origin:.spelling)])
        let old=draft.spans[0].id,next=try draft.replacing(2..<5,with:"",literal:true)
        XCTAssertEqual(next.spans.count,1);XCTAssertEqual(next.source,"nihao");XCTAssertNotEqual(next.spans[0].id,old)
        XCTAssertThrowsError(try next.confirming(old,coverage:0..<2,surface:"你",proof:UUID()))
    }
    func testLimitsUniqueProofsAndLiteralOnlyDraftRemainComposing()throws {
        XCTAssertThrowsError(try MixedDraft(spans:[MixedSpan(source:"a\0",origin:.literal)]))
        XCTAssertThrowsError(try MixedDraft(spans:[MixedSpan(source:String(repeating:"a",count:4097),origin:.spelling)]))
        let proof=UUID();XCTAssertThrowsError(try MixedDraft(spans:[MixedSpan(source:"ni",origin:.engine(surface:"你",proof:proof)),MixedSpan(source:"hao",origin:.engine(surface:"好",proof:proof))]))
        let literal=try MixedDraft(spans:[MixedSpan(source:"𠀀",origin:.literal)],caretUTF8:4)
        XCTAssertFalse(literal.isEmpty);XCTAssertTrue(literal.isResolved);XCTAssertEqual(try literal.displayCaretUTF16,2)
        XCTAssertThrowsError(try literal.replacing(0..<4,with:String(repeating:"a",count:4097),literal:true))
    }
    func testMiddleCoveragePreservesBothSpellingSidesAndEndpointMap()throws {
        let raw=MixedSpan(source:"nihaoma",origin:.spelling)
        let draft=try MixedDraft(spans:[raw]).confirming(raw.id,coverage:2..<5,surface:"好",proof:UUID())
        XCTAssertEqual(draft.source,"nihaoma");XCTAssertEqual(draft.display,"ni好ma")
        XCTAssertEqual(draft.spans.map(\.source),["ni","hao","ma"])
        XCTAssertEqual(draft.map.map(\.sourceUTF8),[0..<2,2..<5,5..<7])
        XCTAssertEqual(draft.caretUTF8,5);XCTAssertEqual(try draft.displayCaretUTF16,3)
        let priorIDs=Set(draft.spans.map(\.id)),reopened=try draft.reopening(draft.spans[1].id)
        XCTAssertEqual(reopened.spans.count,1);XCTAssertEqual(reopened.source,"nihaoma")
        XCTAssertFalse(priorIDs.contains(reopened.spans[0].id));XCTAssertFalse(reopened.isResolved)
    }
    func testSpanIdentityCountAndDisplayLimits()throws {
        let id=UUID()
        XCTAssertThrowsError(try MixedDraft(spans:[MixedSpan(id:id,source:"a",origin:.literal),MixedSpan(id:id,source:"b",origin:.literal)]))
        XCTAssertThrowsError(try MixedDraft(spans:(0..<257).map{_ in MixedSpan(source:"a",origin:.literal)}))
        XCTAssertThrowsError(try MixedDraft(spans:[MixedSpan(source:"a",origin:.engine(surface:String(repeating:"字",count:16385),proof:UUID()))]))
        let exact=try MixedDraft(spans:[MixedSpan(source:"a",origin:.engine(surface:String(repeating:"a",count:16384),proof:UUID()))])
        XCTAssertEqual(exact.display.utf16.count,16384)
        XCTAssertThrowsError(try MixedDraft(spans:[MixedSpan(source:"a",origin:.engine(surface:String(repeating:"字",count:22000),proof:UUID()))]))
    }
    func testInsertionJoiningFollowingGraphemeRefusesWithoutChangingDraft()throws {
        // Bounded refusal until a caller chooses a valid post-insert grapheme caret.
        let draft=try MixedDraft(spans:[MixedSpan(source:"\u{301}",origin:.literal)])
        XCTAssertThrowsError(try draft.replacing(0..<0,with:"e",literal:true))
        XCTAssertTrue(draft.source.utf8.elementsEqual("\u{301}".utf8))
    }
    func testCoreFinalEffectRequiresExactWholeSourceOrFullyResolvedDisplay()throws {
        // SIMULATED proof values test the pure effect gate only.
        var core=SessionCore(dictionaryRevision:"simulated")
        let draft=try MixedDraft(spans:[MixedSpan(source:"ni",origin:.engine(surface:"你",proof:UUID())),MixedSpan(source:"RAG",origin:.literal),MixedSpan(source:"hao",origin:.spelling)],caretUTF8:5)
        _ = try core.receiveMixed(draft,owner:UUID(),span:nil,projection:0,rows:[])
        XCTAssertTrue(core.isComposing);XCTAssertNil(core.idleExpressionBinding)
        XCTAssertThrowsError(try core.finishMixed("你RAGhao",engine:true))
        XCTAssertThrowsError(try core.finishMixed("hao",engine:false))
        let effect=try XCTUnwrap(core.finishMixed("niRAGhao",engine:false).commit)
        XCTAssertEqual(effect.text,"niRAGhao");XCTAssertThrowsError(try core.finishMixed("niRAGhao",engine:false))
        XCTAssertTrue(core.reserve(effect));XCTAssertFalse(core.reserve(effect))
        let resolved=try draft.confirming(draft.spans[2].id,coverage:0..<3,surface:"好",proof:UUID())
        _ = try core.receiveMixed(resolved,owner:UUID(),span:nil,projection:0,rows:[])
        XCTAssertThrowsError(try core.finishMixed("好",engine:true))
        let final=try XCTUnwrap(core.finishMixed("你RAG好",engine:true).commit);XCTAssertTrue(core.reserve(final))
    }
}
