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
    }
    @MainActor func testSelectedIdentityCannotMoveWithAnotherRowAndSourceRevision()throws {
        let(c,w,store,root)=try fixture();defer{w.close();store.close();try? FileManager.default.removeItem(at:root)}
        fill(c,"第一词","di yi ci");c.addButton.performClick(nil);fill(c,"第二词","di er ci");c.addButton.performClick(nil)
        (try XCTUnwrap(c.rows.arrangedSubviews.first as? NSButton)).performClick(nil)
        let oldDelete=try XCTUnwrap(c.actions.arrangedSubviews.last as? NSButton)
        (try XCTUnwrap(c.rows.arrangedSubviews.last as? NSButton)).performClick(nil);oldDelete.performClick(nil)
        XCTAssertEqual(try store.snapshot().activeTerms.count,2)
        let current=try XCTUnwrap(c.actions.arrangedSubviews.first as? NSButton)
        _ = try store.add(surface:"外部明确操作","wai bu ming que cao zuo",expectedRevision:2)
        current.performClick(nil);XCTAssertEqual(try store.snapshot().activeTerms.count,3)
        XCTAssertTrue(c.status.stringValue.contains("reopen"))
    }
    @MainActor func testAccessibleLabelsAndNoImplicitFieldSave()throws {
        let(c,w,store,root)=try fixture();defer{w.close();store.close();try? FileManager.default.removeItem(at:root)}
        let before=try store.exportData();fill(c,"仅编辑未保存","jin bian ji wei bao cun")
        c.controlTextDidChange(Notification(name:NSControl.textDidChangeNotification,object:c.surface));c.pin.performClick(nil)
        XCTAssertEqual(try store.exportData(),before);XCTAssertEqual(c.surface.accessibilityLabel(),"Exact term text")
        XCTAssertEqual(c.previewDetails.accessibilityLabel(),"Complete import additions and conflict details")
    }
}
#endif
