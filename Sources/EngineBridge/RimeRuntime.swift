import Foundation
import CRimeShim
import SessionCore
import ConstraintCore
import TextBoundary

public enum EngineError: Error { case code(Int32), invalidUTF8, closed }
public final class RimeRuntime {
    public let dictionaryRevision: String
    public let version = "1.16.0"
    private static let lifetime = NSLock()
    private static var created = false
    private static var attempts:UInt64=0
    public static var startupAttempts:UInt64 {lifetime.lock();defer{lifetime.unlock()};return attempts}
    public var deploymentCalls:UInt64 {paia_rime_deployment_calls()}
    private let repairDisabledSchemas:Set<String>
    private let repairExtensionLoaded:Bool
    private final class WeakSession {weak var value:InputSession?;init(_ value:InputSession){self.value=value}}
    private let lifecycle=NSRecursiveLock()
    private var sessions=[WeakSession](),closed=false,cleanupSucceeded=true
    private let cleanup:(()throws->Void)?
    // Explicit directories only: callers must create a fresh isolated user directory.
    public init(library: String, shared: String, isolatedUser: String, dictionaryRevision: String, schemas:[String] = [], g01Library:String? = nil,repairDisabledSchemas:Set<String> = [],precompiled:Bool=false,cleanup:(()throws->Void)?=nil) throws {
        self.repairDisabledSchemas=repairDisabledSchemas;self.cleanup=cleanup;repairExtensionLoaded=g01Library != nil
        Self.lifetime.lock(); defer { Self.lifetime.unlock() }
        guard !Self.created else { throw EngineError.code(Int32(PAIA_BUSY)) }
        guard !precompiled || (schemas.isEmpty && g01Library==nil) else{throw EngineError.code(Int32(PAIA_ABI))}
        // A failed C entry can already initialize/finalize upstream state. The
        // startup attempt is consumed before C; retry requires a new process.
        Self.created=true;Self.attempts+=1
        let rc=precompiled ? paia_rime_open_precompiled(library,shared,isolatedUser):paia_rime_open(library,shared,isolatedUser)
        guard rc==PAIA_OK else { throw EngineError.code(rc) }
        self.dictionaryRevision=dictionaryRevision
        do {
            for schema in schemas {let code=paia_rime_deploy_named(schema);guard code==PAIA_OK else{throw EngineError.code(code)}}
            if let path=g01Library {let code=paia_rime_enable_g01(path);guard code==PAIA_OK else{throw EngineError.code(code)}}
        } catch {paia_rime_close();throw error}
    }
    deinit {_ = close()}
    @discardableResult public func close()->Bool {
        lifecycle.lock();defer{lifecycle.unlock()}
        guard !closed else{return cleanupSucceeded};closed=true
        for session in sessions{session.value?.end()};sessions=[]
        paia_rime_close()
        do{try cleanup?()}catch{cleanupSucceeded=false}
        return cleanupSucceeded
    }
    public func makeSession(schema:String = "paia_a1",deferredCommit:Bool = false,chinesePunctuation:Bool = false) throws -> InputSession {
        lifecycle.lock();defer{lifecycle.unlock()};guard !closed else{throw EngineError.closed}
        let id=paia_rime_start_named(schema,deferredCommit ? 1 : 0)
        guard id != 0 else { throw EngineError.code(Int32(PAIA_SESSION)) }
        let session=InputSession(runtime:self,id:id,chinesePunctuation:chinesePunctuation,canRetainForRepair:repairExtensionLoaded && !repairDisabledSchemas.contains(schema),retained:deferredCommit)
        sessions.removeAll{$0.value==nil};sessions.append(WeakSession(session));return session
    }
}

