import Foundation
import TextBoundary

public struct SessionKey: Hashable {
    public let serverInstanceID: UUID
    public let clientSessionID: UUID
    public init(server: UUID = UUID(), client: UUID = UUID()) { serverInstanceID=server; clientSessionID=client }
}
public struct EngineValue {
    public let raw: String, preedit: String
    public let caretUTF8: Int, preeditCaretUTF8: Int, selectionStartUTF8: Int, selectionEndUTF8: Int
    public let candidates: [String], page: Int, highlighted: Int, hasMore: Bool
    public let commit: String?, handled: Bool
    public init(raw: String, preedit: String, caretUTF8: Int, preeditCaretUTF8: Int = 0,
                selectionStartUTF8: Int = 0, selectionEndUTF8: Int = 0,
                candidates: [String] = [], page: Int = 0, highlighted: Int = 0,
                hasMore: Bool = false, commit: String? = nil, handled: Bool = true) {
        self.raw=raw; self.preedit=preedit; self.caretUTF8=caretUTF8; self.preeditCaretUTF8=preeditCaretUTF8
        self.selectionStartUTF8=selectionStartUTF8; self.selectionEndUTF8=selectionEndUTF8
        self.candidates=candidates; self.page=page; self.highlighted=highlighted; self.hasMore=hasMore
        self.commit=commit; self.handled=handled
    }
}
public struct CandidateRef: Hashable {
    public let session: SessionKey, targetEpoch: UInt64, inputGeneration: UInt64, dictionaryRevision: String
    public let page: Int, engineIndexOnPage: Int
    // C API does not expose exact per-row source spans. Do not invent G01 coverage.
    public var rawSpanUTF8: Range<Int>? { nil }
}
public struct CandidateRow { public let ref: CandidateRef, text: String }
public struct CandidateSnapshot {
    public let session: SessionKey, targetEpoch: UInt64, inputGeneration: UInt64, privacyEpoch: UInt64
    public let rawASCII: String, preedit: String, caretUTF8: Int, selectedRangeUTF16: NSRange
    public let rows: [CandidateRow], pageIndex: Int, highlighted: Int, hasMore: Bool
    public let complete: Bool
}
public enum CommitOrigin { case engine, literal, explicitExpression, reviewedEdit }
public struct CommitEffect {
    public let operationID: UUID, session: SessionKey, targetEpoch: UInt64, inputGeneration: UInt64
    public let text: String, origin: CommitOrigin
    // Non-nil only for an explicitly reviewed edit; ordinary C0 effects retain nil.
    public let replacementUTF16:NSRange?
    init(operationID:UUID,session:SessionKey,targetEpoch:UInt64,inputGeneration:UInt64,text:String,origin:CommitOrigin,replacementUTF16:NSRange?=nil) {
        self.operationID=operationID;self.session=session;self.targetEpoch=targetEpoch;self.inputGeneration=inputGeneration;self.text=text;self.origin=origin;self.replacementUTF16=replacementUTF16
    }
}
public enum InputRefusal:Equatable {
    case unsupportedTextDuringComposition, textBeforeRawSuffix, unhandledControlDuringComposition
}
public struct SessionUpdate {
    public let handled: Bool, snapshot: CandidateSnapshot?, commit: CommitEffect?
    public let refusal:InputRefusal?
    public init(handled: Bool, snapshot: CandidateSnapshot?, commit: CommitEffect? = nil,refusal:InputRefusal? = nil) {
        self.handled=handled; self.snapshot=snapshot; self.commit=commit;self.refusal=refusal
    }
}
public enum SessionError: Error { case inactive, staleCandidate, pendingCommit, invalidEngineValue, staleExplicitAction }

public struct ExpressionBinding:Hashable {
    public let session:SessionKey,targetEpoch:UInt64,inputGeneration:UInt64,privacyEpoch:UInt64,dictionaryRevision:String
}

public struct CharacterBinding:Hashable {
    public let session:SessionKey,targetEpoch:UInt64,inputGeneration:UInt64,dictionaryRevision:String
}

