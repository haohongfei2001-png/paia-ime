import XCTest
import Foundation
import Darwin
import SettingsCore

final class SettingsCoreTests:XCTestCase {
    private var roots=[URL]()
    func directory()throws->URL {let root=FileManager.default.temporaryDirectory.appendingPathComponent("paia-b3-test-"+UUID().uuidString);try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true);roots.append(root);return root}
    override func tearDown(){for root in roots{try? FileManager.default.removeItem(at:root)};super.tearDown()}
    func testAll24ClosedPreferencesAndNoTextFields()throws {
        var count=0
        for spelling in SettingsSpelling.allCases {for traditional in [false,true]{for literal in [false,true]{for punctuation in [false,true]{
            var value=SettingsValues();value.spelling=spelling;value.traditional=traditional;value.literal=literal;value.chinesePunctuation=punctuation
            let document=SettingsDocument(revision:1,values:value),bytes=try SettingsCodec.encode(document)
            XCTAssertEqual(try SettingsCodec.decode(bytes),document)
            let envelope=try XCTUnwrap(JSONSerialization.jsonObject(with:bytes) as? [String:Any]),body=try XCTUnwrap(envelope["document"] as? [String:Any]),fields=try XCTUnwrap(body["values"] as? [String:Any])
            XCTAssertEqual(Set(fields.keys),Set(["spelling","traditional","literal","chinesePunctuation"]))
            count+=1
        }}}};XCTAssertEqual(count,24)
    }
    func testUnknownTypeVersionDigestDepthAndOversizeFailClosed()throws {
        let valid=try SettingsCodec.encode(SettingsDocument(revision:1,values:SettingsValues())),text=String(decoding:valid,as:UTF8.self)
        let bad=[Data(),Data([255]),Data(valid.dropLast()),Data(repeating:32,count:SettingsCodec.maximumBytes+1),Data((String(repeating:"[",count:9)+String(repeating:"]",count:9)).utf8),Data((" "+text).utf8),Data(text.replacingOccurrences(of:"paia.settings.v1",with:"paia.settings.v2").utf8),Data(text.replacingOccurrences(of:"full",with:"untrusted-schema").utf8),Data(text.replacingOccurrences(of:"false",with:"0").utf8),Data(text.replacingOccurrences(of:"\"document\":",with:"\"body\":\"never record\",\"document\":").utf8)]
        for bytes in bad{XCTAssertThrowsError(try SettingsCodec.decode(bytes))}
    }
    func testExplicitSaveReopenAndNoImplicitInitializationRecord()throws {
        let path=try directory(),first=try SettingsStore(directory:path)
        XCTAssertNil(try first.snapshot());XCTAssertFalse(FileManager.default.fileExists(atPath:path.appendingPathComponent("settings.json").path));first.close()
        let store=try SettingsStore(directory:path);var value=SettingsValues();value.spelling = .flypy;value.literal=true
        _ = try store.save(value,expectedRevision:0);let before=try Data(contentsOf:path.appendingPathComponent("settings.json"));store.close()
        let reopened=try SettingsStore(directory:path);defer{reopened.close()};XCTAssertEqual(try reopened.snapshot()?.values,value)
        XCTAssertEqual(try Data(contentsOf:path.appendingPathComponent("settings.json")),before)
        XCTAssertThrowsError(try reopened.save(SettingsValues(),expectedRevision:0))
    }
    func testSingleWriterAndSpecialFilesRefused()throws {
        let path=try directory(),store=try SettingsStore(directory:path);defer{store.close()}
        XCTAssertThrowsError(try SettingsStore(directory:path))
        for kind in ["symlink","hardlink","fifo"] {
            let root=try directory(),file=root.appendingPathComponent("settings.json"),outside=try directory().appendingPathComponent("outside")
            try Data("untouched".utf8).write(to:outside)
            if kind=="symlink"{try FileManager.default.createSymbolicLink(at:file,withDestinationURL:outside)}
            else if kind=="hardlink"{try FileManager.default.linkItem(at:outside,to:file)}else{XCTAssertEqual(mkfifo(file.path,0o600),0)}
            XCTAssertThrowsError(try SettingsStore(directory:root));XCTAssertEqual(try Data(contentsOf:outside),Data("untouched".utf8))
        }
    }
    func testExternalAuthorityChangesAndMissingInitializedFileRefused()throws {
        let path=try directory(),store=try SettingsStore(directory:path);_ = try store.save(SettingsValues(),expectedRevision:0)
        try Data("corrupt".utf8).write(to:path.appendingPathComponent("settings.json"))
        XCTAssertThrowsError(try store.snapshot());XCTAssertThrowsError(try store.save(SettingsValues(),expectedRevision:1));store.close()
        XCTAssertThrowsError(try SettingsStore(directory:path))
        try FileManager.default.removeItem(at:path.appendingPathComponent("settings.json"));XCTAssertThrowsError(try SettingsStore(directory:path))
        XCTAssertFalse(FileManager.default.fileExists(atPath:path.appendingPathComponent("settings.json").path))
    }
    func testFailureBeforeAndAfterPublicationDoesNotRetry()throws {
        let path=try directory(),seed=try SettingsStore(directory:path);_ = try seed.save(SettingsValues(),expectedRevision:0);seed.close()
        let before=try Data(contentsOf:path.appendingPathComponent("settings.json")),pre=try SettingsStore(directory:path,fault:.beforePublication)
        var value=SettingsValues();value.traditional=true
        XCTAssertThrowsError(try pre.save(value,expectedRevision:1));XCTAssertEqual(try Data(contentsOf:path.appendingPathComponent("settings.json")),before);pre.close()
        let post=try SettingsStore(directory:path,fault:.afterPublication)
        XCTAssertThrowsError(try post.save(value,expectedRevision:1));XCTAssertThrowsError(try post.snapshot());XCTAssertThrowsError(try post.save(value,expectedRevision:1));post.close()
        let verified=try SettingsStore(directory:path);defer{verified.close()};XCTAssertEqual(try verified.snapshot()?.revision,2);XCTAssertEqual(try verified.snapshot()?.values,value)
    }
}
