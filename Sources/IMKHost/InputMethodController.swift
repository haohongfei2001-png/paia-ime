#if os(macOS)
import AppKit
import InputMethodKit
import EngineBridge
import NativeHost
import SessionCore

@MainActor public enum InputMethodRuntime {
    public static var workspace:IMKWorkspace?
    public static var preferences:IMKPreferencesController?
}

// One IMK event path, forwarded into the exact driver exercised by protocol tests.
@MainActor @objc(PAIAInputMethodController) public final class InputMethodController:IMKInputController {
    private let panel=CandidatePanel()
    private let expressionPanel=ExpressionPanel()
    private let repairPanel=SegmentRepairPanel()
    private lazy var driver:IMKControllerDriver = {
        let hide:()->Void = {[weak self] in self?.panel.orderOut(nil);self?.expressionPanel.orderOut(nil);self?.repairPanel.orderOut(nil)}
        let present:(CandidateSnapshot?,NSRect,String?)->Void = {[weak self] snapshot,rect,notice in
            guard let self=self,let screen=NSScreen.screens.first(where:{$0.frame.intersects(rect)}) else{return}
            if let snapshot=snapshot,!snapshot.rows.isEmpty{self.panel.show(snapshot,below:rect,screen:screen.visibleFrame,notice:notice)}
            else if let notice=notice{self.panel.showNotice(notice,below:rect,screen:screen.visibleFrame)}
        }
        let presentRecall:(ExpressionRecallState,NSRect)->Bool = {[weak self] state,rect in
            guard let self=self,let screen=NSScreen.screens.first(where:{$0.frame.intersects(rect)}),self.driver.recall?.token==state.token else{return false}
            self.panel.orderOut(nil);guard self.driver.recall?.token==state.token else{return false}
            return self.expressionPanel.show(state,below:rect,screen:screen.visibleFrame,isCurrent:{[weak self] in self?.driver.recall?.token==state.token})
        }
        let presentRepair:(SegmentRepairState,NSRect)->Bool = {[weak self] state,rect in
            guard let self=self,let screen=NSScreen.screens.first(where:{$0.frame.intersects(rect)}),self.driver.repair?.token==state.token else{return false}
            self.panel.orderOut(nil);self.expressionPanel.orderOut(nil)
            guard self.driver.repair?.token==state.token else{return false}
            return self.repairPanel.show(state,below:rect,screen:screen.visibleFrame,isCurrent:{[weak self] in self?.driver.repair?.token==state.token})
        }
        return InputMethodRuntime.workspace?.makeDriver(hide:hide,present:present,presentRecall:presentRecall,scrollRecall:{[weak self] direction,token in self?.expressionPanel.scrollReview(direction,token:token)},presentRepair:presentRepair,scrollRepair:{[weak self] direction,token in self?.repairPanel.scrollReview(direction,token:token)}) ?? IMKControllerDriver(makeSession:{nil},hide:hide,present:present)
    }()
    public override func activateServer(_ sender:Any!) {
        guard let bridge=IMKTextInputBridge(sender) else{driver.close();return}
        panel.choose = {[weak self] ref in self?.driver.choose(ref)}
        expressionPanel.review = {[weak self] ref,token in self?.driver.reviewExpression(ref,token:token)}
        expressionPanel.accept = {[weak self] token in self?.driver.acceptExpression(token:token)}
        expressionPanel.cancel = {[weak self] token in self?.driver.cancelRecall(token:token)}
        repairPanel.search = {[weak self] token in self?.driver.searchRepair(token:token)}
        repairPanel.review = {[weak self] row,token in self?.driver.reviewRepair(row:row,token:token)}
        repairPanel.apply = {[weak self] token in self?.driver.applyRepair(token:token)}
        repairPanel.cancel = {[weak self] token in self?.driver.cancelRepair(token:token)}
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
        let preferences=NSMenuItem(title:"Input settings, terms and expressions…",action:#selector(openPreferences(_:)),keyEquivalent:"")
        preferences.target=self;preferences.isEnabled=InputMethodRuntime.workspace?.isIdle==true;menu.addItem(preferences)
        for (title,arm) in [("Retain next composition for segment repair",true),("Commit fully confirmed Chinese",false)] {
            let action=driver.retainedMenuAction(arm:arm),item=NSMenuItem(title:title,action:#selector(retainedAction(_:)),keyEquivalent:"")
            item.target=self;item.representedObject=action;item.isEnabled=action != nil;menu.addItem(item)
        }
        if driver.recovery?.raw.isEmpty==false || driver.recovery?.issuedText != nil {
            let item=NSMenuItem(title:"Inspect retained input…",action:#selector(inspectRetainedSpelling(_:)),keyEquivalent:"")
            item.target=self;item.isEnabled=driver.coordinator.session==nil;menu.addItem(item)
        }
        return menu
    }
    @objc private func retainedAction(_ item:NSMenuItem){
        guard let action=item.representedObject as? RetainedMenuAction else{return};driver.performRetainedMenuAction(action)
    }
    @objc private func openPreferences(_ sender:Any?){
        guard InputMethodRuntime.workspace?.isIdle==true else{return};InputMethodRuntime.preferences?.show()
    }
    @objc private func inspectRetainedSpelling(_ sender:Any?) {
        guard driver.coordinator.session==nil,let recovery=driver.recovery else{return}
        let text=recovery.issuedText ?? recovery.raw;guard !text.isEmpty else{return}
        let alert=NSAlert();alert.messageText="Retained input; insertion outcome may be unknown"
        alert.informativeText="Check the original document before manually using this text. It may already have been inserted. Closing does not write to the client."
        let scroll=NSScrollView(frame:NSRect(x:0,y:0,width:440,height:160));scroll.hasVerticalScroller=true
        let textView=NSTextView(frame:scroll.bounds);textView.isEditable=false;textView.isSelectable=true;textView.isRichText=false;textView.string=text
        scroll.documentView=textView;alert.accessoryView=scroll;alert.addButton(withTitle:"Close");alert.runModal()
    }
}
#endif
