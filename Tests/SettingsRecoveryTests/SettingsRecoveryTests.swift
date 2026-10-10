import XCTest
import Foundation
import Darwin
import SettingsCore

final class SettingsRecoveryTests:XCTestCase {
    private var roots=[URL]()
    func directory()throws->URL {let root=FileManager.default.temporaryDirectory.appendingPathComponent("paia-b5-test-"+UUID().uuidString);try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true);roots.append(root);return root}
    override func tearDown(){for root in roots{try? FileManager.default.removeItem(at:root)};super.tearDown()}
    func changed()->SettingsValues{var value=SettingsValues();value.traditional=true;value.spelling = .flypy;return value}
    func seed(_ root:URL)throws {let store=try SettingsStore(directory:root);defer{store.close()};_ = try store.save(SettingsValues(),expectedRevision:0)}
    func inventory(_ root:URL)throws->[String:Data] {try Dictionary(uniqueKeysWithValues:FileManager.default.contentsOfDirectory(atPath:root.path).map{($0,try Data(contentsOf:root.appendingPathComponent($0)))})}
    func testHealthyOrRejectedSaveHasNoVerifiableAttempt()throws {
        let root=try directory(),store=try SettingsStore(directory:root);defer{store.close()}
        XCTAssertFalse(store.hasUnverifiedSave);XCTAssertThrowsError(try store.verifyLastSave())
        XCTAssertThrowsError(try store.save(changed(),expectedRevision:9));XCTAssertFalse(store.hasUnverifiedSave)
        _ = try store.save(SettingsValues(),expectedRevision:0);let before=try inventory(root)
        XCTAssertFalse(store.hasUnverifiedSave);XCTAssertThrowsError(try store.verifyLastSave());XCTAssertEqual(try inventory(root),before)
    }
    func testPreviousEmptyAndExistingStatesResolveWithoutWriting()throws {
        for existing in [false,true] {
            let root=try directory();if existing{try seed(root)}
            let store=try SettingsStore(directory:root,fault:.beforePublication);defer{store.close()}
            let before=try inventory(root),revision:UInt64=existing ? 1:0
            XCTAssertThrowsError(try store.save(changed(),expectedRevision:revision));XCTAssertTrue(store.hasUnverifiedSave)
            XCTAssertThrowsError(try store.save(changed(),expectedRevision:revision));XCTAssertEqual(try inventory(root),before)
            let result=try store.verifyLastSave();XCTAssertEqual(result.resolution,.previous);XCTAssertEqual(result.document?.revision,existing ? 1:nil)
            XCTAssertFalse(store.hasUnverifiedSave);XCTAssertEqual(try inventory(root),before);XCTAssertThrowsError(try store.verifyLastSave())
            let next=try store.save(changed(),expectedRevision:revision);XCTAssertEqual(next.revision,revision+1);XCTAssertEqual(next.values,changed())
        }
    }
    func testPublishedFirstAndLaterAttemptsResolveKnownEnvelopeOnly()throws {
        for existing in [false,true] {
            let root=try directory();if existing{try seed(root)}
            let store=try SettingsStore(directory:root,fault:.afterPublication);defer{store.close()};let revision:UInt64=existing ? 1:0
            XCTAssertThrowsError(try store.save(changed(),expectedRevision:revision));XCTAssertThrowsError(try store.snapshot())
            let before=try inventory(root),result=try store.verifyLastSave()
            XCTAssertEqual(result.resolution,.published);XCTAssertEqual(result.document?.revision,revision+1);XCTAssertEqual(result.document?.values,changed())
            XCTAssertEqual(try inventory(root),before);XCTAssertEqual(try store.snapshot(),result.document);XCTAssertFalse(store.hasUnverifiedSave)
            XCTAssertThrowsError(try store.verifyLastSave());XCTAssertEqual(try inventory(root),before)
            XCTAssertEqual(try store.save(SettingsValues(),expectedRevision:revision+1).revision,revision+2)
        }
    }
    func testReportedPublicationFailureKeepsPreviousAndOrphanInitializationBlocked()throws {
        let root=try directory();try seed(root);let store=try SettingsStore(directory:root,fault:.publicationFailure);defer{store.close()}
        let before=try inventory(root);XCTAssertThrowsError(try store.save(changed(),expectedRevision:1));XCTAssertThrowsError(try store.snapshot())
        XCTAssertEqual(try store.verifyLastSave().resolution,.previous);XCTAssertEqual(try inventory(root),before)
        for fault in [SettingsTestFault.afterInitialization,.publicationFailure] {
            let empty=try directory(),orphan=try SettingsStore(directory:empty,fault:fault);defer{orphan.close()}
            XCTAssertThrowsError(try orphan.save(changed(),expectedRevision:0));let orphanBytes=try inventory(empty)
            XCTAssertThrowsError(try orphan.verifyLastSave());XCTAssertThrowsError(try orphan.verifyLastSave());XCTAssertTrue(orphan.hasUnverifiedSave)
            XCTAssertThrowsError(try orphan.snapshot());XCTAssertThrowsError(try orphan.save(changed(),expectedRevision:0));XCTAssertEqual(try inventory(empty),orphanBytes)
            XCTAssertFalse(FileManager.default.fileExists(atPath:empty.appendingPathComponent("settings.json").path))
        }
    }
    func testCorruptMissingAndUnexpectedValidAuthorityRemainQuarantined()throws {
        for kind in ["corrupt","missing","wrong-marker","missing-marker","foreign-valid"] {
            let root=try directory();try seed(root);let store=try SettingsStore(directory:root,fault:.afterPublication);defer{store.close()}
            XCTAssertThrowsError(try store.save(changed(),expectedRevision:1));let file=root.appendingPathComponent("settings.json"),marker=root.appendingPathComponent(".initialized")
            if kind=="corrupt"{try Data("corrupt".utf8).write(to:file)}
            if kind=="missing"{try FileManager.default.removeItem(at:file)}
            if kind=="wrong-marker"{try Data("wrong".utf8).write(to:marker)}
            if kind=="missing-marker"{try FileManager.default.removeItem(at:marker)}
            if kind=="foreign-valid"{try SettingsCodec.encode(SettingsDocument(revision:3,values:SettingsValues())).write(to:file)}
            let before=try inventory(root)
            for _ in 0..<2{XCTAssertThrowsError(try store.verifyLastSave());XCTAssertThrowsError(try store.snapshot());XCTAssertThrowsError(try store.save(SettingsValues(),expectedRevision:1))}
            XCTAssertTrue(store.hasUnverifiedSave);XCTAssertEqual(try inventory(root),before)
        }
    }
    func testMovedRootAndReplacedOrLinkedLockCannotBeReopenedByVerification()throws {
        let parent=try directory(),root=parent.appendingPathComponent("selected"),moved=parent.appendingPathComponent("moved")
        let store=try SettingsStore(directory:root,fault:.afterPublication);defer{store.close()};XCTAssertThrowsError(try store.save(changed(),expectedRevision:0))
        let original=try inventory(root);try FileManager.default.moveItem(at:root,to:moved);try FileManager.default.createDirectory(at:root,withIntermediateDirectories:false)
        XCTAssertThrowsError(try store.verifyLastSave());XCTAssertEqual(try inventory(moved),original);XCTAssertTrue(try inventory(root).isEmpty)
        for hardlink in [false,true] {
            let path=try directory(),other=try SettingsStore(directory:path,fault:.afterPublication);defer{other.close()};XCTAssertThrowsError(try other.save(changed(),expectedRevision:0))
            let writer=path.appendingPathComponent(".writer.lock"),second=path.appendingPathComponent("other-lock")
            if hardlink{try FileManager.default.linkItem(at:writer,to:second)}else{try FileManager.default.moveItem(at:writer,to:second);try Data().write(to:writer)}
            let before=try inventory(path);XCTAssertThrowsError(try other.verifyLastSave());XCTAssertEqual(try inventory(path),before)
        }
    }
    func testSpecialAuthorityFilesRefusedWithoutFollowingThem()throws {
        for kind in ["symlink","hardlink","fifo"] {
            let root=try directory(),store=try SettingsStore(directory:root,fault:.afterPublication);defer{store.close()};XCTAssertThrowsError(try store.save(changed(),expectedRevision:0))
            let file=root.appendingPathComponent("settings.json"),outside=try directory().appendingPathComponent("outside");try Data("untouched".utf8).write(to:outside);try FileManager.default.removeItem(at:file)
            if kind=="symlink"{try FileManager.default.createSymbolicLink(at:file,withDestinationURL:outside)}else if kind=="hardlink"{try FileManager.default.linkItem(at:outside,to:file)}else{XCTAssertEqual(mkfifo(file.path,0o600),0)}
            XCTAssertThrowsError(try store.verifyLastSave());XCTAssertThrowsError(try store.save(changed(),expectedRevision:0));XCTAssertEqual(try Data(contentsOf:outside),Data("untouched".utf8))
        }
    }
    func testVerificationKeepsOneWriterAndClosedHandleCannotResolve()throws {
        let root=try directory(),store=try SettingsStore(directory:root,fault:.afterPublication)
        XCTAssertThrowsError(try store.save(changed(),expectedRevision:0));XCTAssertThrowsError(try SettingsStore(directory:root))
        _ = try store.verifyLastSave();XCTAssertThrowsError(try SettingsStore(directory:root));let before=try inventory(root)
        store.close();XCTAssertFalse(store.hasUnverifiedSave);XCTAssertThrowsError(try store.verifyLastSave());XCTAssertEqual(try inventory(root),before)
        let reopened=try SettingsStore(directory:root);defer{reopened.close()};XCTAssertEqual(try reopened.snapshot()?.revision,1)
    }
}
