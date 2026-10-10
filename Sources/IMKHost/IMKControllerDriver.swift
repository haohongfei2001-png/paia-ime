#if os(macOS)
import AppKit
import EngineBridge
import SessionCore
import ExpressionCore
import ConstraintCore

// The framework controller and synthetic tests use this same dispatch/lifecycle
// path. Presentation is injected so synchronous AppKit callbacks are testable
// without constructing IMKServer or claiming framework-created controller proof.
@MainActor public final class IMKControllerDriver {
    public private(set) var coordinator=IMKSessionCoordinator()
    public private(set) var retainedRecovery:IMKSessionCoordinator.Recovery?
    public var recovery:IMKSessionCoordinator.Recovery? {coordinator.recovery ?? retainedRecovery}
    private let makeSession:()->InputSession?
    private let expressions:()->ExpressionCatalog?
    private let presentRecall:(ExpressionRecallState,NSRect)->Bool
    private let scrollRecall:(Int,UUID)->Void
    public private(set) var recall:ExpressionRecallState?
    public private(set) var repair:SegmentRepairState?
    public private(set) var contextEdit:ContextEditState?
    private var presentedContextToken:UUID?
    private var contextCandidate:(bridge:IMKClientAccess,identity:AnyObject)?
    private let presentContext:(ContextEditState,NSRect)->Bool,scrollContext:(Int,UUID)->Void
    private var presentedRepairToken:UUID?
    private var repairPresentationVisible=false,suppressRepeatedRepairEscape=false
    private let presentRepair:(SegmentRepairState,NSRect)->Bool
    private let scrollRepair:(Int,UUID)->Void
    private var presentedRecallToken:UUID?
    private let literal:()->Bool,permitOperation:()->Bool
    private let initialLiteral:((String?)->Bool)?,showCharacters:()->Void
    private var sessionLiteral:Bool?,activeBridge:IMKClientAccess?
    private let habitOwner=UUID()
    public var usesLiteralMode:Bool {sessionLiteral ?? literal()}
    private var operationDepth=0,closed=false
    public var isIdleForManagement:Bool {operationDepth==0 && recall==nil && repair==nil && contextEdit==nil && (closed || (activationDepth==0 && coordinator.isIdleForManagement))}
    public var managementRevision:UInt64 {generation}
    // State retirement is separated from presentation so all old bindings retire
    // before the first reentrant AppKit hide callback.
    public func retireIdleForManagement(resetInitialMode:Bool=false){
        precondition(isIdleForManagement)
        if resetInitialMode{sessionLiteral=nil}
        generation &+= 1;discardContext();discardRepair();recall=nil;pendingActivation=nil;coordinator.retire();contextCandidate=nil;lastRect=nil
    }
    public func dismissCandidatesForManagement(){hideAll()}
    public func discardIdleBindingForManagement(){
        precondition(isIdleForManagement)
        generation &+= 1;discardContext();discardRepair();recall=nil;pendingActivation=nil;coordinator.retire();contextCandidate=nil;current=nil;activeBridge=nil;sessionLiteral=nil;lastRect=nil
    }
    private func enter()->Bool {
        guard permitOperation() else{return false};operationDepth+=1;return true
    }
    private func leave(){operationDepth-=1}
    private let hide:()->Void,present:(CandidateSnapshot?,NSRect,String?)->Void
    private var current:AnyObject?,lastRect:NSRect?
    private var generation:UInt64=0
    private var activationDepth=0
    private var pendingActivation:(ticket:UInt64,owner:IMKSessionCoordinator,identity:AnyObject)?
    public enum ActivationResult:Equatable {case ready,refused,superseded}
    public init(makeSession:@escaping ()->InputSession?,expressions:@escaping()->ExpressionCatalog?={nil},literal:@escaping ()->Bool={false},permitOperation:@escaping ()->Bool={true},initialLiteral:((String?)->Bool)?=nil,showCharacters:@escaping ()->Void={},hide:@escaping ()->Void,present:@escaping (CandidateSnapshot?,NSRect,String?)->Void,presentRecall:@escaping(ExpressionRecallState,NSRect)->Bool={_,_ in false},scrollRecall:@escaping(Int,UUID)->Void={_,_ in},presentRepair:@escaping(SegmentRepairState,NSRect)->Bool={_,_ in false},scrollRepair:@escaping(Int,UUID)->Void={_,_ in},presentContext:@escaping(ContextEditState,NSRect)->Bool={_,_ in false},scrollContext:@escaping(Int,UUID)->Void={_,_ in}) {
        self.presentContext=presentContext;self.scrollContext=scrollContext;self.presentRepair=presentRepair;self.scrollRepair=scrollRepair;self.makeSession=makeSession;self.expressions=expressions;self.presentRecall=presentRecall;self.scrollRecall=scrollRecall;self.literal=literal;self.permitOperation=permitOperation;self.initialLiteral=initialLiteral;self.showCharacters=showCharacters;self.hide=hide;self.present=present
    }
    private func matches(_ ticket:UInt64,_ owner:IMKSessionCoordinator,_ sender:AnyObject)->Bool {
        generation==ticket && coordinator === owner && current===sender
    }
    @discardableResult public func activate(_ bridge:IMKClientAccess)->ActivationResult {activate(bridge,preservingMode:false)}
    private func activate(_ bridge:IMKClientAccess,preservingMode:Bool)->ActivationResult {
        guard enter() else{return .superseded};defer{leave()}
        let previousMode=preservingMode ? sessionLiteral:nil
        activeBridge=nil;contextCandidate=nil;closed=false;activationDepth+=1;defer{activationDepth-=1}
        generation &+= 1;discardContext();discardRepair();recall=nil;let ticket=generation
        coordinator.interrupt("Previous activation ended. No text was replayed or cleared.")
        retainedRecovery=coordinator.recovery ?? retainedRecovery
        let next=IMKSessionCoordinator();coordinator=next;current=nil;lastRect=nil
        pendingActivation=(ticket,next,bridge.callbackIdentity)
        defer{if pendingActivation?.ticket==ticket{pendingActivation=nil}}
        hideAll();guard generation==ticket,coordinator===next else{return .superseded}
        var nextMode=previousMode
        if nextMode==nil,let initialLiteral=initialLiteral {
            let application=bridge.applicationIdentifier
            guard generation==ticket,coordinator===next else{return .superseded}
            nextMode=initialLiteral(application)
            guard generation==ticket,coordinator===next else{return .superseded}
        }
        let accepted=next.activate(bridge,makeSession:makeSession)
        guard generation==ticket,coordinator===next else{next.retire();return .superseded}
        let offered=bridge.offersContext
        guard generation==ticket,coordinator===next else{return .superseded}
        let identity=bridge.callbackIdentity
        guard generation==ticket,coordinator===next else{return .superseded}
        contextCandidate=offered ? (bridge,identity):nil
        guard accepted else{return .refused}
        current=identity;activeBridge=bridge;sessionLiteral=nextMode
        return .ready
    }
    public func handle(_ event:NSEvent,client sender:AnyObject)->Bool {
        guard event.type == .keyDown else{return false}
        guard enter() else{return false};defer{leave()}
        if activationDepth>0{generation &+= 1;coordinator.interrupt("Key event reentered activation. No automatic replay.");return true}
        guard current===sender else{
            // A C0-refused selection can still offer an explicit context menu.
            // Any intervening key for that client retires previously issued menus.
            if contextCandidate?.identity===sender{generation &+= 1};return false
        }
        generation &+= 1
        if coordinator.session==nil {
            guard coordinator.outcome == .ready,let bridge=activeBridge ?? IMKTextInputBridge(sender) else{return true}
            switch activate(bridge,preservingMode:true){case .ready:break;case .refused:return false;case .superseded:return true}
        }
        guard current===sender,coordinator.session != nil else{return false}
        let owner=coordinator,ticket=generation
        if !event.isARepeat{suppressRepeatedRepairEscape=false}
        if event.keyCode==53,event.isARepeat,suppressRepeatedRepairEscape{return true}
        if contextEdit != nil{return handleContext(event,client:sender,ticket:ticket,owner:owner)}
        let modifiers=event.modifierFlags.intersection([.command,.option,.control,.shift])
        if event.keyCode==49,modifiers == [.option] {
            // This must precede generic modifier flush; busy recall never commits.
            if recall==nil,owner.session?.idleExpressionBinding != nil,expressions()==nil {
                let safe=owner.releaseIdle(client:sender);render(sender,ticket:ticket,owner:owner)
                return matches(ticket,owner,sender) ? !safe:true
            }
            if !event.isARepeat,recall==nil,let binding=owner.session?.idleExpressionBinding,
               let catalog=expressions(),owner.hasCurrentTarget(sender),matches(ticket,owner,sender) {
                recall=ExpressionRecallState(query:"",rows:catalog.search(""),binding:binding,catalogEpoch:catalog.epoch)
                renderRecall(sender,ticket:ticket,owner:owner)
            }
            return true
        }
        if recall != nil{return handleRecall(event,client:sender,ticket:ticket,owner:owner)}
        if modifiers == [.option],event.charactersIgnoringModifiers?.lowercased()=="l",let session=owner.session,session.mixedDraft != nil {
            if !event.isARepeat{_=owner.performMixed(session.mixedLiteralIntent ? .spelling:.literal,client:sender)}
            render(sender,ticket:ticket,owner:owner);return true
        }
        if modifiers == [.option],event.keyCode==123 || event.keyCode==124,
           owner.snapshot?.sourceText.isEmpty==false || owner.snapshot?.preedit.isEmpty==false {
            if !event.isARepeat{navigateRepair(event.keyCode==123 ? -1:1,client:sender,ticket:ticket,owner:owner)}
            return true
        }
        if repair != nil {
            if event.keyCode==36 || event.keyCode==76 || !modifiers.intersection([.command,.option,.control]).isEmpty {
                discardRepair() // Default Return/modifier lifecycle semantics remain below.
            }else{return handleRepair(event,client:sender,ticket:ticket,owner:owner)}
        }
        if usesLiteralMode {
            let safe=owner.releaseIdle(client:sender)
            render(sender,ticket:ticket,owner:owner)
            return matches(ticket,owner,sender) ? !safe:true
        }
        if !event.modifierFlags.intersection([.command,.option,.control]).isEmpty {
            let composing=owner.snapshot?.sourceText.isEmpty==false || owner.snapshot?.preedit.isEmpty==false
            let safe=composing ? owner.finish(client:sender):owner.releaseIdle(client:sender)
            render(sender,ticket:ticket,owner:owner)
            return matches(ticket,owner,sender) ? !safe:true
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
        case 48:key = .code(0xff09,modifiers:event.modifierFlags.contains(.shift) ? 1:0)
        default:key = .text(event.characters ?? "")
        }
        let consumed=owner.process(key,client:sender),activation=owner.activation
        render(sender,ticket:ticket,owner:owner)
        return matches(ticket,owner,sender) && owner.activation==activation ? consumed:true
    }
    public func choose(_ candidate:CandidateRef){
        guard enter() else{return};defer{leave()}
        guard let sender=current else{return};generation &+= 1;let ticket=generation,owner=coordinator
        guard contextEdit==nil,recall==nil,repair==nil else{return}
        _=owner.choose(candidate,client:sender);render(sender,ticket:ticket,owner:owner)
    }
    private func cancelPendingActivation(_ sender:AnyObject)->Bool {
        guard let pending=pendingActivation,pending.identity===sender,
              generation==pending.ticket,coordinator===pending.owner else{return false}
        generation &+= 1;discardContext();discardRepair();recall=nil;pendingActivation=nil
        pending.owner.interrupt("Lifecycle ended during activation. No text was written.")
        contextCandidate=nil;current=nil;activeBridge=nil;sessionLiteral=nil;lastRect=nil;hideAll()
        return true
    }
    public func finish(client sender:AnyObject){
        guard enter() else{return};defer{leave()}
        if cancelPendingActivation(sender){return}
        guard current===sender else{
            if contextCandidate?.identity===sender{generation &+= 1;contextCandidate=nil;coordinator.retire();hideAll()};return
        };generation &+= 1;discardContext();discardRepair();recall=nil;let ticket=generation,owner=coordinator
        _=owner.finish(client:sender);render(sender,ticket:ticket,owner:owner)
    }
    public func deactivate(client sender:AnyObject){
        guard enter() else{return};defer{leave()}
        if cancelPendingActivation(sender){return}
        guard current===sender else{
            if contextCandidate?.identity===sender{generation &+= 1;contextCandidate=nil;coordinator.retire();hideAll()};return
        };generation &+= 1;discardContext();discardRepair();recall=nil;let ticket=generation,owner=coordinator
        owner.deactivate(client:sender)
        guard matches(ticket,owner,sender) else{return}
        retainedRecovery=owner.recovery ?? retainedRecovery;contextCandidate=nil;current=nil;activeBridge=nil;sessionLiteral=nil;lastRect=nil
        hideAll() // No state writes follow a presentation callback.
    }
    public func close(){
        guard enter() else{return};defer{leave()}
        generation &+= 1;discardContext();discardRepair();recall=nil;pendingActivation=nil;coordinator.interrupt("Controller closed. No automatic text cleanup.")
        retainedRecovery=coordinator.recovery ?? retainedRecovery;contextCandidate=nil;current=nil;activeBridge=nil;sessionLiteral=nil;lastRect=nil;closed=true;hideAll()
    }
    public func invalidateRecallForShutdown(){generation &+= 1;discardContext();discardRepair();recall=nil;contextCandidate=nil;hideAll()}
    public func cancelRecall(token:UUID){
        guard enter() else{return};defer{leave()};guard recall?.token==token else{return}
        generation &+= 1;discardContext();discardRepair();recall=nil;hideAll()
    }
    public func reviewExpression(_ ref:ExpressionRef,token:UUID){
        guard enter() else{return};defer{leave()}
        guard let sender=current,let state=recall,state.token==token,state.review==nil,
              state.rows.contains(where:{$0.ref==ref}),let catalog=expressions(),catalog.epoch==state.catalogEpoch,
              let record=catalog.resolve(ref) else{return}
        generation &+= 1;let ticket=generation,owner=coordinator
        guard owner.hasCurrentTarget(sender),matches(ticket,owner,sender),recall?.token==token else{if matches(ticket,owner,sender){recall=nil;hideAll()};return}
        guard let match=state.rows.first(where:{$0.ref==ref}),record.exactText?.utf8.elementsEqual(match.record.exactText?.utf8 ?? "".utf8)==true else{return}
        recall=ExpressionRecallState(query:state.query,rows:state.rows,selected:state.selected,review:match,binding:state.binding,catalogEpoch:state.catalogEpoch)
        renderRecall(sender,ticket:ticket,owner:owner)
    }
    public func acceptExpression(token:UUID){
        guard enter() else{return};defer{leave()}
        guard let sender=current,let state=recall,state.token==token,presentedRecallToken==token,let review=state.review,
              let catalog=expressions(),catalog.epoch==state.catalogEpoch,let record=catalog.resolve(review.ref),
              let text=record.exactText,text.utf8.elementsEqual(review.record.exactText?.utf8 ?? "".utf8) else{return}
        // Consume BEFORE the first client or presentation callback. No retry token survives.
        generation &+= 1;let ticket=generation,owner=coordinator;recall=nil
        _=owner.insertExpression(text,binding:state.binding,client:sender)
        guard matches(ticket,owner,sender) else{return};hideAll()
    }
    private func handleRecall(_ event:NSEvent,client sender:AnyObject,ticket:UInt64,owner:IMKSessionCoordinator)->Bool {
        guard let state=recall,let catalog=expressions(),catalog.epoch==state.catalogEpoch,
              owner.session?.idleExpressionBinding==state.binding,owner.hasCurrentTarget(sender),
              matches(ticket,owner,sender),recall?.token==state.token else{
            if matches(ticket,owner,sender){recall=nil;hideAll()};return true
        }
        if event.keyCode==53{recall=nil;hideAll();return true}
        if !event.modifierFlags.intersection([.command,.control,.option]).isEmpty {
            recall=nil;let safe=owner.releaseIdle(client:sender)
            if matches(ticket,owner,sender){hideAll()};return matches(ticket,owner,sender) ? !safe:true
        }
        if event.keyCode==36 || event.keyCode==76 {
            guard !event.isARepeat else{return true}
            if state.review != nil{acceptExpression(token:state.token)}
            else if state.rows.indices.contains(state.selected){reviewExpression(state.rows[state.selected].ref,token:state.token)}
            return true
        }
        if state.review != nil{if event.keyCode==116 || event.keyCode==121{scrollRecall(event.keyCode==116 ? -1:1,state.token)};return true} // Full review stays fixed until explicit use/cancel.
        var query=state.query,selected=state.selected
        switch event.keyCode {
        case 125:selected=min(max(0,state.rows.count-1),selected+1)
        case 126:selected=max(0,selected-1)
        case 51:if !query.isEmpty{query.removeLast()};selected=0
        default:
            let chars=event.characters ?? ""
            guard !chars.isEmpty,!chars.unicodeScalars.contains(where:{CharacterSet.controlCharacters.contains($0)}),
                  query.utf16.count+chars.utf16.count<=256 else{return true}
            query+=chars;selected=0
        }
        recall=ExpressionRecallState(query:query,rows:catalog.search(query),selected:selected,binding:state.binding,catalogEpoch:state.catalogEpoch)
        renderRecall(sender,ticket:ticket,owner:owner);return true
    }
    private func discardContext(){contextEdit=nil;presentedContextToken=nil;coordinator.cancelContext()}
    public func revokeContextAccess(){
        guard enter() else{return};defer{leave()}
        generation &+= 1;discardContext();contextCandidate=nil;hideAll()
    }
    public func contextMenuAction(kind:ContextEditKind)->ContextMenuAction? {
        guard !closed,activationDepth==0,operationDepth==0,contextEdit==nil,recall==nil,repair==nil,
              coordinator.isIdleForManagement,let candidate=contextCandidate else{return nil}
        return ContextMenuAction(generation:generation,activation:coordinator.activation,identity:ObjectIdentifier(candidate.identity),kind:kind)
    }
    public func performContextMenuAction(_ action:ContextMenuAction){
        guard enter() else{return};defer{leave()}
        guard generation==action.generation,coordinator.activation==action.activation,coordinator.isIdleForManagement,
              contextEdit==nil,recall==nil,repair==nil,let candidate=contextCandidate,
              ObjectIdentifier(candidate.identity)==action.identity else{return}
        generation &+= 1;let ticket=generation;activationDepth+=1;defer{activationDepth-=1}
        coordinator.retire();let owner=IMKSessionCoordinator();coordinator=owner;current=nil;lastRect=nil
        pendingActivation=(ticket,owner,candidate.identity)
        defer{if pendingActivation?.ticket==ticket{pendingActivation=nil}}
        hideAll();guard generation==ticket,coordinator===owner else{return}
        let capture=owner.activateContext(candidate.bridge,kind:action.kind,makeSession:makeSession)
        guard generation==ticket,coordinator===owner else{owner.retire();return}
        guard let capture=capture else{retainedRecovery=owner.recovery ?? retainedRecovery;return}
        current=candidate.identity;contextEdit=ContextEditState(capture:capture)
        renderContext(candidate.identity,ticket:ticket,owner:owner)
    }
    public func cancelContext(token:UUID){
        guard enter() else{return};defer{leave()};guard contextEdit?.token==token else{return}
        generation &+= 1;discardContext();hideAll()
    }
    public func reviewContext(token:UUID){
        guard enter() else{return};defer{leave()}
        guard let sender=current,let state=contextEdit,state.token==token,!state.reviewed else{return}
        generation &+= 1;let ticket=generation,owner=coordinator;presentedContextToken=nil
        guard let text=state.replacement else{
            contextEdit=ContextEditState(capture:state.capture,draft:state.draft,caret:state.caret,notice:"Enter one explicit U+ scalar identifier. No guessing or character discovery.")
            renderContext(sender,ticket:ticket,owner:owner);return
        }
        let valid=owner.validateContextReview(state.capture.token,text:text,client:sender)
        guard matches(ticket,owner,sender),contextEdit?.token==token else{return}
        guard owner.isContextReview else{discardContext();hideAll();return}
        contextEdit=ContextEditState(capture:state.capture,draft:state.draft,caret:state.caret,reviewed:valid,notice:owner.notice)
        renderContext(sender,ticket:ticket,owner:owner)
    }
    public func applyContext(token:UUID){
        guard enter() else{return};defer{leave()}
        guard let sender=current,let state=contextEdit,state.token==token,state.reviewed,state.capture.canReplace,
              presentedContextToken==token,let text=state.replacement else{return}
        // Consume the only presentation capability BEFORE any host callback.
        generation &+= 1;let ticket=generation,owner=coordinator;contextEdit=nil;presentedContextToken=nil
        _=owner.applyContextEdit(state.capture.token,text:text,client:sender)
        guard matches(ticket,owner,sender) else{return}
        owner.cancelContext();retainedRecovery=owner.recovery ?? retainedRecovery;hideAll()
    }
    private func handleContext(_ event:NSEvent,client sender:AnyObject,ticket:UInt64,owner:IMKSessionCoordinator)->Bool {
        guard let state=contextEdit,owner.isContextReview,owner.session?.idleExpressionBinding==state.capture.binding else{
            if matches(ticket,owner,sender){discardContext();hideAll()};return true
        }
        if event.keyCode==53{discardContext();suppressRepeatedRepairEscape=true;hideAll();return true}
        if !event.modifierFlags.intersection([.command,.option,.control]).isEmpty {
            discardContext();hideAll();return matches(ticket,owner,sender) ? false:true
        }
        if event.keyCode==36 || event.keyCode==76 {
            if !event.isARepeat {if state.reviewed{applyContext(token:state.token)}else{reviewContext(token:state.token)}}
            return true
        }
        if state.reviewed,(event.keyCode==116 || event.keyCode==121){scrollContext(event.keyCode==116 ? -1:1,state.token);return true}
        let editable=state.reviewed ? ContextEditState(capture:state.capture,draft:state.draft,caret:state.caret):state
        if let next=editable.editing(code:event.keyCode,text:event.characters ?? "") {
            contextEdit=next;presentedContextToken=nil;renderContext(sender,ticket:ticket,owner:owner)
        }else if !(event.characters ?? "").isEmpty || event.keyCode==48 {
            contextEdit=ContextEditState(capture:state.capture,draft:state.draft,caret:state.caret,notice:"Unsupported draft key. Original and draft unchanged; Cancel to return to the host.")
            presentedContextToken=nil;renderContext(sender,ticket:ticket,owner:owner)
        }
        return true
    }
    private func renderContext(_ sender:AnyObject,ticket:UInt64,owner:IMKSessionCoordinator){
        guard matches(ticket,owner,sender),let state=contextEdit,owner.isContextReview,
              owner.session?.idleExpressionBinding==state.capture.binding else{return}
        // No selectedRange/length/context/geometry callbacks on draft keys or paint.
        let shown=presentContext(state,state.capture.rect)
        guard matches(ticket,owner,sender),contextEdit?.token==state.token else{return}
        guard shown else{discardContext();hideAll();return};presentedContextToken=state.token
    }
    private func hideAll(){repairPresentationVisible=false;hide()}
    private func discardRepair(){
        if repair != nil{coordinator.session?.invalidateRepairActions()}
        repair?.proposal?.cancel();repair=nil;presentedRepairToken=nil
    }
    public func inputHabitMenuAction(_ kind:InputHabitActionKind)->InputHabitMenuAction? {
        guard !closed,activationDepth==0,operationDepth==0,contextEdit==nil,recall==nil,repair==nil,
              coordinator.isIdleForManagement,current != nil,activeBridge != nil else{return nil}
        return InputHabitMenuAction(kind:kind,owner:habitOwner,generation:generation,activation:coordinator.activation)
    }
    public func performInputHabitMenuAction(_ action:InputHabitMenuAction){
        guard enter() else{return};defer{leave()}
        guard !closed,activationDepth==0,action.owner==habitOwner,generation==action.generation,coordinator.activation==action.activation,
              coordinator.isIdleForManagement,contextEdit==nil,recall==nil,repair==nil,
              let sender=current,let bridge=activeBridge else{return}
        // Consume the menu before any client callback; no old menu can reenter.
        generation &+= 1
        if coordinator.session==nil {
            guard coordinator.outcome == .ready,activate(bridge,preservingMode:true) == .ready,current===sender else{return}
        }
        let ticket=generation,owner=coordinator
        guard owner.session?.idleExpressionBinding != nil,owner.hasCurrentTarget(sender),matches(ticket,owner,sender) else{return}
        switch action.kind {
        case .chinese:sessionLiteral=false;hideAll()
        case .literal:sessionLiteral=true;hideAll()
        case .characters:
            hideAll();guard matches(ticket,owner,sender),owner.session?.idleExpressionBinding != nil,
                           owner.hasCurrentTarget(sender),matches(ticket,owner,sender) else{return}
            // System UI owns its eventual insertion. We never issue a text effect,
            // fabricate a selected character, poll focus or request extra access.
            showCharacters()
        }
    }
    public func mixedMenuAction(_ kind:MixedActionKind)->MixedMenuAction? {
        guard current != nil,!closed,!usesLiteralMode,contextEdit==nil,!coordinator.isContextReview,recall==nil,repair==nil,
              let session=coordinator.session,let snapshot=session.snapshot else{return nil}
        var span:UUID?
        switch kind {
        case .begin:guard session.canBeginMixed else{return nil}
        case .literal,.spelling:guard session.mixedDraft != nil else{return nil}
        case .commit:guard let draft=session.mixedDraft,!draft.isEmpty,draft.isResolved else{return nil}
        case .reopen:
            guard let draft=session.mixedDraft else{return nil}
            let selected=draft.map.filter{if case .engine=$0.span.origin{return true};return false}
            span=(selected.first{$0.sourceUTF8.upperBound==draft.caretUTF8} ?? selected.first{$0.sourceUTF8.lowerBound==draft.caretUTF8})?.span.id
            guard span != nil else{return nil}
        }
        return MixedMenuAction(kind:kind,driverGeneration:generation,activation:coordinator.activation,session:session.key,inputGeneration:snapshot.inputGeneration,span:span)
    }
    public func performMixedMenuAction(_ action:MixedMenuAction){
        guard enter() else{return};defer{leave()}
        guard let sender=current,contextEdit==nil,!coordinator.isContextReview,recall==nil,repair==nil,
              generation==action.driverGeneration,coordinator.activation==action.activation,
              let session=coordinator.session,session.key==action.session,session.snapshot?.inputGeneration==action.inputGeneration else{return}
        generation &+= 1;let ticket=generation,owner=coordinator
        _=owner.performMixed(action.kind,span:action.span,client:sender)
        render(sender,ticket:ticket,owner:owner)
    }
    public func retainedMenuAction(arm:Bool)->RetainedMenuAction? {
        guard current != nil,!closed,!usesLiteralMode,contextEdit==nil,!coordinator.isContextReview,recall==nil,repair==nil,let session=coordinator.session,let snapshot=session.snapshot else{return nil}
        if arm {guard session.canRetainForRepair,!session.isRetainedComposition,session.idleExpressionBinding != nil else{return nil}}
        else{guard session.supportsRepair,!snapshot.sourceText.isEmpty else{return nil}}
        return RetainedMenuAction(driverGeneration:generation,activation:coordinator.activation,session:session.key,inputGeneration:snapshot.inputGeneration,arm:arm)
    }
    public func performRetainedMenuAction(_ action:RetainedMenuAction){
        guard enter() else{return};defer{leave()}
        guard let sender=current,contextEdit==nil,!coordinator.isContextReview,recall==nil,repair==nil,generation==action.driverGeneration,coordinator.activation==action.activation,
              let session=coordinator.session,session.key==action.session,session.snapshot?.inputGeneration==action.inputGeneration else{return}
        generation &+= 1;let ticket=generation,owner=coordinator
        if action.arm {guard let binding=session.idleExpressionBinding else{return};_=owner.beginRetained(binding:binding,client:sender)}
        else{_=owner.commitRetained(client:sender)}
        render(sender,ticket:ticket,owner:owner)
    }
    private func navigateRepair(_ direction:Int,client sender:AnyObject,ticket:UInt64,owner:IMKSessionCoordinator){
        let previous=repair?.target.index;discardRepair()
        guard let anchors=owner.repairAnchors(client:sender),matches(ticket,owner,sender),!anchors.rows.isEmpty else{
            if matches(ticket,owner,sender){render(sender,ticket:ticket,owner:owner)};return
        }
        let initial=anchors.rows.firstIndex(where:{$0.bytes.upperBound>=(owner.snapshot?.caretUTF8 ?? 0)}) ?? anchors.rows.count-1
        let index=previous.map{min(max(0,$0+direction),anchors.rows.count-1)} ?? initial
        let target=anchors.targets[index],raw=String(decoding:Array(target.lease.raw.utf8)[target.anchor.bytes],as:UTF8.self)
        repair=SegmentRepairState(target:target,original:anchors.preview,replacementRaw:raw)
        renderRepair(sender,ticket:ticket,owner:owner)
    }
    public func searchRepair(token:UUID){
        guard enter() else{return};defer{leave()}
        guard let sender=current,let state=repair,state.token==token,state.proposal==nil else{return}
        generation &+= 1;let ticket=generation,owner=coordinator;presentedRepairToken=nil
        guard let result=owner.repairAlternatives(target:state.target,replacementRaw:state.replacementRaw,client:sender),matches(ticket,owner,sender),repair?.token==token else{
            if matches(ticket,owner,sender),repair?.token==token{refreshFailedRepair(state,sender:sender,ticket:ticket,owner:owner)};return
        }
        let notice=result.complete ? (result.rows.isEmpty ? "No constrained path. Edit spelling or cancel; original unchanged.":"All paths in this bounded supported domain exhausted.") : "Search incomplete. Only these verified choices are usable; absence is not a conflict."
        repair=SegmentRepairState(target:result.target,original:state.original,replacementRaw:state.replacementRaw,caret:state.caret,rows:result.rows,complete:result.complete,searched:true,notice:notice)
        renderRepair(sender,ticket:ticket,owner:owner)
    }
    private func refreshFailedRepair(_ old:SegmentRepairState,sender:AnyObject,ticket:UInt64,owner:IMKSessionCoordinator){
        old.proposal?.cancel();presentedRepairToken=nil
        guard let anchors=owner.repairAnchors(client:sender),matches(ticket,owner,sender),anchors.targets.indices.contains(old.target.index) else{
            if matches(ticket,owner,sender){discardRepair();render(sender,ticket:ticket,owner:owner)};return
        }
        repair=SegmentRepairState(target:anchors.targets[old.target.index],original:old.original,replacementRaw:old.replacementRaw,caret:old.caret,notice:"Search or preview unavailable. Original unchanged. Search again explicitly.")
        renderRepair(sender,ticket:ticket,owner:owner)
    }
    public func reviewRepair(row:Int,token:UUID){
        guard enter() else{return};defer{leave()}
        guard let sender=current,let state=repair,state.token==token,presentedRepairToken==token,state.proposal==nil,state.rows.indices.contains(row),row/5==state.page else{return}
        generation &+= 1;let ticket=generation,owner=coordinator;presentedRepairToken=nil
        guard let proposal=owner.prepareAlternative(state.rows[row],client:sender),matches(ticket,owner,sender),repair?.token==token else{
            if matches(ticket,owner,sender),repair?.token==token{refreshFailedRepair(state,sender:sender,ticket:ticket,owner:owner)};return
        }
        repair=SegmentRepairState(target:state.target,original:state.original,replacementRaw:state.replacementRaw,caret:state.caret,proposal:proposal)
        renderRepair(sender,ticket:ticket,owner:owner)
    }
    public func applyRepair(token:UUID){
        guard enter() else{return};defer{leave()}
        guard let sender=current,let state=repair,state.token==token,presentedRepairToken==token,let proposal=state.proposal else{return}
        generation &+= 1;let ticket=generation,owner=coordinator
        // Consume before the first getter/mark/presentation callback. Do not invalidate
        // the proposal's engine lease until its one transfer has been attempted.
        repair=nil;presentedRepairToken=nil
        _=owner.applyRepair(proposal,client:sender);proposal.cancel()
        render(sender,ticket:ticket,owner:owner)
    }
    public func cancelRepair(token:UUID){
        guard enter() else{return};defer{leave()};guard repair?.token==token,let sender=current else{return}
        generation &+= 1;let ticket=generation,owner=coordinator;discardRepair()
        hideAll();guard matches(ticket,owner,sender) else{return};render(sender,ticket:ticket,owner:owner)
    }
    private func handleRepair(_ event:NSEvent,client sender:AnyObject,ticket:UInt64,owner:IMKSessionCoordinator)->Bool {
        guard let state=repair else{return true}
        guard owner.hasCurrentTarget(sender),matches(ticket,owner,sender),repair?.token==state.token else{
            if matches(ticket,owner,sender),repair?.token==state.token{discardRepair();hideAll()};return true
        }
        if event.keyCode==53{if !event.isARepeat{suppressRepeatedRepairEscape=true;cancelRepair(token:state.token)};return true}
        if state.proposal != nil {
            if event.keyCode==116 || event.keyCode==121{scrollRepair(event.keyCode==116 ? -1:1,state.token)}
            return true // Apply is a separate explicit button; Return keeps its raw policy.
        }
        if event.keyCode==49 {
            if !event.isARepeat {if state.searched,!state.rows.isEmpty{reviewRepair(row:state.selected,token:state.token)}else{searchRepair(token:state.token)}}
            return true
        }
        if let text=event.characters,let number=Int(text),(1...5).contains(number),state.searched {
            let row=state.page*5+number-1;if !event.isARepeat,state.rows.indices.contains(row){reviewRepair(row:row,token:state.token)};return true
        }
        if [125,126,116,121].contains(event.keyCode),state.searched,!state.rows.isEmpty {
            let delta=event.keyCode==125 ? 1:event.keyCode==126 ? -1:event.keyCode==121 ? 5:-5
            let selected=min(max(0,state.selected+delta),state.rows.count-1)
            repair=SegmentRepairState(target:state.target,original:state.original,replacementRaw:state.replacementRaw,caret:state.caret,rows:state.rows,complete:state.complete,selected:selected,searched:true,notice:state.notice)
            renderRepair(sender,ticket:ticket,owner:owner);return true
        }
        var bytes=Array(state.replacementRaw.utf8),caret=state.caret
        switch event.keyCode {
        case 123:caret=max(0,caret-1)
        case 124:caret=min(bytes.count,caret+1)
        case 115:caret=0
        case 119:caret=bytes.count
        case 51:if caret>0{bytes.remove(at:caret-1);caret-=1}
        case 117:if caret<bytes.count{bytes.remove(at:caret)}
        default:
            guard let text=event.characters,text.utf8.count==1,let byte=text.utf8.first,(97...122).contains(byte) || byte==39,bytes.count<4096 else{return true}
            bytes.insert(byte,at:caret);caret+=1
        }
        presentedRepairToken=nil
        guard let target=try? owner.session?.renewRepairTarget(state.target),matches(ticket,owner,sender) else{
            if matches(ticket,owner,sender){discardRepair();render(sender,ticket:ticket,owner:owner)};return true
        }
        repair=SegmentRepairState(target:target,original:state.original,replacementRaw:String(decoding:bytes,as:UTF8.self),caret:caret)
        renderRepair(sender,ticket:ticket,owner:owner);return true
    }
    private func renderRepair(_ sender:AnyObject,ticket:UInt64,owner:IMKSessionCoordinator){
        guard matches(ticket,owner,sender),let state=repair else{return}
        let rect=owner.candidateRect(sender)
        guard matches(ticket,owner,sender),repair?.token==state.token else{return}
        guard let rect=rect,owner.session?.supportsRepair==true else{discardRepair();hideAll();return}
        repairPresentationVisible=true
        let shown=presentRepair(state,rect)
        guard matches(ticket,owner,sender),repair?.token==state.token else{return}
        guard shown else{discardRepair();hideAll();return};presentedRepairToken=state.token
    }
    private func renderRecall(_ sender:AnyObject,ticket:UInt64,owner:IMKSessionCoordinator){
        guard matches(ticket,owner,sender),let state=recall else{return}
        let rect=owner.candidateRect(sender)
        guard matches(ticket,owner,sender),recall?.token==state.token else{return}
        guard owner.session?.idleExpressionBinding==state.binding else{recall=nil;hideAll();return}
        guard let rect=rect else{recall=nil;hideAll();return}
        let presented=presentRecall(state,rect)
        guard matches(ticket,owner,sender),recall?.token==state.token else{return}
        guard presented else{recall=nil;presentedRecallToken=nil;hideAll();return}
        presentedRecallToken=state.token
    }
    private func render(_ sender:AnyObject,ticket:UInt64,owner:IMKSessionCoordinator){
        guard matches(ticket,owner,sender) else{return}
        if repair==nil,repairPresentationVisible{hideAll();guard matches(ticket,owner,sender) else{return}}
        let activation=owner.activation
        let rect=owner.candidateRect(sender)
        guard matches(ticket,owner,sender) else{return}
        guard owner.session != nil,owner.activation==activation else{lastRect=nil;hideAll();return}
        if let rect=rect{lastRect=rect}
        guard let rect=lastRect else{hideAll();return}
        if owner.snapshot?.rows.isEmpty==false || owner.notice != nil{present(owner.snapshot,rect,owner.notice)}else{hideAll()}
    }
}
#endif
