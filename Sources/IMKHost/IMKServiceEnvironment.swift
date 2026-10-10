#if os(macOS)
import Foundation
import EngineBridge
import SettingsCore

// Startup-only selection. The bundle contains the authored fixture, never the
// unbundled research corpus. No fallback retry initializes librime a second time.
@MainActor public final class IMKServiceEnvironment {
    public let runtime:RimeRuntime,workspace:IMKWorkspace
    public let personal:PersonalLabEnvironment?
    public let makeSession:(LabConfiguration)throws->InputSession
    public init(environment:[String:String]=ProcessInfo.processInfo.environment)throws {
        let factory:(LabConfiguration)throws->InputSession,description:String
        if environment["PAIA_IMK_RESEARCH"]=="1" {
            if environment["PAIA_B2_RESEARCH"]=="1" {
                let selected=try PersonalLabEnvironment(environment:environment);personal=selected;runtime=selected.runtime
                factory={try selected.makeSession(configuration:$0)}
                description="Unbundled verified research schemas. "+selected.status
            } else {
                let selected=try ResearchLabEnvironment(environment:environment);personal=nil;runtime=selected.runtime
                factory={try selected.runtime.makeSession(schema:$0.schema,deferredCommit:$0.deferredCommit,chinesePunctuation:$0.chinesePunctuation)}
                description="Unbundled verified research schemas. Personal terms unavailable without an explicit store."
            }
        } else {
            let selected=try LabEnvironment(environment:environment);personal=nil;runtime=selected.runtime
            factory={configuration in
                guard configuration.spelling == .full,!configuration.traditional,!configuration.chinesePunctuation,!configuration.deferredCommit else{throw IMKManagementError.unavailable}
                return try selected.runtime.makeSession()
            }
            description="Authored tiny fixture only. Full/Simplified and literal mode; double pinyin, Traditional and Chinese punctuation require the separately prepared research lane."
        }
        makeSession=factory
        var settings:SettingsStore?
        if environment["PAIA_B3_SETTINGS"]=="1" {
            guard let path=environment["PAIA_B3_STORE"],!path.isEmpty else{_ = runtime.close();throw SettingsError.unsafePath}
            settings=try? SettingsStore(directory:URL(fileURLWithPath:path,isDirectory:true))
        }
        let personal=personal
        workspace=IMKWorkspace(settingsStore:settings,personalStore:personal?.store,resourceDescription:description,makeSession:factory,disablePersonal:{personal?.disableOverlayUntilRestart()})
    }
    public func close(){workspace.close();_ = runtime.close()}
}
#endif
