import Foundation

// A finite application-owned update, not a caller-supplied dictionary importer.
// The anchor must come from the app's declared, verified bundled reference
// before any catalog is opened. Catalog/pack metadata cannot supply this policy.
public enum CandidatePublicPreset:String,Codable,CaseIterable {case baseline,updated}
public struct CandidateSourcePolicy {
    public let bundleReference:ResourceReference,contractSHA:String
    private let baseline:[String:Data],updated:[String:Data]
    private let baselineIdentity:[ResourceFile],updatedIdentity:[ResourceFile]
    public static let updateRaw="lixiangengxin",updateSurface="离线更新🧭"
    public init(bundle:VerifiedCandidatePack,expectedBundle:ResourceReference)throws {
        guard bundle.reference==expectedBundle,bundle.manifest.personal==nil else{throw ResourceError.incompatible}
        try bundle.manifest.validate();bundleReference=expectedBundle;contractSHA=bundle.manifest.dictionaryRevision
        baseline=Dictionary(uniqueKeysWithValues:bundle.manifest.inputs.map{($0.path,bundle.files[$0.path]!)})
        var next=baseline
        let path="templates/paia_candidate.dict.yaml"
        guard let data=baseline[path],let text=String(data:data,encoding:.utf8) else{throw ResourceError.integrity}
        let old="呢\tni\t900\n",new=Self.updateSurface+"\tli xian geng xin\t900\n"
        guard text.components(separatedBy:old).count==2,!text.contains(Self.updateSurface),
              text.components(separatedBy:"...\n").count==2,let body=text.components(separatedBy:"...\n").last,
              body.split(separator:"\n").filter({!$0.hasPrefix("#")}).count==46 else{throw ResourceError.incompatible}
        // Only this authored row differs. All recipes, maps, A1 extension proof
        // inputs and the closed 32-schema inventory remain byte-identical.
        next[path]=Data(text.replacingOccurrences(of:old,with:new).utf8)
        updated=next
        baselineIdentity=Self.identity(baseline);updatedIdentity=Self.identity(next)
    }
    private static func identity(_ files:[String:Data])->[ResourceFile] {
        files.map{ResourceFile(path:$0.key,data:$0.value)}.sorted{$0.path<$1.path}
    }
    public func sources(_ preset:CandidatePublicPreset)->[String:Data] {preset == .baseline ? baseline:updated}
    public func inputsSHA(_ preset:CandidatePublicPreset)throws->String {
        // CandidateCompiler's source digest uses paths relative to its source
        // directory, not the manifest's templates/ storage namespace.
        let values=sources(preset).map{ResourceFile(path:$0.key.hasPrefix("templates/") ? String($0.key.dropFirst(10)):$0.key,data:$0.value)}.sorted{$0.path<$1.path}
        return ResourceContract.digest(try ResourceContract.encode(values))
    }
    // This admits source identity only. It does not authenticate opaque compiled
    // artifacts or defend a same-user attacker coherently rewriting a catalog.
    public func admitSourceIdentity(_ pack:VerifiedCandidatePack)throws->CandidatePublicPreset {
        guard pack.manifest.personal==nil else{throw ResourceError.incompatible}
        try pack.manifest.validate()
        if pack.manifest.inputs==baselineIdentity{return .baseline}
        if pack.manifest.inputs==updatedIdentity{return .updated}
        throw ResourceError.incompatible
    }
    public func writeSources(_ preset:CandidatePublicPreset,to directory:ResourceDirectory)throws {
        guard try directory.names().isEmpty else{throw ResourceError.unsafePath}
        let selected=sources(preset),maps=try directory.createDirectory("opencc")
        for name in CandidateContract.templates{try directory.writeExclusive(name,selected["templates/"+name]!)}
        for name in CandidateContract.opencc{try maps.writeExclusive(name,selected["opencc/"+name]!)}
        try maps.sync();try directory.sync()
    }
}
