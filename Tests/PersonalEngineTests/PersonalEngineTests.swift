#if os(macOS)
import XCTest
import AppKit
import EngineBridge
import LexiconCore
import NativeHost

final class PersonalEngineTests:XCTestCase {
    let marker="穹海测例【B2甲】",rare="𠀀e\u{301}👩🏽‍💻"
    @MainActor func testActivatedGeneration()throws {
        _=NSApplication.shared
        var variables=ProcessInfo.processInfo.environment
        guard let stage=variables["PAIA_B2_TEST_STAGE"],let root=variables["PAIA_B2_STORE"] else{throw XCTSkip("Explicit synthetic B2 generation not selected")}
        let path=URL(fileURLWithPath:root),oldExport=path.deletingLastPathComponent().appendingPathComponent("b2-synthetic-old-export.json")
        if ["active","swapped","deleted","restored"].contains(stage) {
            let store=try LexiconStore(directory:path)
            defer{store.close()}
            func revision()throws->UInt64 {try store.snapshot().revision}
            if stage=="active" {
                XCTAssertEqual(try revision(),0)
                _ = try store.add(surface:marker,reading:"qiong hai ce li jia",aliases:["qiong hai ce li yi"],expectedRevision:revision())
                _ = try store.add(surface:"林小唐",reading:"lin xiao tang",expectedRevision:revision())
                _ = try store.add(surface:"林小棠",reading:"lin xiao tang",pin:true,expectedRevision:revision())
                _ = try store.add(surface:rare,reading:"kuo",expectedRevision:revision())
                _ = try store.add(surface:"林小棠",reading:"lin xiao qiu",expectedRevision:revision())
            } else if stage=="swapped" {
                let terms=try store.snapshot().terms
                let previous=try XCTUnwrap(terms.first{$0.surface=="林小棠" && $0.reading=="lin xiao tang"})
                let next=try XCTUnwrap(terms.first{$0.surface=="林小唐"})
                try store.edit(id:previous.id,surface:previous.surface,reading:previous.reading,aliases:previous.aliases,pin:false,expectedRevision:revision())
                try store.edit(id:next.id,surface:next.surface,reading:next.reading,aliases:next.aliases,pin:true,expectedRevision:revision())
            } else {
                let id=try XCTUnwrap(store.snapshot().terms.first{$0.surface==marker}?.id)
                if stage=="deleted" {
                    try store.exportData().write(to:oldExport)
                    try store.setDeleted(id:id,deleted:true,expectedRevision:revision())
                    let plan=try store.previewImport(Data(contentsOf:oldExport));XCTAssertEqual(plan.protectedDeletions,1)
                    try store.applyImport(plan);XCTAssertTrue(try store.snapshot().terms.first{$0.id==id}!.isDeleted)
                } else {try store.setDeleted(id:id,deleted:false,expectedRevision:revision())}
            }
        } else if stage=="corrupt" {try Data("synthetic-corrupt-authority".utf8).write(to:path.appendingPathComponent("lexicon.json"))}
        else if stage=="missing" {try FileManager.default.removeItem(at:path.appendingPathComponent("lexicon.json"))}
        else if stage=="empty" {variables["PAIA_B2_STORE"]=root+"-empty"}
        else {XCTFail("Unknown synthetic stage");return}
        let environment=try PersonalLabEnvironment(environment:variables)
        defer{environment.store?.close()}
        let authority=URL(fileURLWithPath:try XCTUnwrap(variables["PAIA_B2_STORE"])).appendingPathComponent("lexicon.json")
        let before=try? Data(contentsOf:authority)
        func session()throws->InputSession {try environment.makeSession(configuration:LabConfiguration())}
        func type(_ raw:String,_ host:HostDispatcher)throws {for b in raw.utf8 {XCTAssertTrue(host.apply(try host.session.process(.code(Int32(b)))))}}
        func choose(_ raw:String,_ wanted:String)throws {
            let s=try session();defer{s.end()};let view=NSTextView(frame:.zero),host=HostDispatcher(client:view,session:s)
            try type(raw,host)
            var selected=false
            for _ in 0..<200 {
                let snapshot=try XCTUnwrap(s.snapshot)
                if let candidate=snapshot.rows.first(where:{$0.text==wanted}) {XCTAssertTrue(host.apply(try s.select(candidate.ref)));selected=true;break}
                if !snapshot.hasMore{break};XCTAssertTrue(host.apply(try s.process(.code(0xff56))))
            }
            XCTAssertTrue(selected,"Expected authored fixture candidate absent")
            XCTAssertEqual(view.string,wanted);XCTAssertEqual(host.insertCount,1)
            XCTAssertNil(try s.refresh().commit)
        }
        func choosePersonalPrefixWithoutDroppingSuffix()throws {
            let s=try session();defer{s.end()};let view=NSTextView(frame:.zero),host=HostDispatcher(client:view,session:s)
            try type("qionghaicelijianihao",host)
            var selected=false
            for _ in 0..<200 {
                let snapshot=try XCTUnwrap(s.snapshot)
                if let row=snapshot.rows.first(where:{$0.text==marker}) {
                    let update=try s.select(row.ref);XCTAssertNil(update.commit);XCTAssertTrue(host.apply(update));selected=true;break
                }
                if !snapshot.hasMore{break};XCTAssertTrue(host.apply(try s.process(.code(0xff56))))
            }
            XCTAssertTrue(selected,"Authored personal prefix unavailable with a public suffix")
            XCTAssertEqual(host.insertCount,0)
            let suffix=try XCTUnwrap(s.snapshot?.rows.first(where:{$0.text=="你好"}))
            XCTAssertTrue(host.apply(try s.select(suffix.ref)));XCTAssertEqual(view.string,marker+"你好");XCTAssertEqual(host.insertCount,1)
            XCTAssertNil(try s.refresh().commit)
        }
        func candidates(_ raw:String)throws->[String] {
            let s=try session();defer{s.end()};for b in raw.utf8{_ = try s.process(.code(Int32(b)))}
            var rows=[String](),complete=false
            for _ in 0..<200 {
                let snap=try XCTUnwrap(s.snapshot);rows+=snap.rows.map{$0.text}
                if !snap.hasMore{complete=true;break};_ = try s.process(.code(0xff56))
            }
            XCTAssertTrue(complete,"Bounded candidate enumeration incomplete; absence is not established")
            return rows
        }
        if ["corrupt","missing","empty"].contains(stage) {
            XCTAssertEqual(environment.authorityUnavailable,stage != "empty")
            XCTAssertTrue(environment.resources.overlaySchemas.isEmpty)
            try choose("nihao","你好")
        } else {
            XCTAssertFalse(environment.authorityUnavailable)
            XCTAssertFalse(environment.resources.overlaySchemas.isEmpty)
            let rows=try candidates("linxiaotang")
            let a=try XCTUnwrap(rows.firstIndex(of:"林小棠")),b=try XCTUnwrap(rows.firstIndex(of:"林小唐"))
            XCTAssertEqual(a<b,stage=="active")
            if stage=="deleted" {XCTAssertFalse(try candidates("qionghaicelijia").contains(marker))}
            else {try choosePersonalPrefixWithoutDroppingSuffix();try choose("qionghaicelijia",marker);try choose("qiong'hai'ce'li'jia",marker);try choose("qionghaiceliyi",marker)}
            XCTAssertFalse(try candidates("qionghaiceli").contains(marker))
            try choose("kuo",rare);try choose("linxiaoqiu","林小棠")
            let s=try session();defer{s.end()};_ = try s.process(.code(110));XCTAssertFalse(s.supportsRepair)
            XCTAssertThrowsError(try s.repairChoices());XCTAssertThrowsError(try s.repairAnchors())
            for _ in 0..<20 {try choose("nihao","你好")}
            environment.disableOverlayUntilRestart()
            XCTAssertThrowsError(try s.refresh()) // Existing overlay capabilities die too, not just future sessions.
            XCTAssertTrue(try session().supportsRepair);XCTAssertFalse(try candidates("qionghaicelijia").contains(marker))
            try choose("shurufa","输入法")
        }
        XCTAssertEqual(try? Data(contentsOf:authority),before,"Ordinary engine operations changed explicit authority")
        let user=environment.temporaryDirectory.appendingPathComponent("engine-user")
        let files=FileManager.default.enumerator(at:user,includingPropertiesForKeys:nil)!.allObjects.compactMap{$0 as? URL}
        XCTAssertFalse(files.contains{$0.lastPathComponent.contains("userdb")},"Implicit learning database created")
        let retained=try session();_ = try retained.process(.code(110))
        XCTAssertTrue(environment.runtime.close());XCTAssertThrowsError(try retained.refresh());XCTAssertTrue(environment.runtime.close());XCTAssertFalse(FileManager.default.fileExists(atPath:environment.temporaryDirectory.path))
        XCTAssertThrowsError(try environment.makeSession(configuration:LabConfiguration()))
        print("B2_ENGINE_NATIVE stage=\(stage) activeTerms=\(environment.resources.activeTerms) revision=\(environment.resources.revision); no private input in this fixture")
    }
}
#endif
