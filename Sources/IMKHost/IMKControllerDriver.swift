#if os(macOS)
import AppKit
import EngineBridge
import SessionCore
import ExpressionCore

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
    private var presentedRecallToken:UUID?
    private let literal:()->Bool,permitOperation:()->Bool
    private var operationDepth=0,closed=false
    public var isIdleForManagement:Bool {operationDepth==0 && recall==nil && (closed || (activationDepth==0 && coordinator.isIdleForManagement))}
    public var managementRevision:UInt64 {generation}
    // State retirement is separated from presentation so all old bindings retire
    // before the first reentrant AppKit hide callback.
    public func retireIdleForManagement(){
        precondition(isIdleForManagement)
        generation &+= 1;recall=nil;pendingActivation=nil;coordinator.retire();lastRect=nil
    }
    public func dismissCandidatesForManagement(){hide()}
    public func discardIdleBindingForManagement(){
        precondition(isIdleForManagement)
        generation &+= 1;recall=nil;pendingActivation=nil;coordinator.retire();current=nil;lastRect=nil
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
    public init(makeSession:@escaping ()->InputSession?,expressions:@escaping()->ExpressionCatalog?={nil},literal:@escaping ()->Bool={false},permitOperation:@escaping ()->Bool={true},hide:@escaping ()->Void,present:@escaping (CandidateSnapshot?,NSRect,String?)->Void,presentRecall:@escaping(ExpressionRecallState,NSRect)->Bool={_,_ in false},scrollRecall:@escaping(Int,UUID)->Void={_,_ in}) {
        self.makeSession=makeSession;self.expressions=expressions;self.presentRecall=presentRecall;self.scrollRecall=scrollRecall;self.literal=literal;self.permitOperation=permitOperation;self.hide=hide;self.present=present
    }
    private func matches(_ ticket:UInt64,_ owner:IMKSessionCoordinator,_ sender:AnyObject)->Bool {
        generation==ticket && coordinator === owner && current===sender
    }
    @discardableResult public func activate(_ bridge:IMKClientAccess)->ActivationResult {
        guard enter() else{return .superseded};defer{leave()}
        closed=false;activationDepth+=1;defer{activationDepth-=1}
        generation &+= 1;recall=nil;let ticket=generation
        coordinator.interrupt("Previous activation ended. No text was replayed or cleared.")
        retainedRecovery=coordinator.recovery ?? retainedRecovery
        let next=IMKSessionCoordinator();coordinator=next;current=nil;lastRect=nil
        pendingActivation=(ticket,next,bridge.callbackIdentity)
        defer{if pendingActivation?.ticket==ticket{pendingActivation=nil}}
        hide();guard generation==ticket,coordinator===next else{return .superseded}
        let accepted=next.activate(bridge,makeSession:makeSession)
        guard generation==ticket,coordinator===next else{next.retire();return .superseded}
        guard accepted else{return .refused}
        current=bridge.callbackIdentity
        return .ready
    }
    public func handle(_ event:NSEvent,client sender:AnyObject)->Bool {
        guard event.type == .keyDown else{return false}
        guard enter() else{return false};defer{leave()}
        if activationDepth>0{generation &+= 1;coordinator.interrupt("Key event reentered activation. No automatic replay.");return true}
        guard current===sender else{return false}
        generation &+= 1
        if coordinator.session==nil {
            guard coordinator.outcome == .ready,let bridge=IMKTextInputBridge(sender) else{return true}
            switch activate(bridge){case .ready:break;case .refused:return false;case .superseded:return true}
        }
        guard current===sender,coordinator.session != nil else{return false}
        let owner=coordinator,ticket=generation
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
        if literal() {
            let safe=owner.releaseIdle(client:sender)
            render(sender,ticket:ticket,owner:owner)
            return matches(ticket,owner,sender) ? !safe:true
        }
        if !event.modifierFlags.intersection([.command,.option,.control]).isEmpty {
            let composing=owner.snapshot?.rawASCII.isEmpty==false || owner.snapshot?.preedit.isEmpty==false
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
        guard recall==nil else{return}
        _=owner.choose(candidate,client:sender);render(sender,ticket:ticket,owner:owner)
    }
    private func cancelPendingActivation(_ sender:AnyObject)->Bool {
        guard let pending=pendingActivation,pending.identity===sender,
              generation==pending.ticket,coordinator===pending.owner else{return false}
        generation &+= 1;recall=nil;pendingActivation=nil
        pending.owner.interrupt("Lifecycle ended during activation. No text was written.")
        current=nil;lastRect=nil;hide()
        return true
    }
    public func finish(client sender:AnyObject){
        guard enter() else{return};defer{leave()}
        if cancelPendingActivation(sender){return}
        guard current===sender else{return};generation &+= 1;recall=nil;let ticket=generation,owner=coordinator
        _=owner.finish(client:sender);render(sender,ticket:ticket,owner:owner)
    }
    public func deactivate(client sender:AnyObject){
        guard enter() else{return};defer{leave()}
        if cancelPendingActivation(sender){return}
        guard current===sender else{return};generation &+= 1;recall=nil;let ticket=generation,owner=coordinator
        owner.deactivate(client:sender)
        guard matches(ticket,owner,sender) else{return}
        retainedRecovery=owner.recovery ?? retainedRecovery;current=nil;lastRect=nil
        hide() // No state writes follow a presentation callback.
    }
    public func close(){
        guard enter() else{return};defer{leave()}
        generation &+= 1;recall=nil;pendingActivation=nil;coordinator.interrupt("Controller closed. No automatic text cleanup.")
        retainedRecovery=coordinator.recovery ?? retainedRecovery;current=nil;lastRect=nil;closed=true;hide()
    }
    public func invalidateRecallForShutdown(){generation &+= 1;recall=nil;hide()}
    public func cancelRecall(token:UUID){
        guard enter() else{return};defer{leave()};guard recall?.token==token else{return}
        generation &+= 1;recall=nil;hide()
    }
    public func reviewExpression(_ ref:ExpressionRef,token:UUID){
        guard enter() else{return};defer{leave()}
        guard let sender=current,let state=recall,state.token==token,state.review==nil,
              state.rows.contains(where:{$0.ref==ref}),let catalog=expressions(),catalog.epoch==state.catalogEpoch,
              let record=catalog.resolve(ref) else{return}
        generation &+= 1;let ticket=generation,owner=coordinator
        guard owner.hasCurrentTarget(sender),matches(ticket,owner,sender),recall?.token==token else{if matches(ticket,owner,sender){recall=nil;hide()};return}
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
        guard matches(ticket,owner,sender) else{return};hide()
    }
    private func handleRecall(_ event:NSEvent,client sender:AnyObject,ticket:UInt64,owner:IMKSessionCoordinator)->Bool {
        guard let state=recall,let catalog=expressions(),catalog.epoch==state.catalogEpoch,
              owner.session?.idleExpressionBinding==state.binding,owner.hasCurrentTarget(sender),
              matches(ticket,owner,sender),recall?.token==state.token else{
            if matches(ticket,owner,sender){recall=nil;hide()};return true
        }
        if event.keyCode==53{recall=nil;hide();return true}
        if !event.modifierFlags.intersection([.command,.control,.option]).isEmpty {
            recall=nil;let safe=owner.releaseIdle(client:sender)
            if matches(ticket,owner,sender){hide()};return matches(ticket,owner,sender) ? !safe:true
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
    private func renderRecall(_ sender:AnyObject,ticket:UInt64,owner:IMKSessionCoordinator){
        guard matches(ticket,owner,sender),let state=recall else{return}
        let rect=owner.candidateRect(sender)
        guard matches(ticket,owner,sender),recall?.token==state.token else{return}
        guard owner.session?.idleExpressionBinding==state.binding else{recall=nil;hide();return}
        guard let rect=rect else{recall=nil;hide();return}
        let presented=presentRecall(state,rect)
        guard matches(ticket,owner,sender),recall?.token==state.token else{return}
        guard presented else{recall=nil;presentedRecallToken=nil;hide();return}
        presentedRecallToken=state.token
    }
    private func render(_ sender:AnyObject,ticket:UInt64,owner:IMKSessionCoordinator){
        guard matches(ticket,owner,sender) else{return}
        let activation=owner.activation
        let rect=owner.candidateRect(sender)
        guard matches(ticket,owner,sender) else{return}
        guard owner.session != nil,owner.activation==activation else{lastRect=nil;hide();return}
        if let rect=rect{lastRect=rect}
        guard let rect=lastRect else{hide();return}
        if owner.snapshot?.rows.isEmpty==false || owner.notice != nil{present(owner.snapshot,rect,owner.notice)}else{hide()}
    }
}
#endif
