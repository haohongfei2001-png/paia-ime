import Foundation
import CRimeShim
import SessionCore
import ConstraintCore

public enum EngineError: Error { case code(Int32), invalidUTF8, closed }
public final class RimeRuntime {
    public let dictionaryRevision: String
    public let version = "1.16.0"
    private static let lifetime = NSLock()
    private static var created = false
    private let repairDisabledSchemas:Set<String>
    private final class WeakSession {weak var value:InputSession?;init(_ value:InputSession){self.value=value}}
    private let lifecycle=NSRecursiveLock()
    private var sessions=[WeakSession](),closed=false,cleanupSucceeded=true
    private let cleanup:(()throws->Void)?
    // Explicit directories only: callers must create a fresh isolated user directory.
    public init(library: String, shared: String, isolatedUser: String, dictionaryRevision: String, schemas:[String] = [], g01Library:String? = nil,repairDisabledSchemas:Set<String> = [],cleanup:(()throws->Void)?=nil) throws {
        self.repairDisabledSchemas=repairDisabledSchemas;self.cleanup=cleanup
        Self.lifetime.lock(); defer { Self.lifetime.unlock() }
        guard !Self.created else { throw EngineError.code(Int32(PAIA_BUSY)) }
        let rc=paia_rime_open(library,shared,isolatedUser)
        guard rc==PAIA_OK else { throw EngineError.code(rc) }
        Self.created=true; self.dictionaryRevision=dictionaryRevision
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
        let session=InputSession(runtime:self,id:id,chinesePunctuation:chinesePunctuation,supportsRepair:!repairDisabledSchemas.contains(schema))
        sessions.removeAll{$0.value==nil};sessions.append(WeakSession(session));return session
    }
}

public struct EngineTiming {
    public let engineNanoseconds:UInt64, copyNanoseconds:UInt64
}
public enum InputKey {
    case code(Int32, modifiers: Int32 = 0), returnKey, space, number(Int), escape, command
}
public final class InputSession {
    private let runtime: RimeRuntime
    private var id: UInt64
    private var repairRequest:UInt64=0
    private var issuedChoices:[Int:RepairChoice]=[:]
    private let chinesePunctuation:Bool
    public let supportsRepair:Bool
    private let lock=NSRecursiveLock()
    private var core: SessionCore
    private var ended=false
    private var timing=EngineTiming(engineNanoseconds:0,copyNanoseconds:0)
    public var lastTiming:EngineTiming {lock.lock();defer{lock.unlock()};return timing}
    internal init(runtime: RimeRuntime,id: UInt64,chinesePunctuation:Bool,supportsRepair:Bool) {
        self.runtime=runtime; self.id=id; self.chinesePunctuation=chinesePunctuation;self.supportsRepair=supportsRepair;core=SessionCore(dictionaryRevision:runtime.dictionaryRevision)
    }
    deinit { end() }
    public var snapshot: CandidateSnapshot? { lock.lock(); defer {lock.unlock()}; return core.snapshot }
    public var key: SessionKey { lock.lock(); defer {lock.unlock()}; return core.key }
    public func end() {
        lock.lock(); defer {lock.unlock()}
        if !ended { core.invalidate(); paia_rime_end_session(id); ended=true }
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
    public func refresh() throws -> SessionUpdate { lock.lock(); defer {lock.unlock()}; return try step(0) }
    public func select(_ ref: CandidateRef) throws -> SessionUpdate {
        lock.lock(); defer {lock.unlock()}
        try core.validate(ref)
        return try step(2,Int32(ref.engineIndexOnPage))
    }
    private func lease() throws -> RepairLease {
        guard !ended,let snapshot=core.snapshot else{throw EngineError.closed}
        guard supportsRepair else{throw ConstraintError.native(code:Int32(PG_UNSUPPORTED),examined:0)}
        try core.ensureReady()
        return RepairLease(snapshot:snapshot,revision:runtime.dictionaryRevision,request:repairRequest)
    }
    public func repairAnchors() throws -> RepairAnchors {
        lock.lock();defer{lock.unlock()};let identity=try lease()
        var list=PaiaG01List();let rc=paia_rime_g01_anchors(id,&list);defer{paia_rime_g01_free_list(&list)}
        guard rc==PG_OK else{throw ConstraintError.native(code:rc,examined:0)}
        return RepairAnchors(lease:identity,rows:try copyList(list).anchors)
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
    public func prepareRepair(target:RepairTarget,replacementRaw:String,surface:String,limit:Int=2048) throws -> RepairProposal {
        lock.lock();defer{lock.unlock()};_ = try lease()
        guard target.lease.matches(core.snapshot,revision:runtime.dictionaryRevision,request:repairRequest) else{throw ConstraintError.stale}
        guard target.index>=0,(1...2048).contains(limit),!replacementRaw.utf8.contains(0),!surface.utf8.contains(0) else{throw ConstraintError.invalidSpan}
        let currentAnchors=try repairAnchors().rows
        guard currentAnchors.indices.contains(target.index),currentAnchors[target.index]==target.anchor else{throw ConstraintError.stale}
        repairRequest += 1;let identity=try lease()
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
    public func commitEngineComposition() throws -> SessionUpdate {
        lock.lock();defer{lock.unlock()};return try step(5)
    }
    public func process(_ key: InputKey) throws -> SessionUpdate {
        lock.lock(); defer {lock.unlock()}
        guard !ended, core.active else { throw EngineError.closed }
        let composing=core.isComposing
        func passthrough() -> SessionUpdate { SessionUpdate(handled:false,snapshot:core.snapshot) }
        switch key {
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
    public let lease:RepairLease,rows:[RawAnchor]
    public var targets:[RepairTarget]{rows.enumerated().map{RepairTarget(lease:lease,anchor:$0.element,index:$0.offset)}}
}
