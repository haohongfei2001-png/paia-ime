import Foundation
import Darwin

public enum SettingsTestFault {case beforePublication,afterInitialization,publicationFailure,afterPublication}
// Explicit chosen directory only. Creating a lock is not an implicit preference save.
public final class SettingsStore {
    public let directory:URL
    private let lock=NSLock(),fault:SettingsTestFault?
    private var rootFD:Int32 = -1,writerFD:Int32 = -1
    private var expected:Data?,document:SettingsDocument?,closed=false,uncertain=false
    private let marker=Data("paia.settings.v1\n".utf8)
    public init(directory:URL,fault:SettingsTestFault?=nil)throws {
        self.directory=directory.standardizedFileURL;self.fault=fault
        do {
            try FileManager.default.createDirectory(at:self.directory,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
            rootFD=Darwin.open(self.directory.path,O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC)
            guard rootFD>=0 else{throw SettingsError.unsafePath}
            writerFD=openat(rootFD,".writer.lock",O_RDWR|O_CREAT|O_NOFOLLOW|O_NONBLOCK|O_CLOEXEC,0o600)
            var info=stat();guard writerFD>=0,fstat(writerFD,&info)==0,(info.st_mode & S_IFMT)==S_IFREG,info.st_nlink==1 else{throw SettingsError.unsafePath}
            guard flock(writerFD,LOCK_EX|LOCK_NB)==0 else{throw SettingsError.busy}
            let initialized=try read(".initialized");expected=try read("settings.json")
            if let bytes=expected {guard initialized==marker else{throw SettingsError.invalidFormat};document=try SettingsCodec.decode(bytes)}
            else{guard initialized==nil else{throw SettingsError.invalidFormat}}
        }catch{if writerFD>=0{Darwin.close(writerFD)};if rootFD>=0{Darwin.close(rootFD)};writerFD = -1;rootFD = -1;throw error}
    }
    deinit{if writerFD>=0{Darwin.close(writerFD)};if rootFD>=0{Darwin.close(rootFD)}}
    public func close(){lock.lock();defer{lock.unlock()};if !closed{closed=true;Darwin.close(writerFD);Darwin.close(rootFD);writerFD = -1;rootFD = -1}}
    private func read(_ name:String)throws->Data? {
        let fd=openat(rootFD,name,O_RDWR|O_NONBLOCK|O_NOFOLLOW|O_CLOEXEC)
        if fd<0{if errno==ENOENT{return nil};throw SettingsError.unsafePath};defer{Darwin.close(fd)}
        var info=stat();guard fstat(fd,&info)==0,(info.st_mode & S_IFMT)==S_IFREG,info.st_nlink==1 else{throw SettingsError.unsafePath}
        guard info.st_size>=0,info.st_size<=SettingsCodec.maximumBytes else{throw SettingsError.limit}
        var data=Data(),buffer=[UInt8](repeating:0,count:1024)
        while true{let n=Darwin.read(fd,&buffer,buffer.count);if n<0{if errno==EINTR{continue};throw SettingsError.io};if n==0{break};data.append(contentsOf:buffer.prefix(n));guard data.count<=SettingsCodec.maximumBytes else{throw SettingsError.limit}}
        guard fcntl(fd,F_FULLFSYNC)==0,fsync(rootFD)==0 else{throw SettingsError.durabilityUnknown};return data
    }
    private func verify()throws {
        guard !closed else{throw SettingsError.closed};guard !uncertain else{throw SettingsError.durabilityUnknown}
        var ownedRoot=stat(),linkedRoot=stat()
        guard fstat(rootFD,&ownedRoot)==0,lstat(directory.path,&linkedRoot)==0,(linkedRoot.st_mode & S_IFMT)==S_IFDIR,ownedRoot.st_dev==linkedRoot.st_dev,ownedRoot.st_ino==linkedRoot.st_ino else{throw SettingsError.unsafePath}
        var a=stat(),b=stat();guard fstat(writerFD,&a)==0,fstatat(rootFD,".writer.lock",&b,AT_SYMLINK_NOFOLLOW)==0,a.st_ino==b.st_ino,a.st_dev==b.st_dev else{throw SettingsError.unsafePath}
        guard try read("settings.json")==expected,try read(".initialized")==((expected==nil) ? nil:marker) else{throw SettingsError.stale}
    }
    public func snapshot()throws->SettingsDocument? {lock.lock();defer{lock.unlock()};try verify();return document}
    private func writeAll(_ bytes:Data,_ fd:Int32)throws {
        try bytes.withUnsafeBytes{raw in var offset=0;while offset<raw.count{let n=Darwin.write(fd,raw.baseAddress!.advanced(by:offset),raw.count-offset);if n<0{if errno==EINTR{continue};throw SettingsError.io};guard n>0 else{throw SettingsError.io};offset+=n}}
        guard fcntl(fd,F_FULLFSYNC)==0 else{throw SettingsError.io}
    }
    @discardableResult public func save(_ values:SettingsValues,expectedRevision:UInt64)throws->SettingsDocument {
        lock.lock();defer{lock.unlock()};try verify()
        guard (document?.revision ?? 0)==expectedRevision else{throw SettingsError.stale}
        guard expectedRevision<SettingsCodec.maximumRevision else{throw SettingsError.limit}
        let next=SettingsDocument(revision:expectedRevision+1,values:values),bytes=try SettingsCodec.encode(next)
        let name=".staging-"+UUID().uuidString,fd=openat(rootFD,name,O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW|O_CLOEXEC,0o600)
        guard fd>=0 else{throw SettingsError.io};defer{Darwin.close(fd);unlinkat(rootFD,name,0)}
        try writeAll(bytes,fd)
        if fault == .beforePublication{throw SettingsError.io}
        if expected==nil {
            let initialized=openat(rootFD,".initialized",O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW|O_CLOEXEC,0o600)
            guard initialized>=0 else{throw SettingsError.unsafePath};defer{Darwin.close(initialized)}
            // Once initialization starts, any failure is uncertain; no implicit retry or replacement.
            uncertain=true;try writeAll(marker,initialized);guard fsync(rootFD)==0 else{throw SettingsError.durabilityUnknown}
            if fault == .afterInitialization{throw SettingsError.durabilityUnknown}
        }
        uncertain=true // Conservative quarantine even if a publication syscall reports failure.
        if fault == .publicationFailure{throw SettingsError.durabilityUnknown}
        guard renameat(rootFD,name,rootFD,"settings.json")==0 else{throw SettingsError.durabilityUnknown}
        guard fault != .afterPublication,fsync(rootFD)==0 else{throw SettingsError.durabilityUnknown}
        expected=bytes;document=next;uncertain=false;return next
    }
}
