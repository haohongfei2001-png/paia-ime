#if os(macOS)
import XCTest
import Foundation
import Darwin
import ResourceCore
import SettingsCore
import LexiconCore
import ExpressionCore
import EngineBridge
@testable import IMKHost

// SIMULATED authored stores only. No app, engine, HOME or installed profile.
final class ExistingProductLeaseTests:XCTestCase {
    func parent()throws->URL {
        let value=FileManager.default.temporaryDirectory.appendingPathComponent("paia-release-test-"+UUID().uuidString.lowercased())
        try FileManager.default.createDirectory(at:value,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
        guard let physical=realpath(value.path,nil) else{throw ResourceError.io};defer{free(physical)}
        let result=URL(fileURLWithPath:String(cString:physical));addTeardownBlock{try? FileManager.default.removeItem(at:result)};return result
    }
    func tree(_ directory:URL)throws->[String:Data] {
        var result=[String:Data]()
        func walk(_ path:URL,_ relative:String)throws {
            var info=stat();guard lstat(path.path,&info)==0 else{throw ResourceError.io}
            result[relative+"#identity"]=Data("\(info.st_dev):\(info.st_ino):\(info.st_mode):\(info.st_nlink)".utf8)
            if (info.st_mode&S_IFMT)==S_IFDIR {
                for name in try FileManager.default.contentsOfDirectory(atPath:path.path).sorted(){try walk(path.appendingPathComponent(name),relative+"/"+name)}
            } else if (info.st_mode&S_IFMT)==S_IFLNK {result[relative]=Data(try FileManager.default.destinationOfSymbolicLink(atPath:path.path).utf8)}
            else {result[relative]=try Data(contentsOf:path)}
        }
        try walk(directory,"");return result
    }
    @MainActor func seed(_ parent:URL,saved:Bool=true)throws {
        let stores=ProductStores(parent:parent);defer{stores.close()}
        XCTAssertTrue(stores.unavailable.isEmpty)
        if saved {
            _=try XCTUnwrap(stores.settings).save(SettingsValues(),expectedRevision:0)
            _=try XCTUnwrap(stores.personal).add(surface:"兼容样本",reading:"jian rong yang ben",expectedRevision:0)
            _=try XCTUnwrap(stores.expressions).saveExact("完整原话👩🏽‍💻",aliases:["sample"],expectedRevision:0)
        }
    }
    @MainActor func testMissingRootIsNotCreatedAndLegitimateEmptyStoresRemainEmpty()throws {
        let parent=try parent(),empty=try tree(parent)
        XCTAssertThrowsError(try ExistingProductLease(parent:parent));XCTAssertEqual(try tree(parent),empty)
        try seed(parent,saved:false);let before=try tree(parent),lease=try ExistingProductLease(parent:parent)
        let bytes=try lease.bytes();XCTAssertNil(bytes.settings);XCTAssertNil(bytes.expressions)
        XCTAssertEqual(try LexiconCodec.decode(bytes.personal).revision,0);lease.close()
        XCTAssertEqual(try tree(parent),before);XCTAssertEqual(RimeRuntime.startupAttempts,0)
    }
    @MainActor func testExistingAllStoreLeaseRefusesCompetingWriterAndPreservesBytes()throws {
        let parent=try parent();try seed(parent);let before=try tree(parent)
        let lease=try ExistingProductLease(parent:parent);XCTAssertEqual(try SettingsCodec.decode(XCTUnwrap(lease.bytes().settings)).revision,1)
        XCTAssertThrowsError(try ExistingProductLease(parent:parent));XCTAssertEqual(try tree(parent),before)
        lease.close();let next=try ExistingProductLease(parent:parent);next.close();XCTAssertEqual(try tree(parent),before)
    }
    func testExistingOnlyLexiconNeverInitializesEmptyAuthority()throws {
        let directory=try parent(),path=directory.appendingPathComponent(".writer.lock")
        XCTAssertTrue(FileManager.default.createFile(atPath:path.path,contents:Data(),attributes:[.posixPermissions:0o600]))
        let before=try tree(directory)
        XCTAssertThrowsError(try LexiconStore(directory:directory,allowCreateLock:false))
        XCTAssertEqual(try tree(directory),before)
    }
    @MainActor func testMissingMarkersLocksAndFutureFormatsNeverBecomeFreshAuthority()throws {
        for kind in ["slot","root-lock","settings-lock","personal-marker","expression-marker","future-settings","future-personal","future-expressions"] {
            let parent=try parent();try seed(parent);let root=parent.appendingPathComponent(ProductDataRoot.leaf)
            let removals=["slot":"settings/.slot","root-lock":".product.lock","settings-lock":"settings/.writer.lock","personal-marker":"personal/.initialized","expression-marker":"expressions/.initialized"]
            if let path=removals[kind] {try FileManager.default.removeItem(at:root.appendingPathComponent(path))}
            else {
                let path=kind=="future-settings" ? "settings/settings.json":kind=="future-personal" ? "personal/lexicon.json":"expressions/expressions.json"
                let file=root.appendingPathComponent(path),original=try Data(contentsOf:file)
                var object=try XCTUnwrap(JSONSerialization.jsonObject(with:original) as? [String:Any]);object["format"]="paia.authored.future.v99"
                try JSONSerialization.data(withJSONObject:object,options:[.sortedKeys,.withoutEscapingSlashes]).write(to:file)
            }
            let before=try tree(parent);XCTAssertThrowsError(try ExistingProductLease(parent:parent));XCTAssertEqual(try tree(parent),before)
        }
        XCTAssertEqual(RimeRuntime.startupAttempts,0)
    }
    @MainActor func testLegacySettingsInspectionPreservesOriginalEnvelopeUntilExplicitSave()throws {
        let parent=try parent();try seed(parent)
        let document:[String:Any]=["revision":7,"values":["spelling":"flypy","traditional":true,"literal":false,"chinesePunctuation":true]]
        let payload=try JSONSerialization.data(withJSONObject:document,options:[.sortedKeys,.withoutEscapingSlashes])
        let bytes=try JSONSerialization.data(withJSONObject:["format":"paia.settings.v1","sha256":SettingsCodec.digest(payload),"document":document],options:[.sortedKeys,.withoutEscapingSlashes])
        let path=parent.appendingPathComponent(ProductDataRoot.leaf+"/settings/settings.json");try bytes.write(to:path)
        let before=try tree(parent),lease=try ExistingProductLease(parent:parent)
        XCTAssertEqual(try lease.bytes().settings,bytes);XCTAssertEqual(try lease.settings.snapshot()?.revision,7)
        XCTAssertEqual(try tree(parent),before)
        let values=try XCTUnwrap(lease.settings.snapshot()?.values);_=try lease.settings.save(values,expectedRevision:7)
        let current=try XCTUnwrap(lease.settings.exportData());XCTAssertNotEqual(current,bytes)
        XCTAssertEqual(try SettingsCodec.decode(current).revision,8)
        let header=try XCTUnwrap(JSONSerialization.jsonObject(with:current) as? [String:Any]);XCTAssertEqual(header["format"] as? String,"paia.settings.v2")
        lease.close();let reopened=try ExistingProductLease(parent:parent);defer{reopened.close()};XCTAssertEqual(try reopened.bytes().settings,current)
    }
    @MainActor func testInterruptedSavesPreservePreviousOrPublishedOutcomesWithoutAutomaticRetry()throws {
        for (fault,expected) in [(SettingsTestFault.beforePublication,UInt64(1)),(.afterPublication,UInt64(2))] {
            let parent=try parent();try seed(parent)
            let root=try ProductDataRoot(parent:parent,create:false),slot=try root.slot(.settings)
            let store=try slot.withDescriptor{try SettingsStore(directory:slot.directory,fault:fault,preopenedDirectory:$0,allowCreateLock:false,authorityGuard:{try slot.verify()})}
            var values=SettingsValues();values.traditional=true
            XCTAssertThrowsError(try store.save(values,expectedRevision:1));XCTAssertThrowsError(try store.exportData())
            store.close();root.close();let afterFault=try tree(parent)
            let lease=try ExistingProductLease(parent:parent);XCTAssertEqual(try lease.settings.snapshot()?.revision,expected)
            XCTAssertEqual(try lease.settings.snapshot()?.values.traditional,expected==2);lease.close();XCTAssertEqual(try tree(parent),afterFault)
        }
        let parent=try parent();try seed(parent,saved:false)
        let root=try ProductDataRoot(parent:parent,create:false),slot=try root.slot(.settings)
        let store=try slot.withDescriptor{try SettingsStore(directory:slot.directory,fault:.afterInitialization,preopenedDirectory:$0,allowCreateLock:false,authorityGuard:{try slot.verify()})}
        XCTAssertThrowsError(try store.save(SettingsValues(),expectedRevision:0));store.close();root.close()
        let before=try tree(parent);XCTAssertThrowsError(try ExistingProductLease(parent:parent));XCTAssertEqual(try tree(parent),before)
    }
}
#endif
