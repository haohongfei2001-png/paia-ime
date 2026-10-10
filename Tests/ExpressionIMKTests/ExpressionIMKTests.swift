#if os(macOS)
import XCTest
import AppKit
import ExpressionCore
import SessionCore
import EngineBridge
import IMKHost
import IMKTestClient

final class ExpressionIMKTests:XCTestCase {
    static var lab:LabEnvironment!
    override class func setUp(){super.setUp();do{lab=try LabEnvironment()}catch{XCTFail("Verified real-engine fixture startup failed")}}
    static let exact="  不改 42 / e\u{301} / é / 𠀀 / 👩🏽‍💻\r\n末句不能漏。  "
    @MainActor final class Rig {
        let root:URL,store:ExpressionStore,workspace:IMKWorkspace,client:PAIAIMKTestClient
        let driver:IMKControllerDriver
        init(text:String=ExpressionIMKTests.exact,fault:ExpressionTestFault?=nil,hide:@escaping()->Void={},present:@escaping(ExpressionRecallState,NSRect)->Bool={_,_ in true})throws {
            root=FileManager.default.temporaryDirectory.appendingPathComponent("paia-c-host-"+UUID().uuidString)
            let seed=try ExpressionStore(directory:root);_ = try seed.saveExact(text,aliases:["exact","yuanzhen"],expectedRevision:0);seed.close()
            store=try ExpressionStore(directory:root,fault:fault)
            workspace=IMKWorkspace(expressionStore:store,resourceDescription:"Authored test only",makeSession:{_ in try ExpressionIMKTests.lab.runtime.makeSession()})
            client=PAIAIMKTestClient(text:"prefix👩🏽‍💻")
            driver=workspace.makeDriver(hide:hide,present:{_,_,_ in},presentRecall:present)
            XCTAssertEqual(driver.activate(try XCTUnwrap(IMKTextInputBridge(client))),.ready)
        }
        func close(){driver.close();workspace.close();try? FileManager.default.removeItem(at:root)}
        func authority()throws->Data {try Data(contentsOf:root.appendingPathComponent("expressions.json"))}
    }
    @MainActor func event(_ text:String="",code:UInt16=0,modifiers:NSEvent.ModifierFlags=[],repeatKey:Bool=false)throws->NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:modifiers,timestamp:0,windowNumber:0,context:nil,characters:text,charactersIgnoringModifiers:text,isARepeat:repeatKey,keyCode:code))
    }
    @MainActor func open(_ r:Rig)throws->ExpressionRecallState {
        XCTAssertTrue(r.driver.handle(try event(" ",code:49,modifiers:[.option]),client:r.client));return try XCTUnwrap(r.driver.recall)
    }
    @MainActor func review(_ r:Rig)throws->ExpressionRecallState {
        let state=try open(r),row=try XCTUnwrap(state.rows.first);r.driver.reviewExpression(row.ref,token:state.token)
        let reviewed=try XCTUnwrap(r.driver.recall);XCTAssertNotNil(reviewed.review);return reviewed
    }
    @MainActor func testSaveRecallFullReviewOnceAndNormalInputNeverSavesImplicitly()throws {
        _=NSApplication.shared;let r=try Rig();defer{r.close()}
        let before=try r.authority(),prefix=r.client.view.string,markCalls=r.client.markCalls
        let first=try open(r)
        for c in "yuanzhen"{XCTAssertTrue(r.driver.handle(try event(String(c)),client:r.client))}
        let state=try XCTUnwrap(r.driver.recall);XCTAssertEqual(state.rows.count,1);XCTAssertNotEqual(first.token,state.token)
        r.driver.reviewExpression(first.rows[0].ref,token:first.token);XCTAssertNil(r.driver.recall?.review)
        XCTAssertTrue(r.driver.handle(try event("\r",code:36),client:r.client));let reviewed=try XCTUnwrap(r.driver.recall)
        XCTAssertEqual(reviewed.review?.record.exactText?.utf8.map{$0},Array(Self.exact.utf8));XCTAssertEqual(r.client.insertCalls,0);XCTAssertEqual(r.client.markCalls,markCalls)
        XCTAssertTrue(r.driver.handle(try event("\r",code:36,repeatKey:true),client:r.client));XCTAssertEqual(r.client.insertCalls,0)
        XCTAssertTrue(r.driver.handle(try event("\r",code:36),client:r.client));XCTAssertNil(r.driver.recall)
        r.driver.acceptExpression(token:reviewed.token);XCTAssertEqual(r.client.insertCalls,1)
        XCTAssertEqual(Array(r.client.view.string.utf8),Array((prefix+Self.exact).utf8));XCTAssertEqual(r.client.documentLengthCalls,0)
        for read in r.client.reads.compactMap({($0 as? NSValue)?.rangeValue}){XCTAssertEqual(read.location,prefix.utf16.count);XCTAssertEqual(read.length,Self.exact.utf16.count)}
        for c in "nihao"{XCTAssertTrue(r.driver.handle(try event(String(c)),client:r.client))}
        XCTAssertTrue(r.driver.handle(try event(" ",code:49),client:r.client));XCTAssertEqual(r.client.view.string,prefix+Self.exact+"你好")
        XCTAssertEqual(try r.authority(),before)
    }
    @MainActor func testRecallWhileComposingRefusesBeforeOptionFlushAndEmptyResultDoesNotGenerate()throws {
        _=NSApplication.shared;let r=try Rig();defer{r.close()}
        for c in "nihao"{_ = r.driver.handle(try event(String(c)),client:r.client)}
        let before=r.client.view.string,generation=r.driver.coordinator.snapshot?.inputGeneration,marks=r.client.markCalls
        XCTAssertTrue(r.driver.handle(try event(" ",code:49,modifiers:[.option]),client:r.client));XCTAssertNil(r.driver.recall)
        XCTAssertEqual(r.client.view.string,before);XCTAssertEqual(r.driver.coordinator.snapshot?.inputGeneration,generation);XCTAssertEqual(r.client.markCalls,marks);XCTAssertEqual(r.client.insertCalls,0)
        _ = r.driver.handle(try event("",code:53),client:r.client);_ = try open(r)
        for c in "no matching authored expression"{_ = r.driver.handle(try event(String(c)),client:r.client)}
        XCTAssertTrue(r.driver.recall?.rows.isEmpty==true);_ = r.driver.handle(try event("\r",code:36),client:r.client)
        XCTAssertNil(r.driver.recall?.review);XCTAssertEqual(r.client.insertCalls,0)
        _ = r.driver.handle(try event("",code:53),client:r.client);XCTAssertNil(r.driver.recall);XCTAssertEqual(r.client.insertCalls,0)
    }
    @MainActor func testDisabledExpressionStorePreservesIdleOptionSpaceInBothModes()throws {
        _=NSApplication.shared
        for literal in [false,true] {
            let workspace=IMKWorkspace(resourceDescription:"No expression store",makeSession:{_ in try Self.lab.runtime.makeSession()})
            defer{workspace.close()};var configuration=workspace.configuration;configuration.literal=literal;try workspace.applyConfiguration(configuration)
            let driver=workspace.makeDriver(hide:{},present:{_,_,_ in}),client=PAIAIMKTestClient(text:"");defer{driver.close()}
            XCTAssertEqual(driver.activate(try XCTUnwrap(IMKTextInputBridge(client))),.ready)
            XCTAssertFalse(driver.handle(try event(" ",code:49,modifiers:[.option]),client:client));XCTAssertNil(driver.recall);XCTAssertEqual(client.insertCalls,0)
        }
    }
    @MainActor func testCaretSelectionAndForeignMarkRejectRecallWithoutDocumentScan()throws {
        _=NSApplication.shared
        for change in 0..<3 {
            let r=try Rig();defer{r.close()}
            if change==0{r.client.view.setSelectedRange(NSRange(location:0,length:0))}
            if change==1{r.client.view.setSelectedRange(NSRange(location:0,length:2))}
            if change==2{r.client.view.setMarkedText("foreign",selectedRange:NSRange(location:7,length:0),replacementRange:NSRange(location:NSNotFound,length:0))}
            let before=r.client.view.string;_ = r.driver.handle(try event(" ",code:49,modifiers:[.option]),client:r.client)
            XCTAssertNil(r.driver.recall);XCTAssertEqual(r.client.view.string,before);XCTAssertEqual(r.client.insertCalls,0);XCTAssertEqual(r.client.markCalls,0);XCTAssertEqual(r.client.documentLengthCalls,0)
        }
    }
    @MainActor func testLifecycleAndSameObjectReactivationInvalidateIssuedReview()throws {
        _=NSApplication.shared
        for lifecycle in 0..<5 {
            let r=try Rig();defer{r.close()};let state=try review(r),before=r.client.view.string,b=PAIAIMKTestClient(text:"other")
            switch lifecycle {
            case 0:r.driver.finish(client:r.client)
            case 1:r.driver.deactivate(client:r.client)
            case 2:r.driver.close()
            case 3:r.driver.activate(try XCTUnwrap(IMKTextInputBridge(r.client)))
            default:r.driver.activate(try XCTUnwrap(IMKTextInputBridge(b)))
            }
            r.driver.acceptExpression(token:state.token);XCTAssertNil(r.driver.recall);XCTAssertEqual(r.client.view.string,before);XCTAssertEqual(r.client.insertCalls,0);XCTAssertEqual(b.insertCalls,0)
        }
    }
    @MainActor func testStaleReviewCannotSurviveCancelConfigurationEditDeleteOrShutdown()throws {
        _=NSApplication.shared
        for action in 0..<5 {
            let r=try Rig();defer{r.close()};let state=try review(r),record=try XCTUnwrap(state.review?.record)
            XCTAssertFalse(r.workspace.isIdle)
            XCTAssertThrowsError(try r.workspace.saveExpression("blocked",aliases:[],catalogRevision:1))
            r.driver.cancelRecall(token:state.token)
            switch action {
            case 0:try r.workspace.applyConfiguration(r.workspace.configuration)
            case 1:_ = try r.workspace.saveExpression("edited",aliases:[],editing:record.id,recordRevision:record.revision,catalogRevision:1)
            case 2:_ = try r.workspace.deleteExpression(record,catalogRevision:1)
            case 3:try r.workspace.reloadExpressions()
            default:r.workspace.close()
            }
            r.driver.acceptExpression(token:state.token);XCTAssertEqual(r.client.insertCalls,0)
        }
    }
    @MainActor func testStagedMarkedRangeCallbackSelectionChangeIsRefusedBeforeInsert()throws {
        _=NSApplication.shared;let r=try Rig();defer{r.close()};let state=try review(r),before=r.client.view.string
        var callbacks=0
        r.client.onMarkedRange={callbacks+=1;r.client.onMarkedRange={callbacks+=1;r.client.view.setSelectedRange(NSRange(location:0,length:2))}}
        r.driver.acceptExpression(token:state.token)
        XCTAssertEqual(callbacks,2);XCTAssertEqual(r.client.insertCalls,0);XCTAssertEqual(r.client.markCalls,0);XCTAssertEqual(r.client.view.string,before);XCTAssertNil(r.driver.recall)
    }
    @MainActor func testUnknownOutcomeNeverRetriesOrClearsForeignText()throws {
        _=NSApplication.shared
        for foreign in [false,true] {
            let r=try Rig();defer{r.close()};let state=try review(r)
            r.client.onInsert={if foreign{r.client.view.setMarkedText("foreign",selectedRange:NSRange(location:7,length:0),replacementRange:NSRange(location:NSNotFound,length:0))}else{r.client.truncateReads=true}}
            r.driver.acceptExpression(token:state.token);XCTAssertEqual(r.driver.coordinator.outcome,.outcomeUnknown)
            XCTAssertEqual(r.driver.recovery?.issuedText?.utf8.map{$0},Array(Self.exact.utf8));XCTAssertEqual(r.client.insertCalls,1);XCTAssertEqual(r.client.markCalls,0)
            r.driver.acceptExpression(token:state.token);r.driver.finish(client:r.client);r.driver.deactivate(client:r.client)
            XCTAssertEqual(r.client.insertCalls,1);XCTAssertEqual(r.client.markCalls,0);if foreign{XCTAssertTrue(r.client.view.hasMarkedText())}
        }
    }
    @MainActor func testEveryRecallGetterPresentationAndInsertReentryCannotResumeOldAction()throws {
        _=NSApplication.shared
        for phase in 0..<6 {
            weak var target:IMKControllerDriver?;var armed=false
            let r=try Rig(present:{_,_ in if armed{armed=false;target?.close()};return true});target=r.driver;defer{r.close()}
            if phase==5{armed=true;_ = r.driver.handle(try event(" ",code:49,modifiers:[.option]),client:r.client);XCTAssertNil(r.driver.recall);XCTAssertEqual(r.client.insertCalls,0);continue}
            if phase==4{var calls=0;r.client.onGeometry={calls+=1;r.driver.close()};_ = r.driver.handle(try event(" ",code:49,modifiers:[.option]),client:r.client);XCTAssertEqual(calls,1);XCTAssertNil(r.driver.recall);XCTAssertEqual(r.client.insertCalls,0);continue}
            let state=try review(r),callback={r.driver.close()}
            switch phase {case 0:r.client.onSelectedRange=callback;case 1:r.client.onMarkedRange=callback;case 2:r.client.onRead=callback;case 3:r.client.onInsert=callback;default:r.client.onGeometry=callback}
            r.driver.acceptExpression(token:state.token)
            XCTAssertNil(r.driver.recall);XCTAssertLessThanOrEqual(r.client.insertCalls,1);XCTAssertEqual(r.client.markCalls,0)
            if phase<2{XCTAssertEqual(r.client.insertCalls,0)}
            r.driver.acceptExpression(token:state.token);XCTAssertLessThanOrEqual(r.client.insertCalls,1)
        }
    }
    @MainActor func testFailedExpressionSaveQuarantinesUntilExplicitReadOnlyVerification()throws {
        _=NSApplication.shared
        for fault in [ExpressionTestFault.beforePublication,.afterPublication] {
            let r=try Rig(fault:fault);defer{r.close()}
            XCTAssertThrowsError(try r.workspace.saveExpression("new exact",aliases:[],catalogRevision:1));XCTAssertNil(r.workspace.expressionCatalog)
            XCTAssertThrowsError(try r.workspace.reloadExpressions());XCTAssertNil(r.workspace.expressionCatalog)
            r.driver.activate(try XCTUnwrap(IMKTextInputBridge(r.client)));_ = r.driver.handle(try event(" ",code:49,modifiers:[.option]),client:r.client);XCTAssertNil(r.driver.recall)
            let disk=try r.authority(),result=try r.workspace.verifyExpressionSave();XCTAssertEqual(try r.authority(),disk);XCTAssertNotNil(r.workspace.expressionCatalog)
            XCTAssertEqual(result.resolution,fault == .afterPublication ? .published:.previous);XCTAssertEqual(r.client.insertCalls,0)
        }
    }
    @MainActor func testUnconfirmedManagerNewSaveAndDeletionReconcileWithoutDuplicateOrResurrection()throws {
        _=NSApplication.shared
        for deletion in [false,true] {
            let r=try Rig(fault:.afterPublication);defer{r.close()}
            let manager=ExpressionManager(workspace:r.workspace);manager.show();defer{manager.close()}
            if deletion{manager.records.selectItem(at:1);manager.selectRecord(nil);manager.deleteAction(nil)}
            else{manager.editor.string="new exact";manager.aliases.stringValue="new";manager.saveAction(nil)}
            XCTAssertTrue(r.store.hasUnverifiedSave);XCTAssertFalse(manager.editor.isEditable)
            manager.show();XCTAssertNil(r.workspace.expressionCatalog);XCTAssertThrowsError(try r.store.snapshot())
            let disk=try r.authority();manager.newRecord(nil);manager.saveAction(nil);XCTAssertEqual(try r.authority(),disk)
            manager.verifyAction(nil);XCTAssertEqual(try r.authority(),disk);XCTAssertFalse(r.store.hasUnverifiedSave);manager.verifyAction(nil);XCTAssertNotNil(r.workspace.expressionCatalog);XCTAssertEqual(try r.authority(),disk)
            if deletion{XCTAssertNil(manager.selected);XCTAssertTrue(manager.editor.string.isEmpty);manager.saveAction(nil);XCTAssertTrue(r.workspace.expressionCatalog?.search("").isEmpty==true)}
            else{let id=try XCTUnwrap(manager.selected?.id);XCTAssertEqual(manager.editor.string,"new exact");manager.saveAction(nil);XCTAssertEqual(manager.selected?.id,id);XCTAssertEqual(r.workspace.expressionCatalog?.document?.records.count,2)}
        }
    }
    @MainActor func testInvalidDraftCanBeCorrectedWithoutRestartAndStaleDraftNeverRebases()throws {
        _=NSApplication.shared;let r=try Rig();defer{r.close()}
        let manager=ExpressionManager(workspace:r.workspace);manager.show();defer{manager.close()}
        let initial=try r.authority();manager.saveAction(nil);XCTAssertEqual(try r.authority(),initial);XCTAssertTrue(manager.save.isEnabled)
        manager.editor.string="new exact";manager.saveAction(nil);XCTAssertEqual(r.workspace.expressionCatalog?.document?.records.count,2)
        let selected=try XCTUnwrap(manager.selected)
        _ = try r.workspace.saveExpression("changed elsewhere",aliases:[],editing:selected.id,recordRevision:selected.revision,catalogRevision:2)
        manager.show();XCTAssertEqual(manager.selected?.revision,selected.revision);XCTAssertFalse(manager.save.isEnabled)
        let current=try r.authority();manager.saveAction(nil);XCTAssertEqual(try r.authority(),current)
    }
    @MainActor func testFailedOrReentrantReviewPresentationNeverAuthorizesInsertion()throws {
        _=NSApplication.shared
        for reentrant in [false,true] {
            weak var target:IMKControllerDriver?;var attempts=0
            let r=try Rig(present:{state,_ in
                if state.review != nil{attempts+=1;if reentrant{target?.acceptExpression(token:state.token)};return false};return true
            });target=r.driver;defer{r.close()}
            let state=try open(r);r.driver.reviewExpression(state.rows[0].ref,token:state.token)
            XCTAssertEqual(attempts,1);XCTAssertNil(r.driver.recall);XCTAssertEqual(r.client.insertCalls,0)
            r.driver.acceptExpression(token:state.token);XCTAssertEqual(r.client.insertCalls,0)
        }
        let panel=ExpressionPanel();defer{panel.orderOut(nil)};let r=try Rig();defer{r.close()};let state=try review(r)
        XCTAssertFalse(panel.show(state,below:NSRect(x:10000,y:10000,width:1,height:22),screen:NSRect(x:0,y:0,width:800,height:600)))
        XCTAssertFalse(panel.isVisible)
    }
    @MainActor func testRealNonKeyFullReviewPanelAndExplicitEditorSave()throws {
        let app=NSApplication.shared;_ = app.setActivationPolicy(.accessory)
        let long=String(repeating:"原话保留数字 42、否定、e\u{301} 与 👩🏽‍💻。\n",count:80)+"末句完整。",panel=ExpressionPanel()
        defer{panel.orderOut(nil)}
        let screen=try XCTUnwrap(NSScreen.main).visibleFrame
        let r=try Rig(text:long,hide:{panel.orderOut(nil)},present:{state,rect in panel.show(state,below:rect,screen:screen)});defer{r.close()}
        let host=NSWindow(contentRect:NSRect(x:40,y:60,width:640,height:240),styleMask:[.titled],backing:.buffered,defer:false);host.isReleasedWhenClosed=false;host.contentView=r.client.view;host.makeKeyAndOrderFront(nil);host.makeFirstResponder(r.client.view);defer{host.close()}
        _ = try review(r);panel.displayIfNeeded()
        XCTAssertTrue(panel.isVisible);XCTAssertFalse(panel.isKeyWindow);XCTAssertFalse(panel.canBecomeKey);XCTAssertTrue(host.firstResponder===r.client.view)
        XCTAssertEqual(Array(panel.textView.string.utf8),Array(long.utf8));XCTAssertFalse(panel.textView.isEditable)
        let state=try XCTUnwrap(r.driver.recall);panel.scrollReview(1,token:state.token);XCTAssertGreaterThan(panel.scroll.contentView.bounds.minY,0)
        panel.scrollReview(-1,token:state.token)
        let view=try XCTUnwrap(panel.contentView),bitmap=try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in:view.bounds));view.cacheDisplay(in:view.bounds,to:bitmap)
        let data=try XCTUnwrap(bitmap.representation(using:.png,properties:[:]))
        if let path=ProcessInfo.processInfo.environment["PAIA_EXPRESSION_CAPTURE"]{try data.write(to:URL(fileURLWithPath:path),options:.atomic)}
        for _ in 0..<30{panel.scrollReview(1,token:state.token)}
        let endRange=try XCTUnwrap(panel.textView.layoutManager).glyphRange(forBoundingRect:panel.textView.visibleRect,in:try XCTUnwrap(panel.textView.textContainer))
        XCTAssertEqual(NSMaxRange(endRange),panel.textView.layoutManager?.numberOfGlyphs)
        XCTAssertTrue(panel.textView.string.hasSuffix("末句完整。"))
        let tail=try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in:view.bounds));view.cacheDisplay(in:view.bounds,to:tail)
        if let path=ProcessInfo.processInfo.environment["PAIA_EXPRESSION_CAPTURE_TAIL"]{try XCTUnwrap(tail.representation(using:.png,properties:[:])).write(to:URL(fileURLWithPath:path),options:.atomic)}
        fputs("EXPRESSION_UI_STAGE captured\n",stderr)
        r.driver.cancelRecall(token:state.token);XCTAssertFalse(panel.isVisible);fputs("EXPRESSION_UI_STAGE cancelled\n",stderr);let manager=ExpressionManager(workspace:r.workspace);manager.show();defer{manager.close()}
        fputs("EXPRESSION_UI_STAGE manager-open\n",stderr)
        XCTAssertTrue(manager.isOpen);XCTAssertTrue(manager.editor.string.isEmpty)
        manager.editor.string=Self.exact;manager.aliases.stringValue="newalias";manager.saveAction(nil);fputs("EXPRESSION_UI_STAGE saved\n",stderr)
        XCTAssertEqual(r.workspace.expressionCatalog?.search("newalias").first?.record.exactText?.utf8.map{$0},Array(Self.exact.utf8));XCTAssertEqual(r.client.insertCalls,0)
        fputs("EXPRESSION_UI_STAGE before-cleanup\n",stderr)
        print("EXPRESSION_NATIVE ENGINE_NATIVE + APPKIT_HOST; exact store/editor/recall/full review/one commit; authored protocol clients only")
    }
}
#endif
