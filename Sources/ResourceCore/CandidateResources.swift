import Foundation

// Version 2 is a separate closed authored-candidate contract. It does not
// reinterpret the existing two-schema public ResourceManifest/store format.
public enum CandidateContract {
    public static let profile="authored-candidate-v1"
    public static let provenance="46 repository-authored integration rows; pinned GPL-3.0-only Rime Ice spelling derivatives and Apache-2.0 OpenCC conversion maps. No research corpus or ordinary input history. Not a qualified production language model."
    public static let opencc=["s2t.json","stcharacters.txt","stphrases.txt"]
    public static var schemas:[String] {
        var result=[String]()
        for kind in ["full","flypy","natural"] {for traditional in [false,true] {for punctuation in [false,true] {for fuzzy in [false,true] {for correction in (kind=="full" ? [true,false]:[true]) {
            result.append("paia_candidate_"+kind+(traditional ? "_traditional":"")+(punctuation ? "_punct":"_ascii")+(fuzzy ? "_fuzzy":"")+(!correction ? "_strict":""))
        }}}}}
        return result.sorted()
    }
    public static var prisms:[String] {
        ["full","full_strict","full_fuzzy","full_fuzzy_strict","flypy","flypy_fuzzy","natural","natural_fuzzy"].map{"paia_candidate_"+$0}.sorted()
    }
    public static var templates:[String] {(["default.yaml","paia_a1.schema.yaml","paia_a1.dict.yaml","paia_candidate.dict.yaml"]+schemas.map{$0+".schema.yaml"}).sorted()}
    public static var sourcePaths:[String] {(templates.map{"templates/"+$0}+opencc.map{"opencc/"+$0}).sorted()}
    public static var publicArtifacts:[String] {
        (["default.yaml","build/paia_a1.schema.yaml","build/paia_a1.table.bin","build/paia_a1.reverse.bin","build/paia_a1.prism.bin","build/paia_candidate.table.bin","build/paia_candidate.reverse.bin"]+schemas.map{"build/"+$0+".schema.yaml"}+prisms.map{"build/"+$0+".prism.bin"}+opencc.map{"opencc/"+$0}).sorted()
    }
    public static var baselineSchemas:[String] {
        schemas.filter{$0.hasPrefix("paia_candidate_full_") && !$0.contains("_traditional_")}.map{$0.replacingOccurrences(of:"paia_candidate_full_",with:"paia_candidate_baseline_full_")}.sorted()
    }
}

public struct CandidatePersonalBinding:Codable,Equatable {
    public let base:ResourceReference,authoritySHA:String,revision:UInt64,tiers:[String],builder:String
    public init(base:ResourceReference,authoritySHA:String,revision:UInt64,tiers:[String])throws {
        self.base=base;self.authoritySHA=authoritySHA;self.revision=revision;self.tiers=tiers;builder="candidate-personal-1";try validate()
    }
    public func validate()throws {
        try base.validate()
        guard ResourceContract.hash(authoritySHA),revision<UInt64.max,tiers==tiers.sorted(),Set(tiers).count==tiers.count,
              !tiers.isEmpty,Set(tiers).isSubset(of:["pin","terms"]),builder=="candidate-personal-1" else{throw ResourceError.format}
    }
    public var extraArtifacts:[String] {
        let suffix=String(authoritySHA.prefix(32))
        return (CandidateContract.baselineSchemas.map{"build/"+$0+".schema.yaml"}+tiers.flatMap{tier in
            ["build/paia_b2_\(tier)_\(suffix).table.bin","build/paia_b2_\(tier)_\(suffix).reverse.bin","build/paia_b2_\(tier)_full_\(suffix).prism.bin","build/paia_b2_build_\(tier)_\(suffix).schema.yaml"]
        }).sorted()
    }
}

