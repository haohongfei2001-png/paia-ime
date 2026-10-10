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
    public let candidate:CandidateEnvironment?
    public let productStores:ProductStores?
    public let makeSession:(LabConfiguration)throws->InputSession
    public init(environment:[String:String]=ProcessInfo.processInfo.environment,preflight:Bool=false,isolatedDataParent:URL?=nil,applicationBundle:Bundle = .main)throws {
        let factory:(LabConfiguration)throws->InputSession,description:String,supportsPolicies:Bool
        let bundle=applicationBundle.resourceURL,bundledPack=bundle?.appendingPathComponent("DictionaryFixturePack")
        let explicitStore=environment["PAIA_RESOURCE_ROOT"]
        // The service's resource contract is chosen by its application metadata,
        // never by a resource file's current existence. Missing packs fail closed.
        let useBundled=environment["PAIA_FIXTURE_DIR"]==nil && (applicationBundle.bundleIdentifier=="dev.paia.ime.integration" || applicationBundle.object(forInfoDictionaryKey:"PAIAResourceGeneration") != nil)
        let candidateMarkers=["PAIACandidateProfile","PAIACandidateGeneration","PAIACandidateManifestSHA","PAIACandidateExtensionSHA","PAIACandidateResourceCatalog"]
        if applicationBundle.bundleIdentifier=="dev.paia.ime.candidate" || candidateMarkers.contains(where:{applicationBundle.object(forInfoDictionaryKey:$0) != nil}) {
            guard applicationBundle.object(forInfoDictionaryKey:"PAIACandidateProfile") as? String==CandidateContract.profile,
                  applicationBundle.object(forInfoDictionaryKey:"PAIACandidateResourceCatalog") as? String==CandidateUpdate.catalogContract,
                  !environment.keys.contains(where:{$0.hasPrefix("PAIA_") && $0 != "PAIA_SOURCE_SHA"}),
                  let resources=bundle,let executable=applicationBundle.executableURL,
                  let generation=applicationBundle.object(forInfoDictionaryKey:"PAIACandidateGeneration") as? String,
                  let digest=applicationBundle.object(forInfoDictionaryKey:"PAIACandidateManifestSHA") as? String,
                  let bridgeSHA=applicationBundle.object(forInfoDictionaryKey:"PAIACandidateExtensionSHA") as? String,
                  let helperSHA=applicationBundle.object(forInfoDictionaryKey:"PAIAResourceHelperSHA") as? String else{throw ResourceError.incompatible}
            let dataParent=preflight ? isolatedDataParent:FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask).first
            let catalog=try CandidateUpdate.selectedCatalog(parent:dataParent)
            let stores:ProductStores
            if preflight {stores=try ProductStores.preflight(parent:isolatedDataParent)}
            else {
                guard isolatedDataParent==nil else{throw ResourceError.incompatible}
                stores=ProductStores(parent:dataParent)
            }
            do {
                let components=try CandidateComponents(library:resources.appendingPathComponent("Engine/librime.1.dylib"),extensionLibrary:resources.appendingPathComponent("Engine/paia-g01.dylib"),helper:executable.deletingLastPathComponent().appendingPathComponent("paia-resources"),extensionSHA:bridgeSHA,helperSHA:helperSHA)
                let selected=try CandidateEnvironment(pack:resources.appendingPathComponent("CandidatePack"),reference:ResourceReference(generation:generation,manifestSHA:digest),components:components,personalStore:stores.personal,catalog:catalog)
                candidate=selected;productStores=stores;personal=nil;publicResources=nil;runtime=selected.runtime
                factory={try selected.makeSession(configuration:$0)};makeSession=factory
                workspace=IMKWorkspace(settingsStore:stores.settings,personalStore:stores.personal,expressionStore:stores.expressions,resourceDescription:selected.status+" "+stores.status,supportsSpellingPolicies:true,makeSession:factory,disablePersonal:{selected.disableOverlayUntilRestart()})
                return
            } catch {stores.close();throw error}
        }
        candidate=nil;productStores=nil
        if explicitStore != nil || useBundled {
            supportsPolicies=false
            guard environment["PAIA_IMK_RESEARCH"] != "1",environment["PAIA_B1_RESEARCH"] != "1",environment["PAIA_B2_RESEARCH"] != "1",
                  explicitStore == nil || !explicitStore!.isEmpty,
                  let library=environment["PAIA_RIME_LIBRARY"] ?? bundle?.appendingPathComponent("Engine/librime.1.16.0.dylib").path,
                  let helper=environment["PAIA_RESOURCE_HELPER"] ?? applicationBundle.executableURL?.deletingLastPathComponent().appendingPathComponent("paia-resources").path,
                  let helperSHA=environment["PAIA_RESOURCE_HELPER_SHA"] ?? applicationBundle.object(forInfoDictionaryKey:"PAIAResourceHelperSHA") as? String else{throw ResourceError.incompatible}
            let generation=applicationBundle.object(forInfoDictionaryKey:"PAIAResourceGeneration") as? String
            let digest=applicationBundle.object(forInfoDictionaryKey:"PAIAResourceManifestSHA") as? String
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
            supportsPolicies=true;publicResources=nil
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
            supportsPolicies=false
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
        workspace=IMKWorkspace(settingsStore:settings,personalStore:personal?.store,expressionStore:expressions,resourceDescription:description,supportsSpellingPolicies:supportsPolicies,makeSession:factory,disablePersonal:{personal?.disableOverlayUntilRestart()})
    }
    public func close(){workspace.close();_ = runtime.close();productStores?.close()}
}
#endif
