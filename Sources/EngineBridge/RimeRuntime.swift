import Foundation
import CRimeShim
import SessionCore

public enum EngineError: Error { case code(Int32), invalidUTF8, closed }
public final class RimeRuntime {
    public let dictionaryRevision: String
    public let version = "1.16.0"
    private static let lifetime = NSLock()
    private static var created = false
    // Explicit directories only: callers must create a fresh isolated user directory.
    public init(library: String, shared: String, isolatedUser: String, dictionaryRevision: String) throws {
        Self.lifetime.lock(); defer { Self.lifetime.unlock() }
        guard !Self.created else { throw EngineError.code(Int32(PAIA_BUSY)) }
        let rc=paia_rime_open(library,shared,isolatedUser)
        guard rc==PAIA_OK else { throw EngineError.code(rc) }
        Self.created=true; self.dictionaryRevision=dictionaryRevision
    }
    deinit { paia_rime_close() }
    public func makeSession() throws -> InputSession {
        let id=paia_rime_start_session()
        guard id != 0 else { throw EngineError.code(Int32(PAIA_SESSION)) }
        return InputSession(runtime:self,id:id)
    }
}

public struct EngineTiming {
    public let engineNanoseconds:UInt64, copyNanoseconds:UInt64
}
public enum InputKey {
    case code(Int32, modifiers: Int32 = 0), returnKey, space, number(Int), escape, command
}
public final class InputSession {
    private let runtime: RimeRuntime, id: UInt64
    private let lock=NSRecursiveLock()
    private var core: SessionCore
    private var ended=false
    private var timing=EngineTiming(engineNanoseconds:0,copyNanoseconds:0)
    public var lastTiming:EngineTiming {lock.lock();defer{lock.unlock()};return timing}
    internal init(runtime: RimeRuntime,id: UInt64) {
        self.runtime=runtime; self.id=id; core=SessionCore(dictionaryRevision:runtime.dictionaryRevision)
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
        func string(_ p: UnsafeMutablePointer<CChar>?) throws -> String {
            guard let p=p else { return "" }
            guard let s=String(validatingUTF8:p) else { throw EngineError.invalidUTF8 }
            return s
        }
        do {
            let rows=try (0..<Int(c.count)).map { i in try string(c.candidates?[i]) }
            let value=try EngineValue(raw:string(c.raw),preedit:string(c.preedit),caretUTF8:Int(c.caret_utf8),
                preeditCaretUTF8:Int(c.preedit_caret_utf8),selectionStartUTF8:Int(c.selection_start_utf8),
                selectionEndUTF8:Int(c.selection_end_utf8),candidates:rows,page:Int(c.page),highlighted:Int(c.highlighted),
                hasMore:c.has_more != 0,commit:c.commit == nil ? nil : string(c.commit),handled:c.handled != 0)
            return try core.receive(value,literal:literal)
        } catch { core.invalidate(); throw error }
    }
    public func refresh() throws -> SessionUpdate { lock.lock(); defer {lock.unlock()}; return try step(0) }
    public func select(_ ref: CandidateRef) throws -> SessionUpdate {
        lock.lock(); defer {lock.unlock()}
        try core.validate(ref)
        return try step(2,Int32(ref.engineIndexOnPage))
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
            if !composing && !(97...122).contains(code) {return passthrough()}
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
