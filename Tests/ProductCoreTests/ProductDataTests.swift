import XCTest
import Foundation
import Darwin
import ResourceCore
import SettingsCore
@testable import LexiconCore
import ExpressionCore

// SIMULATED authored filesystem authorities. No engine, real HOME or installed service.
final class ProductDataTests:XCTestCase {
    func parent()throws->URL {
        let root=FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("paia-product-test-"+UUID().uuidString.lowercased())
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
        addTeardownBlock{try? FileManager.default.removeItem(at:root)}
        // Darwin's physical spelling, not Foundation's /private path aliases.
        guard let physical=realpath(root.path,nil) else{throw ResourceError.io};defer{free(physical)}
        let result=URL(fileURLWithPath:String(cString:physical),isDirectory:true)
        print("PRODUCT_TEST_PARENT physical=\(result.path) standardized=\(result.standardizedFileURL.path)")
        return result
    }
    func settings(_ root:ProductDataRoot)throws->SettingsStore {
        let slot=try root.slot(.settings)
        return try slot.withDescriptor{try SettingsStore(directory:slot.directory,preopenedDirectory:$0,allowCreateLock:root.createdThisLaunch,authorityGuard:{try slot.verify()})}
    }
    func personal(_ root:ProductDataRoot)throws->LexiconStore {
        let slot=try root.slot(.personal)
        return try slot.withDescriptor{try LexiconStore(directory:slot.directory,preopenedDirectory:$0,allowCreateLock:root.createdThisLaunch,authorityGuard:{try slot.verify()})}
    }
    func expressions(_ root:ProductDataRoot)throws->ExpressionStore {
        let slot=try root.slot(.expressions)
        return try slot.withDescriptor{try ExpressionStore(directory:slot.directory,preopenedDirectory:$0,allowCreateLock:root.createdThisLaunch,authorityGuard:{try slot.verify()})}
    }
    func testPrivateAtomicLayoutAndCloseOnExecDescriptors()throws {
        let parent=try parent(),root=try ProductDataRoot(parent:parent,create:true);defer{root.close()}
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath:root.directory.path).sorted(),[".layout",".product.lock","expressions","personal","settings"])
        let stores=(try settings(root),try personal(root),try expressions(root));defer{stores.0.close();stores.1.close();stores.2.close()}
        for slot in ProductDataRoot.Slot.allCases {
            let selected=try root.slot(slot)
            XCTAssertEqual((try FileManager.default.attributesOfItem(atPath:selected.directory.path)[.posixPermissions] as? NSNumber)?.intValue,0o700)
            try selected.withDescriptor{XCTAssertNotEqual(fcntl($0,F_GETFD)&FD_CLOEXEC,0)}
        }
        var found=0
        for fd:Int32 in 3..<1024 {
            var path=[CChar](repeating:0,count:Int(MAXPATHLEN))
            if fcntl(fd,F_GETPATH,&path)==0,String(cString:path).hasPrefix(root.directory.path) {
                XCTAssertNotEqual(fcntl(fd,F_GETFD)&FD_CLOEXEC,0,"Owned data FD must not reach the resource helper");found+=1
            }
        }
        XCTAssertGreaterThanOrEqual(found,7)
        XCTAssertNil(try stores.0.snapshot());XCTAssertTrue(try stores.1.snapshot().terms.isEmpty);XCTAssertNil(try stores.2.snapshot())
    }
    func testThreeExistingFormatsPersistWithoutImplicitReplacement()throws {
        let parent=try parent(),root=try ProductDataRoot(parent:parent,create:true)
        let s=try settings(root),p=try personal(root),e=try expressions(root)
        var preferences=SettingsValues();preferences.fuzzyInitials=true;preferences.initialModes=["dev.paia.authored":.literal]
        _ = try s.save(preferences,expectedRevision:0)
        let term=try p.add(surface:"自主样本",reading:"zi zhu yang ben",expectedRevision:0)
        _ = try e.saveExact("原话尾段👩🏽‍💻e\u{301}",aliases:["own"],expectedRevision:0)
        let old=[s.directory.appendingPathComponent("settings.json"),p.directory.appendingPathComponent("lexicon.json"),e.directory.appendingPathComponent("expressions.json")]
        let bytes=try old.map{try Data(contentsOf:$0)}
        s.close();p.close();e.close();root.close()
        let second=try ProductDataRoot(parent:parent,create:false),s2=try settings(second),p2=try personal(second),e2=try expressions(second)
        XCTAssertEqual(try s2.snapshot()?.values,preferences);XCTAssertEqual(try p2.snapshot().terms.first?.id,term)
        XCTAssertEqual(try e2.snapshot()?.records.first?.exactText,"原话尾段👩🏽‍💻e\u{301}")
        XCTAssertEqual(try old.map{try Data(contentsOf:$0)},bytes)
        try p2.setDeleted(id:term,deleted:true,expectedRevision:1)
        s2.close();p2.close();e2.close();second.close()
        let third=try ProductDataRoot(parent:parent,create:false),p3=try personal(third);defer{p3.close();third.close()}
        XCTAssertTrue(try XCTUnwrap(p3.snapshot().terms.first).isDeleted)
        XCTAssertThrowsError(try p3.add(surface:"自主样本",reading:"zi zhu yang ben",expectedRevision:2))
    }
    func testMissingOrRebuiltEmptySlotIsNotReinitialized()throws {
        for replace in [false,true] {
            let parent=try parent(),root=try ProductDataRoot(parent:parent,create:true),path=try root.slot(.personal).directory
            let s=try settings(root);_ = try s.save(SettingsValues(),expectedRevision:0);s.close();root.close()
            try FileManager.default.removeItem(at:path)
            if replace{try FileManager.default.createDirectory(at:path,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])}
            let reopened=try ProductDataRoot(parent:parent,create:false);defer{reopened.close()}
            XCTAssertThrowsError(try reopened.slot(.personal))
            let available=try settings(reopened);defer{available.close()};XCTAssertEqual(try available.snapshot()?.revision,1)
            XCTAssertEqual(FileManager.default.fileExists(atPath:path.path),replace)
            if replace{XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath:path.path).isEmpty)}
        }
    }
    func testForeignSlotNonceAndOtherSlotMarkerAreRefused()throws {
        let one=try ProductDataRoot(parent:parent(),create:true),two=try ProductDataRoot(parent:parent(),create:true);defer{one.close();two.close()}
        let slot=try one.slot(.personal),foreign=try two.slot(.personal)
        let other=try one.slot(.settings),destination=slot.directory.appendingPathComponent(".slot")
        for source in [foreign.directory,other.directory] {
            try Data(contentsOf:source.appendingPathComponent(".slot")).write(to:destination)
            XCTAssertThrowsError(try slot.verify());XCTAssertThrowsError(try one.slot(.personal));XCTAssertNoThrow(try one.slot(.settings))
        }
    }
    func testSecondWriterAndRemovedGlobalLockFailClosed()throws {
        let parent=try parent(),root=try ProductDataRoot(parent:parent,create:true);defer{root.close()}
        XCTAssertThrowsError(try ProductDataRoot(parent:parent,create:false))
        let lock=root.directory.appendingPathComponent(".product.lock");try FileManager.default.removeItem(at:lock)
        XCTAssertThrowsError(try root.verify());XCTAssertThrowsError(try ProductDataRoot(parent:parent,create:true))
        XCTAssertFalse(FileManager.default.fileExists(atPath:lock.path))
    }
    func testUnknownRootPermissionsAndAncestorSymlinksAreNotAdopted()throws {
        let parent=try parent(),unknown=parent.appendingPathComponent(ProductDataRoot.leaf)
        try FileManager.default.createDirectory(at:unknown,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
        let sentinel=unknown.appendingPathComponent("untouched");try Data("authored existing file".utf8).write(to:sentinel)
        XCTAssertThrowsError(try ProductDataRoot(parent:parent,create:true));XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath:unknown.path),["untouched"])
        let real=try self.parent(),outer=try self.parent(),alias=outer.appendingPathComponent("alias")
        try FileManager.default.createSymbolicLink(at:alias,withDestinationURL:real)
        XCTAssertThrowsError(try ProductDataRoot(parent:alias,create:true));XCTAssertFalse(FileManager.default.fileExists(atPath:real.appendingPathComponent(ProductDataRoot.leaf).path))
        try FileManager.default.setAttributes([.posixPermissions:0o777],ofItemAtPath:real.path)
        XCTAssertThrowsError(try ProductDataRoot(parent:real,create:true))
        XCTAssertEqual((try FileManager.default.attributesOfItem(atPath:real.path)[.posixPermissions] as? NSNumber)?.intValue,0o777)
    }
    func testDescriptorMismatchAndRootReplacementNeverCreateForeignAuthority()throws {
        let parent=try parent(),root=try ProductDataRoot(parent:parent,create:true),slot=try root.slot(.settings),foreign=try self.parent();defer{root.close()}
        try slot.withDescriptor {fd in
            XCTAssertThrowsError(try SettingsStore(directory:foreign,preopenedDirectory:fd,authorityGuard:{try slot.verify()}))
            XCTAssertThrowsError(try LexiconStore(directory:foreign,preopenedDirectory:fd,authorityGuard:{try slot.verify()}))
            XCTAssertThrowsError(try ExpressionStore(directory:foreign,preopenedDirectory:fd,authorityGuard:{try slot.verify()}))
        }
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath:foreign.path).isEmpty)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath:slot.directory.path),[".slot"])
        let moved=parent.appendingPathComponent("moved");try FileManager.default.moveItem(at:root.directory,to:moved)
        try FileManager.default.createSymbolicLink(at:root.directory,withDestinationURL:moved)
        XCTAssertThrowsError(try slot.withDescriptor{try SettingsStore(directory:slot.directory,preopenedDirectory:$0,allowCreateLock:root.createdThisLaunch,authorityGuard:{try slot.verify()})})
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath:moved.appendingPathComponent("settings").path),[".slot"])
    }
    func testPostPublicationGuardFailureKeepsUnknownSaveUntilExplicitVerify()throws {
        let root=try ProductDataRoot(parent:parent(),create:true),slot=try root.slot(.settings);defer{root.close()}
        var reject=true
        let file=slot.directory.appendingPathComponent("settings.json")
        let store=try slot.withDescriptor {fd in
            try SettingsStore(directory:slot.directory,preopenedDirectory:fd,authorityGuard:{
                try slot.verify();if reject && FileManager.default.fileExists(atPath:file.path){throw ResourceError.stale}
            })
        };defer{store.close()}
        XCTAssertThrowsError(try store.save(SettingsValues(),expectedRevision:0));XCTAssertTrue(store.hasUnverifiedSave)
        let published=try Data(contentsOf:file);reject=false
        XCTAssertThrowsError(try store.snapshot());XCTAssertThrowsError(try store.save(SettingsValues(),expectedRevision:0))
        XCTAssertEqual(try store.verifyLastSave().resolution,.published);XCTAssertEqual(try store.snapshot()?.revision,1)
        XCTAssertEqual(try Data(contentsOf:file),published)
    }
    func testUnknownRootPublicationRequiresSuccessfulReopenBarriers()throws {
        // Injected startup failure, not evidence of a physical disk fault.
        let parent=try parent(),path=parent.appendingPathComponent(ProductDataRoot.leaf)
        XCTAssertThrowsError(try ProductDataRoot(parent:parent,create:true,fault:.afterPublication))
        let marker=try Data(contentsOf:path.appendingPathComponent(".layout"))
        XCTAssertThrowsError(try ProductDataRoot(parent:parent,create:false,fault:.readySyncFailure))
        XCTAssertEqual(try Data(contentsOf:path.appendingPathComponent(".layout")),marker)
        let root=try ProductDataRoot(parent:parent,create:false);defer{root.close()}
        XCTAssertNoThrow(try root.verify());XCTAssertEqual(try Data(contentsOf:path.appendingPathComponent(".layout")),marker)
        for slot in ProductDataRoot.Slot.allCases{XCTAssertNoThrow(try root.slot(slot))}
    }
    func testEstablishedSlotLosingAllStoreFilesCannotBecomeFresh()throws {
        for kind in ProductDataRoot.Slot.allCases {for eraseAll in [false,true] {
            let parent=try parent(),root=try ProductDataRoot(parent:parent,create:true)
            XCTAssertTrue(root.createdThisLaunch)
            let s=try settings(root),p=try personal(root),e=try expressions(root)
            _=try s.save(SettingsValues(),expectedRevision:0)
            _=try p.add(surface:"保留词条",reading:"bao liu ci tiao",expectedRevision:0)
            _=try e.saveExact("保留原话",aliases:[],expectedRevision:0)
            s.close();p.close();e.close();root.close()
            let path=root.directory.appendingPathComponent(kind.rawValue)
            let marker=try Data(contentsOf:path.appendingPathComponent(".slot"))
            for name in try FileManager.default.contentsOfDirectory(atPath:path.path) where name != ".slot" && (eraseAll || name==".writer.lock") {
                try FileManager.default.removeItem(at:path.appendingPathComponent(name))
            }
            let remaining=try FileManager.default.contentsOfDirectory(atPath:path.path).sorted()
            let reopened=try ProductDataRoot(parent:parent,create:true);defer{reopened.close()}
            XCTAssertFalse(reopened.createdThisLaunch)
            switch kind {
            case .settings:XCTAssertThrowsError(try settings(reopened))
            case .personal:XCTAssertThrowsError(try personal(reopened))
            case .expressions:XCTAssertThrowsError(try expressions(reopened))
            }
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath:path.path).sorted(),remaining)
            XCTAssertEqual(try Data(contentsOf:path.appendingPathComponent(".slot")),marker)
            if kind != .settings{let value=try settings(reopened);XCTAssertEqual(try value.snapshot()?.revision,1);value.close()}
            if kind != .personal{let value=try personal(reopened);XCTAssertEqual(try value.snapshot().activeTerms.count,1);value.close()}
            if kind != .expressions{let value=try expressions(reopened);XCTAssertEqual(try value.snapshot()?.records.first?.exactText,"保留原话");value.close()}
        }}
        // Empty settings/expressions are legitimate until their first explicit
        // Save, but an established product root still needs its original locks.
        let parent=try parent(),root=try ProductDataRoot(parent:parent,create:true)
        let s=try settings(root),e=try expressions(root);s.close();e.close();root.close()
        let reopened=try ProductDataRoot(parent:parent,create:true),s2=try settings(reopened),e2=try expressions(reopened)
        defer{s2.close();e2.close();reopened.close()}
        XCTAssertNil(try s2.snapshot());XCTAssertNil(try e2.snapshot())
    }
    func testPersonalAuthorityReplacedDuringReadCannotReturnOldSnapshot()throws {
        let root=try ProductDataRoot(parent:parent(),create:true),store=try personal(root);defer{store.close();root.close()}
        _=try store.add(surface:"显式样例",reading:"xian shi yang li",expectedRevision:0)
        let before=try store.exportData(),file=store.directory.appendingPathComponent("lexicon.json")
        var triggered=false
        store.afterReadBeforeVerification={name in
            guard name=="lexicon.json",!triggered else{return};triggered=true
            // Same valid bytes, different inode: a read must not acknowledge the
            // old descriptor after the authority name has already been replaced.
            try before.write(to:file,options:.atomic)
        }
        XCTAssertThrowsError(try store.exportData());XCTAssertTrue(triggered)
        XCTAssertEqual(try Data(contentsOf:file),before)
    }
}
