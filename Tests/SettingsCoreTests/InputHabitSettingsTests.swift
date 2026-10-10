import XCTest
import Foundation
import SettingsCore

final class InputHabitSettingsTests:XCTestCase {
    private func legacy(_ values:[String:Any],revision:UInt64=7)throws->Data {
        let document:[String:Any]=["revision":revision,"values":values]
        let payload=try JSONSerialization.data(withJSONObject:document,options:[.sortedKeys,.withoutEscapingSlashes])
        return try JSONSerialization.data(withJSONObject:["format":"paia.settings.v1","sha256":SettingsCodec.digest(payload),"document":document],options:[.sortedKeys,.withoutEscapingSlashes])
    }
    func testLegacyContractIsVerifiedBeforeMemoryOnlyDefaults()throws {
        for spelling in SettingsSpelling.allCases {
            let bytes=try legacy(["spelling":spelling.rawValue,"traditional":true,"literal":false,"chinesePunctuation":true])
            let restored=try SettingsCodec.decode(bytes)
            XCTAssertEqual(restored.revision,7);XCTAssertEqual(restored.values.spelling,spelling)
            XCTAssertFalse(restored.values.fuzzyInitials);XCTAssertTrue(restored.values.fullPinyinCorrection)
            XCTAssertTrue(restored.values.initialModes.isEmpty)
            let current=try SettingsCodec.encode(restored)
            XCTAssertTrue(String(decoding:current,as:UTF8.self).contains("paia.settings.v2"))
            XCTAssertEqual(try SettingsCodec.decode(current),restored)
            var bad:[String:Any]=["spelling":spelling.rawValue,"traditional":true,"literal":false,"chinesePunctuation":true]
            bad["initialModes"]=["dev.paia.test":"literal"]
            XCTAssertThrowsError(try SettingsCodec.decode(legacy(bad))) // Even a recomputed digest does not extend v1.
        }
    }
    func testIndependentClosedPoliciesAndExactApplicationDefaults()throws {
        for fuzzy in [false,true] {for correction in [false,true] {
            var value=SettingsValues();value.fuzzyInitials=fuzzy;value.fullPinyinCorrection=correction
            value.initialModes=["dev.paia.a":.literal,"dev.paia.B":.chinese];value.literal=true
            let document=SettingsDocument(revision:1,values:value)
            XCTAssertEqual(try SettingsCodec.decode(SettingsCodec.encode(document)),document)
            XCTAssertTrue(value.initialLiteral(for:"dev.paia.a"));XCTAssertFalse(value.initialLiteral(for:"dev.paia.B"))
            XCTAssertTrue(value.initialLiteral(for:"dev.paia.b")) // Identity is not guessed or lowercased.
            XCTAssertTrue(value.initialLiteral(for:nil));XCTAssertTrue(value.initialLiteral(for:"unknown"))
        }}
    }
    func testApplicationPreferenceBoundsAndCanonicalDuplicateRefusal()throws {
        for id in ["",".app","app.","dev..app","dev/app","app_1","应用",String(repeating:"a",count:128),"dev.app\u{0}"] {
            var value=SettingsValues();value.initialModes[id] = .literal
            XCTAssertFalse(ApplicationPreference.validIdentifier(id))
            XCTAssertThrowsError(try SettingsCodec.encode(SettingsDocument(revision:1,values:value)))
        }
        var value=SettingsValues()
        for n in 0..<ApplicationPreference.maximumCount {value.initialModes["dev.paia.app\(n)"] = .literal}
        let valid=try SettingsCodec.encode(SettingsDocument(revision:1,values:value))
        XCTAssertEqual(try SettingsCodec.decode(valid).values,value)
        value.initialModes["dev.paia.overflow"] = .chinese
        XCTAssertThrowsError(try SettingsCodec.encode(SettingsDocument(revision:1,values:value)))
        let text=String(decoding:valid,as:UTF8.self)
        let duplicated=text.replacingOccurrences(of:"\"dev.paia.app0\":\"literal\"",with:"\"dev.paia.app0\":\"literal\",\"dev.paia.app0\":\"literal\"")
        XCTAssertThrowsError(try SettingsCodec.decode(Data(duplicated.utf8)))
    }
    func testLegacyStoreReadDoesNotRewriteAndExplicitSaveMigratesOnce()throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("paia-habits-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:false)
        defer{try? FileManager.default.removeItem(at:root)}
        let bytes=try legacy(["spelling":"flypy","traditional":false,"literal":false,"chinesePunctuation":false])
        let file=root.appendingPathComponent("settings.json")
        try bytes.write(to:file);try Data("paia.settings.v1\n".utf8).write(to:root.appendingPathComponent(".initialized"))
        let store=try SettingsStore(directory:root);let restored=try XCTUnwrap(store.snapshot())
        XCTAssertEqual(try Data(contentsOf:file),bytes)
        var next=restored.values;next.initialModes["dev.paia.explicit"] = .literal;next.fuzzyInitials=true
        XCTAssertEqual(try store.save(next,expectedRevision:7).revision,8);store.close()
        XCTAssertNotEqual(try Data(contentsOf:file),bytes)
        let reopened=try SettingsStore(directory:root);defer{reopened.close()}
        XCTAssertEqual(try reopened.snapshot()?.values,next);XCTAssertEqual(try reopened.snapshot()?.revision,8)
    }
    func testUnconfirmedMigrationUsesSameKnownOutcomeVerification()throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("paia-habits-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:false)
        defer{try? FileManager.default.removeItem(at:root)}
        try legacy(["spelling":"full","traditional":false,"literal":false,"chinesePunctuation":false]).write(to:root.appendingPathComponent("settings.json"))
        try Data("paia.settings.v1\n".utf8).write(to:root.appendingPathComponent(".initialized"))
        let store=try SettingsStore(directory:root,fault:.afterPublication);defer{store.close()}
        var next=try XCTUnwrap(store.snapshot()).values;next.fullPinyinCorrection=false
        XCTAssertThrowsError(try store.save(next,expectedRevision:7));XCTAssertThrowsError(try store.save(next,expectedRevision:7))
        let verified=try store.verifyLastSave();XCTAssertEqual(verified.resolution,.published)
        XCTAssertEqual(verified.document?.revision,8);XCTAssertEqual(verified.document?.values,next)
    }
}
