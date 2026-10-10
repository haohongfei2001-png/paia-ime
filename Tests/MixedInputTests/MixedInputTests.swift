import XCTest
import Foundation
@testable import EngineBridge
import SessionCore

final class MixedInputTests:XCTestCase {
    static var environment:ResearchLabEnvironment!
    override class func setUp(){super.setUp();do{environment=try ResearchLabEnvironment()}catch{XCTFail("Verified mixed engine startup failed: \(error)")}}
    func session(_ schema:String="paia_b1_full_ascii")throws->InputSession {
        let session=try Self.environment.runtime.makeSession(schema:schema);_ = try session.refresh()
        _ = try session.beginMixed(binding:XCTUnwrap(session.idleExpressionBinding));return session
    }
    func choose(_ text:String,_ session:InputSession)throws {
        for _ in 0..<13 {
            let snapshot=try XCTUnwrap(session.snapshot)
            if let row=snapshot.rows.first(where:{$0.text.utf8.elementsEqual(text.utf8)}){let result=try session.select(row.ref);XCTAssertNil(result.commit);return}
            if !snapshot.hasMore{break};_ = try session.process(.code(0xff56))
        }
        XCTFail("Genuine mixed candidate unavailable: "+text);throw EngineError.closed
    }
    func split(_ s:InputSession,literal:String="RAG")throws {
        _ = try s.process(.text("nihao"));_ = try s.process(.code(0xff50))
        _ = try s.process(.code(0xff53));_ = try s.process(.code(0xff53))
        _ = try s.setMixedLiteralIntent(true);_ = try s.process(.text(literal));_ = try s.setMixedLiteralIntent(false)
    }
    func testInteriorRawRightThenLeftRealCommitAndOneEffect()throws {
        let s=try session();defer{s.end()};try split(s)
        XCTAssertEqual(s.mixedDraft?.spans.map(\.source),["ni","RAG","hao"])
        XCTAssertEqual(s.snapshot?.sourceText,"niRAGhao");XCTAssertEqual(s.snapshot?.preedit,"niRAGhao")
        try choose("好",s);_ = try s.process(.code(0xff09));try choose("你",s)
        XCTAssertEqual(s.snapshot?.preedit,"你RAG好");XCTAssertEqual(s.snapshot?.sourceText,"niRAGhao")
        let effect=try XCTUnwrap(s.process(.space).commit)
        XCTAssertEqual(effect.text,"你RAG好");XCTAssertThrowsError(try s.process(.returnKey))
        XCTAssertTrue(s.reserve(effect));XCTAssertFalse(s.reserve(effect));XCTAssertFalse(try s.process(.returnKey).handled)
        _ = try s.process(.text("n"));_ = try s.process(.text("i"))
        let normal=try XCTUnwrap(s.snapshot?.rows.first(where:{$0.text=="你"}))
        let next=try XCTUnwrap(s.select(normal.ref).commit);XCTAssertEqual(next.text,"你");XCTAssertTrue(s.reserve(next))
        print("MIXED_SWIFT_NATIVE actual owner/shim/engine to one core effect")
    }
    func testFullSourceReturnFromEveryAllowedCaret()throws {
        for offset in [0,2,5,8] {
            let s=try session();defer{s.end()};try split(s);try choose("好",s);_ = try s.process(.code(0xff09));try choose("你",s)
            _ = try s.process(.code(0xff50))
            for _ in 0..<8 where s.snapshot!.caretUTF8<offset{_ = try s.process(.code(0xff53))}
            XCTAssertEqual(s.snapshot?.caretUTF8,offset)
            let result=try s.process(.returnKey),effect=try XCTUnwrap(result.commit)
            XCTAssertTrue(result.handled);XCTAssertEqual(effect.text,"niRAGhao");XCTAssertTrue(s.reserve(effect));XCTAssertFalse(s.reserve(effect))
        }
    }
    func testLiteralIntentProtectsSpaceDigitsPathsAndGraphemeEdits()throws {
        let s=try session();defer{s.end()};_ = try s.setMixedLiteralIntent(true)
        let text="data user_id https://example.test/a_b?q=1.2 12:30"
        for character in text {_ = try s.process(character==" " ? .space:.text(String(character)))}
        _ = try s.process(.text(" e"));_ = try s.process(.text("\u{301}"));_ = try s.process(.text("👩🏽‍💻"))
        _ = try s.process(.code(0xff08))
        let expected=text+" e\u{301}"
        XCTAssertTrue(s.snapshot!.sourceText.utf8.elementsEqual(expected.utf8));XCTAssertEqual(s.snapshot?.preedit,expected)
        XCTAssertEqual(s.mixedDraft?.spans.count,1)
        _ = try s.setMixedLiteralIntent(false)
        let effect=try XCTUnwrap(s.process(.space).commit);XCTAssertTrue(effect.text.utf8.elementsEqual(expected.utf8));XCTAssertTrue(s.reserve(effect))
    }
    func testStaleCandidatesAndExplicitReopenKeepOtherProofs()throws {
        let a=try session(),b=try session();defer{a.end();b.end()};try split(a);try split(b)
        let old=try XCTUnwrap(a.snapshot?.rows.first?.ref)
        XCTAssertThrowsError(try b.select(old));_ = try a.process(.code(0xff50));XCTAssertThrowsError(try a.select(old))
        try choose("你",a);_ = try a.process(.code(0xff09));try choose("好",a)
        let draft=try XCTUnwrap(a.mixedDraft),right=draft.spans.last!
        _ = try a.reopenMixedSpan(draft.spans[0].id)
        XCTAssertEqual(a.mixedDraft?.spans.last,right);XCTAssertFalse(a.mixedDraft!.isResolved)
        XCTAssertThrowsError(try a.commitEngineComposition());XCTAssertEqual(a.snapshot?.sourceText,"niRAGhao")
        _ = try a.process(.code(0xff09));try choose("你",a)
        let effect=try XCTUnwrap(a.commitEngineComposition().commit);XCTAssertEqual(effect.text,"你RAG好");XCTAssertTrue(a.reserve(effect))
    }
    func testPartialSelectionAndRefusedCrossOriginEditKeepSource()throws {
        let s=try session();defer{s.end()};_ = try s.process(.text("nihao"));try choose("你",s)
        XCTAssertEqual(s.mixedDraft?.spans.map(\.source),["ni","hao"]);XCTAssertEqual(s.snapshot?.sourceText,"nihao")
        _ = try s.process(.text("RAG"));try choose("好",s)
        let effect=try XCTUnwrap(s.commitEngineComposition().commit);XCTAssertEqual(effect.text,"你RAG好");XCTAssertTrue(s.reserve(effect))
        let other=try session();defer{other.end()};_ = try other.process(.text("e"))
        let before=try XCTUnwrap(other.snapshot),row=try XCTUnwrap(before.rows.first)
        let refused=try other.process(.text("\u{301}"));XCTAssertNotNil(refused.refusal);XCTAssertNil(refused.commit);XCTAssertEqual(other.snapshot?.sourceText,"e")
        XCTAssertEqual(other.snapshot?.inputGeneration,before.inputGeneration);XCTAssertEqual(other.snapshot?.caretUTF8,before.caretUTF8)
        XCTAssertEqual(other.snapshot?.rows.map(\.ref),before.rows.map(\.ref));XCTAssertNil(try other.select(row.ref).commit)
    }
    func testImportRealSelectedPrefixAndUnresolvedSuffixWithoutChangingChoice()throws {
        let s=try Self.environment.runtime.makeSession(schema:"paia_b1_full_ascii",deferredCommit:true);defer{s.end()}
        _ = try s.refresh();for byte in "nihaoshijie".utf8{_ = try s.process(.code(Int32(byte)))}
        let chosen=try XCTUnwrap(s.repairChoices().rows.first{$0.anchor.text=="你好" && $0.anchor.bytes.upperBound==5})
        _ = try s.selectForRepair(chosen)
        let prior=try XCTUnwrap(s.snapshot);_ = try s.beginMixed(snapshot:prior)
        XCTAssertEqual(s.mixedDraft?.spans.map(\.source),["nihao","shijie"])
        XCTAssertEqual(s.mixedDraft?.spans.first?.display,"你好");XCTAssertFalse(s.mixedDraft!.isResolved)
        _ = try s.process(.code(0xff50));_ = try s.process(.code(0xff53));XCTAssertEqual(s.snapshot?.caretUTF8,5)
        _ = try s.process(.text("RAG"));try choose("世界",s)
        let effect=try XCTUnwrap(s.commitEngineComposition().commit);XCTAssertEqual(effect.text,"你好RAG世界");XCTAssertTrue(s.reserve(effect))
    }
    func testRealNativeSuccessThenSwiftRejectionRetiresInsteadOfReusingOldProjection()throws {
        for point in [MixedValidationPoint.projection,.selection,.commit,.sourceClear] {
            let s=try Self.environment.runtime.makeSession(schema:"paia_b1_full_ascii");defer{s.end()};_ = try s.refresh()
            if point != .sourceClear{_ = try s.beginMixed(binding:XCTUnwrap(s.idleExpressionBinding))}
            if point != .projection{for byte in "ni".utf8{_ = try s.process(.code(Int32(byte)))}}
            if point == .commit{try choose("你",s)}
            let old=s.snapshot?.rows.first?.ref,snapshot=try XCTUnwrap(s.snapshot)
            var rejected=false
            s.mixedResultValidation={stage in if stage==point{rejected=true;throw MixedDraftError.invalid}}
            switch point {
            case .projection:XCTAssertThrowsError(try s.process(.text("ni")))
            case .selection:XCTAssertThrowsError(try s.select(XCTUnwrap(old)))
            case .commit:XCTAssertThrowsError(try s.commitEngineComposition())
            case .sourceClear:XCTAssertThrowsError(try s.beginMixed(snapshot:snapshot))
            }
            XCTAssertTrue(rejected);XCTAssertNil(s.snapshot);XCTAssertNil(s.mixedDraft)
            if let old=old{XCTAssertThrowsError(try s.select(old))}
            XCTAssertThrowsError(try s.refresh());XCTAssertThrowsError(try s.commitEngineComposition())
        }
    }
    func testEveryExposedSpellingScriptPunctuationAndInitialsCommitsWholeMixedValue()throws {
        var commits=0,returns=0
        for (mode,left,right) in [("full","nihao","shurufa"),("full","nh","srf"),("flypy","nihc","uurufa"),("natural","nihk","uurufa")] {
            for traditional in [false,true] {for punctuation in [false,true] {
                let schema="paia_b1_"+mode+(traditional ? "_traditional":"")+(punctuation ? "_punct":"_ascii")
                for literal in ["data 3.14","👩🏽‍💻，e\u{301}"] {
                    for original in [false,true] {
                        let s=try session(schema);defer{s.end()};_ = try s.process(.text(left+right));_ = try s.process(.code(0xff50))
                        for _ in 0..<left.utf8.count{_ = try s.process(.code(0xff53))}
                        _ = try s.setMixedLiteralIntent(true);_ = try s.process(.text(literal));_ = try s.setMixedLiteralIntent(false)
                        try choose(traditional ? "輸入法":"输入法",s);_ = try s.process(.code(0xff09));try choose("你好",s)
                        let expected=original ? left+literal+right:"你好"+literal+(traditional ? "輸入法":"输入法")
                        if original{_ = try s.process(.code(0xff50))}
                        let update=try s.process(original ? .returnKey:.space),effect=try XCTUnwrap(update.commit)
                        XCTAssertTrue(effect.text.utf8.elementsEqual(expected.utf8));XCTAssertTrue(s.reserve(effect));XCTAssertFalse(s.reserve(effect))
                        if original{returns+=1}else{commits+=1}
                    }
                }
            }}
        }
        XCTAssertEqual(commits,32);XCTAssertEqual(returns,32)
        print("MIXED_MODE_MATRIX native_commits=32 full_source_returns=32; all12 exposed schemas plus full initials")
    }
    func testHighlightedNonDefaultCandidateAndPagingUseActualNativeIdentity()throws {
        let s=try session();defer{s.end()};_ = try s.process(.text("ni"))
        let old=try XCTUnwrap(s.snapshot?.rows.first?.ref)
        _ = try s.process(.code(0xff54));let snapshot=try XCTUnwrap(s.snapshot)
        XCTAssertEqual(snapshot.highlighted,1);XCTAssertThrowsError(try s.select(old))
        let chosen=snapshot.rows[snapshot.highlighted].text;_ = try s.process(.space)
        XCTAssertEqual(s.mixedDraft?.display,chosen)
        let result=try XCTUnwrap(s.process(.space).commit);XCTAssertEqual(result.text,chosen);XCTAssertTrue(s.reserve(result))
        _ = try s.beginMixed(binding:XCTUnwrap(s.idleExpressionBinding));_ = try s.process(.text("shi"))
        for _ in 0..<6{_ = try s.process(.code(0xff54))}
        XCTAssertEqual(s.snapshot?.pageIndex,1);XCTAssertEqual(s.snapshot?.highlighted,1)
        _ = try s.process(.code(0xff52));XCTAssertEqual(s.snapshot?.highlighted,0)
        _ = try s.process(.code(0xff52));XCTAssertEqual(s.snapshot?.pageIndex,0);XCTAssertEqual(s.snapshot?.highlighted,4)
        _ = try s.setMixedLiteralIntent(true);_ = try s.process(.text("RAG"));_ = try s.setMixedLiteralIntent(false);_ = try s.process(.text("shi"))
        let right=try XCTUnwrap(s.snapshot?.rows.first?.ref)
        _ = try s.process(.code(0xff09,modifiers:1));let left=try XCTUnwrap(s.snapshot?.rows.first?.ref)
        XCTAssertEqual(s.snapshot?.rawASCII,"shi");XCTAssertEqual(s.snapshot?.caretUTF8,0);XCTAssertNotEqual(left.mixed?.span,right.mixed?.span)
        XCTAssertThrowsError(try s.select(right))
        _ = try s.process(.code(0xff09,modifiers:1));XCTAssertEqual(s.snapshot?.caretUTF8,6)
        _ = try s.process(.code(0xff09));XCTAssertEqual(s.snapshot?.caretUTF8,0)
    }
    func testChainedLiteralEditsAnd128IndependentSuffixProofsKeepWholeDraft()throws {
        let s=try session();defer{s.end()};_ = try s.process(.text("nihao"));try choose("你好",s)
        _ = try s.setMixedLiteralIntent(true);_ = try s.process(.text("e"));_ = try s.process(.text("\u{301}"));_ = try s.process(.text("👩🏽‍💻"))
        _ = try s.process(.code(0xff08));_ = try s.process(.text("RAG"));_ = try s.process(.code(0xff51));_ = try s.process(.code(0xffff))
        XCTAssertEqual(s.mixedDraft?.display,"你好e\u{301}RA")
        _ = try s.setMixedLiteralIntent(false);_ = try s.process(.text(String(repeating:"shijie",count:128)))
        for _ in 0..<128{try choose("世界",s)}
        let source="nihaoe\u{301}RA"+String(repeating:"shijie",count:128),expected="你好e\u{301}RA"+String(repeating:"世界",count:128)
        XCTAssertTrue(s.snapshot!.sourceText.utf8.elementsEqual(source.utf8));XCTAssertEqual(s.mixedDraft?.spans.count,130)
        let effect=try XCTUnwrap(s.commitEngineComposition().commit);XCTAssertTrue(effect.text.utf8.elementsEqual(expected.utf8));XCTAssertTrue(s.reserve(effect))
        print("MIXED_CHAIN_NATIVE chained grapheme edit and 128 distinct suffix proofs; no latency percentile claim")
    }
}
