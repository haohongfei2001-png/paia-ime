#if os(macOS)
import AppKit
import EngineBridge
import NativeHost
import SettingsCore
import LexiconCore
import SessionCore
import ExpressionCore

public enum IMKManagementError:Error {case busy,unavailable,interrupted}

// One process-wide configuration and mutation owner, shared by all IMK controllers.
// Store IO occurs only in explicit management actions, never in makeSession/key paths.
@MainActor public final class IMKWorkspace {
    public private(set) var configuration=LabConfiguration()
    public let settingsStore:SettingsStore?,personalStore:LexiconStore?
    public let expressionStore:ExpressionStore?
    public private(set) var expressionCatalog:ExpressionCatalog?
    public let resourceDescription:String
    private let factory:(LabConfiguration)throws->InputSession
    private let disablePersonal:()->Void
    private final class WeakDriver {weak var value:IMKControllerDriver?;init(_ value:IMKControllerDriver){self.value=value}}
    private var drivers=[WeakDriver](),managing=false,interrupted=false,closed=false
    public private(set) var configurationRevision:UInt64=0
    public init(settingsStore:SettingsStore?=nil,personalStore:LexiconStore?=nil,expressionStore:ExpressionStore?=nil,resourceDescription:String,
                makeSession:@escaping(LabConfiguration)throws->InputSession,disablePersonal:@escaping()->Void={}) {
        self.settingsStore=settingsStore;self.personalStore=personalStore;self.resourceDescription=resourceDescription
        factory=makeSession;self.disablePersonal=disablePersonal;self.expressionStore=expressionStore
        if let store=expressionStore {do{expressionCatalog=ExpressionCatalog(document:try store.snapshot())}catch{expressionCatalog=nil}}
    }
    private var live:[IMKControllerDriver] {drivers.compactMap{$0.value}}
    public var isIdle:Bool {!closed && !managing && live.allSatisfy{$0.isIdleForManagement}}
    public func withIdleAccess<T>(_ action:()throws->T)throws->T {
        guard isIdle else{throw IMKManagementError.busy}
        managing=true;interrupted=false
        defer{
            // A callback during management was not processed by the engine. Do
            // not revive its old target after the action; the next activation is explicit.
            if interrupted{for driver in live{driver.discardIdleBindingForManagement()}}
            managing=false
        }
        return try action()
    }
    private func permitInput()->Bool {
        if managing{interrupted=true;return false}
        return !closed
    }
    public func makeDriver(hide:@escaping()->Void,present:@escaping(CandidateSnapshot?,NSRect,String?)->Void,presentRecall:@escaping(ExpressionRecallState,NSRect)->Bool={_,_ in false},scrollRecall:@escaping(Int,UUID)->Void={_,_ in},presentRepair:@escaping(SegmentRepairState,NSRect)->Bool={_,_ in false},scrollRepair:@escaping(Int,UUID)->Void={_,_ in},presentContext:@escaping(ContextEditState,NSRect)->Bool={_,_ in false},scrollContext:@escaping(Int,UUID)->Void={_,_ in},showCharacters:@escaping()->Void={NSApp.orderFrontCharacterPalette(nil)})->IMKControllerDriver {
        let driver=IMKControllerDriver(makeSession:{[weak self] in
            guard let self=self,!self.closed,!self.managing else{return nil};return try? self.factory(self.configuration)
        },expressions:{[weak self] in self?.expressionCatalog},literal:{[weak self] in self?.configuration.literal==true},permitOperation:{[weak self] in self?.permitInput()==true},initialLiteral:{[weak self] application in self?.configuration.preferences.initialLiteral(for:application)==true},showCharacters:showCharacters,hide:hide,present:present,presentRecall:presentRecall,scrollRecall:scrollRecall,presentRepair:presentRepair,scrollRepair:scrollRepair,presentContext:presentContext,scrollContext:scrollContext)
        drivers.removeAll{$0.value==nil};drivers.append(WeakDriver(driver))
        if managing{interrupted=true}
        return driver
    }
    public func applyConfiguration(_ next:LabConfiguration)throws {
        try withIdleAccess {
            guard !next.deferredCommit else{throw IMKManagementError.unavailable}
            try SettingsCodec.validate(next.preferences)
            let prepared=try factory(next);defer{prepared.end()}
            let initial=try prepared.refresh()
            guard !interrupted,live.allSatisfy({$0.isIdleForManagement}),initial.commit==nil,
                  initial.snapshot?.sourceText.isEmpty==true,initial.snapshot?.preedit.isEmpty==true else{throw IMKManagementError.interrupted}
            // No callbacks between global publication and all-owner retirement.
            configuration=next;configurationRevision &+= 1
            let owners=live;for driver in owners{driver.retireIdleForManagement(resetInitialMode:true)}
            for driver in owners{driver.dismissCandidatesForManagement()}
        }
    }
    // Called only inside the manager's held access boundary, including authority
    // failure. Every idle engine owner is retired before the shared overlay ends.
    public func personalAuthorityChanged(){
        precondition(managing && live.allSatisfy{$0.isIdleForManagement})
        let owners=live;for driver in owners{driver.retireIdleForManagement()}
        disablePersonal()
        for driver in owners{driver.dismissCandidatesForManagement()}
    }
    private func publishExpressions(_ document:ExpressionDocument?) {
        precondition(managing && live.allSatisfy{$0.isIdleForManagement})
        expressionCatalog=ExpressionCatalog(document:document)
        let owners=live;for driver in owners{driver.retireIdleForManagement()}
        for driver in owners{driver.dismissCandidatesForManagement()}
    }
    private func quarantineExpressions(){
        expressionCatalog=nil
        let owners=live;for driver in owners{driver.retireIdleForManagement()}
        for driver in owners{driver.dismissCandidatesForManagement()}
    }
    public func reloadExpressions()throws {
        try withIdleAccess {guard let store=expressionStore else{throw IMKManagementError.unavailable}
            do{publishExpressions(try store.snapshot())}catch{quarantineExpressions();throw error}}
    }
    @discardableResult public func saveExpression(_ text:String,aliases:[String],editing:UUID?=nil,recordRevision:UInt64?=nil,catalogRevision:UInt64)throws->ExpressionDocument {
        try ExpressionCodec.validate(text:text,aliases:aliases)
        return try withIdleAccess {guard let store=expressionStore else{throw IMKManagementError.unavailable}
            do{let document=try store.saveExact(text,aliases:aliases,editing:editing,expectedRecordRevision:recordRevision,expectedRevision:catalogRevision);publishExpressions(document);return document}
            catch{quarantineExpressions();throw error}}
    }
    @discardableResult public func deleteExpression(_ record:ExpressionRecord,catalogRevision:UInt64)throws->ExpressionDocument {
        try withIdleAccess {guard let store=expressionStore else{throw IMKManagementError.unavailable}
            do{let document=try store.delete(record.id,expectedRecordRevision:record.revision,expectedRevision:catalogRevision);publishExpressions(document);return document}
            catch{quarantineExpressions();throw error}}
    }
    @discardableResult public func verifyExpressionSave()throws->ExpressionSaveVerification {
        try withIdleAccess {guard let store=expressionStore else{throw IMKManagementError.unavailable}
            do{let result=try store.verifyLastSave();publishExpressions(result.document);return result}
            catch{quarantineExpressions();throw error}}
    }
    public func close(){
        closed=true
        // Shutdown is not a commit request. No host mutation or implicit save.
        for driver in live{driver.coordinator.interrupt("Input service closed. No automatic replay.")}
        expressionCatalog=nil;for driver in live{driver.invalidateRecallForShutdown()}
        settingsStore?.close();personalStore?.close();expressionStore?.close()
    }
}
#endif
