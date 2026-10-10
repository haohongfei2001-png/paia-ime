import XCTest
import Foundation
import EngineBridge
import SessionCore
import SettingsCore

final class InputHabitNativeTests:XCTestCase {
    static var environment:ResearchLabEnvironment!
    override class func setUp(){super.setUp();do{environment=try ResearchLabEnvironment()}catch{XCTFail("Verified policy startup failed: \(error)")}}
    func convert(_ config:LabConfiguration,_ raw:String,_ text:String)throws {
        let session=try Self.environment.runtime.makeSession(schema:config.schema,deferredCommit:true,chinesePunctuation:config.chinesePunctuation)
        defer{session.end()};_ = try session.refresh()
        for character in raw {let initial=try session.process(.text(String(character)));XCTAssertTrue(initial.handled);XCTAssertNil(initial.commit)};XCTAssertEqual(session.snapshot?.sourceText,raw)
        let choices=try session.repairChoices(limit:512)
        let row=try XCTUnwrap(choices.rows.first{$0.anchor.bytes==(0..<raw.utf8.count) && $0.anchor.text.utf8.elementsEqual(text.utf8)},"\(config.schema) / \(raw) → \(text), complete=\(choices.complete)")
        XCTAssertNil(try session.selectForRepair(row).commit)
        let effect=try XCTUnwrap(session.commitEngineComposition().commit)
        XCTAssertTrue(effect.text.utf8.elementsEqual(text.utf8));XCTAssertTrue(session.reserve(effect));XCTAssertFalse(session.reserve(effect))
        XCTAssertNil(try session.process(.returnKey).commit)
    }
    func testAllEffectiveSchemasKeepSameMeaningSpellingAndOneCommit()throws {
        var count=0,schemas=Set<String>()
        for spelling in LabSpelling.allCases {for traditional in [false,true] {for punctuation in [false,true] {for fuzzy in [false,true] {for correction in (spelling == .full ? [true,false]:[true]) {
            var c=LabConfiguration();c.spelling=spelling;c.traditional=traditional;c.chinesePunctuation=punctuation;c.fuzzyInitials=fuzzy;c.fullPinyinCorrection=correction;schemas.insert(c.schema)
            let full=spelling == .full
            var cases=[("nv","女"),("lv",traditional ? "綠":"绿"),(full ? "lve":"lt","略"),(full ? "nve":"nt","虐"),("xi'an","西安"),(full ? "xian":"xm","先"),(full ? "shurufa":"uurufa",traditional ? "輸入法":"输入法")]
            if full{cases += [("lue","略"),("nue","虐")]}else{cases += [("xi'aj","西安")]}
            for (raw,text) in cases {try convert(c,raw,text);count+=1}
        }}}}}
        XCTAssertEqual(schemas.count,32);XCTAssertEqual(count,272)
        print("HABIT_RESEARCH_NATIVE schemas=32 actual_commits=272; v/ü meaning, syllable boundary, full/double and scripts; no quality claim")
    }
    func testFuzzyAndFullTypoPositivePathsUseActualResearchCandidates()throws {
        var count=0
        for spelling in LabSpelling.allCases {for traditional in [false,true] {
            var c=LabConfiguration();c.spelling=spelling;c.traditional=traditional;c.fuzzyInitials=true
            let full=spelling == .full
            for (raw,text) in [(full ? "zongguo":"zsgo",traditional ? "中國":"中国"),("surufa",traditional ? "輸入法":"输入法"),(full ? "nantian":"njtm",traditional ? "藍天":"蓝天"),(full ? "cumen":"cumf",traditional ? "出門":"出门")] {try convert(c,raw,text);count+=1}
            if full{c.fuzzyInitials=false;try convert(c,"hzi","知");try convert(c,"hzongguo",traditional ? "中國":"中国");count+=2}
        }}
        XCTAssertEqual(count,28)
        print("HABIT_POLICY_RESEARCH_NATIVE actual_commits=28 positive paths; exhaustive negative proof is separate authored corpus")
    }
    func testPolicyChangesDoNotChangeWholeRawReturnOrStaleCandidateRules()throws {
        for spelling in LabSpelling.allCases {for fuzzy in [false,true] {for correction in [false,true] {
            var c=LabConfiguration();c.spelling=spelling;c.fuzzyInitials=fuzzy;c.fullPinyinCorrection=correction
            let s=try Self.environment.runtime.makeSession(schema:c.schema);defer{s.end()}
            _ = try s.refresh();let raw=spelling == .full ? "xi'an":"xi'aj";for character in raw {_ = try s.process(.text(String(character)))}
            let old=try XCTUnwrap(s.snapshot?.rows.first?.ref);_ = try s.process(.code(0xff50))
            XCTAssertThrowsError(try s.select(old))
            let effect=try XCTUnwrap(s.process(.returnKey).commit);XCTAssertEqual(effect.text,raw);XCTAssertTrue(s.reserve(effect));XCTAssertFalse(s.reserve(effect))
        }}}
    }
    func testClosedSchemaIdentityAndPreferenceRoundTrip()throws {
        // SIMULATED value/identity assertions, not additional engine conversions.
        XCTAssertEqual(LabConfiguration.researchSchemas.count,32)
        var full=LabConfiguration();XCTAssertEqual(full.schema,"paia_b1_full_ascii")
        full.fullPinyinCorrection=false;full.fuzzyInitials=true;XCTAssertEqual(full.schema,"paia_b1_full_ascii_fuzzy_strict")
        full.initialModes=["dev.paia.app":.literal]
        XCTAssertEqual(LabConfiguration(preferences:full.preferences),full)
        for spelling in [LabSpelling.flypy,.natural] {
            var a=full;a.spelling=spelling;var b=a;b.fullPinyinCorrection=true
            XCTAssertEqual(a.schema,b.schema);XCTAssertFalse(a.schema.contains("strict"))
        }
    }
}
