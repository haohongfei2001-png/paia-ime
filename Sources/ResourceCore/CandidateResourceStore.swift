import Foundation
import Darwin

public struct CandidateResourceIndex:Codable,Equatable {
    public let format:Int,sourceContract:String,revision:UInt64,current:ResourceReference,lastGood:ResourceReference?
    public init(policy:CandidateSourcePolicy,revision:UInt64,current:ResourceReference,lastGood:ResourceReference?) {
        format=2;sourceContract=policy.contractSHA;self.revision=revision;self.current=current;self.lastGood=lastGood
    }
    public func validate(policy:CandidateSourcePolicy)throws {
        guard format==2,sourceContract==policy.contractSHA,revision>0,revision<UInt64.max,lastGood != current else{throw ResourceError.incompatible}
        try current.validate();try lastGood?.validate()
    }
}
public struct CandidateResourceSelection {
    public let snapshot:CandidateResourceSnapshot,reason:ResourceSelectionReason,preset:CandidatePublicPreset
    public init(snapshot:CandidateResourceSnapshot,reason:ResourceSelectionReason,preset:CandidatePublicPreset) {
        self.snapshot=snapshot;self.reason=reason;self.preset=preset
    }
}
public final class CandidateResourceCatalog {
    private let owner:CandidateCatalogRoot,policy:CandidateSourcePolicy
    public init(directory:URL,policy:CandidateSourcePolicy)throws {
        owner=try CandidateCatalogRoot(directory:directory,create:false);self.policy=policy
    }
    fileprivate init(owner:CandidateCatalogRoot,policy:CandidateSourcePolicy){self.owner=owner;self.policy=policy}
    public func index()throws->CandidateResourceIndex {
        try owner.verify()
        guard let bytes=try owner.directory.optional("index.json") else{throw ResourceError.unavailable}
        let value=try ResourceContract.decode(CandidateResourceIndex.self,bytes);try value.validate(policy:policy)
        try owner.verify();return value
    }
    public func pack(_ reference:ResourceReference)throws->VerifiedCandidatePack {
        try owner.verify();try reference.validate()
        let pack=try VerifiedCandidatePack(directory:owner.generations.child(reference.generation),expected:reference)
        _=try policy.admitSourceIdentity(pack);try owner.verify();return pack
    }
    // A selected catalog has exactly these recorded fallback candidates. It
    // never scans staging/old generations or silently tries the bundled source.
    public func select(probe:(CandidateResourceSnapshot,CandidatePublicPreset)throws->Void)throws->CandidateResourceSelection {
        let selected=try index(),references=[selected.current]+(selected.lastGood.map{[$0]} ?? [])
        for (offset,reference) in references.enumerated() {
            var snapshot:CandidateResourceSnapshot?
            do {
                let pack=try pack(reference),preset=try policy.admitSourceIdentity(pack),copy=try CandidateResourceSnapshot(pack)
                snapshot=copy;try probe(copy,preset);try copy.verify();try owner.verify()
                return CandidateResourceSelection(snapshot:copy,reason:offset==0 ? .current:.lastGood,preset:preset)
            } catch {snapshot?.close()}
        }
        throw ResourceError.unavailable
    }
}
public struct CandidateResourcePublication {public let index:CandidateResourceIndex;public let restartRequired=true}

