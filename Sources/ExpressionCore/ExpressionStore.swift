import Foundation
import Darwin

public enum ExpressionTestFault {case beforePublication,afterInitialization,publicationFailure,afterPublication}
public enum ExpressionSaveResolution:Equatable {case previous,published}
public struct ExpressionSaveVerification:Equatable {
    public let resolution:ExpressionSaveResolution,document:ExpressionDocument?
    public let attemptedRecordID:UUID?
}
// Explicit chosen directory only. Creating a lock is not an implicit expression save.
public final class ExpressionStore {
    public let directory:URL
    private let authorityGuard:()throws->Void
    private let lock=NSLock()
    private var fault:ExpressionTestFault?
    private var rootFD:Int32 = -1,writerFD:Int32 = -1
    private var expected:Data?,document:ExpressionDocument?,closed=false,uncertain=false
    private struct PendingSave {let bytes:Data,document:ExpressionDocument}
    private var pending:PendingSave?
    private let marker=Data("paia.expressions.v1\n".utf8)
    public init(directory:URL,fault:ExpressionTestFault?=nil,preopenedDirectory:Int32?=nil,allowCreateLock:Bool=true,authorityGuard:@escaping()throws->Void={})throws {
        self.directory=directory.standardizedFileURL;self.fault=fault;self.authorityGuard=authorityGuard
        do {
            try authorityGuard()
            if let descriptor=preopenedDirectory {rootFD=fcntl(descriptor,F_DUPFD_CLOEXEC,0)}
            else {
                if allowCreateLock{try FileManager.default.createDirectory(at:self.directory,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])}
                rootFD=Darwin.open(self.directory.path,O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC)
            }
            var rootInfo=stat(),linkedRoot=stat();guard rootFD>=0,fstat(rootFD,&rootInfo)==0,lstat(self.directory.path,&linkedRoot)==0,
                  (rootInfo.st_mode&S_IFMT)==S_IFDIR,(linkedRoot.st_mode&S_IFMT)==S_IFDIR,rootInfo.st_dev==linkedRoot.st_dev,rootInfo.st_ino==linkedRoot.st_ino else{throw ExpressionError.unsafePath}
            try authorityGuard()
            writerFD=openat(rootFD,".writer.lock",O_RDWR|(allowCreateLock ? O_CREAT:0)|O_NOFOLLOW|O_NONBLOCK|O_CLOEXEC,0o600)
            var info=stat();guard writerFD>=0,fstat(writerFD,&info)==0,(info.st_mode & S_IFMT)==S_IFREG,info.st_nlink==1 else{throw ExpressionError.unsafePath}
            guard flock(writerFD,LOCK_EX|LOCK_NB)==0 else{throw ExpressionError.busy}
            let initialized=try read(".initialized");expected=try read("expressions.json")
            if let bytes=expected {guard initialized==marker else{throw ExpressionError.invalidFormat};document=try ExpressionCodec.decode(bytes)}
            else{guard initialized==nil else{throw ExpressionError.invalidFormat}}
            try authorityGuard()
        }catch{if writerFD>=0{Darwin.close(writerFD)};if rootFD>=0{Darwin.close(rootFD)};writerFD = -1;rootFD = -1;throw error}
    }
    deinit{if writerFD>=0{Darwin.close(writerFD)};if rootFD>=0{Darwin.close(rootFD)}}
    public func close(){lock.lock();defer{lock.unlock()};if !closed{closed=true;Darwin.close(writerFD);Darwin.close(rootFD);writerFD = -1;rootFD = -1}}
    private func read(_ name:String)throws->Data? {
        let fd=openat(rootFD,name,O_RDWR|O_NONBLOCK|O_NOFOLLOW|O_CLOEXEC)
        if fd<0{if errno==ENOENT{return nil};throw ExpressionError.unsafePath};defer{Darwin.close(fd)}
        var info=stat();guard fstat(fd,&info)==0,(info.st_mode & S_IFMT)==S_IFREG,info.st_nlink==1 else{throw ExpressionError.unsafePath}
        guard info.st_size>=0,info.st_size<=ExpressionCodec.maximumBytes else{throw ExpressionError.limit}
        var data=Data(),buffer=[UInt8](repeating:0,count:1024)
        while true{let n=Darwin.read(fd,&buffer,buffer.count);if n<0{if errno==EINTR{continue};throw ExpressionError.io};if n==0{break};data.append(contentsOf:buffer.prefix(n));guard data.count<=ExpressionCodec.maximumBytes else{throw ExpressionError.limit}}
        guard fcntl(fd,F_FULLFSYNC)==0,fsync(rootFD)==0 else{throw ExpressionError.durabilityUnknown}
        var after=stat(),linked=stat()
        guard fstat(fd,&after)==0,fstatat(rootFD,name,&linked,AT_SYMLINK_NOFOLLOW)==0,
              after.st_nlink==1,linked.st_nlink==1,(linked.st_mode & S_IFMT)==S_IFREG,after.st_ino==linked.st_ino,after.st_dev==linked.st_dev,
              after.st_size==info.st_size,after.st_mtimespec.tv_sec==info.st_mtimespec.tv_sec,after.st_mtimespec.tv_nsec==info.st_mtimespec.tv_nsec,
              after.st_ctimespec.tv_sec==info.st_ctimespec.tv_sec,after.st_ctimespec.tv_nsec==info.st_ctimespec.tv_nsec else{throw ExpressionError.stale}
        return data
    }
    private func verifyIdentity()throws {
        try authorityGuard()
        guard !closed else{throw ExpressionError.closed}
        var ownedRoot=stat(),linkedRoot=stat()
        guard fstat(rootFD,&ownedRoot)==0,lstat(directory.path,&linkedRoot)==0,(linkedRoot.st_mode & S_IFMT)==S_IFDIR,ownedRoot.st_dev==linkedRoot.st_dev,ownedRoot.st_ino==linkedRoot.st_ino else{throw ExpressionError.unsafePath}
        var a=stat(),b=stat();guard fstat(writerFD,&a)==0,fstatat(rootFD,".writer.lock",&b,AT_SYMLINK_NOFOLLOW)==0,a.st_ino==b.st_ino,a.st_dev==b.st_dev,(a.st_mode & S_IFMT)==S_IFREG,a.st_nlink==1,b.st_nlink==1 else{throw ExpressionError.unsafePath}
    }
    private func verify()throws {
        try verifyIdentity();guard !uncertain else{throw ExpressionError.durabilityUnknown}
        guard try read("expressions.json")==expected,try read(".initialized")==((expected==nil) ? nil:marker) else{throw ExpressionError.stale}
        try verifyIdentity()
    }
    public var hasUnverifiedSave:Bool {lock.lock();defer{lock.unlock()};return !closed && pending != nil}
    // Preserve the actual canonical source envelope, including legacy format.
    // Inspection is explicit; it neither migrates bytes nor retries pending saves.
    public func exportData()throws->Data? {lock.lock();defer{lock.unlock()};try verify();guard pending==nil else{throw ExpressionError.durabilityUnknown};return expected}
    public func snapshot()throws->ExpressionDocument? {lock.lock();defer{lock.unlock()};try verify();guard pending==nil else{throw ExpressionError.durabilityUnknown};return document}
    // Resolve only this handle's attempted save, under its original lock and root identity.
    // Reads include file/directory durability barriers; no authority bytes are written or retried.
    public func verifyLastSave()throws->ExpressionSaveVerification {
        lock.lock();defer{lock.unlock()};guard !closed else{throw ExpressionError.closed}
        guard let pending=pending else{throw ExpressionError.stale}
        uncertain=true;try verifyIdentity()
        let bytes=try read("expressions.json"),initialized=try read(".initialized")
        // Absence returns before read's barrier, so even the empty previous state needs this.
        guard fsync(rootFD)==0 else{throw ExpressionError.durabilityUnknown};try verifyIdentity()
        let result:ExpressionSaveVerification
        if bytes==expected && initialized==((expected==nil) ? nil:marker) {
            result=ExpressionSaveVerification(resolution:.previous,document:document,attemptedRecordID:pending.document.records.first(where:{$0.revision==pending.document.revision})?.id)
        }else if bytes==pending.bytes && initialized==marker {
            let decoded=try ExpressionCodec.decode(pending.bytes)
            guard decoded==pending.document else{throw ExpressionError.invalidFormat}
            expected=pending.bytes;document=decoded
            result=ExpressionSaveVerification(resolution:.published,document:decoded,attemptedRecordID:pending.document.records.first(where:{$0.revision==pending.document.revision})?.id)
        }else{throw ExpressionError.stale}
        uncertain=false;self.pending=nil;return result
    }
    private func inject(_ point:ExpressionTestFault)->Bool {
        guard fault==point else{return false};fault=nil;return true // One-shot, test-only injection.
    }
    private func writeAll(_ bytes:Data,_ fd:Int32)throws {
        try bytes.withUnsafeBytes{raw in var offset=0;while offset<raw.count{let n=Darwin.write(fd,raw.baseAddress!.advanced(by:offset),raw.count-offset);if n<0{if errno==EINTR{continue};throw ExpressionError.io};guard n>0 else{throw ExpressionError.io};offset+=n}}
        guard fcntl(fd,F_FULLFSYNC)==0 else{throw ExpressionError.io}
    }
    @discardableResult public func saveExact(_ text:String,aliases:[String],editing id:UUID?=nil,expectedRecordRevision:UInt64?=nil,expectedRevision:UInt64,now:Int64=Int64(Date().timeIntervalSince1970*1000))throws->ExpressionDocument {
        lock.lock();defer{lock.unlock()};try verify()
        try ExpressionCodec.validate(text:text,aliases:aliases)
        guard now>0 else{throw ExpressionError.invalidFormat}
        guard expectedRevision<ExpressionCodec.maximumRevision,(document?.revision ?? 0)==expectedRevision else{throw ExpressionError.stale}
        var records=document?.records ?? []
        if let id=id {
            guard let index=records.firstIndex(where:{$0.id==id}),records[index].deletedAt==nil,records[index].revision==expectedRecordRevision else{throw ExpressionError.stale}
            let old=records[index];guard now>=old.updatedAt else{throw ExpressionError.stale}
            records[index]=ExpressionRecord(id:id,revision:expectedRevision+1,recordCreatedAt:old.recordCreatedAt,savedAt:old.savedAt,updatedAt:now,exactText:text,aliases:aliases)
        }else{
            guard expectedRecordRevision==nil,records.count<ExpressionCodec.maximumRecords else{throw ExpressionError.limit}
            records.append(ExpressionRecord(id:UUID(),revision:expectedRevision+1,recordCreatedAt:now,savedAt:now,updatedAt:now,exactText:text,aliases:aliases))
        }
        return try publish(records,expectedRevision:expectedRevision)
    }
    @discardableResult public func delete(_ id:UUID,expectedRecordRevision:UInt64,expectedRevision:UInt64,now:Int64=Int64(Date().timeIntervalSince1970*1000))throws->ExpressionDocument {
        lock.lock();defer{lock.unlock()};try verify()
        guard expectedRevision<ExpressionCodec.maximumRevision,(document?.revision ?? 0)==expectedRevision else{throw ExpressionError.stale}
        var records=document?.records ?? []
        guard let index=records.firstIndex(where:{$0.id==id}),records[index].deletedAt==nil,records[index].revision==expectedRecordRevision,now>=records[index].updatedAt else{throw ExpressionError.stale}
        let old=records[index]
        records[index]=ExpressionRecord(id:id,revision:expectedRevision+1,recordCreatedAt:old.recordCreatedAt,savedAt:old.savedAt,updatedAt:now,exactText:nil,aliases:[],deletedAt:now)
        return try publish(records,expectedRevision:expectedRevision)
    }
    private func publish(_ records:[ExpressionRecord],expectedRevision:UInt64)throws->ExpressionDocument {
        try verify()
        guard pending==nil else{throw ExpressionError.durabilityUnknown}
        guard (document?.revision ?? 0)==expectedRevision else{throw ExpressionError.stale}
        guard expectedRevision<ExpressionCodec.maximumRevision else{throw ExpressionError.limit}
        let next=ExpressionDocument(revision:expectedRevision+1,records:records),bytes=try ExpressionCodec.encode(next)
        pending=PendingSave(bytes:bytes,document:next)
        let name=".staging-"+UUID().uuidString,fd=openat(rootFD,name,O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW|O_CLOEXEC,0o600)
        guard fd>=0 else{throw ExpressionError.io};defer{Darwin.close(fd);unlinkat(rootFD,name,0)}
        try writeAll(bytes,fd)
        if inject(.beforePublication){throw ExpressionError.io}
        if expected==nil {
            let initialized=openat(rootFD,".initialized",O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW|O_CLOEXEC,0o600)
            guard initialized>=0 else{throw ExpressionError.unsafePath};defer{Darwin.close(initialized)}
            // Once initialization starts, any failure is uncertain; no implicit retry or replacement.
            uncertain=true;try writeAll(marker,initialized);guard fsync(rootFD)==0 else{throw ExpressionError.durabilityUnknown}
            if inject(.afterInitialization){throw ExpressionError.durabilityUnknown}
        }
        uncertain=true // Conservative quarantine even if a publication syscall reports failure.
        if inject(.publicationFailure){throw ExpressionError.durabilityUnknown}
        guard renameat(rootFD,name,rootFD,"expressions.json")==0 else{throw ExpressionError.durabilityUnknown}
        guard !inject(.afterPublication),fsync(rootFD)==0 else{throw ExpressionError.durabilityUnknown}
        try authorityGuard() // Failure after publication remains an unknown save; never retry.
        expected=bytes;document=next;uncertain=false;pending=nil;return next
    }
}
