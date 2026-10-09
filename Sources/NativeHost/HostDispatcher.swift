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
    public private(set) var insertCount=0
    public var isCurrentTarget:Bool {
        guard active,let client=client else{return false}
        return client.string==expectedText && client.selectedRange()==expectedSelection && client.markedRange()==expectedMarked &&
          (client.window == nil || client.window?.firstResponder === client)
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
    deinit {for token in observers {NotificationCenter.default.removeObserver(token)}}
    @discardableResult public func apply(_ update: SessionUpdate) -> Bool {
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
        active=false; session.end()
        if let client=client,client.string==expectedText,client.selectedRange()==expectedSelection,client.markedRange()==expectedMarked,client.hasMarkedText() {
            client.setMarkedText("",selectedRange:NSRange(location:0,length:0),replacementRange:NSRange(location:NSNotFound,length:0))
            client.unmarkText()
        }
    }
}
#endif
