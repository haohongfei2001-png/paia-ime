import XCTest
import Foundation
@testable import LexiconCore

final class LexiconCoreTests:XCTestCase {
    private var roots=[URL]()
    func directory()throws->URL {let p=FileManager.default.temporaryDirectory.appendingPathComponent("paia-b2-test-"+UUID().uuidString);try FileManager.default.createDirectory(at:p,withIntermediateDirectories:true);roots.append(p);return p}
    override func tearDown(){for p in roots{try? FileManager.default.removeItem(at:p)};super.tearDown()}
    func testExplicitTermsIdentityAliasesPinAndReopen()throws {
        let path=try directory(),store=try LexiconStore(directory:path)
        let a=try store.add(surface:"林小棠",reading:"lin  xiao tang",aliases:["lin xiao"],pin:true,expectedRevision:0)
        let b=try store.add(surface:"林小唐",reading:"lin xiao tang",expectedRevision:1)
        XCTAssertNotEqual(a,b);XCTAssertEqual(try store.snapshot().terms.first?.reading,"lin xiao tang")
        XCTAssertThrowsError(try store.edit(id:b,surface:"林小唐",reading:"lin xiao tang",aliases:[],pin:true,expectedRevision:2))
        XCTAssertEqual(try store.snapshot().revision,2)
        try store.edit(id:a,surface:"林小棠",reading:"lin xiao tang",aliases:["lin xiao"],pin:false,expectedRevision:2)
        try store.edit(id:b,surface:"林小唐",reading:"lin xiao tang",aliases:[],pin:true,expectedRevision:3)
        let before=try store.exportData();store.close()
        let reopened=try LexiconStore(directory:path);defer{reopened.close()}
        XCTAssertEqual(try reopened.exportData(),before);XCTAssertEqual(try reopened.snapshot().terms.filter{$0.explicitPin}.map{$0.id},[b])
        XCTAssertThrowsError(try reopened.add(surface:"林小棠",reading:"lin xiao tang",expectedRevision:4))
        _ = try reopened.add(surface:"林小棠",reading:"lin xiao tan",expectedRevision:4) // Surface alone is not identity.
    }
    func testDeletionStaleImportAndExplicitRestore()throws {
        let store=try LexiconStore(directory:directory());defer{store.close()}
        let id=try store.add(surface:"穹海测例【B2甲】",reading:"qiong hai ce li jia",expectedRevision:0)
        let old=try store.exportData();try store.setDeleted(id:id,deleted:true,expectedRevision:1)
        let plan=try store.previewImport(old)
        XCTAssertEqual(plan.protectedDeletions,1);XCTAssertFalse(plan.canApply);try store.applyImport(plan)
        XCTAssertTrue(try store.snapshot().activeTerms.isEmpty);XCTAssertTrue(try store.snapshot().terms[0].noRelearn)
        XCTAssertThrowsError(try store.add(surface:"穹海测例【B2甲】",reading:"qiong hai ce li jia",expectedRevision:2))
        try store.setDeleted(id:id,deleted:false,expectedRevision:2)
        XCTAssertEqual(try store.snapshot().activeTerms.map{$0.id},[id])
    }
    func testImportPreviewByteAndRevisionBinding()throws {
        let a=try LexiconStore(directory:directory()),b=try LexiconStore(directory:directory());defer{a.close();b.close()}
        _ = try a.add(surface:"𠀀e\u{301}👩🏽‍💻",reading:"kuo",expectedRevision:0)
        let data=try a.exportData(),plan=try b.previewImport(data)
        XCTAssertEqual(plan.additions.count,1);XCTAssertTrue(plan.canApply)
        _ = try b.add(surface:"另一词",reading:"ling yi ci",expectedRevision:0)
        XCTAssertThrowsError(try b.applyImport(plan)){XCTAssertEqual($0 as? LexiconError,.stale)}
        let current=try b.previewImport(data);try b.applyImport(current)
        XCTAssertEqual(try b.snapshot().terms.count,2)
        XCTAssertThrowsError(try a.applyImport(current))
        let bytes=try b.exportData();XCTAssertEqual(try LexiconCodec.encode(LexiconCodec.decode(bytes)),bytes)
    }
    func testCorruptUnknownOversizeAndInjectionRejected()throws {
        let store=try LexiconStore(directory:directory());defer{store.close()};let valid=try store.exportData()
        var malformed=[Data("[]".utf8),Data(valid.dropLast()),Data([0xff]),Data(repeating:32,count:LexiconRules.maximumBytes+1)]
        malformed.append(Data((String(repeating:"[",count:9)+String(repeating:"]",count:9)).utf8))
        var root=try XCTUnwrap(JSONSerialization.jsonObject(with:valid) as? [String:Any]);root["script"]="do not execute"
        malformed.append(try JSONSerialization.data(withJSONObject:root))
        malformed.append(Data((" "+String(decoding:valid,as:UTF8.self)).utf8))
        for data in malformed {XCTAssertThrowsError(try store.previewImport(data))}
        for surface in ["bad\trow","bad\nrow","\0","# comment","x\u{202e}y"] {XCTAssertThrowsError(try store.add(surface:surface,reading:"ni",expectedRevision:0))}
        for reading in ["NI","ni\nhao","ni:hao","ni/hao","ni'hao","regex.*"] {XCTAssertThrowsError(try store.add(surface:"你好",reading:reading,expectedRevision:0))}
        XCTAssertEqual(try store.exportData(),valid)
    }
    func testSingleWriterAndOwnedSymlinkRefusal()throws {
        let path=try directory(),first=try LexiconStore(directory:path);defer{first.close()}
        XCTAssertThrowsError(try LexiconStore(directory:path)){XCTAssertEqual($0 as? LexiconError,.busy)}
        let bad=try directory(),outside=try directory().appendingPathComponent("outside.json")
        try Data("untouched".utf8).write(to:outside)
        try FileManager.default.createSymbolicLink(at:bad.appendingPathComponent("lexicon.json"),withDestinationURL:outside)
        XCTAssertThrowsError(try LexiconStore(directory:bad))
        XCTAssertEqual(try Data(contentsOf:outside),Data("untouched".utf8))
    }
    func testAtomicFailureAndUncertainPublicationAreNotRetried()throws {
        let path=try directory(),first=try LexiconStore(directory:path);let old=try first.exportData();first.close()
        let failed=try LexiconStore(directory:path,fault:.beforePublication)
        XCTAssertThrowsError(try failed.add(surface:"失败词",reading:"shi bai ci",expectedRevision:0))
        XCTAssertEqual(try failed.exportData(),old);failed.close()
        let uncertain=try LexiconStore(directory:path,fault:.afterPublication)
        XCTAssertThrowsError(try uncertain.add(surface:"已发布待核",reading:"yi fa bu dai he",expectedRevision:0)){XCTAssertEqual($0 as? LexiconError,.durabilityUnknown)}
        XCTAssertThrowsError(try uncertain.snapshot());XCTAssertThrowsError(try uncertain.add(surface:"不得重试",reading:"bu de chong shi",expectedRevision:0));uncertain.close()
        let reopened=try LexiconStore(directory:path);defer{reopened.close()}
        XCTAssertEqual(try reopened.snapshot().activeTerms.map{$0.surface},["已发布待核"])
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath:path.path).contains{$0.hasPrefix(".staging-")})
    }
    func testCorruptAuthorityIsNeverReplacedByOldBackup()throws {
        let path=try directory(),store=try LexiconStore(directory:path)
        let id=try store.add(surface:"不得复活",reading:"bu de fu huo",expectedRevision:0)
        let old=try store.exportData();try store.setDeleted(id:id,deleted:true,expectedRevision:1);store.close()
        try old.write(to:path.appendingPathComponent("lexicon.previous.json"))
        let broken=Data("corrupt-current-authority".utf8);try broken.write(to:path.appendingPathComponent("lexicon.json"))
        XCTAssertThrowsError(try LexiconStore(directory:path))
        XCTAssertEqual(try Data(contentsOf:path.appendingPathComponent("lexicon.json")),broken)
    }
}