// Pure value state. The only effect reservation gate, with no AppKit, C calls, disk or network.
public struct SessionCore {
    public let key: SessionKey, dictionaryRevision: String
    public private(set) var targetEpoch: UInt64 = 0, inputGeneration: UInt64 = 0, privacyEpoch: UInt64 = 0
    public private(set) var snapshot: CandidateSnapshot?
    public private(set) var active = true
    private var pendingOperation: UUID?
    public init(key: SessionKey = SessionKey(), dictionaryRevision: String) { self.key=key; self.dictionaryRevision=dictionaryRevision }
    public var isComposing: Bool { !(snapshot?.rawASCII.isEmpty ?? true) || !(snapshot?.preedit.isEmpty ?? true) }
    public func validate(_ ref: CandidateRef) throws {
        guard active else { throw SessionError.inactive }
        guard let s=snapshot, ref.session==key, ref.targetEpoch==targetEpoch,
              ref.inputGeneration==inputGeneration, ref.dictionaryRevision==dictionaryRevision,
              ref.page==s.pageIndex, s.rows.contains(where: {$0.ref==ref}) else { throw SessionError.staleCandidate }
    }
    public func ensureReady() throws {
        guard active else { throw SessionError.inactive }
        guard pendingOperation == nil else { throw SessionError.pendingCommit }
    }
    public mutating func receive(_ v: EngineValue, literal: String? = nil) throws -> SessionUpdate {
        guard active else { throw SessionError.inactive }
        guard pendingOperation == nil else { throw SessionError.pendingCommit }
        guard v.raw.utf8.count<=4096, v.raw.utf8.allSatisfy({$0<128}), v.candidates.count<=64,
              v.page>=0, v.highlighted>=0, v.candidates.isEmpty || v.highlighted<v.candidates.count,
              literal == nil || v.commit == nil else { throw SessionError.invalidEngineValue }
        _ = try TextBoundary.utf16Offset(in: v.raw, utf8: v.caretUTF8)
        let caret16 = try TextBoundary.utf16Offset(in: v.preedit, utf8: v.preeditCaretUTF8)
        _ = try TextBoundary.range(in: v.preedit, startUTF8: v.selectionStartUTF8, endUTF8: v.selectionEndUTF8)
        let selection=NSRange(location:caret16,length:0)
        inputGeneration += 1
        let rows=v.candidates.enumerated().map { i,text in CandidateRow(ref: CandidateRef(session:key,
            targetEpoch:targetEpoch,inputGeneration:inputGeneration,dictionaryRevision:dictionaryRevision,
            page:v.page,engineIndexOnPage:i),text:text) }
        let s=CandidateSnapshot(session:key,targetEpoch:targetEpoch,inputGeneration:inputGeneration,
            privacyEpoch:privacyEpoch,rawASCII:v.raw,preedit:v.preedit,caretUTF8:v.caretUTF8,
            selectedRangeUTF16:selection,rows:rows,pageIndex:v.page,highlighted:v.highlighted,hasMore:v.hasMore,complete:true)
        snapshot=s
        var effect: CommitEffect?
        if let text=literal ?? v.commit, !text.isEmpty {
            let id=UUID(); pendingOperation=id
            effect=CommitEffect(operationID:id,session:key,targetEpoch:targetEpoch,inputGeneration:inputGeneration,
                                text:text,origin:literal == nil ? .engine : .literal)
        }
        return SessionUpdate(handled:v.handled,snapshot:s,commit:effect)
    }
    public var idleCharacterBinding:CharacterBinding? {
        guard active,pendingOperation==nil,let s=snapshot,s.rawASCII.isEmpty,s.preedit.isEmpty,s.rows.isEmpty else{return nil}
        return CharacterBinding(session:key,targetEpoch:targetEpoch,inputGeneration:inputGeneration,dictionaryRevision:dictionaryRevision)
    }
    public mutating func commitKnownCharacter(_ value:KnownCharacter,binding:CharacterBinding)throws->SessionUpdate {
        try ensureReady()
        guard let current=idleCharacterBinding,current==binding else{throw SessionError.staleExplicitAction}
        // The initialized engine snapshot is idle; the explicit literal action does not decode
        // or fabricate a candidate. Reuse the same generation/effect reservation machinery.
        return try receive(EngineValue(raw:"",preedit:"",caretUTF8:0),literal:value.text)
    }
    public var idleExpressionBinding:ExpressionBinding? {
        guard let idle=idleCharacterBinding else{return nil}
        return ExpressionBinding(session:idle.session,targetEpoch:idle.targetEpoch,inputGeneration:idle.inputGeneration,privacyEpoch:privacyEpoch,dictionaryRevision:idle.dictionaryRevision)
    }
    public mutating func commitExpression(_ text:String,binding:ExpressionBinding)throws->SessionUpdate {
        try ensureReady()
        guard let current=idleExpressionBinding,current==binding,!text.isEmpty,text.utf16.count<=16384,!text.unicodeScalars.contains(where:{$0.value==0}) else{throw SessionError.staleExplicitAction}
        let update=try receive(EngineValue(raw:"",preedit:"",caretUTF8:0),literal:text)
        guard let effect=update.commit else{throw SessionError.invalidEngineValue}
        return SessionUpdate(handled:true,snapshot:update.snapshot,commit:CommitEffect(operationID:effect.operationID,session:effect.session,targetEpoch:effect.targetEpoch,inputGeneration:effect.inputGeneration,text:effect.text,origin:.explicitExpression))
    }
    public mutating func commitReviewedEdit(_ text:String,replacing range:NSRange,binding:ExpressionBinding)throws->SessionUpdate {
        try ensureReady()
        guard idleExpressionBinding==binding,let end=ContextBudget.end(range),end<=ContextBudget.document,
              range.length<=ContextBudget.selection,text.utf16.count<=ContextBudget.selection,
              !text.unicodeScalars.contains(where:{$0.value==0}),!text.isEmpty || range.length>0 else{throw SessionError.staleExplicitAction}
        // Empty replacement is a real deletion effect, not receive's empty no-op.
        let update=try receive(EngineValue(raw:"",preedit:"",caretUTF8:0))
        let id=UUID();pendingOperation=id
        let effect=CommitEffect(operationID:id,session:key,targetEpoch:targetEpoch,inputGeneration:inputGeneration,
            text:text,origin:.reviewedEdit,replacementUTF16:range)
        return SessionUpdate(handled:true,snapshot:update.snapshot,commit:effect)
    }
    // Reserve BEFORE calling a host. An uncertain host outcome is not replayable.
    public mutating func reserve(_ effect: CommitEffect) -> Bool {
        guard active, effect.session==key, effect.targetEpoch==targetEpoch,
              effect.inputGeneration==inputGeneration, effect.operationID==pendingOperation else { return false }
        pendingOperation=nil; return true
    }
    public mutating func invalidate() {
        targetEpoch += 1; inputGeneration += 1; privacyEpoch += 1
        snapshot=nil; pendingOperation=nil; active=false
    }
}