public struct CandidateManifest:Codable,Equatable {
    public let format:Int,profile:String,generation:String,engineSHA:String,headerSHA:String,dictionaryRevision:String,provenance:String
    public let schemas:[String],inputs:[ResourceFile],artifacts:[ResourceFile],personal:CandidatePersonalBinding?
    public init(generation:String,inputs:[String:Data],artifacts:[String:Data],personal:CandidatePersonalBinding?=nil)throws {
        format=2;profile=CandidateContract.profile;self.generation=generation;engineSHA=ResourceContract.engineSHA;headerSHA=ResourceContract.headerSHA
        provenance=CandidateContract.provenance;schemas=CandidateContract.schemas;self.personal=personal
        self.inputs=inputs.map{ResourceFile(path:$0.key,data:$0.value)}.sorted{$0.path<$1.path}
        self.artifacts=artifacts.map{ResourceFile(path:$0.key,data:$0.value)}.sorted{$0.path<$1.path}
        dictionaryRevision=try Self.revision(inputs:self.inputs,personal:personal);try validate()
    }
    private static func revision(inputs:[ResourceFile],personal:CandidatePersonalBinding?)throws->String {
        var bytes=try ResourceContract.encode(inputs)
        if let personal=personal{bytes.append(Data([10]));bytes.append(try ResourceContract.encode(personal))}
        return ResourceContract.digest(bytes)
    }
    public var requiredArtifacts:[String] {(CandidateContract.publicArtifacts+(personal?.extraArtifacts ?? [])).sorted()}
    public func validate()throws {
        guard format==2,profile==CandidateContract.profile,ResourceContract.generation(generation),engineSHA==ResourceContract.engineSHA,
              headerSHA==ResourceContract.headerSHA,provenance==CandidateContract.provenance,schemas==CandidateContract.schemas,
              inputs.map(\.path)==CandidateContract.sourcePaths,artifacts.map(\.path)==requiredArtifacts,
              dictionaryRevision == (try Self.revision(inputs:inputs,personal:personal)) else{throw ResourceError.incompatible}
        try personal?.validate()
        var total=0
        for item in inputs+artifacts {
            guard item.bytes>0,item.bytes<=ResourceContract.maximumFile,ResourceContract.hash(item.sha256) else{throw ResourceError.limit}
            total+=item.bytes;guard total<=ResourceContract.maximumPack else{throw ResourceError.limit}
        }
        for name in CandidateContract.opencc {
            guard inputs.first(where:{$0.path=="opencc/"+name})==artifacts.first(where:{$0.path=="opencc/"+name}) else{throw ResourceError.integrity}
        }
        guard let original=inputs.first(where:{$0.path=="templates/default.yaml"}),let deployed=artifacts.first(where:{$0.path=="default.yaml"}),
              original.bytes==deployed.bytes,original.sha256==deployed.sha256 else{throw ResourceError.integrity}
    }
    public var reference:ResourceReference {get throws {ResourceReference(generation:generation,manifestSHA:ResourceContract.digest(try ResourceContract.encode(self)))}}
}

