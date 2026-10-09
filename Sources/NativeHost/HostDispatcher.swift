#if os(macOS)
import AppKit
import EngineBridge
import SessionCore

@MainActor public final class HostDispatcher {
    public let session: InputSession
    private weak var client: NSTextView?
    private var active=true
    private var observers:[NSObjectProtocol]=[]
    private var expectedText:String
    private var expectedSelection:NSRange
    private var expectedMarked:NSRange
    private struct InspectorState {let token:UUID,generation:UInt64,views:[NSView]}
    private var inspector:InspectorState?
    public var isInspectorSuspended:Bool {inspector != nil}
    public private(set) var insertCount=0
    public var isCurrentTarget:Bool {
        guard inspector==nil,unchangedTarget,let client=client else{return false}
        return client.window == nil || client.window?.firstResponder === client
    }
    private var unchangedTarget:Bool {
        guard active,let client=client else{return false}
        return client.string==expectedText && client.selectedRange()==expectedSelection && client.markedRange()==expectedMarked
    }
    public init(client: NSTextView, session: InputSession) {
        self.client=client; self.session=session
        expectedText=client.string;expectedSelection=client.selectedRange();expectedMarked=client.markedRange()
        if let window=client.window {
            observers.append(NotificationCenter.default.addObserver(forName:NSWindow.didResignKeyNotification,object:window,queue:.main) { [weak self] _ in
                MainActor.assumeIsolated {self?.invalidate()}
            })
        }
        observers.append(NotificationCenter.default.addObserver(forName:NSApplication.didResignActiveNotification,object:nil,queue:.main) { [weak self] _ in
            MainActor.assumeIsolated {self?.invalidate()}
        })
    }
    // Only an explicitly owned same-window inspector may temporarily hold keyboard focus.
    public func beginInspector(views:[NSView])->UUID? {
        guard isCurrentTarget,let client=client,let window=client.window,let s=session.snapshot,
              !views.isEmpty,views.allSatisfy({$0.window===window}) else{return nil}
        let token=UUID();inspector=InspectorState(token:token,generation:s.inputGeneration,views:views);return token
    }
    public func updateInspectorViews(_ token:UUID,views:[NSView])->Bool {
        guard let state=inspector,state.token==token,unchangedTarget,
              session.snapshot?.inputGeneration==state.generation,let window=client?.window,
              !views.isEmpty,views.allSatisfy({$0.window===window}) else{return false}
        inspector=InspectorState(token:token,generation:state.generation,views:views);return true
    }
    public func permitsInspectorFocus(_ responder:NSResponder?)->Bool {
        guard unchangedTarget,let state=inspector,session.snapshot?.inputGeneration==state.generation,let client=client else{return false}
        if responder===client{return true}
        if state.views.contains(where:{$0===responder}){return true}
        if let editor=responder as? NSTextView,editor.isFieldEditor,
           let delegate=editor.delegate as? NSView,state.views.contains(where:{$0===delegate}) {return true}
        return false
    }
    public func validateFocusChange(to responder:NSResponder?) {
        if inspector != nil && !permitsInspectorFocus(responder){invalidate()}
    }
    public func resumeInspector(_ token:UUID)->Bool {
        guard let state=inspector,state.token==token,let client=client,let window=client.window,
              permitsInspectorFocus(window.firstResponder) else{invalidate();return false}
        inspector=nil
        guard window.makeFirstResponder(client),isCurrentTarget else{invalidate();return false}
        return true
    }
    deinit {for token in observers {NotificationCenter.default.removeObserver(token)}}
    @discardableResult public func apply(_ update: SessionUpdate) -> Bool {
        guard inspector==nil else{return false}
        guard isCurrentTarget else {invalidate();return false}
        guard active, let client=client, let s=update.snapshot, s.session==session.key,
              let current=session.snapshot, s.targetEpoch==current.targetEpoch,
              s.inputGeneration==current.inputGeneration else {return false}
        if let effect=update.commit {
            guard session.reserve(effect) else {return false}
            // Reservation precedes the only insertText call. No retry even if a real host's outcome is uncertain.
            client.insertText(effect.text,replacementRange:NSRange(location:NSNotFound,length:0))
            insertCount += 1
        }
        if s.preedit.isEmpty {
            if client.hasMarkedText() {
                client.setMarkedText("",selectedRange:NSRange(location:0,length:0),replacementRange:NSRange(location:NSNotFound,length:0))
                client.unmarkText()
            }
        } else {
            client.setMarkedText(s.preedit,selectedRange:s.selectedRangeUTF16,replacementRange:NSRange(location:NSNotFound,length:0))
        }
        expectedText=client.string;expectedSelection=client.selectedRange();expectedMarked=client.markedRange()
        return true
    }
    public func invalidate() {
        guard active else {return}
        active=false; inspector=nil; session.end()
        if let client=client,client.string==expectedText,client.selectedRange()==expectedSelection,client.markedRange()==expectedMarked,client.hasMarkedText() {
            client.setMarkedText("",selectedRange:NSRange(location:0,length:0),replacementRange:NSRange(location:NSNotFound,length:0))
            client.unmarkText()
        }
    }
}
#endif
