import Foundation
import Darwin
import ResourceCore

// Bundle metadata anchors this finite offline update. This API never accepts a
// caller's pack, YAML, source digest, executable path, or allowlist as authority.
public enum CandidateUpdate {
    public static let catalogLeaf="paia-ime-public-resources",catalogContract="paia-public-candidate-v2"
    // Presence selects the catalog, including malformed/special-file roots. An
    // existing but unusable catalog never silently falls through to the bundle.
    // Erasing the entire public root is indistinguishable from never opting in;
    // this is not same-user deletion/rollback authentication.
    public static func selectedCatalog(parent:URL?)throws->URL? {
        guard let parent=parent else{return nil}
        let selected=parent.appendingPathComponent(catalogLeaf);var info=stat()
        if lstat(selected.path,&info)==0{return selected}
        guard errno==ENOENT else{throw ResourceError.unsafePath};return nil
    }
    public static func bundleInputs(_ bundle:Bundle)throws->(URL,ResourceReference,CandidateComponents) {
        guard bundle.bundleIdentifier=="dev.paia.ime.candidate",
              bundle.object(forInfoDictionaryKey:"PAIACandidateProfile") as? String==CandidateContract.profile,
              bundle.object(forInfoDictionaryKey:"PAIACandidateResourceCatalog") as? String==catalogContract,
              let resources=bundle.resourceURL,let executable=bundle.executableURL,
              let generation=bundle.object(forInfoDictionaryKey:"PAIACandidateGeneration") as? String,
              let digest=bundle.object(forInfoDictionaryKey:"PAIACandidateManifestSHA") as? String,
              let bridgeSHA=bundle.object(forInfoDictionaryKey:"PAIACandidateExtensionSHA") as? String,
              let helperSHA=bundle.object(forInfoDictionaryKey:"PAIAResourceHelperSHA") as? String else{throw ResourceError.incompatible}
        let components=try CandidateComponents(library:resources.appendingPathComponent("Engine/librime.1.dylib"),extensionLibrary:resources.appendingPathComponent("Engine/paia-g01.dylib"),helper:executable.deletingLastPathComponent().appendingPathComponent("paia-resources"),extensionSHA:bridgeSHA,helperSHA:helperSHA)
        return (resources.appendingPathComponent("CandidatePack"),ResourceReference(generation:generation,manifestSHA:digest),components)
    }
    // Shared startup/explicit compatibility selector. Only helpers enter native
    // code here; no personal store is opened and no main engine is initialized.
    public static func selectPublic(pack:URL,reference:ResourceReference,components:CandidateComponents,catalog:URL?,
                                    probeOverride:((CandidateResourceSnapshot,CandidatePublicPreset)throws->Void)?=nil)throws->CandidateResourceSelection {
        try components.verify()
        let bundled=try VerifiedCandidatePack(directory:ResourceDirectory(pack),expected:reference)
        let policy=try CandidateSourcePolicy(bundle:bundled,expectedBundle:reference)
        let probe=probeOverride ?? {snapshot,preset in
            try CandidateHelper.probe(snapshot,components:components,timeout:120)
            try CandidateHelper.probeUpdate(snapshot,preset:preset,components:components)
        }
        if let catalog=catalog{return try CandidateResourceCatalog(directory:catalog,policy:policy).select(probe:probe)}
        let copy=try CandidateResourceSnapshot(bundled)
        do {try probe(copy,.baseline);try copy.verify()}catch{copy.close();throw error}
        return CandidateResourceSelection(snapshot:copy,reason:.bundled,preset:.baseline)
    }
    public static func publish(bundle:Bundle,preset:CandidatePublicPreset,parent:URL,expectedRevision:UInt64,create:Bool)throws->CandidateResourceIndex {
        guard RimeRuntime.startupAttempts==0 else{throw ResourceError.busy}
        let (directory,reference,components)=try bundleInputs(bundle);defer{components.close()}
        let base=try VerifiedCandidatePack(directory:ResourceDirectory(directory),expected:reference)
        let policy=try CandidateSourcePolicy(bundle:base,expectedBundle:reference)
        let root=try CandidateCompiler.scratch(),owner=try ResourceDirectory(root)
        defer{if (try? owner.check()) != nil{try? FileManager.default.removeItem(at:root)}}
        let source=try owner.createDirectory("source"),output=root.appendingPathComponent("compiled")
        try policy.writeSources(preset,to:source);try components.verify()
        // Compilation has its own process and private files. The publisher never
        // initializes librime and cannot publish an arbitrary incoming artifact.
        let receipt=try ResourceHelper.run(executable:components.helper,arguments:["candidate-compile",source.url.path,policy.inputsSHA(preset),output.path,components.library.path],home:root,timeout:120)
        let compiledReference=try ResourceContract.decode(ResourceReference.self,receipt)
        let pack=try VerifiedCandidatePack(directory:ResourceDirectory(output),expected:compiledReference)
        guard try policy.admitSourceIdentity(pack)==preset else{throw ResourceError.incompatible}
        try components.verify()
        let store=try CandidateResourceStore(directory:parent.appendingPathComponent(catalogLeaf),policy:policy,create:create);defer{store.close()}
        let result=try store.publish(pack,expectedRevision:expectedRevision){snapshot,preset in
            try CandidateHelper.probe(snapshot,components:components,timeout:120)
            try CandidateHelper.probeUpdate(snapshot,preset:preset,components:components)
        }
        guard RimeRuntime.startupAttempts==0 else{throw ResourceError.probe}
        return result.index
    }
}
public struct CandidateUpdateProbeReceipt:Codable,Equatable {
    public let format:Int,reference:ResourceReference,preset:CandidatePublicPreset,schemas:Int,commits:Int,negatives:Int,deployments:UInt64
    public init(reference:ResourceReference,preset:CandidatePublicPreset){format=1;self.reference=reference;self.preset=preset;schemas=8;commits=8;negatives=8;deployments=0}
}
