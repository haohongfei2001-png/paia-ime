#if os(macOS)
import Foundation
import EngineBridge
import SettingsCore
import ExpressionCore
import ResourceCore

// Startup-only selection. The bundle contains the authored fixture, never the
// unbundled research corpus. No fallback retry initializes librime a second time.
@MainActor public final class IMKServiceEnvironment {
    public let runtime:RimeRuntime,workspace:IMKWorkspace
    public let personal:PersonalLabEnvironment?
    public let publicResources:PublicResourceEnvironment?
    public let makeSession:(LabConfiguration)throws->InputSession
    public init(environment:[String:String]=ProcessInfo.processInfo.environment)throws {
        let factory:(LabConfiguration)throws->InputSession,description:String
        let bundle=Bundle.main.resourceURL,bundledPack=bundle?.appendingPathComponent("DictionaryFixturePack")
        let explicitStore=environment["PAIA_RESOURCE_ROOT"]
        // The service's resource contract is chosen by its application metadata,
        // never by a resource file's current existence. Missing packs fail closed.
        let useBundled=environment["PAIA_FIXTURE_DIR"]==nil && (Bundle.main.bundleIdentifier=="dev.paia.ime.integration" || Bundle.main.object(forInfoDictionaryKey:"PAIAResourceGeneration") != nil)
        if explicitStore != nil || useBundled {
            guard environment["PAIA_IMK_RESEARCH"] != "1",environment["PAIA_B1_RESEARCH"] != "1",environment["PAIA_B2_RESEARCH"] != "1",
                  explicitStore == nil || !explicitStore!.isEmpty,
                  let library=environment["PAIA_RIME_LIBRARY"] ?? bundle?.appendingPathComponent("Engine/librime.1.16.0.dylib").path,
                  let helper=environment["PAIA_RESOURCE_HELPER"] ?? Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent("paia-resources").path,
                  let helperSHA=environment["PAIA_RESOURCE_HELPER_SHA"] ?? Bundle.main.object(forInfoDictionaryKey:"PAIAResourceHelperSHA") as? String else{throw ResourceError.incompatible}
            let generation=Bundle.main.object(forInfoDictionaryKey:"PAIAResourceGeneration") as? String
            let digest=Bundle.main.object(forInfoDictionaryKey:"PAIAResourceManifestSHA") as? String
            let reference=(generation != nil && digest != nil) ? ResourceReference(generation:generation!,manifestSHA:digest!):nil
            let selected=try PublicResourceEnvironment(store:explicitStore.map{URL(fileURLWithPath:$0)},bundle:bundledPack,bundleReference:reference,
                library:URL(fileURLWithPath:library),helper:URL(fileURLWithPath:helper),helperSHA:helperSHA)
            publicResources=selected;personal=nil;runtime=selected.runtime
            factory={configuration in
                guard configuration.spelling == .full,!configuration.traditional,!configuration.chinesePunctuation,!configuration.deferredCommit,!configuration.fuzzyInitials,configuration.fullPinyinCorrection else{throw IMKManagementError.unavailable}
                return try selected.runtime.makeSession()
            }
            description=selected.status
        } else if environment["PAIA_IMK_RESEARCH"]=="1" {
            publicResources=nil
            if environment["PAIA_B2_RESEARCH"]=="1" {
                let selected=try PersonalLabEnvironment(environment:environment);personal=selected;runtime=selected.runtime
                factory={try selected.makeSession(configuration:$0)}
                description="Unbundled verified research schemas. Startup snapshot: "+selected.status
            } else {
                let selected=try ResearchLabEnvironment(environment:environment);personal=nil;runtime=selected.runtime
                factory={try selected.runtime.makeSession(schema:$0.schema,deferredCommit:$0.deferredCommit,chinesePunctuation:$0.chinesePunctuation)}
                description="Unbundled verified research schemas. Personal terms unavailable without an explicit store."
            }
        } else {
            let selected=try LabEnvironment(environment:environment);publicResources=nil;personal=nil;runtime=selected.runtime
            factory={configuration in
                guard configuration.spelling == .full,!configuration.traditional,!configuration.chinesePunctuation,!configuration.deferredCommit,!configuration.fuzzyInitials,configuration.fullPinyinCorrection else{throw IMKManagementError.unavailable}
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
        var expressions:ExpressionStore?
        if let path=environment["PAIA_C_STORE"],!path.isEmpty {expressions=try? ExpressionStore(directory:URL(fileURLWithPath:path,isDirectory:true))}
        let personal=personal
        workspace=IMKWorkspace(settingsStore:settings,personalStore:personal?.store,expressionStore:expressions,resourceDescription:description,makeSession:factory,disablePersonal:{personal?.disableOverlayUntilRestart()})
    }
    public func close(){workspace.close();_ = runtime.close()}
}
#endif