public struct EngineTiming {
    public let engineNanoseconds:UInt64, copyNanoseconds:UInt64
}
public enum InputKey {
    case text(String), code(Int32, modifiers: Int32 = 0), returnKey, space, number(Int), escape, command
}
public final class InputSession {
    private let runtime: RimeRuntime
    private var id: UInt64
    private var repairRequest:UInt64=0
    private var issuedChoices:[Int:RepairChoice]=[:]
    private var issuedAlternatives:[UUID:RepairAlternative]=[:]
    private let chinesePunctuation:Bool
    public let canRetainForRepair:Bool
    private var retained:Bool
    private var mixed:MixedComposition?
    // Internal post-C validation dependency. Tests inject rejection after real
    // native success, never a fabricated engine result or public setting.
    var mixedResultValidation:(MixedValidationPoint)throws->Void={_ in}
    public var supportsRepair:Bool {lock.lock();defer{lock.unlock()};return !ended && canRetainForRepair && retained && mixed==nil}
    public var isRetainedComposition:Bool {lock.lock();defer{lock.unlock()};return !ended && (retained || mixed != nil)}
    private let lock=NSRecursiveLock()
    private var core: SessionCore
    private var ended=false
    private var timing=EngineTiming(engineNanoseconds:0,copyNanoseconds:0)
    public var lastTiming:EngineTiming {lock.lock();defer{lock.unlock()};return timing}
    internal init(runtime: RimeRuntime,id: UInt64,chinesePunctuation:Bool,canRetainForRepair:Bool,retained:Bool) {
        self.runtime=runtime; self.id=id; self.chinesePunctuation=chinesePunctuation;self.canRetainForRepair=canRetainForRepair;self.retained=retained;core=SessionCore(dictionaryRevision:runtime.dictionaryRevision)
    }
    deinit { end() }
    public var snapshot: CandidateSnapshot? { lock.lock(); defer {lock.unlock()}; return core.snapshot }
    public var key: SessionKey { lock.lock(); defer {lock.unlock()}; return core.key }
    public func end() {
        lock.lock(); defer {lock.unlock()}
        if !ended { core.invalidate(); mixed?.close();mixed=nil;paia_rime_end_session(id); ended=true }
    }
    public func reserve(_ effect: CommitEffect) -> Bool {
        lock.lock(); defer {lock.unlock()}; return core.reserve(effect)
    }
    private func step(_ action: Int32, _ key: Int32 = 0, _ modifiers: Int32 = 0, literal: String? = nil) throws -> SessionUpdate {
        guard !ended else { throw EngineError.closed }
        try core.ensureReady()
        var c=PaiaRimeSnapshot()
        let rc=paia_rime_step(id,action,key,modifiers,&c)
        defer {paia_rime_free_snapshot(&c)}
        guard rc==PAIA_OK else { core.invalidate(); throw EngineError.code(rc) }
        // Retention is not a promise about arbitrary schema processors. Never
        // expose an unsolicited engine commit to the host; retire safely instead.
        if retained && action != 5 && c.commit != nil {core.invalidate();throw ConstraintError.invalidSpan}
        timing=EngineTiming(engineNanoseconds:c.engine_nanoseconds,copyNanoseconds:c.copy_nanoseconds)
        do { return try core.receive(Self.decode(c),literal:literal) }
        catch { core.invalidate(); throw error }
    }
    private static func decode(_ c:PaiaRimeSnapshot) throws -> EngineValue {
        func string(_ p:UnsafeMutablePointer<CChar>?) throws -> String {
            guard let p=p else{return ""}
            guard let s=String(validatingUTF8:p) else{throw EngineError.invalidUTF8};return s
        }
        let rows=try (0..<Int(c.count)).map {i in try string(c.candidates?[i])}
        return try EngineValue(raw:string(c.raw),preedit:string(c.preedit),caretUTF8:Int(c.caret_utf8),
            preeditCaretUTF8:Int(c.preedit_caret_utf8),selectionStartUTF8:Int(c.selection_start_utf8),
            selectionEndUTF8:Int(c.selection_end_utf8),candidates:rows,page:Int(c.page),highlighted:Int(c.highlighted),
            hasMore:c.has_more != 0,commit:c.commit == nil ? nil : string(c.commit),handled:c.handled != 0)
    }
    public func refresh() throws -> SessionUpdate { lock.lock(); defer {lock.unlock()}; if let mixed=mixed{return try mixedOperation{try mixed.republish(core:&core)}};return try step(0) }
    public func select(_ ref: CandidateRef) throws -> SessionUpdate {
        lock.lock(); defer {lock.unlock()}
        try core.validate(ref)
        if let mixed=mixed{return try mixedOperation{try mixed.select(ref,core:&core)}}
        return try step(2,Int32(ref.engineIndexOnPage))
    }
    private func lease() throws -> RepairLease {
        guard !ended,let snapshot=core.snapshot else{throw EngineError.closed}
        guard supportsRepair else{throw ConstraintError.native(code:Int32(PG_UNSUPPORTED),examined:0)}
        try core.ensureReady()
        return RepairLease(snapshot:snapshot,revision:runtime.dictionaryRevision,request:repairRequest)
    }
    public func beginRetained(binding:ExpressionBinding)throws->SessionUpdate {
        lock.lock();defer{lock.unlock()}
        guard !ended,canRetainForRepair,!retained,core.idleExpressionBinding==binding else{throw ConstraintError.stale}
        let update=try step(6)
        guard update.commit==nil,update.snapshot?.rawASCII.isEmpty==true,update.snapshot?.preedit.isEmpty==true else{core.invalidate();throw ConstraintError.invalidSpan}
        retained=true;repairRequest += 1;return update
    }
    public func invalidateRepairActions(){
        lock.lock();defer{lock.unlock()};repairRequest += 1;issuedChoices.removeAll();issuedAlternatives.removeAll()
    }
    public func renewRepairTarget(_ target:RepairTarget)throws->RepairTarget {
        lock.lock();defer{lock.unlock()};_ = try lease()
        // Draft edits change no engine input. Validate its full source identity,
        // then revoke query/proposal capabilities without running native search.
        guard target.lease.matches(core.snapshot,revision:runtime.dictionaryRevision,request:target.lease.request) else{throw ConstraintError.stale}
        repairRequest += 1;issuedChoices.removeAll();issuedAlternatives.removeAll()
        return RepairTarget(lease:try lease(),anchor:target.anchor,index:target.index)
    }
    public func repairAnchors() throws -> RepairAnchors {
        lock.lock();defer{lock.unlock()};let identity=try lease()
        var list=PaiaG01List();let rc=paia_rime_g01_anchors(id,&list);defer{paia_rime_g01_free_list(&list)}
        guard rc==PG_OK else{throw ConstraintError.native(code:rc,examined:0)}
        let copied=try copyList(list);return RepairAnchors(lease:identity,rows:copied.anchors,preview:copied.preview)
    }
    public func repairChoices(limit:Int=256) throws -> RepairChoices {
        lock.lock();defer{lock.unlock()};let identity=try lease()
        guard (1...2048).contains(limit) else{throw ConstraintError.invalidSpan}
        var list=PaiaG01List();let rc=paia_rime_g01_candidates(id,limit,&list);defer{paia_rime_g01_free_list(&list)}
        guard rc==PG_OK else{throw ConstraintError.native(code:rc,examined:0)}
        let rows=try copyList(list).anchors.map {RepairChoice(lease:identity,anchor:$0,token:UUID())}
        issuedChoices=Dictionary(uniqueKeysWithValues:rows.map{($0.anchor.engineIndex,$0)})
        return RepairChoices(rows:rows,complete:list.complete != 0)
    }
    public func selectForRepair(_ choice:RepairChoice) throws -> SessionUpdate {
        lock.lock();defer{lock.unlock()};_ = try lease()
        guard choice.lease.matches(core.snapshot,revision:runtime.dictionaryRevision,request:repairRequest),
              (0..<2048).contains(choice.anchor.engineIndex),
              issuedChoices[choice.anchor.engineIndex]?.token==choice.token else{throw ConstraintError.stale}
        return try step(4,Int32(choice.anchor.engineIndex))
    }
    public func repairAlternatives(target:RepairTarget,replacementRaw:String,limit:Int=2048,maxRows:Int=32)throws->RepairAlternatives {
        lock.lock();defer{lock.unlock()};_ = try lease()
        guard target.lease.matches(core.snapshot,revision:runtime.dictionaryRevision,request:repairRequest),
              (1...2048).contains(limit),(1...32).contains(maxRows),replacementRaw.utf8.count<=4096,
              replacementRaw.utf8.allSatisfy({(97...122).contains($0) || $0==39 || $0==32}) else{throw ConstraintError.stale}
        let anchors=try repairAnchors().rows
        guard anchors.indices.contains(target.index),anchors[target.index]==target.anchor else{throw ConstraintError.stale}
        repairRequest += 1;issuedAlternatives.removeAll();let identity=try lease()
        let current=RepairTarget(lease:identity,anchor:anchors[target.index],index:target.index)
        var bytes=Array(identity.raw.utf8);bytes.replaceSubrange(current.anchor.bytes,with:replacementRaw.utf8)
        guard bytes.count<=4096,let expectedRaw=String(bytes:bytes,encoding:.utf8) else{throw ConstraintError.invalidSpan}
        var list=PaiaG01Alternatives()
        let rc=paia_rime_g01_alternatives(id,current.index,replacementRaw,limit,maxRows,&list)
        defer{paia_rime_g01_free_alternatives(&list)}
        guard [Int32(PG_OK),Int32(PG_CONFLICT),Int32(PG_INCOMPLETE)].contains(rc) else{throw ConstraintError.native(code:rc,examined:Int(list.examined))}
        guard list.status==rc,list.count<=maxRows,list.examined<=limit,list.count==0 || list.items != nil,
              list.complete==(rc==PG_INCOMPLETE ? 0:1) else{throw ConstraintError.invalidSpan}
        func copy(_ pointer:UnsafeMutablePointer<CChar>?)throws->String {
            guard let pointer=pointer,let text=String(validatingUTF8:pointer),text.utf8.count<=65536 else{throw EngineError.invalidUTF8};return text
        }
        let raw=try copy(list.raw)
        guard raw.utf8.elementsEqual(expectedRaw.utf8) || (rc==PG_INCOMPLETE && list.count==0 && raw.isEmpty) else{throw ConstraintError.invalidSpan}
        var total=0
        let rows=try (0..<Int(list.count)).map {i -> RepairAlternative in
            let item=list.items![i],surface=try copy(item.surface),preview=try copy(item.preview)
            total+=surface.utf8.count+preview.utf8.count;guard total<=524288 else{throw ConstraintError.invalidSpan}
            return RepairAlternative(target:current,replacementRaw:replacementRaw,raw:expectedRaw,surface:surface,preview:preview,token:UUID())
        }
        guard (rc != PG_OK || !rows.isEmpty),(rc != PG_CONFLICT || rows.isEmpty) else{throw ConstraintError.invalidSpan}
        issuedAlternatives=Dictionary(uniqueKeysWithValues:rows.map{($0.token,$0)})
        return RepairAlternatives(target:current,rows:rows,complete:list.complete != 0,examined:Int(list.examined),status:rc)
    }
    public func prepareAlternative(_ choice:RepairAlternative)throws->RepairProposal {
        lock.lock();defer{lock.unlock()};_ = try lease()
        guard choice.target.lease.matches(core.snapshot,revision:runtime.dictionaryRevision,request:repairRequest),
              let issued=issuedAlternatives[choice.token],issued.target.index==choice.target.index,
              issued.raw.utf8.elementsEqual(choice.raw.utf8),issued.surface.utf8.elementsEqual(choice.surface.utf8),
              issued.preview.utf8.elementsEqual(choice.preview.utf8),issued.replacementRaw==choice.replacementRaw else{throw ConstraintError.stale}
        issuedAlternatives.removeAll()
        let proposal=try prepareRepair(target:issued.target,replacementRaw:issued.replacementRaw,surface:issued.surface)
        guard proposal.raw.utf8.elementsEqual(issued.raw.utf8),proposal.preview.utf8.elementsEqual(issued.preview.utf8) else{proposal.cancel();throw ConstraintError.invalidSpan}
        return proposal
    }
    public func prepareRepair(target:RepairTarget,replacementRaw:String,surface:String,limit:Int=2048) throws -> RepairProposal {
        lock.lock();defer{lock.unlock()};_ = try lease()
        guard target.lease.matches(core.snapshot,revision:runtime.dictionaryRevision,request:repairRequest) else{throw ConstraintError.stale}
        guard target.index>=0,(1...2048).contains(limit),!replacementRaw.utf8.contains(0),!surface.utf8.contains(0) else{throw ConstraintError.invalidSpan}
        let currentAnchors=try repairAnchors().rows
        guard currentAnchors.indices.contains(target.index),currentAnchors[target.index]==target.anchor else{throw ConstraintError.stale}
        repairRequest += 1;issuedAlternatives.removeAll();let identity=try lease()
        var trial=PaiaG01Trial()
        let rc=paia_rime_g01_prepare(id,target.index,replacementRaw,surface,limit,&trial)
        defer{paia_rime_g01_free_list(&trial.result)}
        guard rc==PG_OK,trial.session != 0 else{throw ConstraintError.native(code:rc,examined:Int(trial.examined))}
        do {
            let copied=try copyList(trial.result)
            return RepairProposal(runtime:runtime,id:trial.session,lease:identity,raw:copied.raw,preview:copied.preview,
                                  anchors:copied.anchors,examined:Int(trial.examined))
        } catch {paia_rime_end_session(trial.session);throw error}
    }
    public func applyRepair(_ proposal:RepairProposal) throws -> SessionUpdate {
        lock.lock();defer{lock.unlock()};_ = try lease()
        guard proposal.lease.matches(core.snapshot,revision:runtime.dictionaryRevision,request:repairRequest) else{throw ConstraintError.stale}
        return try proposal.transfer {trialID in
            var c=PaiaRimeSnapshot();let rc=paia_rime_step(trialID,0,0,0,&c);defer{paia_rime_free_snapshot(&c)}
            guard rc==PAIA_OK,c.commit==nil else{throw ConstraintError.native(code:rc,examined:0)}
            var next=core;let value=try Self.decode(c)
            guard value.raw==proposal.raw else{throw ConstraintError.invalidSpan}
            let update=try next.receive(value)
            let old=id;id=trialID;core=next;repairRequest += 1;paia_rime_end_session(old)
            return update
        }
    }
    public var idleCharacterBinding:CharacterBinding? {lock.lock();defer{lock.unlock()};return ended ? nil:core.idleCharacterBinding}
    public func commitKnownCharacter(_ value:KnownCharacter,binding:CharacterBinding)throws->SessionUpdate {
        lock.lock();defer{lock.unlock()};guard !ended else{throw EngineError.closed}
        return try core.commitKnownCharacter(value,binding:binding)
    }
    public var idleExpressionBinding:ExpressionBinding? {lock.lock();defer{lock.unlock()};return ended ? nil:core.idleExpressionBinding}
    public func commitExpression(_ text:String,binding:ExpressionBinding)throws->SessionUpdate {
        lock.lock();defer{lock.unlock()};guard !ended else{throw EngineError.closed}
        return try core.commitExpression(text,binding:binding)
    }
    public func commitReviewedEdit(_ text:String,replacing range:NSRange,binding:ExpressionBinding)throws->SessionUpdate {
        lock.lock();defer{lock.unlock()};guard !ended else{throw EngineError.closed}
        return try core.commitReviewedEdit(text,replacing:range,binding:binding)
    }
    public func commitEngineComposition() throws -> SessionUpdate {
        lock.lock();defer{lock.unlock()};if mixed != nil{return try commitMixed()};return try step(5)
    }
    public var mixedDraft:MixedDraft? {lock.lock();defer{lock.unlock()};return mixed?.state.draft}
    public var mixedLiteralIntent:Bool {lock.lock();defer{lock.unlock()};return mixed?.literalIntent ?? false}
    public var canBeginMixed:Bool {lock.lock();defer{lock.unlock()};return !ended && canRetainForRepair && mixed==nil && core.snapshot != nil && core.active}
    public func beginMixed(binding:ExpressionBinding)throws->SessionUpdate {
        lock.lock();defer{lock.unlock()}
        guard core.idleExpressionBinding==binding,let snapshot=core.snapshot else{throw SessionError.staleExplicitAction}
        return try beginMixed(snapshot:snapshot)
    }
    public func beginMixed(snapshot expected:CandidateSnapshot)throws->SessionUpdate {
        lock.lock();defer{lock.unlock()};try core.ensureReady()
        guard canBeginMixed,let snapshot=core.snapshot,snapshot.session==expected.session,
              snapshot.targetEpoch==expected.targetEpoch,snapshot.inputGeneration==expected.inputGeneration else{throw SessionError.staleExplicitAction}
        let prepared=try MixedComposition(source:id,snapshot:snapshot,validateResult:{[weak self] point in try self?.mixedResultValidation(point)})
        var next=core;let update=try prepared.republish(core:&next)
        // Original engine state is no longer the draft authority. Clear only
        // after a complete verified import and pure publication are prepared.
        var cleared=PaiaRimeSnapshot();let rc=paia_rime_step(id,3,0,0,&cleared)
        defer{paia_rime_free_snapshot(&cleared)}
        do{
            guard rc==PAIA_OK,cleared.commit==nil else{throw EngineError.code(rc)}
            try mixedResultValidation(.sourceClear)
            let value=try Self.decode(cleared)
            guard value.raw.isEmpty,value.preedit.isEmpty,value.candidates.isEmpty else{throw SessionError.invalidEngineValue}
        }catch{core.invalidate();throw error}
        core=next;mixed=prepared;invalidateRepairActions();return update
    }
    public func setMixedLiteralIntent(_ literal:Bool)throws->SessionUpdate {
        lock.lock();defer{lock.unlock()};try core.ensureReady();guard let mixed=mixed else{throw SessionError.staleExplicitAction}
        let update=try mixed.republish(core:&core);mixed.literalIntent=literal;return update
    }
    public func reopenMixedSpan(_ span:UUID)throws->SessionUpdate {
        lock.lock();defer{lock.unlock()};try core.ensureReady();guard let mixed=mixed else{throw SessionError.staleExplicitAction}
        let draft=try mixed.state.draft.reopening(span)
        return try mixedOperation{try mixed.publish(mixed.prepared(draft),core:&core)}
    }
    private func mixedOperation(_ action:()throws->SessionUpdate)throws->SessionUpdate {
        do{return try action()}catch{
            if let mixed=mixed,mixed.unsafeTransition || mixed.sealed{mixed.close();self.mixed=nil;core.invalidate()}
            throw error
        }
    }
    private func commitMixed()throws->SessionUpdate {
        try core.ensureReady();guard let mixed=mixed else{throw SessionError.staleExplicitAction}
        // Native failures before a result preserve the draft. A sealed result
        // can create at most one core effect; later publication failure retires.
        do{
            let text=try mixed.commit(),update=try core.finishMixed(text,engine:true)
            mixed.close();self.mixed=nil;return update
        }catch{
            if mixed.sealed{mixed.close();self.mixed=nil;core.invalidate()}
            throw error
        }
    }
    private func processMixed(_ key:InputKey)throws->SessionUpdate {
        guard let mixed=mixed else{throw SessionError.staleExplicitAction}
        let draft=mixed.state.draft
        func refusal()->SessionUpdate {SessionUpdate(handled:true,snapshot:core.snapshot,refusal:.unsupportedTextDuringComposition)}
        func edit(_ range:Range<Int>,_ text:String,_ literal:Bool)throws->SessionUpdate {
            let changed:MixedDraft
            do{changed=try draft.replacing(range,with:text,literal:literal)}
            catch is MixedDraftError{return refusal()}
            catch is BoundaryError{return refusal()}
            return try mixed.publish(mixed.prepared(changed),core:&core)
        }
        func insert(_ text:String)throws->SessionUpdate {
            guard !text.isEmpty else{return SessionUpdate(handled:true,snapshot:core.snapshot)}
            let spelling=text.utf8.allSatisfy{(97...122).contains($0) || $0==39}
            return try edit(draft.caretUTF8..<draft.caretUTF8,text,mixed.literalIntent || !spelling)
        }
        switch key {
        case .command:return SessionUpdate(handled:false,snapshot:core.snapshot)
        case .returnKey:
            guard !draft.isEmpty else{return SessionUpdate(handled:false,snapshot:core.snapshot)}
            let update=try core.finishMixed(draft.source,engine:false);mixed.close();self.mixed=nil;return update
        case .escape:
            mixed.close();self.mixed=nil;return try step(3)
        case .text(let text):
            if !mixed.literalIntent,text.utf8.count==1,let byte=text.utf8.first,(48...57).contains(byte){return try processMixed(.number(Int(byte-48)))}
            return try insert(text)
        case .space:
            if mixed.literalIntent{return try insert(" ")}
            if draft.isResolved && !draft.isEmpty{return try commitMixed()}
            guard let snapshot=core.snapshot,let row=snapshot.rows.first else{return SessionUpdate(handled:true,snapshot:core.snapshot)}
            return try mixed.select(row.ref,core:&core)
        case .number(let number):
            if mixed.literalIntent{return try insert(String(number))}
            guard let snapshot=core.snapshot,(1...5).contains(number),snapshot.rows.indices.contains(number-1) else{return SessionUpdate(handled:true,snapshot:core.snapshot)}
            return try mixed.select(snapshot.rows[number-1].ref,core:&core)
        case .code(let code,let modifiers):
            guard modifiers==0 else{return refusal()}
            if (32...126).contains(code),let scalar=UnicodeScalar(UInt32(code)){return try processMixed(.text(String(scalar)))}
            if code==0xff55 || code==0xff56{return try mixed.page(code==0xff55 ? -1:1,core:&core)}
            if code==0xff09 {
                let spelling=draft.map.filter{if case .spelling=$0.span.origin{return true};return false}
                guard !spelling.isEmpty else{return SessionUpdate(handled:true,snapshot:core.snapshot)}
                let index=spelling.firstIndex{$0.span.id==mixed.state.active} ?? -1,next=spelling[(index+1)%spelling.count]
                let moved=try draft.movingCaret(to:next.sourceUTF8.lowerBound)
                return try mixed.publish(mixed.prepared(moved,active:next.span.id),core:&core)
            }
            // Walk actual graphemes once. Confirmed spans expose only proven
            // endpoints, without rebuilding/validating a draft for every byte.
            var allowed=[0]
            for item in draft.map {
                if case .engine=item.span.origin{allowed.append(item.sourceUTF8.upperBound)}
                else{var position=item.sourceUTF8.lowerBound;for character in item.span.source{position+=String(character).utf8.count;allowed.append(position)}}
            }
            if code==0xff51 || code==0xff53 || code==0xff50 || code==0xff57 {
                let destination:Int
                if code==0xff50{destination=0}else if code==0xff57{destination=draft.source.utf8.count}
                else if code==0xff51{destination=allowed.last{$0<draft.caretUTF8} ?? draft.caretUTF8}
                else{destination=allowed.first{$0>draft.caretUTF8} ?? draft.caretUTF8}
                let moved=try draft.movingCaret(to:destination);return try mixed.publish(mixed.prepared(moved),core:&core)
            }
            if code==0xff08 || code==0xffff {
                let start=code==0xff08 ? (allowed.last{$0<draft.caretUTF8} ?? draft.caretUTF8):draft.caretUTF8
                let end=code==0xffff ? (allowed.first{$0>draft.caretUTF8} ?? draft.caretUTF8):draft.caretUTF8
                return try edit(start..<end,"",true)
            }
            return refusal()
        }
    }
    public func process(_ key: InputKey) throws -> SessionUpdate {
        lock.lock(); defer {lock.unlock()}
        guard !ended, core.active else { throw EngineError.closed }
        try core.ensureReady()
        if mixed != nil{return try mixedOperation{try processMixed(key)}}
        let composing=core.isComposing
        func passthrough() -> SessionUpdate { SessionUpdate(handled:false,snapshot:core.snapshot) }
        func refuse(_ reason:InputRefusal)->SessionUpdate {SessionUpdate(handled:true,snapshot:core.snapshot,refusal:reason)}
        switch key {
        case .text(let text):
            // Ordinary Unicode text is never interpreted as a Rime/X11 control keysym.
            var scalars=text.unicodeScalars.makeIterator()
            guard let scalar=scalars.next(),scalars.next()==nil,(32...126).contains(scalar.value) else {
                return composing ? refuse(.unsupportedTextDuringComposition):passthrough()
            }
            if scalar.value==32{return try process(.space)}
            if (48...57).contains(scalar.value){return try process(.number(Int(scalar.value-48)))}
            return try process(.code(Int32(scalar.value)))
        case .command: return passthrough()
        case .returnKey:
            guard composing else {return passthrough()}
            return try step(3,literal:core.snapshot?.rawASCII)
        case .escape: return composing ? try step(3) : passthrough()
        case .space:
            guard composing else {return passthrough()}
            guard let s=core.snapshot, s.rows.indices.contains(s.highlighted) else {return SessionUpdate(handled:true,snapshot:core.snapshot)}
            return try select(s.rows[s.highlighted].ref)
        case .number(let number):
            guard composing else {return passthrough()}
            guard let s=core.snapshot, (1...5).contains(number), s.rows.indices.contains(number-1) else {return SessionUpdate(handled:true,snapshot:core.snapshot)}
            return try select(s.rows[number-1].ref)
        case .code(let code, let modifiers):
            if composing {
                let controls:Set<Int32>=[0xff08,0xffff,0xff51,0xff53,0xff54,0xff52,0xff50,0xff57,0xff55,0xff56,0xff09]
                if !(32...126).contains(code) && !controls.contains(code){return refuse(.unsupportedTextDuringComposition)}
                if let snapshot=core.snapshot,snapshot.caretUTF8<snapshot.rawASCII.utf8.count,
                   (32...126).contains(code),!(97...122).contains(code),!(48...57).contains(code),code != 39 {
                    // Includes caret zero, punctuation and uppercase; apostrophe is the
                    // pinned schema's explicit spelling delimiter. No engine mutation.
                    return refuse(.textBeforeRawSuffix)
                }
            }
            if retained && (32...126).contains(code) && !(97...122).contains(code) && code != 39 {
                return composing ? refuse(.unsupportedTextDuringComposition):passthrough()
            }
            // Non-text keys belong to the host when idle. Command/Option are handled by the host adapter.
            if !composing && !(97...122).contains(code) && !(chinesePunctuation && [44,63,33,59].contains(code)) {return passthrough()}
            if composing && (core.snapshot?.rawASCII.utf8.count ?? 0)>=4096 && ((97...122).contains(code) || code==39) {
                return SessionUpdate(handled:true,snapshot:core.snapshot)
            }
            // Rime ordinary Left/Right jump syllables; the contract here is raw-character movement.
            // Its keypad-left/right bindings explicitly invoke engine LeftByChar/RightByChar.
            let engineCode:Int32 = code==0xff51 ? 0xff96 : (code==0xff53 ? 0xff98 : code)
            return try step(1,engineCode,modifiers)
        }
    }
}

