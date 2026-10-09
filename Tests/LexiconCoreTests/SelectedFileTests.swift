import XCTest
import Foundation
import Darwin
import LexiconCore

final class SelectedFileTests:XCTestCase {
    func testExplicitFileRoundTripAndSpecialFileRefusal()throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("paia-b2-files-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true);defer{try? FileManager.default.removeItem(at:root)}
        let store=try LexiconStore(directory:root.appendingPathComponent("store"));defer{store.close()}
        _ = try store.add(surface:"手动导出",reading:"shou dong dao chu",expectedRevision:0)
        let bytes=try store.exportData(),file=root.appendingPathComponent("selected.json")
        try SelectedLexiconFile.write(bytes,to:file);XCTAssertEqual(try SelectedLexiconFile.read(file),bytes)
        let symbolic=root.appendingPathComponent("alias.json");try FileManager.default.createSymbolicLink(at:symbolic,withDestinationURL:file)
        XCTAssertThrowsError(try SelectedLexiconFile.read(symbolic));XCTAssertThrowsError(try SelectedLexiconFile.write(bytes,to:symbolic))
        let fifo=root.appendingPathComponent("pipe.json");XCTAssertEqual(mkfifo(fifo.path,0o600),0)
        XCTAssertThrowsError(try SelectedLexiconFile.read(fifo));XCTAssertThrowsError(try SelectedLexiconFile.write(bytes,to:fifo))
        XCTAssertEqual(try Data(contentsOf:file),bytes)
    }
    func testManagedScratchTeardownAndBoundedInactiveOrphans()throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("paia-b2-scratch-test-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true);defer{try? FileManager.default.removeItem(at:root)}
        let live=try PersonalScratch(storeDirectory:root),managed=live.directory.deletingLastPathComponent()
        let process=Process();process.executableURL=URL(fileURLWithPath:"/usr/bin/true");try process.run();process.waitUntilExit()
        let pid=process.processIdentifier;var orphans=[URL]()
        for _ in 0..<17 {
            let id=UUID().uuidString,url=managed.appendingPathComponent(id);try FileManager.default.createDirectory(at:url,withIntermediateDirectories:false)
            try JSONSerialization.data(withJSONObject:["format":1,"id":id,"pid":pid]).write(to:url.appendingPathComponent(".owner.json"));orphans.append(url)
        }
        let untouched=managed.appendingPathComponent("unrecognized");try FileManager.default.createDirectory(at:untouched,withIntermediateDirectories:false)
        let next=try PersonalScratch(storeDirectory:root)
        XCTAssertEqual(orphans.filter{FileManager.default.fileExists(atPath:$0.path)}.count,1)
        XCTAssertTrue(FileManager.default.fileExists(atPath:live.directory.path));XCTAssertTrue(FileManager.default.fileExists(atPath:untouched.path))
        try next.remove();XCTAssertFalse(FileManager.default.fileExists(atPath:next.directory.path));try live.remove()
    }
}
