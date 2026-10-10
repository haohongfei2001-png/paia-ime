#if os(macOS)
import AppKit
import EngineBridge
import SessionCore
import ConstraintCore
import TextBoundary

// A restricted, uninstalled C0 integration lane. Nonempty/unknown initial selections
// and foreign marks are not adopted. No surrounding context or document scan is used.
@MainActor public final class IMKSessionCoordinator {
    public private(set) var session:InputSession?
    public private(set) var insertCount=0
    public private(set) var notice:String?
    public enum Outcome:Equatable {case inactive,ready,refused,ownershipLost,outcomeUnknown}
    public struct Recovery {
        public let raw:String,preedit:String,issuedText:String?
        public var hasContent:Bool {!raw.isEmpty || !preedit.isEmpty || issuedText != nil}
        public var inspectionText:String {
            var sections:[String]=[]
            if !raw.isEmpty{sections.append("Retained spelling\n"+raw)}
            if !preedit.isEmpty{sections.append("Original composition or selected text\n"+preedit)}
            if let issuedText=issuedText{sections.append("Issued text (outcome may be unknown)\n"+(issuedText.isEmpty ? "[Empty replacement: deletion]":issuedText))}
            else{sections.append("No text insertion was issued by this operation.")}
            return sections.joined(separator:"\n\n")
        }
    }
    public private(set) var outcome:Outcome = .inactive
    public private(set) var recovery:Recovery?
    public private(set) var activation:UInt64=0
    private var client:IMKClientAccess?
    private var contextOnly=false,capturedContext:ContextCapture?
    public var isContextReview:Bool {contextOnly}
    private var expectedSelection=NSRange(location:NSNotFound,length:0)
    private var expectedMark=NSRange(location:NSNotFound,length:0)
    private var ownedText:String?
    private var executing=false
    private var terminalRetiredFrom:UInt64?
    private var operationRaw="",operationPreedit="",issuedText:String?
    private var hostWriteIssued=false
    public init() {}
    public var snapshot:CandidateSnapshot? {session?.snapshot}
    // No host callbacks: process-wide management can inspect this without reentry.
    public var isIdleForManagement:Bool {
        !executing && !contextOnly && ownedText==nil && (snapshot == nil || (snapshot?.rawASCII.isEmpty==true && snapshot?.preedit.isEmpty==true)) &&
        (outcome == .ready || outcome == .inactive)
    }
    public var identity:AnyObject? {client?.callbackIdentity}
    private func same(_ other:AnyObject)->Bool {client?.callbackIdentity === other}
    public func retire() {
        activation &+= 1;terminalRetiredFrom=nil;contextOnly=false;capturedContext=nil;session?.end();session=nil;client=nil;ownedText=nil
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
    // Qualified C2/C3 actions are isolated from C0 even though they reserve effects
    // through the same InputSession and this same host dispatcher.
    private func observeContext(_ ticket:UInt64,_ owner:IMKClientAccess,_ active:InputSession,
                                selection:NSRange,request:NSRange?=nil)->(ContextEvidence,ContextAuthority)? {
        guard stillOwned(ticket,owner,active),let authority=owner.contextAuthority(),stillOwned(ticket,owner,active),
              authority.canRead,authority.cheapReliableLength else{return nil}
        let beforeSelection=owner.selectedRange();guard stillOwned(ticket,owner,active),beforeSelection==selection else{return nil}
        let beforeMark=owner.markedRange();guard stillOwned(ticket,owner,active),beforeMark.length==0 else{return nil}
        guard let length=owner.contextualLength(),stillOwned(ticket,owner,active),
              let requested=request ?? (try? ContextBudget.request(selection:selection,length:length)) else{return nil}
        guard let first=owner.boundedText(in:requested),stillOwned(ticket,owner,active) else{return nil}
        let midSelection=owner.selectedRange();guard stillOwned(ticket,owner,active),midSelection==selection else{return nil}
        let midMark=owner.markedRange();guard stillOwned(ticket,owner,active),midMark.length==0 else{return nil}
        let midLength=owner.contextualLength();guard stillOwned(ticket,owner,active),midLength==length else{return nil}
        let midAuthority=owner.contextAuthority();guard stillOwned(ticket,owner,active),midAuthority==authority else{return nil}
        guard let second=owner.boundedText(in:requested),stillOwned(ticket,owner,active),first.exactlyMatches(second) else{return nil}
        let afterSelection=owner.selectedRange();guard stillOwned(ticket,owner,active),afterSelection==selection else{return nil}
        let afterMark=owner.markedRange();guard stillOwned(ticket,owner,active),afterMark.length==0 else{return nil}
        let afterLength=owner.contextualLength();guard stillOwned(ticket,owner,active),afterLength==length else{return nil}
        let afterAuthority=owner.contextAuthority();guard stillOwned(ticket,owner,active),afterAuthority==authority,
              let evidence=try? ContextEvidence(read:first,selection:selection,documentLength:length) else{return nil}
        return (evidence,authority)
    }
    public func activateContext(_ next:IMKClientAccess,kind:ContextEditKind,makeSession:()->InputSession?)->ContextCapture? {
        guard !executing else{fail("Context capture reentered another operation.");return nil}
        executing=true;defer{executing=false};retire();outcome = .inactive;notice=nil
        let ticket=activation,offered=next.offersContext
        guard activation==ticket,offered else{return nil}
        let selection=next.selectedRange();guard activation==ticket,ContextBudget.end(selection) != nil,
              selection.length<=ContextBudget.selection,(kind == .knownCharacter ? selection.length==0:selection.length>0) else{return nil}
        let mark=next.markedRange();guard activation==ticket,mark.length==0 else{return nil}
        guard let prepared=makeSession() else{return nil}
        guard activation==ticket else{prepared.end();return nil}
        do {
            let initial=try prepared.refresh()
            guard initial.commit==nil,let binding=prepared.idleExpressionBinding,activation==ticket else{prepared.end();return nil}
            client=next;session=prepared;expectedSelection=selection;expectedMark=mark;contextOnly=true
            guard let (evidence,authority)=observeContext(ticket,next,prepared,selection:selection) else{
                if stillOwned(ticket,next,prepared){fail("Bounded context or its Unicode/permission evidence is unavailable.")};return nil
            }
            let rect=next.lineRect(at:selection.location)
            guard stillOwned(ticket,next,prepared),let rect=rect,
                  let (again,afterAuthority)=observeContext(ticket,next,prepared,selection:selection),
                  evidence.exactlyMatches(again),authority==afterAuthority else{
                if stillOwned(ticket,next,prepared){fail("Client changed while capturing the explicit context.")};return nil
            }
            let capture=ContextCapture(token:UUID(),original:evidence.original,selection:selection,kind:kind,
                canReplace:authority.canReplace,binding:binding,authority:authority,evidence:evidence,rect:rect)
            capturedContext=capture;outcome = .ready;return capture
        }catch{prepared.end();if activation==ticket{retire()};return nil}
    }
    public func validateContextReview(_ token:UUID,text:String,client sender:AnyObject)->Bool {
        guard !executing,contextOnly,same(sender),let capture=capturedContext,capture.token==token,
              let owner=client,let active=session,active.idleExpressionBinding==capture.binding else{return false}
        executing=true;defer{executing=false};let ticket=activation;beginOperation(active);operationPreedit=capture.original
        guard let (observed,authority)=observeContext(ticket,owner,active,selection:capture.selection),
              observed.exactlyMatches(capture.evidence),authority==capture.authority else{
            if stillOwned(ticket,owner,active){fail("Selected text or context permission changed. Review discarded.")};return false
        }
        guard (try? capture.evidence.replacing(with:text)) != nil else{
            notice="The proposed text exceeds the bound or joins a neighboring grapheme. Nothing changed.";return false
        }
        notice=nil;return true
    }
    public func applyContextEdit(_ token:UUID,text:String,client sender:AnyObject)->Bool {
        if executing{fail("Reentrant reviewed edit refused.");return false}
        guard contextOnly,same(sender),let capture=capturedContext,capture.token==token,capture.canReplace,
              let owner=client,let active=session,active.idleExpressionBinding==capture.binding,
              let replacement=try? capture.evidence.replacing(with:text) else{return false}
        executing=true;defer{executing=false};let ticket=activation;beginOperation(active);operationPreedit=capture.original
        do {
            let update=try active.commitReviewedEdit(text,replacing:capture.selection,binding:capture.binding)
            guard apply(update,ticket:ticket,owner:owner,active:active,reviewed:replacement) else{
                if stillOwned(ticket,owner,active){fail("Reviewed edit is unconfirmed. Check the document; no automatic retry or undo.")};return false
            }
            notice=nil;outcome = .ready;retire();return true
        }catch{if stillOwned(ticket,owner,active){fail("Reviewed edit refused. No text replay.")};return false}
    }
    public func cancelContext(){if contextOnly{if executing{fail("Context cancelled during a client operation.")}else{retire();outcome = .ready}}}
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
        guard mark.length==0 else{return false}
        // Idle expressions must not adopt a selection changed by a later getter.
        // Bounded repeated observations improve detection, not atomic host CAS.
        let afterSelection=owner.selectedRange();guard stillOwned(ticket,owner,active),afterSelection==selection else{return false}
        let afterMark=owner.markedRange();guard stillOwned(ticket,owner,active),afterMark==mark else{return false}
        let finalSelection=owner.selectedRange();return stillOwned(ticket,owner,active) && finalSelection==selection
    }
    public func hasCurrentTarget(_ sender:AnyObject)->Bool {
        guard !executing,!contextOnly,same(sender),let owner=client,let active=session else{return false}
        executing=true;defer{executing=false};beginOperation(active)
        let ticket=activation
        guard verify(ticket,owner,active) else{if stillOwned(ticket,owner,active){fail("Client ownership changed.")};return false}
        return true
    }
    public func candidateRect(_ sender:AnyObject)->NSRect? {
        guard !executing,!contextOnly,same(sender),let owner=client,let active=session else{return nil}
        executing=true;defer{executing=false};beginOperation(active)
        let ticket=activation
        guard verify(ticket,owner,active) else{if stillOwned(ticket,owner,active){fail("Client changed before candidate positioning.")};return nil}
        let rect=owner.lineRect(at:expectedSelection.location)
        guard stillOwned(ticket,owner,active),verify(ticket,owner,active) else{if stillOwned(ticket,owner,active){fail("Client changed during candidate positioning.")};return nil}
        return rect
    }
    private func fail(_ text:String){
        notice=text;outcome = (hostWriteIssued || outcome == .outcomeUnknown) ? .outcomeUnknown:.ownershipLost
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
    private func apply(_ update:SessionUpdate,ticket:UInt64,owner:IMKClientAccess,active:InputSession,reviewed:ContextReplacement?=nil)->Bool {
        guard let value=update.snapshot,value.session==active.key,
              active.snapshot?.inputGeneration==value.inputGeneration else{return false}
        if let replacement=reviewed {
            guard contextOnly,let capture=capturedContext,let effect=update.commit,effect.origin == .reviewedEdit,
                  effect.replacementUTF16==capture.selection,effect.text.utf8.elementsEqual(replacement.text.utf8),
                  let (observed,authority)=observeContext(ticket,owner,active,selection:capture.selection),
                  observed.exactlyMatches(capture.evidence),authority==capture.authority,authority.canReplace,
                  active.reserve(effect) else{return false}
            issuedText=effect.text;hostWriteIssued=true;owner.insert(effect.text,replacing:capture.selection);insertCount+=1
            guard stillOwned(ticket,owner,active),
                  let (after,afterAuthority)=observeContext(ticket,owner,active,selection:replacement.caret,request:replacement.expected.requested),
                  afterAuthority.permissionEpoch==authority.permissionEpoch,afterAuthority.canReplace,
                  after.documentLength==replacement.documentLength,after.read.exactlyMatches(replacement.expected) else{return false}
            expectedSelection=replacement.caret;expectedMark=NSRange(location:NSNotFound,length:0);ownedText=nil;return true
        }
        guard !contextOnly,verify(ticket,owner,active),update.commit?.replacementUTF16==nil else{return false}
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
        guard !contextOnly,same(sender),let owner=client,let active=session else{return false}
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
            if active.isRetainedComposition && update.snapshot?.rawASCII.isEmpty==true && update.snapshot?.preedit.isEmpty==true {
                retire();terminalRetiredFrom=ticket
            } else if !update.handled{retire()}
            return update.handled
        } catch {if stillOwned(ticket,owner,active){fail("Input stopped safely. No automatic retry or text cleanup.")};return true}
    }
    @discardableResult public func choose(_ ref:CandidateRef,client sender:AnyObject)->Bool {
        if executing{fail("Reentrant candidate operation refused.");return false}
        guard !contextOnly,same(sender),let owner=client,let active=session else{return false}
        executing=true;defer{executing=false};let ticket=activation
        beginOperation(active)
        guard verify(ticket,owner,active) else{fail("Client changed. Candidate discarded.");return false}
        do {
            let update=try active.select(ref)
            preserveAcceptedInput(update)
            guard stillOwned(ticket,owner,active),apply(update,ticket:ticket,owner:owner,active:active) else{
                if stillOwned(ticket,owner,active){fail("Candidate outcome is unconfirmed. It will not be replayed.")};return false
            }
            notice=nil;outcome = .ready
            if active.isRetainedComposition && active.snapshot?.rawASCII.isEmpty==true && active.snapshot?.preedit.isEmpty==true{retire()}
            return true
        }catch{return false}
    }
    private func observeRepair<T>(client sender:AnyObject,_ action:(InputSession)throws->T)->T? {
        if executing{fail("Reentrant repair operation refused.");return nil}
        guard !contextOnly,same(sender),let owner=client,let active=session else{return nil}
        executing=true;defer{executing=false};let ticket=activation;beginOperation(active)
        guard verify(ticket,owner,active) else{if stillOwned(ticket,owner,active){fail("Repair target changed.")};return nil}
        do {
            let result=try action(active)
            guard stillOwned(ticket,owner,active),verify(ticket,owner,active) else{if stillOwned(ticket,owner,active){fail("Repair target changed during search.")};return nil}
            notice=nil;outcome = .ready;return result
        }catch{
            guard stillOwned(ticket,owner,active),verify(ticket,owner,active) else{if stillOwned(ticket,owner,active){fail("Repair target changed during refusal.")};return nil}
            notice="Repair unavailable or stale. Original composition retained; confirm every remaining segment before repair.";outcome = .refused;return nil
        }
    }
    public func repairAnchors(client sender:AnyObject)->RepairAnchors? {
        observeRepair(client:sender){try $0.repairAnchors()}
    }
    public func repairAlternatives(target:RepairTarget,replacementRaw:String,client sender:AnyObject)->RepairAlternatives? {
        observeRepair(client:sender){try $0.repairAlternatives(target:target,replacementRaw:replacementRaw)}
    }
    public func prepareAlternative(_ choice:RepairAlternative,client sender:AnyObject)->RepairProposal? {
        observeRepair(client:sender){try $0.prepareAlternative(choice)}
    }
    @discardableResult public func beginRetained(binding:ExpressionBinding,client sender:AnyObject)->Bool {
        if executing{fail("Reentrant retained-session activation refused.");return false}
        guard !contextOnly,same(sender),let owner=client,let active=session,active.canRetainForRepair,
              !active.isRetainedComposition,active.idleExpressionBinding==binding else{return false}
        executing=true;defer{executing=false};let ticket=activation;beginOperation(active)
        guard verify(ticket,owner,active) else{if stillOwned(ticket,owner,active){fail("Retained-session target changed.")};return false}
        do {
            let update=try active.beginRetained(binding:binding)
            guard stillOwned(ticket,owner,active),apply(update,ticket:ticket,owner:owner,active:active) else{
                if stillOwned(ticket,owner,active){fail("Retained-session activation is unconfirmed.")};return false
            }
            notice="Next composition retained for repair. Return keeps spelling; Escape cancels. Confirm Chinese explicitly.";outcome = .ready;return true
        }catch{if stillOwned(ticket,owner,active){fail("Retained-session activation refused.")};return false}
    }
    @discardableResult public func applyRepair(_ proposal:RepairProposal,client sender:AnyObject)->Bool {
        if executing{fail("Reentrant repair application refused.");return false}
        guard !contextOnly,same(sender),let owner=client,let active=session,active.supportsRepair else{return false}
        executing=true;defer{executing=false};let ticket=activation;beginOperation(active)
        guard verify(ticket,owner,active) else{if stillOwned(ticket,owner,active){fail("Repair review target changed.")};return false}
        do {
            let update=try active.applyRepair(proposal);preserveAcceptedInput(update)
            guard update.commit==nil,stillOwned(ticket,owner,active),apply(update,ticket:ticket,owner:owner,active:active) else{
                if stillOwned(ticket,owner,active){fail("Repair mark application is unconfirmed. No automatic retry or cleanup.")};return false
            }
            notice="Repair applied only to composition. Commit Chinese explicitly, or Return keeps spelling.";outcome = .ready
            if active.snapshot?.rawASCII.isEmpty==true,active.snapshot?.preedit.isEmpty==true{retire()}
            return true
        }catch{notice="Repair proposal is stale or unavailable. Original composition retained.";return false}
    }
    @discardableResult public func commitRetained(client sender:AnyObject)->Bool {
        if executing{fail("Reentrant Chinese commit refused.");return false}
        guard !contextOnly,same(sender),let owner=client,let active=session,active.supportsRepair else{return false}
        executing=true;defer{executing=false};let ticket=activation;beginOperation(active)
        guard verify(ticket,owner,active) else{if stillOwned(ticket,owner,active){fail("Chinese commit target changed.")};return false}
        guard let anchors=try? active.repairAnchors(),!anchors.rows.isEmpty else{
            notice="Confirm every remaining segment before committing Chinese. Composition retained.";return false
        }
        do {
            let update=try active.commitEngineComposition()
            guard update.commit != nil,stillOwned(ticket,owner,active),apply(update,ticket:ticket,owner:owner,active:active) else{
                if stillOwned(ticket,owner,active){fail("Chinese commit is unconfirmed. No repeat or cleanup.")};return false
            }
            guard active.snapshot?.rawASCII.isEmpty==true,active.snapshot?.preedit.isEmpty==true else{fail("Engine did not finish the retained composition.");return false}
            notice=nil;outcome = .ready;retire();return true
        }catch{if stillOwned(ticket,owner,active){fail("Chinese commit failed. Check retained input; no replay or cleanup.")};return false}
    }
    // Explicit idle insertion shares apply/reserve, finite range and unknown-outcome policy.
    @discardableResult public func insertExpression(_ text:String,binding:ExpressionBinding,client sender:AnyObject)->Bool {
        if executing{fail("Reentrant expression insertion refused.");return false}
        guard !contextOnly,same(sender),let owner=client,let active=session,active.idleExpressionBinding==binding else{return false}
        executing=true;defer{executing=false};let ticket=activation;beginOperation(active)
        guard verify(ticket,owner,active) else{if stillOwned(ticket,owner,active){fail("Expression target changed. Nothing replayed.")};return false}
        do {
            let update=try active.commitExpression(text,binding:binding)
            guard stillOwned(ticket,owner,active),apply(update,ticket:ticket,owner:owner,active:active) else{
                if stillOwned(ticket,owner,active){fail("Expression insertion is unconfirmed. Check the original document; no retry.")};return false
            }
            notice=nil;outcome = .ready;if active.isRetainedComposition{retire()};return true
        }catch{if stillOwned(ticket,owner,active){fail("Expression insertion refused. No replay.")};return false}
    }
    // Only a matching lifecycle callback may request the existing raw-Return policy.
    // A stale callback never binds itself to the newly active client.
    @discardableResult public func finish(client sender:AnyObject)->Bool {
        guard same(sender) else{return false}
        if executing{fail("Lifecycle changed during a client operation.");return false}
        if contextOnly{cancelContext();return true}
        let ticket=activation
        _=process(.returnKey,client:sender)
        if terminalRetiredFrom==ticket,activation==ticket &+ 1,session==nil,outcome == .ready{return true}
        guard activation==ticket,same(sender),outcome == .ready else{return false}
        retire();return true
    }
    public func deactivate(client sender:AnyObject){
        guard same(sender) else{return};let ticket=activation
        _=finish(client:sender)
        if activation==ticket,same(sender){retire()}
    }
    @discardableResult public func releaseIdle(client sender:AnyObject)->Bool {
        guard !executing,!contextOnly,same(sender),let owner=client,let active=session,
              active.snapshot?.rawASCII.isEmpty==true,active.snapshot?.preedit.isEmpty==true else{return false}
        executing=true;defer{executing=false};let ticket=activation;beginOperation(active)
        guard verify(ticket,owner,active) else{if stillOwned(ticket,owner,active){fail("Client changed before idle passthrough.")};return false}
        retire();outcome = .ready;return true
    }
}
#endif
