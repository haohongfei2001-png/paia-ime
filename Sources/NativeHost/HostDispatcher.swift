#if os(macOS)
import AppKit
import EngineBridge
import SessionCore

// Exact native state, also used to predict the only permitted cancellation write.
// Never replace this prediction with whatever a synchronous callback left behind.
@MainActor struct NativeTextState {
    let text:String,selection:NSRange,marked:NSRange
    private let hasMarked:Bool,cleared:Bool
    init(_ client:NSTextView){text=client.string;selection=client.selectedRange();marked=client.markedRange();hasMarked=client.hasMarkedText();cleared=false}
    private init(text:String,selection:NSRange,marked:NSRange,hasMarked:Bool){self.text=text;self.selection=selection;self.marked=marked;self.hasMarked=hasMarked;cleared = !hasMarked}
    func replacing(with replacement:String,selectedRange:NSRange?=nil,asMarked:Bool)->NativeTextState? {
        let range=hasMarked ? marked:selection,length=(text as NSString).length,newLength=(replacement as NSString).length
        let relative=selectedRange ?? NSRange(location:newLength,length:0)
        guard range.location != NSNotFound,range.location>=0,range.length>=0,
              range.location<=length,range.length<=length-range.location,
              relative.location>=0,relative.length>=0,relative.location<=newLength,relative.length<=newLength-relative.location else{return nil}
        let (location,overflow)=range.location.addingReportingOverflow(relative.location);guard !overflow else{return nil}
        let value=(text as NSString).replacingCharacters(in:range,with:replacement),isMarked=asMarked && !replacement.isEmpty
        return NativeTextState(text:value,selection:NSRange(location:location,length:relative.length),
                               marked:NSRange(location:isMarked ? range.location:location,length:isMarked ? newLength:0),hasMarked:isMarked)
    }
    func removingMark()->NativeTextState? {
        guard hasMarked else{return nil}
        return replacing(with:"",asMarked:false)
    }
    func matchesDocumentAndSelection(_ client:NSTextView)->Bool {client.string.utf8.elementsEqual(text.utf8) && client.selectedRange()==selection}
    func matches(_ client:NSTextView)->Bool {
        guard matchesDocumentAndSelection(client),client.hasMarkedText()==hasMarked else{return false}
        // NSTextView can retain finite empty-mark metadata after a completed write.
        // Only a projected unmarked result may ignore that empty location; entry
        // snapshots and every actual marked composition still compare exact ranges.
        return cleared ? client.markedRange().length==0 : client.markedRange()==marked
    }
}