public struct VerifiedCandidatePack {
    public let manifest:CandidateManifest,manifestBytes:Data,files:[String:Data]
    public var reference:ResourceReference {ResourceReference(generation:manifest.generation,manifestSHA:ResourceContract.digest(manifestBytes))}
    public init(directory:ResourceDirectory,expected:ResourceReference,personal:CandidatePersonalBinding?=nil)throws {
        try expected.validate()
        let bytes=try directory.read("manifest.json",maximum:ResourceContract.maximumJSON)
        guard ResourceContract.digest(bytes)==expected.manifestSHA else{throw ResourceError.integrity}
        let value=try ResourceContract.decode(CandidateManifest.self,bytes);try value.validate()
        guard value.generation==expected.generation,value.personal==personal,
              try directory.names()==["build","default.yaml","manifest.json","opencc","templates"] else{throw ResourceError.integrity}
        let items=value.inputs+value.artifacts,paths=Set(items.map(\.path))
        for folder in ["build","opencc","templates"] {
            let prefix=folder+"/"
            guard try directory.child(folder).names()==paths.filter({$0.hasPrefix(prefix)}).map({String($0.dropFirst(prefix.count))}).sorted() else{throw ResourceError.integrity}
        }
        var copied=[String:Data]()
        for item in items {
            let data=try Self.read(item.path,from:directory)
            guard ResourceFile(path:item.path,data:data)==item else{throw ResourceError.integrity};copied[item.path]=data
        }
        guard try directory.read("manifest.json",maximum:ResourceContract.maximumJSON)==bytes else{throw ResourceError.stale}
        manifest=value;manifestBytes=bytes;files=copied
    }
    public static func read(_ path:String,from directory:ResourceDirectory)throws->Data {
        let parts=path.split(separator:"/",omittingEmptySubsequences:false)
        if parts.count==1,path=="default.yaml"{return try directory.read(path)}
        guard parts.count==2,["build","opencc","templates"].contains(String(parts[0])) else{throw ResourceError.unsafePath}
        return try directory.child(String(parts[0])).read(String(parts[1]))
    }
    public static func write(manifest:CandidateManifest,files:[String:Data],to directory:ResourceDirectory)throws {
        try manifest.validate();let items=manifest.inputs+manifest.artifacts
        guard Set(files.keys)==Set(items.map(\.path)) else{throw ResourceError.integrity}
        for item in items {guard let data=files[item.path],ResourceFile(path:item.path,data:data)==item else{throw ResourceError.integrity}}
        var children=[String:ResourceDirectory]()
        for name in ["build","opencc","templates"]{children[name]=try directory.createDirectory(name)}
        for path in files.keys.sorted() {
            let parts=path.split(separator:"/")
            if parts.count==1{try directory.writeExclusive(path,files[path]!)}
            else{try children[String(parts[0])]!.writeExclusive(String(parts[1]),files[path]!)}
        }
        for child in children.values{try child.sync()}
        try directory.writeExclusive("manifest.json",ResourceContract.encode(manifest));try directory.sync()
    }
    public func writeSources(to directory:ResourceDirectory)throws {
        let opencc=try directory.createDirectory("opencc")
        for name in CandidateContract.templates{try directory.writeExclusive(name,files["templates/"+name]!)}
        for name in CandidateContract.opencc{try opencc.writeExclusive(name,files["opencc/"+name]!)}
        try opencc.sync();try directory.sync()
    }
    public func validateDerived(from base:VerifiedCandidatePack,binding:CandidatePersonalBinding)throws {
        guard base.manifest.personal==nil,manifest.personal==binding,binding.base==base.reference,manifest.inputs==base.manifest.inputs else{throw ResourceError.integrity}
        let replaced=Set(CandidateContract.schemas.filter{$0.hasPrefix("paia_candidate_full_") && !$0.contains("_traditional_")}.map{"build/"+$0+".schema.yaml"})
        for item in base.manifest.inputs+base.manifest.artifacts where !replaced.contains(item.path) {
            guard files[item.path]==base.files[item.path] else{throw ResourceError.integrity}
        }
    }
}

public final class CandidateResourceSnapshot {
    public let root:URL,directory:URL,userDirectory:URL,pack:VerifiedCandidatePack
    private let owner:ResourceDirectory
    private var closed=false
    public init(_ pack:VerifiedCandidatePack)throws {
        self.pack=pack
        root=FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("paia-candidate-"+UUID().uuidString.lowercased(),isDirectory:true)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
        owner=try ResourceDirectory(root)
        directory=root.appendingPathComponent("pack");userDirectory=root.appendingPathComponent("user")
        do {
            _=try owner.createDirectory("user");let destination=try owner.createDirectory("pack")
            try VerifiedCandidatePack.write(manifest:pack.manifest,files:pack.files,to:destination);try verify()
        } catch {close();throw error}
    }
    public func verify()throws {
        guard !closed else{throw ResourceError.stale};try owner.check()
        _=try VerifiedCandidatePack(directory:ResourceDirectory(directory),expected:pack.reference,personal:pack.manifest.personal)
    }
    public func close(){guard !closed else{return};closed=true;if (try? owner.check()) != nil{try? FileManager.default.removeItem(at:root)}}
    deinit{close()}
}
