import Foundation
import LexiconCore

// Explicit B2 launch only. No profile discovery, background import, or per-keystroke store access.
@MainActor public final class PersonalLabEnvironment {
    public let runtime:RimeRuntime,temporaryDirectory:URL,resources:PersonalResources
    public let store:LexiconStore?
    public let authorityUnavailable:Bool
    public private(set) var pendingRestart=false
    public init(environment:[String:String]=ProcessInfo.processInfo.environment)throws {
        func required(_ key:String)throws->String {
            guard let value=environment[key],!value.isEmpty else{throw EngineError.closed};return value
        }
        guard environment["PAIA_B2_RESEARCH"]=="1" else{throw EngineError.closed}
        let storeURL=URL(fileURLWithPath:try required("PAIA_B2_STORE"),isDirectory:true)
        var authority:LexiconStore?,document=LexiconDocument(),unavailable=false
        do {authority=try LexiconStore(directory:storeURL);document=try authority!.snapshot()}
        catch {authority?.close();authority=nil;unavailable=true} // Never revive a stale personal dictionary on corrupt authority.
        store=authority;authorityUnavailable=unavailable
        let temp=FileManager.default.temporaryDirectory.appendingPathComponent("paia-b2-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:temp,withIntermediateDirectories:false);temporaryDirectory=temp
        do {
            resources=try PersonalSchemaBuilder.prepare(baseline:URL(fileURLWithPath:required("PAIA_B1_SHARED")),destination:temp.appendingPathComponent("shared"),document:document,baseRevision:required("PAIA_B1_REVISION"))
            let user=temp.appendingPathComponent("engine-user");try FileManager.default.createDirectory(at:user,withIntermediateDirectories:false)
            runtime=try RimeRuntime(library:required("PAIA_RIME_LIBRARY"),shared:resources.shared.path,isolatedUser:user.path,dictionaryRevision:resources.revision,
                schemas:resources.schemas,g01Library:required("PAIA_G01_LIBRARY"),repairDisabledSchemas:resources.overlaySchemas)
            try PersonalSchemaBuilder.verifyCompiled(resources,userDirectory:user)
        } catch {authority?.close();try? FileManager.default.removeItem(at:temp);throw error}
    }
    public func disableOverlayUntilRestart(){pendingRestart=true}
    public func makeSession(configuration:LabConfiguration)throws->InputSession {
        var schema=configuration.schema
        if pendingRestart && configuration.spelling == .full && !configuration.traditional {schema=PersonalResources.baselineSchema(punctuation:configuration.chinesePunctuation)}
        return try runtime.makeSession(schema:schema,deferredCommit:configuration.deferredCommit,chinesePunctuation:configuration.chinesePunctuation)
    }
    public var status:String {
        if authorityUnavailable{return "Personal authority unavailable. Public baseline only; no older personal data restored."}
        if pendingRestart{return "Saved changes. Personal overlay disabled until next launch; baseline input remains available."}
        return "Personal entries active only in Full/Simplified. Other modes use the baseline; personal-overlay repair is unsupported."
    }
}