@MainActor public final class HostDispatcher {
    public let session: InputSession
    private weak var client: NSTextView?
    private var active=true,applying=false
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
        return client.string.utf8.elementsEqual(expectedText.utf8) && client.selectedRange()==expectedSelection && client.markedRange()==expectedMarked
    }
    public init(client: NSTextView, session: InputSession) {
        self.client=client; self.session=session
        expectedText=client.string;expectedSelection=client.selectedRange();expectedMarked=client.markedRange()
        // Never adopt a composition that another text-input owner already placed here.
        // Every mark later cleared by this dispatcher must originate in its own apply.
        guard !client.hasMarkedText() else{active=false;session.end();return}
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
        return false
    }
    public func validateFocusChange(to responder:NSResponder?) {
        if inspector != nil && !permitsInspectorFocus(responder){invalidate()}
    }
    public func resumeInspector(_ token:UUID)->Bool {
        guard let state=inspector,state.token==token,let client=client,let window=client.window,
              permitsInspectorFocus(window.firstResponder) else{invalidate();return false}
        // Keep the lease live across the synchronous window focus callback; otherwise
        // the controller could cancel the still-owned proposal during restoration.
        guard window.makeFirstResponder(client) else{invalidate();return false}
        inspector=nil
        guard isCurrentTarget else{invalidate();return false}
        return true
    }
    deinit {for token in observers {NotificationCenter.default.removeObserver(token)}}
    @discardableResult public func apply(_ update: SessionUpdate) -> Bool {
        guard !applying,inspector==nil,update.refusal==nil else{return false}
        guard isCurrentTarget else {invalidate();return false}
        guard active, let client=client, let s=update.snapshot, s.session==session.key,
              let current=session.snapshot, s.targetEpoch==current.targetEpoch,
              s.inputGeneration==current.inputGeneration else {return false}
        applying=true;defer{applying=false}
        let originalWindow=client.window
        func stillOwned()->Bool {
            guard active,inspector==nil,self.client===client,client.window===originalWindow,
                  let now=session.snapshot,now.session==s.session,now.targetEpoch==s.targetEpoch,
                  now.inputGeneration==s.inputGeneration else{return false}
            return originalWindow==nil || originalWindow?.firstResponder===client
        }
        func abandon()->Bool {
            // Do not touch a host again after losing ownership inside a native call.
            // An already reserved insertion is not replayable, even if its outcome is uncertain.
            retireWithoutHostMutation();return false
        }
        if let effect=update.commit {
            // Exact-range reviewed edits require the qualified IMK context owner.
            // This owned-lab dispatcher must not silently ignore a replacement range.
            guard effect.replacementUTF16==nil,effect.origin != .reviewedEdit else{return abandon()}
            guard let inserted=NativeTextState(client).replacing(with:effect.text,asMarked:false) else{return abandon()}
            guard session.reserve(effect) else {return false}
            // Reservation precedes the only insertText call. No retry even if a real host's outcome is uncertain.
            client.insertText(effect.text,replacementRange:NSRange(location:NSNotFound,length:0))
            insertCount += 1
            guard stillOwned(),inserted.matches(client) else{return abandon()}
        }
        if s.preedit.isEmpty {
            if client.hasMarkedText() {
                guard let cleared=NativeTextState(client).removingMark() else{return abandon()}
                client.setMarkedText("",selectedRange:NSRange(location:0,length:0),replacementRange:NSRange(location:NSNotFound,length:0))
                guard stillOwned(),cleared.matchesDocumentAndSelection(client) else{return abandon()}
                if client.hasMarkedText() {
                    guard client.markedRange()==NSRange(location:cleared.selection.location,length:0) else{return abandon()}
                    client.unmarkText()
                }
                guard stillOwned(),cleared.matches(client) else{return abandon()}
            }
        } else {
            guard let marked=NativeTextState(client).replacing(with:s.preedit,selectedRange:s.selectedRangeUTF16,asMarked:true) else{return abandon()}
            client.setMarkedText(s.preedit,selectedRange:s.selectedRangeUTF16,replacementRange:NSRange(location:NSNotFound,length:0))
            guard stillOwned(),marked.matches(client) else{return abandon()}
        }
        guard stillOwned() else{return abandon()}
        expectedText=client.string;expectedSelection=client.selectedRange();expectedMarked=client.markedRange()
        return true
    }
    // Retiring an obsolete dispatcher must not clear the new owner's native text.
    func retireWithoutHostMutation(){active=false;inspector=nil;session.end()}
    public func invalidate() {
        guard active else {return}
        retireWithoutHostMutation()
        if let client=client,client.string.utf8.elementsEqual(expectedText.utf8),client.selectedRange()==expectedSelection,client.markedRange()==expectedMarked,client.hasMarkedText() {
            let originalWindow=client.window,originalResponder=client.window?.firstResponder
            guard let cancelled=NativeTextState(client).removingMark() else{return}
            client.setMarkedText("",selectedRange:NSRange(location:0,length:0),replacementRange:NSRange(location:NSNotFound,length:0))
            guard client.window===originalWindow,originalWindow?.firstResponder===originalResponder,
                  cancelled.matchesDocumentAndSelection(client) else{return}
            // Clearing may already have unmarked. Otherwise only our empty mark is
            // eligible; a foreign mark installed by the callback must be preserved.
            if client.hasMarkedText(),client.markedRange()==NSRange(location:expectedMarked.location,length:0){client.unmarkText()}
        }
    }
}
#endif
