import Foundation
import Darwin

public enum ResourceSelectionReason:String {case current,lastGood,bundled}
public struct ResourceSelection {
    public let snapshot:ResourceSnapshot,reason:ResourceSelectionReason
    public init(snapshot:ResourceSnapshot,reason:ResourceSelectionReason){self.snapshot=snapshot;self.reason=reason}
}
public final class ResourceCatalog {
    let root:ResourceDirectory
    static let marker=Data("paia.public-fixture-resources.v1\n".utf8)
    public init(directory:URL)throws {
        root=try ResourceDirectory(directory)
        guard try root.read(".format",maximum:128)==Self.marker else{throw ResourceError.format}
    }
    public func index()throws->ResourceIndex? {
        guard let bytes=try root.optional("index.json") else{return nil}
        let value=try ResourceContract.decode(ResourceIndex.self,bytes);try value.validate();return value
    }
    public func pack(_ reference:ResourceReference)throws->VerifiedResourcePack {
        try reference.validate();return try VerifiedResourcePack(directory:root.child("generations").child(reference.generation),expected:reference)
    }
    // At most two candidates, read only. Failures never rewrite pointers. A
    // native probe must finish/reap before this proceeds to another candidate.
    public func select(probe:(ResourceSnapshot)throws->Void)throws->ResourceSelection {
        guard let selected=try index() else{throw ResourceError.unavailable}
        let references=[selected.current]+(selected.lastGood.map{[$0]} ?? [])
        for (i,reference) in references.enumerated() {
            var snapshot:ResourceSnapshot?
            do {
                let copy=try ResourceSnapshot(pack(reference));snapshot=copy
                try probe(copy);try copy.verify()
                return ResourceSelection(snapshot:copy,reason:i==0 ? .current:.lastGood)
            } catch {snapshot?.close()}
        }
        throw ResourceError.unavailable
    }
}
public enum ResourcePublicationFault {case beforeGenerationRename,afterGenerationRename,beforeIndexRename,afterIndexRename}
public struct ResourcePublication {public let index:ResourceIndex;public let restartRequired=true}

// One explicit offline writer. Public artifacts only; no personal authority,
// restoration, implicit retry, generation pruning or active-session switch.
public final class ResourceStore {
    private let root:ResourceDirectory,generations:ResourceDirectory
    private var writer:Int32 = -1,closed=false,uncertain=false
    private let fault:ResourcePublicationFault?
    private let lock=NSLock()
    public init(directory:URL,create:Bool=false,fault:ResourcePublicationFault?=nil)throws {
        self.fault=fault
        if create {try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])}
        root=try ResourceDirectory(directory)
        if create {
            guard try root.names().isEmpty else{throw ResourceError.unsafePath}
            generations=try root.createDirectory("generations")
            try root.writeExclusive(".format",ResourceCatalog.marker);try root.sync();try ResourceDirectory(directory.deletingLastPathComponent()).sync()
        } else {
            guard try root.read(".format",maximum:128)==ResourceCatalog.marker else{throw ResourceError.format}
            generations=try root.child("generations")
        }
        writer=openat(root.fd,".writer.lock",O_RDWR|O_CREAT|O_NOFOLLOW|O_NONBLOCK|O_CLOEXEC,0o600)
        guard writer>=0 else{throw ResourceError.unsafePath}
        var info=stat()
        guard fstat(writer,&info)==0,(info.st_mode&S_IFMT)==S_IFREG,info.st_nlink==1 else{Darwin.close(writer);writer = -1;throw ResourceError.unsafePath}
        guard flock(writer,LOCK_EX|LOCK_NB)==0 else{Darwin.close(writer);writer = -1;throw ResourceError.busy}
    }
    deinit{if writer>=0{Darwin.close(writer)}}
    public func close(){lock.lock();defer{lock.unlock()};closed=true;if writer>=0{Darwin.close(writer);writer = -1}}
    private func ready()throws {
        guard !closed,!uncertain,writer>=0 else{throw uncertain ? ResourceError.durabilityUnknown:ResourceError.stale}
        try root.check();try generations.check()
        var owned=stat(),linked=stat()
        guard fstat(writer,&owned)==0,owned.st_nlink==1,fstatat(root.fd,".writer.lock",&linked,AT_SYMLINK_NOFOLLOW)==0,
              (linked.st_mode&S_IFMT)==S_IFREG,owned.st_dev==linked.st_dev,owned.st_ino==linked.st_ino,
              try root.read(".format",maximum:128)==ResourceCatalog.marker else{throw ResourceError.stale}
    }
    public func publish(_ pack:VerifiedResourcePack,expectedRevision:UInt64,probe:(ResourceSnapshot)throws->Void)throws->ResourcePublication {
        lock.lock();defer{lock.unlock()};try ready()
        let oldBytes=try root.optional("index.json"),catalog=try ResourceCatalog(directory:root.url),old=try catalog.index()
        guard (old?.revision ?? 0)==expectedRevision,expectedRevision<UInt64.max-1 else{throw ResourceError.stale}
        // A corrupt current cannot become last-good in the new index.
        var prior:ResourceReference?
        if old != nil {let selected=try catalog.select(probe:probe);prior=selected.snapshot.pack.reference;selected.snapshot.close()}
        guard prior != pack.reference else{throw ResourceError.stale}
        let snapshot=try ResourceSnapshot(pack);defer{snapshot.close()};try probe(snapshot);try snapshot.verify()
        try ready();guard try root.optional("index.json")==oldBytes else{throw ResourceError.stale}
        let staging=".staging-"+UUID().uuidString.lowercased(),directory=try root.createDirectory(staging)
        try VerifiedResourcePack.write(manifest:pack.manifest,files:pack.files,to:directory)
        _=try VerifiedResourcePack(directory:directory,expected:pack.reference)
        if fault == .beforeGenerationRename{throw ResourceError.io}
        try root.rename(staging,to:generations,as:pack.reference.generation,exclusive:true)
        try generations.sync();try root.sync()
        if fault == .afterGenerationRename{throw ResourceError.io}
        let next=ResourceIndex(revision:expectedRevision+1,current:pack.reference,lastGood:prior);try next.validate()
        let name=".index-"+UUID().uuidString.lowercased();try root.writeExclusive(name,ResourceContract.encode(next))
        try ready();guard try root.optional("index.json")==oldBytes else{throw ResourceError.stale}
        if fault == .beforeIndexRename{throw ResourceError.io}
        uncertain=true // Before the syscall; every later error is an unknown publication.
        do {
            try root.rename(name,to:root,as:"index.json")
            if fault == .afterIndexRename{throw ResourceError.durabilityUnknown}
            try root.sync()
            guard try catalog.index()==next else{throw ResourceError.durabilityUnknown}
        } catch {throw ResourceError.durabilityUnknown}
        uncertain=false
        return ResourcePublication(index:next)
    }
}