private func copyList(_ list:PaiaG01List) throws -> (raw:String,preview:String,anchors:[RawAnchor]) {
    func text(_ p:UnsafeMutablePointer<CChar>?) throws -> String {
        guard let p=p,let value=String(validatingUTF8:p) else{throw EngineError.invalidUTF8};return value
    }
    let raw=try text(list.raw),preview=try text(list.preview)
    guard list.count<=2048,list.count==0 || list.items != nil else{throw ConstraintError.invalidSpan}
    let anchors=try (0..<Int(list.count)).map {i -> RawAnchor in
        let item=list.items![i];guard item.start_utf8<item.end_utf8,item.end_utf8<=raw.utf8.count else{throw ConstraintError.invalidSpan};let anchor=RawAnchor(bytes:Int(item.start_utf8)..<Int(item.end_utf8),text:try text(item.text),engineIndex:Int(item.index))
        try anchor.validate(in:raw);return anchor
    }
    return (raw,preview,anchors)
}
public final class RepairProposal {
    private let runtime:RimeRuntime,lock=NSLock()
    private var id:UInt64
    public let lease:RepairLease,raw:String,preview:String,anchors:[RawAnchor],examined:Int
    fileprivate init(runtime:RimeRuntime,id:UInt64,lease:RepairLease,raw:String,preview:String,anchors:[RawAnchor],examined:Int) {
        self.runtime=runtime;self.id=id;self.lease=lease;self.raw=raw;self.preview=preview;self.anchors=anchors;self.examined=examined
    }
    deinit{cancel()}
    public func cancel(){lock.lock();defer{lock.unlock()};if id != 0 {paia_rime_end_session(id);id=0}}
    fileprivate func transfer(_ apply:(UInt64)throws->SessionUpdate) throws -> SessionUpdate {
        lock.lock();defer{lock.unlock()};guard id != 0 else{throw ConstraintError.consumed}
        let result=try apply(id);id=0;return result
    }
}

// Only engine-issued snapshots can construct these action identities.
public struct RepairChoice {
    public let lease:RepairLease,anchor:RawAnchor
    fileprivate let token:UUID
}
public struct RepairChoices {
    public let rows:[RepairChoice],complete:Bool
}
public struct RepairTarget {
    public let lease:RepairLease,anchor:RawAnchor,index:Int
    fileprivate init(lease:RepairLease,anchor:RawAnchor,index:Int){self.lease=lease;self.anchor=anchor;self.index=index}
}
public struct RepairAnchors {
    public let lease:RepairLease,rows:[RawAnchor],preview:String
    public var targets:[RepairTarget]{rows.enumerated().map{RepairTarget(lease:lease,anchor:$0.element,index:$0.offset)}}
}

// Values issued only by an exact-source, bounded native replay. No live trial per row.
public struct RepairAlternative {
    public let target:RepairTarget,replacementRaw:String,raw:String,surface:String,preview:String
    fileprivate let token:UUID
}
public struct RepairAlternatives {
    public let target:RepairTarget,rows:[RepairAlternative],complete:Bool,examined:Int,status:Int32
}
