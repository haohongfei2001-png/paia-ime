#if os(macOS)
import XCTest
import AppKit
import IMKHost
import IMKTestClient
import EngineBridge

final class IMKFixtureBasicsTests:XCTestCase {
    @MainActor func testActualFixtureFactoryRefusesMissingSchemasAndPreservesHostOwnership()throws {
        _=NSApplication.shared
        var variables=ProcessInfo.processInfo.environment;variables["PAIA_IMK_RESEARCH"]="0";variables["PAIA_B3_SETTINGS"]="0"
        let environment=try IMKServiceEnvironment(environment:variables);defer{environment.close()}
        let workspace=environment.workspace
        let driver=workspace.makeDriver(hide:{},present:{_,_,_ in}),client=PAIAIMKTestClient(text:"existing👩🏽‍💻")
        defer{driver.close()}
        XCTAssertEqual(driver.activate(try XCTUnwrap(IMKTextInputBridge(client))),.ready)
        let old=try XCTUnwrap(driver.coordinator.session)
        for spelling in [LabSpelling.flypy,.natural] {
            var next=LabConfiguration();next.spelling=spelling
            XCTAssertThrowsError(try workspace.applyConfiguration(next));XCTAssertTrue(driver.coordinator.session===old)
        }
        var next=LabConfiguration();next.traditional=true;XCTAssertThrowsError(try workspace.applyConfiguration(next))
        next=LabConfiguration();next.chinesePunctuation=true;XCTAssertThrowsError(try workspace.applyConfiguration(next))
        XCTAssertEqual(workspace.configuration,LabConfiguration());XCTAssertNoThrow(try old.refresh())
        next=LabConfiguration();next.literal=true;try workspace.applyConfiguration(next)
        let event=try XCTUnwrap(NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[],timestamp:0,windowNumber:0,context:nil,characters:"x",charactersIgnoringModifiers:"x",isARepeat:false,keyCode:0))
        XCTAssertFalse(driver.handle(event,client:client));XCTAssertEqual(client.view.string,"existing👩🏽‍💻");XCTAssertEqual(client.insertCalls,0)
        // This mark belongs to an external text system after idle release. No
        // PAIA settings/callback path may adopt, clear, commit or rewrite it.
        client.view.setMarkedText("外部e\u{301}",selectedRange:NSRange(location:0,length:0),replacementRange:client.view.selectedRange())
        let text=client.view.string,mark=client.view.markedRange(),selection=client.view.selectedRange()
        XCTAssertFalse(driver.handle(event,client:client))
        XCTAssertEqual(client.view.string,text);XCTAssertEqual(client.view.markedRange(),mark);XCTAssertEqual(client.view.selectedRange(),selection)
        XCTAssertEqual(client.insertCalls,0);XCTAssertEqual(client.markCalls,0);XCTAssertEqual(client.documentLengthCalls,0)
        print("IMK_FIXTURE_BASIC missing schemas refused; verified literal release; external marked owner retained; no service started")
    }
}
#endif
