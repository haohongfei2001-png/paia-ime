#if os(macOS)
import AppKit
import EngineBridge
import SessionCore
@MainActor public final class LabTextView: NSTextView {
    public var dispatcher: HostDispatcher? {didSet{
        dispatcherGeneration &+= 1
        if oldValue !== dispatcher{oldValue?.retireWithoutHostMutation()}
    }}
    private var dispatcherGeneration:UInt64=0,keyGeneration:UInt64=0
    private var renewing=false
    public var literalMode=false {didSet{if literalMode != oldValue{keyGeneration &+= 1}}}
    public var willEdit:(()->Void)?
    public var didChangeState:(()->Void)?
    public var didRefuseInput:((InputRefusal)->Void)?
    public private(set) var lastInputRefusal:InputRefusal?
    private func refuse(_ reason:InputRefusal){lastInputRefusal=reason;didRefuseInput?(reason)}
    public let candidates=CandidatePanel()
    public var makeSession:(()->HostDispatcher?)?
    // A cancelled dispatcher is intentionally no longer current. Continuation
    // requires the precomputed native result, not that ended session's identity.
    private func cancelForContinuation()->Bool {
        let old=dispatcher,generation=dispatcherGeneration,key=keyGeneration,mode=literalMode
        let originalWindow=window,originalResponder=window?.firstResponder,before=NativeTextState(self)
        let expected = old?.isCurrentTarget==true && hasMarkedText() ? before.removingMark():before
        func sameContext()->Bool {
            dispatcherGeneration==generation && dispatcher===old && keyGeneration==key && literalMode==mode &&
                window===originalWindow && originalWindow?.firstResponder===originalResponder
        }
        candidates.orderOut(nil)
        guard sameContext(),before.matches(self) else{return false}
        old?.invalidate()
        return sameContext() && expected?.matches(self)==true
    }
    @discardableResult public func renew()->Bool {
        guard !renewing else{return false};renewing=true;defer{renewing=false}
        guard cancelForContinuation() else{return false}
        dispatcher=nil
        // If invalidation could not clear the mark, it is not ours to replace.
        // A nil dispatcher lets keyDown continue through AppKit's text system.
        guard !hasMarkedText() else{return true}
        let generation=dispatcherGeneration,key=keyGeneration,mode=literalMode,before=NativeTextState(self)
        let originalWindow=window,originalResponder=window?.firstResponder
        let prepared=makeSession?()
        guard dispatcherGeneration==generation,dispatcher==nil,keyGeneration==key,literalMode==mode,
              window===originalWindow,originalWindow?.firstResponder===originalResponder,before.matches(self) else{
            if prepared !== dispatcher{prepared?.retireWithoutHostMutation()};return false
        }
        dispatcher=prepared;return true
    }
    public override func resignFirstResponder()->Bool {defer{didChangeState?()};if dispatcher?.isInspectorSuspended != true {dispatcher?.invalidate();candidates.orderOut(nil)};return super.resignFirstResponder()}
    // Shared mouse-edit policy; tests invoke this boundary without pretending to exercise pointer tracking.
    private func prepareHostEdit()->Bool {
        keyGeneration &+= 1;let eventTicket=keyGeneration
        willEdit?();guard keyGeneration==eventTicket else{return false}
        return cancelForContinuation()
    }
    @discardableResult public func cancelCompositionForHostEdit()->Bool {let safe=prepareHostEdit();didChangeState?();return safe}
    public override func mouseDown(with event:NSEvent) {
        defer{didChangeState?()}
        guard prepareHostEdit() else{return};super.mouseDown(with:event)
    }
    public override func keyDown(with event:NSEvent) {
        keyGeneration &+= 1;let eventTicket=keyGeneration
        willEdit?()
        guard keyGeneration==eventTicket,window==nil || window?.firstResponder===self else{return}
        lastInputRefusal=nil
        defer{didChangeState?()}
        if literalMode {guard cancelForContinuation() else{return};super.keyDown(with:event);return}
        if dispatcher?.isCurrentTarget != true {guard renew(),keyGeneration==eventTicket else{return}}
        guard let dispatcher=dispatcher else {super.keyDown(with:event);return}
        func currentEvent()->Bool {keyGeneration==eventTicket && self.dispatcher===dispatcher}
        if event.modifierFlags.contains(.command) || event.modifierFlags.contains(.option) {
            guard cancelForContinuation() else{return};super.keyDown(with:event);return
        }
        let key:InputKey
        switch event.keyCode {
        case 36,76:key = .returnKey
        case 49:key = .space
        case 53:key = .escape
        case 51:key = .code(0xff08)
        case 117:key = .code(0xffff)
        case 123:key = .code(0xff51)
        case 124:key = .code(0xff53)
        case 125:key = .code(0xff54)
        case 126:key = .code(0xff52)
        case 115:key = .code(0xff50)
        case 119:key = .code(0xff57)
        case 116:key = .code(0xff55)
        case 121:key = .code(0xff56)
        case 48:key = .code(0xff09,modifiers:event.modifierFlags.contains(.shift) ? 1 : 0)
        default:
            key = .text(event.characters ?? "")
        }
        do {
            // The minimal A1 factory may return a fresh, uninitialized session.
            // Establish its real idle snapshot before requiring a successful apply.
            if dispatcher.session.snapshot==nil {
                guard dispatcher.apply(try dispatcher.session.refresh()) else{return}
            }
            let update=try dispatcher.session.process(key)
            // Refusal is an exact no-op: even applying its unchanged snapshot would
            // rewrite marked text and invite synchronous host callbacks.
            if let reason=update.refusal{refuse(reason);return}
            guard dispatcher.apply(update) else{if currentEvent(){candidates.orderOut(nil)};return}
            guard currentEvent() else{return}
            renderCandidates()
            if !update.handled {
                guard keyGeneration==eventTicket,self.dispatcher===dispatcher,dispatcher.isCurrentTarget else{return}
                let snapshot=dispatcher.session.snapshot
                guard !hasMarkedText(),snapshot?.sourceText.isEmpty != false,snapshot?.preedit.isEmpty != false else{
                    refuse(.unhandledControlDuringComposition);return
                }
                super.keyDown(with:event)
            }
        } catch {
            guard currentEvent() else{dispatcher.retireWithoutHostMutation();return}
            candidates.orderOut(nil)
            guard currentEvent() else{dispatcher.retireWithoutHostMutation();return}
            dispatcher.invalidate();if currentEvent(){NSSound.beep()}
        }
    }
    public func renderCandidates() {
        guard let s=dispatcher?.session.snapshot,!s.rows.isEmpty,let screen=window?.screen else {candidates.orderOut(nil);return}
        let rect=firstRect(forCharacterRange:selectedRange(),actualRange:nil)
        candidates.show(s,below:rect,screen:screen.visibleFrame)
    }
}

#endif
