import Foundation
public struct LabEnvironment {
    public let runtime: RimeRuntime, temporaryDirectory: URL
    public init(environment: [String:String] = ProcessInfo.processInfo.environment) throws {
        let bundled=Bundle.main.resourceURL
        guard let library=environment["PAIA_RIME_LIBRARY"] ?? bundled?.appendingPathComponent("Engine/librime.1.16.0.dylib").path,
              let fixture=environment["PAIA_FIXTURE_DIR"] ?? bundled?.appendingPathComponent("Dictionaries/A1Fixture").path,
              let revision=environment["PAIA_DICTIONARY_REVISION"] ?? Bundle.main.object(forInfoDictionaryKey:"PAIADictionaryRevision") as? String,
              !revision.isEmpty else {
            throw NSError(domain:"PAIA.A1",code:1,userInfo:[NSLocalizedDescriptionKey:"Set PAIA_RIME_LIBRARY, PAIA_FIXTURE_DIR and PAIA_DICTIONARY_REVISION to verified A1 inputs."])
        }
        let tmp=FileManager.default.temporaryDirectory.appendingPathComponent("paia-a1-"+UUID().uuidString,isDirectory:true)
        try FileManager.default.createDirectory(at:tmp,withIntermediateDirectories:false)
        temporaryDirectory=tmp
        do { runtime=try RimeRuntime(library:library,shared:fixture,isolatedUser:tmp.path,dictionaryRevision:revision) }
        catch { try? FileManager.default.removeItem(at:tmp); throw error }
    }
}