// One explicit offline public-resource writer. Personal sources and derived
// packs are never admitted or copied here. Existing generations are immutable.
public final class CandidateResourceStore {
    private let owner:CandidateCatalogRoot,root:ResourceDirectory,generations:ResourceDirectory,policy:CandidateSourcePolicy
    private let fault:ResourcePublicationFault?,createdHere:Bool
    private let lock=NSLock()
    private var writer:Int32 = -1,closed=false,uncertain=false,published=false
    public init(directory:URL,policy:CandidateSourcePolicy,create:Bool=false,fault:ResourcePublicationFault?=nil)throws {
        self.policy=policy;self.fault=fault;createdHere=create
        let owner=try CandidateCatalogRoot(directory:directory,create:create)
        self.owner=owner;root=owner.directory;generations=owner.generations
        do {
            // Never recreate a lost writer lock, including on a marked root.
            writer=openat(root.fd,".writer.lock",O_RDWR|O_NOFOLLOW|O_NONBLOCK|O_CLOEXEC)
            guard writer>=0 else{throw ResourceError.unsafePath}
            guard flock(writer,LOCK_EX|LOCK_NB)==0 else{throw ResourceError.busy}
            try ready()
            if !create {_ = try CandidateResourceCatalog(owner:owner,policy:policy).index()}
        } catch {if writer>=0{Darwin.close(writer);writer = -1};throw error}
    }
    deinit{if writer>=0{Darwin.close(writer)}}
    public func close(){lock.lock();defer{lock.unlock()};closed=true;if writer>=0{Darwin.close(writer);writer = -1}}
    private func ready()throws {
        guard !closed,!uncertain,writer>=0 else{throw uncertain ? ResourceError.durabilityUnknown:ResourceError.stale}
        try verifyIdentity()
    }
    private func verifyIdentity()throws {
        guard !closed,writer>=0 else{throw ResourceError.stale}
        try owner.verify();try generations.check()
        var owned=stat(),linked=stat()
        guard fstat(writer,&owned)==0,fstatat(root.fd,".writer.lock",&linked,AT_SYMLINK_NOFOLLOW)==0,
              owned.st_nlink==1,linked.st_nlink==1,(owned.st_mode&S_IFMT)==S_IFREG,
              owned.st_ino==linked.st_ino,owned.st_dev==linked.st_dev else{throw ResourceError.stale}
    }
    // Explicit release assessment holds the same existing writer flock without
    // publishing or creating any authority. Runtime fallback semantics are kept.
    public func selectForInspection(probe:(CandidateResourceSnapshot,CandidatePublicPreset)throws->Void)throws->CandidateResourceSelection {
        lock.lock();defer{lock.unlock()};try ready()
        let catalog=CandidateResourceCatalog(owner:owner,policy:policy),before=try catalog.index()
        let selected=try catalog.select(probe:probe)
        do {try ready();guard try catalog.index()==before else{throw ResourceError.stale};return selected}
        catch {selected.snapshot.close();throw error}
    }
    // Low-level transaction, not an arbitrary-pack importer. Production callers
    // publish only a fixed preset just compiled by the verified helper. Source
    // hashes plus a finite behavior probe are not compiled-artifact authentication.
    public func publish(_ pack:VerifiedCandidatePack,expectedRevision:UInt64,
                        probe:(CandidateResourceSnapshot,CandidatePublicPreset)throws->Void)throws->CandidateResourcePublication {
        lock.lock();defer{lock.unlock()};try ready()
        let preset=try policy.admitSourceIdentity(pack) // Before native parsing of the proposed pack.
        let oldBytes=try root.optional("index.json"),catalog=CandidateResourceCatalog(owner:owner,policy:policy)
        let old:CandidateResourceIndex?
        if oldBytes != nil {old=try catalog.index()}
        else {
            guard createdHere,!published,expectedRevision==0 else{throw ResourceError.unavailable}
            old=nil
        }
        guard (old?.revision ?? 0)==expectedRevision,expectedRevision<UInt64.max-1 else{throw ResourceError.stale}
        var prior:ResourceReference?
        if old != nil {
            let selected=try catalog.select(probe:probe);prior=selected.snapshot.pack.reference;selected.snapshot.close()
        }
        guard prior != pack.reference else{throw ResourceError.stale}
        let snapshot=try CandidateResourceSnapshot(pack);defer{snapshot.close()}
        try probe(snapshot,preset);try snapshot.verify()
        try ready();guard try root.optional("index.json")==oldBytes else{throw ResourceError.stale}
        let staging=".staging-"+UUID().uuidString.lowercased(),directory=try root.createDirectory(staging)
        try VerifiedCandidatePack.write(manifest:pack.manifest,files:pack.files,to:directory)
        _=try policy.admitSourceIdentity(VerifiedCandidatePack(directory:directory,expected:pack.reference))
        if fault == .beforeGenerationRename{throw ResourceError.io}
        try ready();uncertain=true // Irreversible generation publication begins.
        let next=CandidateResourceIndex(policy:policy,revision:expectedRevision+1,current:pack.reference,lastGood:prior)
        do {
            try root.rename(staging,to:generations,as:pack.reference.generation,exclusive:true)
            try generations.sync();try root.sync()
            if fault == .afterGenerationRename{throw ResourceError.durabilityUnknown}
            try next.validate(policy:policy)
            let name=".index-"+UUID().uuidString.lowercased();try root.writeExclusive(name,ResourceContract.encode(next))
            try verifyIdentity();guard try root.optional("index.json")==oldBytes else{throw ResourceError.stale}
            if fault == .beforeIndexRename{throw ResourceError.durabilityUnknown}
            try root.rename(name,to:root,as:"index.json")
            if fault == .afterIndexRename{throw ResourceError.durabilityUnknown}
            try root.sync();try owner.verify()
            guard try catalog.index()==next else{throw ResourceError.durabilityUnknown}
        } catch {throw ResourceError.durabilityUnknown}
        published=true;uncertain=false
        return CandidateResourcePublication(index:next)
    }
}
