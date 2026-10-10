import Foundation
import Darwin

// Private, public-resource-only root. This is deliberately separate from the
// existing three-authority ProductDataRoot and the v1 fixture resource store.
final class CandidateCatalogRoot {
    static let prefix="paia.public-candidate-resources.v2\n"
    let directory:ResourceDirectory,parent:ResourceDirectory,generations:ResourceDirectory
    private let lockFD:Int32,lockDevice:dev_t,lockInode:ino_t
    private struct Ancestor {let url:URL,fd:Int32,device:dev_t,inode:ino_t}
    private var ancestors=[Ancestor]()
    private let marker:Data
    init(directory url:URL,create:Bool)throws {
        var opened=[Ancestor](),openedLock:Int32 = -1
        do {
            guard url.isFileURL,!url.path.utf8.contains(0) else{throw ResourceError.unsafePath}
            let whole=url.pathComponents;guard whole.count>1 else{throw ResourceError.unsafePath}
            let leaf=url.lastPathComponent,parts=Array(whole.dropLast())
            try ResourceDirectory.name(leaf)
            guard parts.first=="/",parts.count<=64 else{throw ResourceError.unsafePath}
            var path=URL(fileURLWithPath:"/",isDirectory:true),fd=Darwin.open("/",O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC),info=stat()
            guard fd>=0 else{throw ResourceError.unsafePath}
            guard fstat(fd,&info)==0 else{Darwin.close(fd);throw ResourceError.io}
            opened.append(Ancestor(url:path,fd:fd,device:info.st_dev,inode:info.st_ino))
            for part in parts.dropFirst() {
                guard part != ".",part != "..",part.utf8.count<=Int(MAXNAMLEN) else{throw ResourceError.unsafePath}
                let next=openat(fd,part,O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC)
                guard next>=0 else{throw ResourceError.unsafePath}
                guard fstat(next,&info)==0 else{Darwin.close(next);throw ResourceError.io}
                path.appendPathComponent(part,isDirectory:true)
                opened.append(Ancestor(url:path,fd:next,device:info.st_dev,inode:info.st_ino));fd=next
            }
            guard info.st_uid==getuid(),(info.st_mode&0o022)==0 else{throw ResourceError.unsafePath}
            let parent=try ResourceDirectory(duplicating:fd,url:path)
            if create {
                let name=".candidate-root-"+UUID().uuidString.lowercased(),staging=try parent.createDirectory(name)
                let generations=try staging.createDirectory("generations")
                try staging.writeExclusive(".format",Data((Self.prefix+UUID().uuidString.lowercased()+"\n").utf8))
                try staging.writeExclusive(".writer.lock",Data())
                try generations.sync();try staging.sync()
                try Self.check(opened);try parent.rename(name,to:parent,as:leaf,exclusive:true);try parent.sync()
            }
            let selected=try parent.child(leaf)
            try Self.privateDirectory(selected)
            let bytes=try selected.read(".format",maximum:128)
            guard let text=String(data:bytes,encoding:.utf8),text.hasPrefix(Self.prefix),text.hasSuffix("\n"),
                  ResourceContract.generation(String(text.dropFirst(Self.prefix.count).dropLast())) else{throw ResourceError.format}
            let generations=try selected.child("generations");try Self.privateDirectory(generations)
            openedLock=openat(selected.fd,".writer.lock",O_RDONLY|O_NOFOLLOW|O_NONBLOCK|O_CLOEXEC)
            var lockInfo=stat()
            guard openedLock>=0,fstat(openedLock,&lockInfo)==0 else{throw ResourceError.unsafePath}
            try Self.checkLock(selected,descriptor:openedLock,device:lockInfo.st_dev,inode:lockInfo.st_ino)
            try Self.check(opened);try selected.sync();try parent.sync()
            self.parent=parent;directory=selected;self.generations=generations;marker=bytes;ancestors=opened
            lockFD=openedLock;lockDevice=lockInfo.st_dev;lockInode=lockInfo.st_ino
        } catch {if openedLock>=0{Darwin.close(openedLock)};for item in opened{Darwin.close(item.fd)};throw error}
    }
    deinit{Darwin.close(lockFD);for item in ancestors{Darwin.close(item.fd)}}
    private static func check(_ values:[Ancestor])throws {
        guard !values.isEmpty else{throw ResourceError.stale}
        for item in values {
            var linked=stat(),owned=stat()
            guard lstat(item.url.path,&linked)==0,fstat(item.fd,&owned)==0,
                  (linked.st_mode&S_IFMT)==S_IFDIR,linked.st_dev==item.device,linked.st_ino==item.inode,
                  owned.st_dev==item.device,owned.st_ino==item.inode else{throw ResourceError.stale}
        }
        var value=stat();guard let last=values.last,fstat(last.fd,&value)==0,value.st_uid==getuid(),(value.st_mode&0o022)==0 else{throw ResourceError.unsafePath}
    }
    private static func privateDirectory(_ value:ResourceDirectory)throws {
        try value.check();var info=stat()
        guard fstat(value.fd,&info)==0,info.st_uid==getuid(),(info.st_mode&S_IFMT)==S_IFDIR,(info.st_mode&0o077)==0 else{throw ResourceError.unsafePath}
    }
    private static func checkLock(_ directory:ResourceDirectory,descriptor:Int32,device:dev_t,inode:ino_t)throws {
        var info=stat(),owned=stat()
        guard fstat(descriptor,&owned)==0,fstatat(directory.fd,".writer.lock",&info,AT_SYMLINK_NOFOLLOW)==0,
              (info.st_mode&S_IFMT)==S_IFREG,info.st_nlink==1,info.st_uid==getuid(),(info.st_mode&0o077)==0,
              owned.st_nlink==1,owned.st_dev==device,owned.st_ino==inode,info.st_dev==device,info.st_ino==inode else{throw ResourceError.unsafePath}
    }
    func verify()throws {
        try Self.check(ancestors);try Self.privateDirectory(directory)
        guard try directory.read(".format",maximum:128)==marker else{throw ResourceError.stale}
        try Self.privateDirectory(generations);try Self.checkLock(directory,descriptor:lockFD,device:lockDevice,inode:lockInode);try Self.check(ancestors)
    }
}
