#if os(macOS)
import XCTest
import AppKit
import NativeHost
import LexiconCore

final class PersonalControlTests:XCTestCase {
    @MainActor func fixture()throws->(PersonalLexiconController,NSWindow,LexiconStore,URL){
        _=NSApplication.shared
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("paia-b2-controls-"+UUID().uuidString)
        let store=try LexiconStore(directory:root.appendingPathComponent("store"))
        let c=PersonalLexiconController(store:store,onChange:{})
        let w=NSWindow(contentRect:NSRect(x:0,y:0,width:900,height:850),styleMask:[.titled,.closable],backing:.buffered,defer:false);w.isReleasedWhenClosed=false
        try c.attach(to:w);return(c,w,store,root)
    }
    @MainActor func fill(_ c:PersonalLexiconController,_ surface:String,_ reading:String){c.surface.stringValue=surface;c.reading.stringValue=reading}
    @MainActor func testNativeAddEditPinDeleteRestoreAndOldActions()throws {
        let(c,w,store,root)=try fixture();defer{w.close();store.close();try? FileManager.default.removeItem(at:root)}
        fill(c,"界面词甲","jie mian ci jia");c.addButton.performClick(nil)
        XCTAssertEqual(try store.snapshot().activeTerms.count,1)
        let original=try XCTUnwrap(c.rows.arrangedSubviews.first as? NSButton);original.performClick(nil)
        let oldSave=try XCTUnwrap(c.actions.arrangedSubviews.first as? NSButton)
        c.pin.performClick(nil);oldSave.performClick(nil);XCTAssertTrue(try store.snapshot().terms[0].explicitPin)
        oldSave.performClick(nil);XCTAssertEqual(try store.snapshot().revision,2)
        original.performClick(nil);XCTAssertEqual(c.surface.stringValue,"")
        (try XCTUnwrap(c.rows.arrangedSubviews.first as? NSButton)).performClick(nil)
        let remove=try XCTUnwrap(c.actions.arrangedSubviews.last as? NSButton);remove.performClick(nil)
        XCTAssertTrue(try store.snapshot().activeTerms.isEmpty)
        (try XCTUnwrap(c.rows.arrangedSubviews.first as? NSButton)).performClick(nil)
        let restore=try XCTUnwrap(c.actions.arrangedSubviews.last as? NSButton);restore.performClick(nil)
        XCTAssertEqual(try store.snapshot().activeTerms.count,1);remove.performClick(nil);XCTAssertEqual(try store.snapshot().revision,4)
        w.close();c.addButton.performClick(nil);restore.performClick(nil);XCTAssertEqual(try store.snapshot().revision,4)
    }
    @MainActor func testImportPreviewCancelFrozenBytesAndStaleApply()throws {
        let(c,w,store,root)=try fixture();defer{w.close();store.close();try? FileManager.default.removeItem(at:root)}
        let source=try LexiconStore(directory:root.appendingPathComponent("source"));defer{source.close()}
        _ = try source.add(surface:"审阅的词",reading:"shen yue de ci",expectedRevision:0)
        let file=root.appendingPathComponent("chosen.json");try SelectedLexiconFile.write(source.exportData(),to:file)
        try c.previewSelectedFile(file);XCTAssertTrue(c.previewDetails.string.contains("审阅的词"))
        let old=try XCTUnwrap(c.importActions.arrangedSubviews.first as? NSButton);c.cancelImportButton.performClick(nil)
        old.performClick(nil);XCTAssertTrue(try store.snapshot().terms.isEmpty)
        try c.previewSelectedFile(file);let current=try XCTUnwrap(c.importActions.arrangedSubviews.first as? NSButton)
        try Data("file changed after preview".utf8).write(to:file)
        current.performClick(nil);XCTAssertEqual(try store.snapshot().activeTerms.map{$0.surface},["审阅的词"])
        old.performClick(nil);current.performClick(nil);XCTAssertEqual(try store.snapshot().revision,1)
        let exported=root.appendingPathComponent("export.json");try c.writeSelectedExport(exported);XCTAssertEqual(try SelectedLexiconFile.read(exported),try store.exportData())
        let before=try store.exportData();XCTAssertThrowsError(try c.writeSelectedExport(store.directory.appendingPathComponent("lexicon.json")))
        XCTAssertEqual(try store.exportData(),before)
    }
    @MainActor func testSelectedIdentityCannotMoveWithAnotherRowAndSourceRevision()throws {
        let(c,w,store,root)=try fixture();defer{w.close();store.close();try? FileManager.default.removeItem(at:root)}
        fill(c,"第一词","di yi ci");c.addButton.performClick(nil);fill(c,"第二词","di er ci");c.addButton.performClick(nil)
        (try XCTUnwrap(c.rows.arrangedSubviews.first as? NSButton)).performClick(nil)
        let oldDelete=try XCTUnwrap(c.actions.arrangedSubviews.last as? NSButton)
        (try XCTUnwrap(c.rows.arrangedSubviews.last as? NSButton)).performClick(nil);oldDelete.performClick(nil)
        XCTAssertEqual(try store.snapshot().activeTerms.count,2)
        let current=try XCTUnwrap(c.actions.arrangedSubviews.first as? NSButton)
        _ = try store.add(surface:"外部明确操作",reading:"wai bu ming que cao zuo",expectedRevision:2)
        current.performClick(nil);XCTAssertEqual(try store.snapshot().activeTerms.count,3)
        XCTAssertTrue(c.status.stringValue.contains("Restart the lab"))
    }
    @MainActor func testAccessibleLabelsAndNoImplicitFieldSave()throws {
        let(c,w,store,root)=try fixture();defer{w.close();store.close();try? FileManager.default.removeItem(at:root)}
        let before=try store.exportData();fill(c,"仅编辑未保存","jin bian ji wei bao cun")
        c.controlTextDidChange(Notification(name:NSControl.textDidChangeNotification,object:c.surface));c.pin.performClick(nil)
        XCTAssertEqual(try store.exportData(),before);XCTAssertEqual(c.surface.accessibilityLabel(),"Exact term text")
        XCTAssertEqual(c.previewDetails.accessibilityLabel(),"Complete import additions and conflict details")
    }
    @MainActor func testSyntheticManagerLayoutCapture()throws {
        guard ProcessInfo.processInfo.environment["PAIA_CAPTURE_B2_LAYOUT"]=="1" else{throw XCTSkip("Synthetic B2 root-view capture not selected")}
        let(c,w,store,root)=try fixture();defer{w.close();store.close();try? FileManager.default.removeItem(at:root)}
        w.orderFront(nil);fill(c,"林小棠","lin xiao tang");c.pin.performClick(nil);c.addButton.performClick(nil)
        let source=try LexiconStore(directory:root.appendingPathComponent("source"));defer{source.close()}
        _ = try source.add(surface:"穹海测例【B2甲】",reading:"qiong hai ce li jia",aliases:["qiong hai ce li yi"],expectedRevision:0)
        let chosen=root.appendingPathComponent("synthetic-import.json");try SelectedLexiconFile.write(source.exportData(),to:chosen);try c.previewSelectedFile(chosen)
        c.root.layoutSubtreeIfNeeded();c.root.displayIfNeeded()
        let bitmap=try XCTUnwrap(c.root.bitmapImageRepForCachingDisplay(in:c.root.bounds));c.root.cacheDisplay(in:c.root.bounds,to:bitmap)
        let data=try XCTUnwrap(bitmap.representation(using:.png,properties:[:]))
        let output=URL(fileURLWithPath:FileManager.default.currentDirectoryPath).appendingPathComponent("evidence/b2-run");try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
        try data.write(to:output.appendingPathComponent("personal-manager.png"))
        let encoded=data.base64EncodedString();var offset=encoded.startIndex,index=0
        while offset<encoded.endIndex{let end=encoded.index(offset,offsetBy:3000,limitedBy:encoded.endIndex) ?? encoded.endIndex;FileHandle.standardError.write(Data(("PAIA_B2_IMAGE_\(index):"+encoded[offset..<end]+"\n").utf8));offset=end;index+=1}
    }
}
#endif
