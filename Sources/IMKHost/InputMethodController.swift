#if os(macOS)
import AppKit
import InputMethodKit
import EngineBridge
import NativeHost

@MainActor public enum InputMethodRuntime {public static var makeSession:(()->InputSession?)?}

// One IMK event path, forwarded into the exact driver exercised by protocol tests.
@MainActor @objc(PAIAInputMethodController) public final class InputMethodController:IMKInputController {
    private let panel=CandidatePanel()
    private lazy var driver=IMKControllerDriver(makeSession:{InputMethodRuntime.makeSession?()},hide:{[weak self] in self?.panel.orderOut(nil)},present:{[weak self] snapshot,rect,notice in
        guard let self=self,let screen=NSScreen.screens.first(where:{$0.frame.intersects(rect)}) else{return}
        if let snapshot=snapshot,!snapshot.rows.isEmpty{self.panel.show(snapshot,below:rect,screen:screen.visibleFrame,notice:notice)}
        else if let notice=notice{self.panel.showNotice(notice,below:rect,screen:screen.visibleFrame)}
    })
    public override func activateServer(_ sender:Any!) {
        guard let bridge=IMKTextInputBridge(sender) else{driver.close();return}
        panel.choose = {[weak self] ref in self?.driver.choose(ref)}
        driver.activate(bridge)
    }
    public override func recognizedEvents(_ sender:Any!)->Int {Int(NSEvent.EventTypeMask.keyDown.rawValue)}
    public override func handle(_ event:NSEvent!,client sender:Any!)->Bool {
        guard let event=event,let sender=sender as AnyObject? else{return false};return driver.handle(event,client:sender)
    }
    public override func commitComposition(_ sender:Any!){guard let sender=sender as AnyObject? else{return};driver.finish(client:sender)}
    public override func deactivateServer(_ sender:Any!){guard let sender=sender as AnyObject? else{return};driver.deactivate(client:sender)}
    public override func inputControllerWillClose(){driver.close()}
    public override func menu()->NSMenu! {
        let menu=NSMenu(title:"PAIA input method integration")
        let status=NSMenuItem(title:driver.coordinator.notice ?? "Uninstalled integration lane; no implicit learning",action:nil,keyEquivalent:"")
        status.isEnabled=false;menu.addItem(status)
        if driver.recovery?.raw.isEmpty==false {
            let item=NSMenuItem(title:"Inspect retained raw spelling…",action:#selector(inspectRetainedSpelling(_:)),keyEquivalent:"")
            item.target=self;item.isEnabled=driver.coordinator.session==nil;menu.addItem(item)
        }
        return menu
    }
    @objc private func inspectRetainedSpelling(_ sender:Any?) {
        guard driver.coordinator.session==nil,let text=driver.recovery?.raw,!text.isEmpty else{return}
        let alert=NSAlert();alert.messageText="Retained spelling; input outcome may be unknown"
        alert.informativeText="Check the original document before manually using this text. It may already have been inserted. Closing does not write to the client."
        let scroll=NSScrollView(frame:NSRect(x:0,y:0,width:440,height:160));scroll.hasVerticalScroller=true
        let textView=NSTextView(frame:scroll.bounds);textView.isEditable=false;textView.isSelectable=true;textView.isRichText=false;textView.string=text
        scroll.documentView=textView;alert.accessoryView=scroll;alert.addButton(withTitle:"Close");alert.runModal()
    }
}
#endif
