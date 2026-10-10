#if os(macOS)
import AppKit
import EngineBridge
import SessionCore

// A restricted, uninstalled C0 integration lane. Nonempty/unknown initial selections
// and foreign marks are not adopted. No surrounding context or document scan is used.
@MainActor public final class IMKSessionCoordinator {
    public private(set) var session:InputSession?
    public private(set) var insertCount=0
    public private(set) var notice:String?
    public enum Outcome:Equatable {case inactive,ready,refused,ownershipLost,outcomeUnknown}
    public struct Recovery {public let raw:String,preedit:String,issuedText:String?}
    public private(set) var outcome:Outcome = .inactive
    public private(set) var recovery:Recovery?
    public private(set) var activation:UInt64=0
    private var client:IMKClientAccess?
    private var expectedSelection=NSRange(location:NSNotFound,length:0)
    private var expectedMark=NSRange(location:NSNotFound,length:0)
    private var ownedText:String?
    private var executing=false
    private var operationRaw="",operationPreedit="",issuedText:String?
    private var hostWriteIssued=false
    public init() {}
    public var snapshot:CandidateSnapshot? {session?.snapshot}
    public var identity:AnyObject? {client?.callbackIdentity}
    private func same(_ other:AnyObject)->Bool {client?.callbackIdentity === other}
    public func retire() {
        activation &+= 1;session?.end();session=nil;client=nil;ownedText=nil
        expectedSelection=NSRange(location:NSNotFound,length:0);expectedMark=expectedSelection
        operationRaw="";operationPreedit="";issuedText=nil;hostWriteIssued=false
    }
    public func interrupt(_ reason:String){
        guard session != nil || executing else{retire();return}
        if !executing,let active=session{beginOperation(active)}
        fail(reason)
    }
    @discardableResult public func activate(_ next:IMKClientAccess,makeSession:()->InputSession?) -> Bool {
        if executing{fail("Activation changed during a client operation.");return false}
        executing=true;defer{executing=false}
        retire();notice=nil;outcome = .inactive
        let ticket=activation
        let selection=next.selectedRange();guard activation==ticket else{return false}
        let mark=next.markedRange()
        guard activation==ticket,selection.location>=0,selection.location != NSNotFound,selection.length==0,mark.length==0 else{
            notice="This client selection or foreign composition is not supported by this integration lane.";return false
        }
        guard let prepared=makeSession() else{notice="Verified input resources are unavailable.";return false}
        guard activation==ticket else{prepared.end();return false}
        do {
            let initial=try prepared.refresh()
            guard initial.commit==nil,initial.snapshot?.rawASCII.isEmpty==true,initial.snapshot?.preedit.isEmpty==true,
                  activation==ticket else{prepared.end();return false}
            let afterSelection=next.selectedRange();guard activation==ticket,afterSelection==selection else{prepared.end();return false}
            let afterMark=next.markedRange();guard activation==ticket,afterMark==mark else{prepared.end();return false}
        } catch {prepared.end();return false}
        client=next;session=prepared;expectedSelection=selection;expectedMark=mark;outcome = .ready;return true
    }
    private func stillOwned(_ ticket:UInt64,_ owner:IMKClientAccess,_ active:InputSession)->Bool {
        activation==ticket && client === owner && session === active
    }
    private func verify(_ ticket:UInt64,_ owner:IMKClientAccess,_ active:InputSession)->Bool {
        guard stillOwned(ticket,owner,active) else{return false}
        let selection=owner.selectedRange();guard stillOwned(ticket,owner,active) else{return false}
        let mark=owner.markedRange()
        guard stillOwned(ticket,owner,active),selection==expectedSelection else{return false}
        if let ownedText=ownedText {
            guard mark==expectedMark,mark.length==ownedText.utf16.count else{return false}
            let text=owner.text(in:mark)
            guard stillOwned(ticket,owner,active),text?.utf8.elementsEqual(ownedText.utf8)==true else{return false}
            let afterSelection=owner.selectedRange();guard stillOwned(ticket,owner,active),afterSelection==selection else{return false}
            let afterMark=owner.markedRange();return stillOwned(ticket,owner,active) && afterMark==mark
        }
        return mark.length==0
    }
    public func hasCurrentTarget(_ sender:AnyObject)->Bool {
        guard !executing,same(sender),let owner=client,let active=session else{return false}
        executing=true;defer{executing=false};beginOperation(active)
        let ticket=activation
        guard verify(ticket,owner,active) else{if stillOwned(ticket,owner,active){fail("Client ownership changed.")};return false}
        return true
    }
    public func candidateRect(_ sender:AnyObject)->NSRect? {
        guard !executing,same(sender),let owner=client,let active=session else{return nil}
        executing=true;defer{executing=false};beginOperation(active)
        let ticket=activation
        guard verify(ticket,owner,active) else{if stillOwned(ticket,owner,active){fail("Client changed before candidate positioning.")};return nil}
        let rect=owner.lineRect(at:expectedSelection.location)
        guard stillOwned(ticket,owner,active),verify(ticket,owner,active) else{if stillOwned(ticket,owner,active){fail("Client changed during candidate positioning.")};return nil}
        return rect
    }
    private func fail(_ text:String){
        notice=text;outcome = hostWriteIssued ? .outcomeUnknown:.ownershipLost
        if !operationRaw.isEmpty || !operationPreedit.isEmpty || issuedText != nil {
            recovery=Recovery(raw:operationRaw,preedit:operationPreedit,issuedText:issuedText)
        }
        retire()
    }
    private func beginOperation(_ active:InputSession){
        operationRaw=active.snapshot?.rawASCII ?? "";operationPreedit=active.snapshot?.preedit ?? "";issuedText=nil;hostWriteIssued=false
    }
    private func preserveAcceptedInput(_ update:SessionUpdate){
        if let raw=update.snapshot?.rawASCII,!raw.isEmpty{operationRaw=raw}
        if let preedit=update.snapshot?.preedit,!preedit.isEmpty{operationPreedit=preedit}
    }
    private func apply(_ update:SessionUpdate,ticket:UInt64,owner:IMKClientAccess,active:InputSession)->Bool {
        guard verify(ticket,owner,active),let value=update.snapshot,value.session==active.key,
              active.snapshot?.inputGeneration==value.inputGeneration else{return false}
        if let effect=update.commit {
            let start=ownedText==nil ? expectedSelection.location:expectedMark.location,length=effect.text.utf16.count
            guard length<=16384,start>=0,start != NSNotFound,length<=Int.max-start,active.reserve(effect) else{return false}
            let replacement=ownedText==nil ? expectedSelection:expectedMark
            issuedText=effect.text;hostWriteIssued=true;owner.insert(effect.text,replacing:replacement);insertCount+=1
            guard stillOwned(ticket,owner,active) else{return false}
            let selection=owner.selectedRange();guard stillOwned(ticket,owner,active) else{return false}
            let mark=owner.markedRange();guard stillOwned(ticket,owner,active) else{return false}
            guard selection==NSRange(location:start+length,length:0),mark.length==0 else{return false}
            let text=owner.text(in:NSRange(location:start,length:length))
            guard stillOwned(ticket,owner,active),text?.utf8.elementsEqual(effect.text.utf8)==true else{return false}
            let afterSelection=owner.selectedRange();guard stillOwned(ticket,owner,active),afterSelection==selection else{return false}
            let afterMark=owner.markedRange();guard stillOwned(ticket,owner,active),afterMark.length==0 else{return false}
            expectedSelection=selection;expectedMark=mark;ownedText=nil
        }
        guard verify(ticket,owner,active) else{return false}
        if value.preedit.isEmpty {
            if ownedText != nil {
                let start=expectedMark.location
                hostWriteIssued=true;owner.mark("",selection:NSRange(location:0,length:0),replacing:expectedMark)
                guard stillOwned(ticket,owner,active) else{return false}
                let afterSelection=owner.selectedRange();guard stillOwned(ticket,owner,active),afterSelection==NSRange(location:start,length:0) else{return false}
                let afterMark=owner.markedRange();guard stillOwned(ticket,owner,active),afterMark.length==0 else{return false}
                expectedSelection=NSRange(location:start,length:0);expectedMark=afterMark;ownedText=nil
            }
        } else {
            let start=ownedText==nil ? expectedSelection.location:expectedMark.location,length=value.preedit.utf16.count
            let relative=value.selectedRangeUTF16
            guard length<=16384,start>=0,start != NSNotFound,length<=Int.max-start,relative.location>=0,
                  relative.length>=0,relative.location<=length,relative.length<=length-relative.location else{return false}
            let mark=NSRange(location:start,length:length),selection=NSRange(location:start+relative.location,length:relative.length)
            hostWriteIssued=true;owner.mark(value.preedit,selection:relative,replacing:ownedText==nil ? expectedSelection:expectedMark)
            guard stillOwned(ticket,owner,active) else{return false}
            let afterMark=owner.markedRange();guard stillOwned(ticket,owner,active),afterMark==mark else{return false}
            let afterSelection=owner.selectedRange();guard stillOwned(ticket,owner,active),afterSelection==selection else{return false}
            let text=owner.text(in:mark)
            guard stillOwned(ticket,owner,active),text?.utf8.elementsEqual(value.preedit.utf8)==true else{return false}
            let finalMark=owner.markedRange();guard stillOwned(ticket,owner,active),finalMark==mark else{return false}
            let finalSelection=owner.selectedRange();guard stillOwned(ticket,owner,active),finalSelection==selection else{return false}
            expectedMark=mark;expectedSelection=selection;ownedText=value.preedit
        }
        return verify(ticket,owner,active)
    }
    @discardableResult public func process(_ key:InputKey,client sender:AnyObject)->Bool {
        if executing{fail("Reentrant client operation refused. No text was replayed.");return true}
        guard same(sender),let owner=client,let active=session else{return false}
        executing=true;defer{executing=false};let ticket=activation
        beginOperation(active)
        guard verify(ticket,owner,active) else{if stillOwned(ticket,owner,active){fail("Client changed. No text was replayed or cleared.")};return true}
        do {
            let update=try active.process(key)
            preserveAcceptedInput(update)
            if let refusal=update.refusal {
                outcome = .refused
                switch refusal {
                case .textBeforeRawSuffix:notice="Text before the remaining spelling is unsupported. Composition unchanged. Move to the end or use Return/Escape first."
                case .unsupportedTextDuringComposition:notice="This text is unsupported during composition. Return keeps spelling; Escape cancels. Then enter it again."
                case .unhandledControlDuringComposition:notice="This key is unsupported during composition. Composition unchanged."
                }
                return true
            }
            guard stillOwned(ticket,owner,active),apply(update,ticket:ticket,owner:owner,active:active) else{
                if stillOwned(ticket,owner,active){fail("Input outcome is unconfirmed. No automatic retry or further text write.")}
                return true
            }
            if !update.handled,(update.snapshot?.rawASCII.isEmpty==false || update.snapshot?.preedit.isEmpty==false) {
                notice="This control is unsupported during composition. Use Return or Escape before continuing.";outcome = .refused;return true
            }
            notice=nil;outcome = .ready
            if !update.handled{retire()}
            return update.handled
        } catch {if stillOwned(ticket,owner,active){fail("Input stopped safely. No automatic retry or text cleanup.")};return true}
    }
    @discardableResult public func choose(_ ref:CandidateRef,client sender:AnyObject)->Bool {
        if executing{fail("Reentrant candidate operation refused.");return false}
        guard same(sender),let owner=client,let active=session else{return false}
        executing=true;defer{executing=false};let ticket=activation
        beginOperation(active)
        guard verify(ticket,owner,active) else{fail("Client changed. Candidate discarded.");return false}
        do {
            let update=try active.select(ref)
            preserveAcceptedInput(update)
            guard stillOwned(ticket,owner,active),apply(update,ticket:ticket,owner:owner,active:active) else{
                if stillOwned(ticket,owner,active){fail("Candidate outcome is unconfirmed. It will not be replayed.")};return false
            }
            notice=nil;outcome = .ready;return true
        }catch{return false}
    }
    // Only a matching lifecycle callback may request the existing raw-Return policy.
    // A stale callback never binds itself to the newly active client.
    @discardableResult public func finish(client sender:AnyObject)->Bool {
        guard same(sender) else{return false}
        if executing{fail("Lifecycle changed during a client operation.");return false}
        let ticket=activation
        _=process(.returnKey,client:sender)
        guard activation==ticket,same(sender),outcome == .ready else{return false}
        retire();return true
    }
    public func deactivate(client sender:AnyObject){
        guard same(sender) else{return};let ticket=activation
        _=finish(client:sender)
        if activation==ticket,same(sender){retire()}
    }
    @discardableResult public func releaseIdle(client sender:AnyObject)->Bool {
        guard !executing,same(sender),let owner=client,let active=session,
              active.snapshot?.rawASCII.isEmpty==true,active.snapshot?.preedit.isEmpty==true else{return false}
        executing=true;defer{executing=false};let ticket=activation;beginOperation(active)
        guard verify(ticket,owner,active) else{if stillOwned(ticket,owner,active){fail("Client changed before idle passthrough.")};return false}
        retire();outcome = .ready;return true
    }
}
#endif
