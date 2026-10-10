#if os(macOS)
import AppKit
import EngineBridge
import SessionCore
@MainActor public final class LabTextView: NSTextView {
    public var dispatcher: HostDispatcher?
    public var literalMode=false
    public var willEdit:(()->Void)?
    public var didChangeState:(()->Void)?
    public var didRefuseInput:((InputRefusal)->Void)?
    public private(set) var lastInputRefusal:InputRefusal?
    private func refuse(_ reason:InputRefusal){lastInputRefusal=reason;didRefuseInput?(reason)}
    public let candidates=CandidatePanel()
    public var makeSession:(()->HostDispatcher?)?
    public func renew() {
        dispatcher?.invalidate();candidates.orderOut(nil);dispatcher=nil
        // If invalidation could not clear the mark, it is not ours to replace.
        // A nil dispatcher lets keyDown continue through AppKit's text system.
        guard !hasMarkedText() else{return}
        dispatcher=makeSession?()
    }
    public override func resignFirstResponder()->Bool {defer{didChangeState?()};if dispatcher?.isInspectorSuspended != true {dispatcher?.invalidate();candidates.orderOut(nil)};return super.resignFirstResponder()}
    // Shared mouse-edit policy; tests invoke this boundary without pretending to exercise pointer tracking.
    public func cancelCompositionForHostEdit(){willEdit?();dispatcher?.invalidate();candidates.orderOut(nil);didChangeState?()}
    public override func mouseDown(with event:NSEvent) {cancelCompositionForHostEdit();super.mouseDown(with:event);didChangeState?()}
    public override func keyDown(with event:NSEvent) {
        willEdit?()
        guard window==nil || window?.firstResponder===self else{return}
        lastInputRefusal=nil
        if literalMode {dispatcher?.invalidate();candidates.orderOut(nil);super.keyDown(with:event);didChangeState?();return}
        defer{didChangeState?()}
        if dispatcher?.isCurrentTarget != true {renew()}
        guard let dispatcher=dispatcher else {super.keyDown(with:event);return}
        if event.modifierFlags.contains(.command) || event.modifierFlags.contains(.option) {
            dispatcher.invalidate();candidates.orderOut(nil);super.keyDown(with:event);return
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
            guard dispatcher.apply(update) else{candidates.orderOut(nil);return}
            renderCandidates()
            if !update.handled {
                guard self.dispatcher===dispatcher,dispatcher.isCurrentTarget else{return}
                let snapshot=dispatcher.session.snapshot
                guard !hasMarkedText(),snapshot?.rawASCII.isEmpty != false,snapshot?.preedit.isEmpty != false else{
                    refuse(.unhandledControlDuringComposition);return
                }
                super.keyDown(with:event)
            }
        } catch {
            candidates.orderOut(nil);dispatcher.invalidate();NSSound.beep()
        }
    }
    public func renderCandidates() {
        guard let s=dispatcher?.session.snapshot,!s.rows.isEmpty,let screen=window?.screen else {candidates.orderOut(nil);return}
        let rect=firstRect(forCharacterRange:selectedRange(),actualRange:nil)
        candidates.show(s,below:rect,screen:screen.visibleFrame)
    }
}

#endif
