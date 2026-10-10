import Foundation
import SettingsCore
public enum LabSpelling:String,CaseIterable {case full,flypy,natural}
public struct LabConfiguration:Equatable {
    public var spelling:LabSpelling = .full
    public var traditional=false, literal=false, chinesePunctuation=false, deferredCommit=false
    public var fuzzyInitials=false,fullPinyinCorrection=true
    public var initialModes:[String:InitialInputMode]=[:]
    public init(){}
    public var preferences:SettingsValues {
        var value=SettingsValues();value.spelling=SettingsSpelling(rawValue:spelling.rawValue)!;value.traditional=traditional;value.literal=literal;value.chinesePunctuation=chinesePunctuation;value.fuzzyInitials=fuzzyInitials;value.fullPinyinCorrection=fullPinyinCorrection;value.initialModes=initialModes;return value
    }
    public init(preferences:SettingsValues){spelling=LabSpelling(rawValue:preferences.spelling.rawValue)!;traditional=preferences.traditional;literal=preferences.literal;chinesePunctuation=preferences.chinesePunctuation;fuzzyInitials=preferences.fuzzyInitials;fullPinyinCorrection=preferences.fullPinyinCorrection;initialModes=preferences.initialModes}
    public var spellingPolicySuffix:String {(fuzzyInitials ? "_fuzzy":"")+(spelling == .full && !fullPinyinCorrection ? "_strict":"")}
    public var schema:String {"paia_b1_"+spelling.rawValue+(traditional ? "_traditional" : "")+(chinesePunctuation ? "_punct" : "_ascii")+spellingPolicySuffix}
    public static var researchSchemas:[String] {
        var result=Set<String>()
        for spelling in LabSpelling.allCases {for traditional in [false,true] {for punctuation in [false,true] {for fuzzy in [false,true] {for correction in [false,true] {
            var c=LabConfiguration();c.spelling=spelling;c.traditional=traditional;c.chinesePunctuation=punctuation;c.fuzzyInitials=fuzzy;c.fullPinyinCorrection=correction;result.insert(c.schema)
        }}}}}
        return result.sorted()
    }
}
public struct ResearchLabEnvironment {
    public let runtime:RimeRuntime,temporaryDirectory:URL
    public init(environment:[String:String]=ProcessInfo.processInfo.environment)throws {
        func required(_ key:String)throws->String {
            guard let value=environment[key],!value.isEmpty else{throw NSError(domain:"PAIA.B1",code:1,userInfo:[NSLocalizedDescriptionKey:"Missing verified research configuration: "+key])};return value
        }
        guard environment["PAIA_B1_RESEARCH"]=="1" else{throw EngineError.closed}
        let schemas=LabConfiguration.researchSchemas
        let temp=FileManager.default.temporaryDirectory.appendingPathComponent("paia-b1-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:temp,withIntermediateDirectories:false);temporaryDirectory=temp
        do {runtime=try RimeRuntime(library:required("PAIA_RIME_LIBRARY"),shared:required("PAIA_B1_SHARED"),isolatedUser:temp.path,
             dictionaryRevision:required("PAIA_B1_REVISION"),schemas:schemas,g01Library:required("PAIA_G01_LIBRARY"))}
        catch{try? FileManager.default.removeItem(at:temp);throw error}
    }
}
