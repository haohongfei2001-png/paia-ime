import XCTest
import Foundation
import ExpressionCore
import SessionCore

final class ExpressionCoreTests:XCTestCase {
    func testExactBytesProvenanceRevisionDeletionAndNoResurrection()throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("paia-c-"+UUID().uuidString)
        defer{try? FileManager.default.removeItem(at:root)}
        let store=try ExpressionStore(directory:root);defer{store.close()}
        let original=" \r\n否定：不是 42。e\u{301} / é / 𠀀 / 👩🏽‍💻\n最后一句。  "
        let a=try store.saveExact(original,aliases:["fouding","EXACT"],expectedRevision:0,now:1000),record=try XCTUnwrap(a.records.first)
        XCTAssertEqual(record.savedAt,1000);XCTAssertEqual(record.updatedAt,1000);XCTAssertEqual(record.sourceType,"manualSaved")
        let bytes=try ExpressionCodec.encode(a),object=try XCTUnwrap(JSONSerialization.jsonObject(with:bytes) as? [String:Any]),doc=try XCTUnwrap(object["document"] as? [String:Any]),rows=try XCTUnwrap(doc["records"] as? [[String:Any]])
        XCTAssertTrue(rows[0]["sentAt"] is NSNull);XCTAssertTrue(rows[0]["sourceCreatedAt"] is NSNull)
        XCTAssertEqual(try ExpressionCodec.decode(bytes).records[0].exactText?.utf8.map{$0},Array(original.utf8))
        let catalog=ExpressionCatalog(document:a),match=try XCTUnwrap(catalog.search("exact").first)
        XCTAssertEqual(match.record.id,record.id);XCTAssertEqual(catalog.search("does not exist").count,0)
        XCTAssertEqual(catalog.search("fouding").count,1);XCTAssertEqual(catalog.resolve(match.ref)?.exactText?.utf8.map{$0},Array(original.utf8))
        let b=try store.saveExact(original+"修订",aliases:["fouding"],editing:record.id,expectedRecordRevision:record.revision,expectedRevision:1,now:2000)
        XCTAssertEqual(b.records[0].savedAt,1000);XCTAssertEqual(b.records[0].updatedAt,2000)
        XCTAssertNil(ExpressionCatalog(document:b).resolve(match.ref))
        XCTAssertThrowsError(try store.saveExact("stale",aliases:[],editing:record.id,expectedRecordRevision:record.revision,expectedRevision:2,now:2100))
        let c=try store.delete(record.id,expectedRecordRevision:2,expectedRevision:2,now:3000)
        XCTAssertNil(c.records[0].exactText);XCTAssertTrue(c.records[0].aliases.isEmpty);XCTAssertEqual(c.records[0].deletedAt,3000)
        XCTAssertTrue(ExpressionCatalog(document:c).search("").isEmpty)
        XCTAssertThrowsError(try store.saveExact(original,aliases:[],editing:record.id,expectedRecordRevision:3,expectedRevision:3,now:4000))
        let disk=try Data(contentsOf:root.appendingPathComponent("expressions.json"));XCTAssertFalse(String(decoding:disk,as:UTF8.self).contains("否定"))
        store.close();let reopened=try ExpressionStore(directory:root);defer{reopened.close()};XCTAssertEqual(try reopened.snapshot(),c)
    }
    func testCodecRejectsChangedBytesDuplicateUnknownKeysOversizeAndInvalidProvenance()throws {
        let r=ExpressionRecord(id:UUID(),revision:1,recordCreatedAt:1000,savedAt:1000,updatedAt:1000,exactText:"e\u{301}",aliases:[]),d=ExpressionDocument(revision:1,records:[r]),bytes=try ExpressionCodec.encode(d)
        var altered=String(decoding:bytes,as:UTF8.self).replacingOccurrences(of:"e\u{301}",with:"é")
        XCTAssertThrowsError(try ExpressionCodec.decode(Data(altered.utf8)))
        altered=String(decoding:bytes,as:UTF8.self).replacingOccurrences(of:"\"sentAt\":null",with:"\"sentAt\":1000")
        XCTAssertThrowsError(try ExpressionCodec.decode(Data(altered.utf8)))
        altered=String(decoding:bytes,as:UTF8.self).replacingOccurrences(of:"\"sentAt\":null",with:"\"sentAt\":null,\"sentAt\":null")
        XCTAssertThrowsError(try ExpressionCodec.decode(Data(altered.utf8)))
        XCTAssertThrowsError(try ExpressionCodec.decode(Data(("{"+String(repeating:"[",count:13)).utf8)))
        XCTAssertThrowsError(try ExpressionCodec.validate(text:String(repeating:"𠀀",count:8193),aliases:[]))
        XCTAssertThrowsError(try ExpressionCodec.validate(text:"",aliases:[]));XCTAssertThrowsError(try ExpressionCodec.validate(text:"a\0b",aliases:[]))
        XCTAssertThrowsError(try ExpressionCodec.validate(text:"exact",aliases:["bad\nkey"]))
        XCTAssertThrowsError(try ExpressionCodec.encode(ExpressionDocument(revision:1,records:[r,r])))
    }
    func testIdleEffectUsesSameReservationGateAndExactBytePayload()throws {
        var core=SessionCore(dictionaryRevision:"fixture")
        XCTAssertNil(core.idleExpressionBinding);_ = try core.receive(EngineValue(raw:"",preedit:"",caretUTF8:0))
        let binding=try XCTUnwrap(core.idleExpressionBinding),text=" \r\ne\u{301}👩🏽‍💻 42 不变。\n末句。 "
        let effect=try XCTUnwrap(core.commitExpression(text,binding:binding).commit)
        XCTAssertEqual(Array(effect.text.utf8),Array(text.utf8));if case .explicitExpression=effect.origin{}else{XCTFail("wrong origin")}
        XCTAssertThrowsError(try core.commitExpression(text,binding:binding));XCTAssertTrue(core.reserve(effect));XCTAssertFalse(core.reserve(effect))
        XCTAssertThrowsError(try core.commitExpression(text,binding:binding))
        let newer=try XCTUnwrap(core.idleExpressionBinding);core.invalidate();XCTAssertThrowsError(try core.commitExpression(text,binding:newer))
        var composing=SessionCore(dictionaryRevision:"fixture");_ = try composing.receive(EngineValue(raw:"ni",preedit:"你",caretUTF8:2));XCTAssertNil(composing.idleExpressionBinding)
    }
}
