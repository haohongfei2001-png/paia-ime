#if os(macOS)
import AppKit
import EngineBridge
import NativeHost
import SettingsCore
import LexiconCore
import SessionCore

public enum IMKManagementError:Error {case busy,unavailable,interrupted}

// One process-wide configuration and mutation owner, shared by all IMK controllers.
// Store IO occurs only in explicit management actions, never in makeSession/key paths.
@MainActor public final class IMKWorkspace {
    public private(set) var configuration=LabConfiguration()
    public let settingsStore:SettingsStore?,personalStore:LexiconStore?
    public let resourceDescription:String
    private let factory:(LabConfiguration)throws->InputSession
    private let disablePersonal:()->Void
    private final class WeakDriver {weak var value:IMKControllerDriver?;init(_ value:IMKControllerDriver){self.value=value}}
    private var drivers=[WeakDriver](),managing=false,interrupted=false,closed=false
    public private(set) var configurationRevision:UInt64=0
    public init(settingsStore:SettingsStore?=nil,personalStore:LexiconStore?=nil,resourceDescription:String,
                makeSession:@escaping(LabConfiguration)throws->InputSession,disablePersonal:@escaping()->Void={}) {
        self.settingsStore=settingsStore;self.personalStore=personalStore;self.resourceDescription=resourceDescription
        factory=makeSession;self.disablePersonal=disablePersonal
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
    public func makeDriver(hide:@escaping()->Void,present:@escaping(CandidateSnapshot?,NSRect,String?)->Void)->IMKControllerDriver {
        let driver=IMKControllerDriver(makeSession:{[weak self] in
            guard let self=self,!self.closed,!self.managing else{return nil};return try? self.factory(self.configuration)
        },literal:{[weak self] in self?.configuration.literal==true},permitOperation:{[weak self] in self?.permitInput()==true},hide:hide,present:present)
        drivers.removeAll{$0.value==nil};drivers.append(WeakDriver(driver))
        if managing{interrupted=true}
        return driver
    }
    public func applyConfiguration(_ next:LabConfiguration)throws {
        try withIdleAccess {
            guard !next.deferredCommit else{throw IMKManagementError.unavailable}
            let prepared=try factory(next);defer{prepared.end()}
            let initial=try prepared.refresh()
            guard !interrupted,live.allSatisfy({$0.isIdleForManagement}),initial.commit==nil,
                  initial.snapshot?.rawASCII.isEmpty==true,initial.snapshot?.preedit.isEmpty==true else{throw IMKManagementError.interrupted}
            // No callbacks between global publication and all-owner retirement.
            configuration=next;configurationRevision &+= 1
            let owners=live;for driver in owners{driver.retireIdleForManagement()}
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
    public func close(){
        closed=true
        // Shutdown is not a commit request. No host mutation or implicit save.
        for driver in live{driver.coordinator.interrupt("Input service closed. No automatic replay.")}
        settingsStore?.close();personalStore?.close()
    }
}
#endif
