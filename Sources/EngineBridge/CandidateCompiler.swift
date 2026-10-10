import Foundation
import ResourceCore
import LexiconCore

// Offline helper-process operations. No store is opened here: personal input is
// one bounded validated frozen document, never a writer/profile discovery path.
public enum CandidateCompiler {
    public static func scratch()throws->URL {
        let path=FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("paia-candidate-build-"+UUID().uuidString.lowercased())
        try FileManager.default.createDirectory(at:path,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700]);return path
    }
    public static func binding(base:VerifiedCandidatePack,document:LexiconDocument)throws->CandidatePersonalBinding {
        guard base.manifest.personal==nil else{throw ResourceError.incompatible}
        let bytes=try LexiconCodec.encode(document)
        let tiers=[("pin",true),("terms",false)].filter{tier in document.activeTerms.contains{$0.explicitPin==tier.1}}.map{$0.0}
        return try CandidatePersonalBinding(base:base.reference,authoritySHA:LexiconCodec.digest(bytes),revision:document.revision,tiers:tiers)
    }
    public static func sources(_ directory:ResourceDirectory,expectedSHA:String)throws->[String:Data] {
        guard ResourceContract.hash(expectedSHA),try directory.names()==(CandidateContract.templates+["opencc"]).sorted(),
              try directory.child("opencc").names()==CandidateContract.opencc else{throw ResourceError.integrity}
        var files=[String:Data](),raw=[ResourceFile]()
        for name in CandidateContract.templates {
            let data=try directory.read(name);files["templates/"+name]=data;raw.append(ResourceFile(path:name,data:data))
        }
        for name in CandidateContract.opencc {
            let data=try directory.child("opencc").read(name);files["opencc/"+name]=data;raw.append(ResourceFile(path:"opencc/"+name,data:data))
        }
        guard ResourceContract.digest(try ResourceContract.encode(raw.sorted{$0.path<$1.path}))==expectedSHA else{throw ResourceError.integrity}
        return files
    }
    private static func publish(output:URL,inputs:[String:Data],build:ResourceDirectory,personal:CandidatePersonalBinding?,base:VerifiedCandidatePack?=nil)throws->ResourceReference {
        var artifacts=[String:Data]()
        for path in (CandidateContract.publicArtifacts+(personal?.extraArtifacts ?? [])).sorted() {
            if path=="default.yaml"{artifacts[path]=inputs["templates/default.yaml"]!}
            else if path.hasPrefix("opencc/"){artifacts[path]=inputs[path]!}
            else{artifacts[path]=try build.read(String(path.dropFirst(6)))}
        }
        if let base=base {
            let replaced=Set(CandidateContract.schemas.filter{$0.hasPrefix("paia_candidate_full_") && !$0.contains("_traditional_")}.map{"build/"+$0+".schema.yaml"})
            for item in base.manifest.artifacts where !replaced.contains(item.path){artifacts[item.path]=base.files[item.path]!}
        }
        let manifest=try CandidateManifest(generation:UUID().uuidString.lowercased(),inputs:inputs,artifacts:artifacts,personal:personal)
        try FileManager.default.createDirectory(at:output,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
        let directory=try ResourceDirectory(output),files=inputs.merging(artifacts){a,b in b}
        try VerifiedCandidatePack.write(manifest:manifest,files:files,to:directory)
        _=try VerifiedCandidatePack(directory:directory,expected:manifest.reference,personal:personal)
        return try manifest.reference
    }
    public static func compile(sources directory:URL,inputsSHA:String,output:URL,library:URL)throws->ResourceReference {
        try ResourceHelper.checkLibrary(library)
        let inputs=try sources(ResourceDirectory(directory),expectedSHA:inputsSHA)
        let root=try scratch();defer{try? FileManager.default.removeItem(at:root)}
        let owner=try ResourceDirectory(root),shared=try owner.createDirectory("shared"),user=try owner.createDirectory("user")
        let maps=try shared.createDirectory("opencc")
        for name in CandidateContract.templates{try shared.writeExclusive(name,inputs["templates/"+name]!)}
        for name in CandidateContract.opencc{try maps.writeExclusive(name,inputs["opencc/"+name]!)}
        let runtime=try RimeRuntime(library:library.path,shared:shared.url.path,isolatedUser:user.url.path,dictionaryRevision:"candidate-build",schemas:CandidateContract.schemas)
        guard runtime.close() else{throw ResourceError.io}
        return try publish(output:output,inputs:inputs,build:user.child("build"),personal:nil)
    }
    public static func compilePersonal(base:VerifiedCandidatePack,document:LexiconDocument,output:URL,library:URL)throws->ResourceReference {
        try ResourceHelper.checkLibrary(library);let personal=try binding(base:base,document:document)
        let root=try scratch();defer{try? FileManager.default.removeItem(at:root)}
        let owner=try ResourceDirectory(root),source=try owner.createDirectory("source"),user=try owner.createDirectory("user")
        // Only already verified closed source bytes are copied to this new,
        // private baseline before the legacy fixed-template builder sees them.
        try base.writeSources(to:source)
        let resources=try PersonalSchemaBuilder.prepare(baseline:source.url,destination:root.appendingPathComponent("shared"),document:document,baseRevision:base.manifest.dictionaryRevision,profile:.candidate)
        let runtime=try RimeRuntime(library:library.path,shared:resources.shared.path,isolatedUser:user.url.path,dictionaryRevision:resources.revision,schemas:resources.schemas)
        guard runtime.close() else{throw ResourceError.io}
        let inputs=Dictionary(uniqueKeysWithValues:base.manifest.inputs.map{($0.path,base.files[$0.path]!)})
        return try publish(output:output,inputs:inputs,build:user.child("build"),personal:personal,base:base)
    }
}
