#if os(macOS)
import AppKit
import EngineBridge
import SessionCore

// The framework controller and synthetic tests use this same dispatch/lifecycle
// path. Presentation is injected so synchronous AppKit callbacks are testable
// without constructing IMKServer or claiming framework-created controller proof.
@MainActor public final class IMKControllerDriver {
    public private(set) var coordinator=IMKSessionCoordinator()
    public private(set) var retainedRecovery:IMKSessionCoordinator.Recovery?
    public var recovery:IMKSessionCoordinator.Recovery? {coordinator.recovery ?? retainedRecovery}
    private let makeSession:()->InputSession?
    private let literal:()->Bool,permitOperation:()->Bool
    private var operationDepth=0,closed=false
    public var isIdleForManagement:Bool {operationDepth==0 && (closed || (activationDepth==0 && coordinator.isIdleForManagement))}
    public var managementRevision:UInt64 {generation}
    // State retirement is separated from presentation so all old bindings retire
    // before the first reentrant AppKit hide callback.
    public func retireIdleForManagement(){
        precondition(isIdleForManagement)
        generation &+= 1;pendingActivation=nil;coordinator.retire();lastRect=nil
    }
    public func dismissCandidatesForManagement(){hide()}
    public func discardIdleBindingForManagement(){
        precondition(isIdleForManagement)
        generation &+= 1;pendingActivation=nil;coordinator.retire();current=nil;lastRect=nil
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
    public init(makeSession:@escaping ()->InputSession?,literal:@escaping ()->Bool={false},permitOperation:@escaping ()->Bool={true},hide:@escaping ()->Void,present:@escaping (CandidateSnapshot?,NSRect,String?)->Void) {
        self.makeSession=makeSession;self.literal=literal;self.permitOperation=permitOperation;self.hide=hide;self.present=present
    }
    private func matches(_ ticket:UInt64,_ owner:IMKSessionCoordinator,_ sender:AnyObject)->Bool {
        generation==ticket && coordinator === owner && current===sender
    }
    @discardableResult public func activate(_ bridge:IMKClientAccess)->ActivationResult {
        guard enter() else{return .superseded};defer{leave()}
        closed=false;activationDepth+=1;defer{activationDepth-=1}
        generation &+= 1;let ticket=generation
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
        _=owner.choose(candidate,client:sender);render(sender,ticket:ticket,owner:owner)
    }
    private func cancelPendingActivation(_ sender:AnyObject)->Bool {
        guard let pending=pendingActivation,pending.identity===sender,
              generation==pending.ticket,coordinator===pending.owner else{return false}
        generation &+= 1;pendingActivation=nil
        pending.owner.interrupt("Lifecycle ended during activation. No text was written.")
        current=nil;lastRect=nil;hide()
        return true
    }
    public func finish(client sender:AnyObject){
        guard enter() else{return};defer{leave()}
        if cancelPendingActivation(sender){return}
        guard current===sender else{return};generation &+= 1;let ticket=generation,owner=coordinator
        _=owner.finish(client:sender);render(sender,ticket:ticket,owner:owner)
    }
    public func deactivate(client sender:AnyObject){
        guard enter() else{return};defer{leave()}
        if cancelPendingActivation(sender){return}
        guard current===sender else{return};generation &+= 1;let ticket=generation,owner=coordinator
        owner.deactivate(client:sender)
        guard matches(ticket,owner,sender) else{return}
        retainedRecovery=owner.recovery ?? retainedRecovery;current=nil;lastRect=nil
        hide() // No state writes follow a presentation callback.
    }
    public func close(){
        guard enter() else{return};defer{leave()}
        generation &+= 1;pendingActivation=nil;coordinator.interrupt("Controller closed. No automatic text cleanup.")
        retainedRecovery=coordinator.recovery ?? retainedRecovery;current=nil;lastRect=nil;closed=true;hide()
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
