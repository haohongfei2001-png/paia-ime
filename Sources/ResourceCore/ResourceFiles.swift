import Foundation
import Darwin

// Every descendant is opened relative to an owned directory descriptor. No
// recursive copy of a previously checked public path and no special files.
public final class ResourceDirectory {
    public let url:URL
    let fd:Int32
    private var identity=stat()
    public init(_ url:URL)throws {
        let selected=url.standardizedFileURL
        let handle=Darwin.open(selected.path,O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC)
        guard handle>=0 else{throw ResourceError.unsafePath}
        var checked=stat()
        guard fstat(handle,&checked)==0 else{Darwin.close(handle);throw ResourceError.io}
        self.url=selected;fd=handle;identity=checked
    }
    // Internal descriptor handoff from a verified ancestor walk. Do not reopen
    // the URL and lose protection against replacement of an intermediate parent.
    init(duplicating descriptor:Int32,url:URL)throws {
        let selected=url,handle=fcntl(descriptor,F_DUPFD_CLOEXEC,0)
        guard handle>=0 else{throw ResourceError.io}
        var owned=stat(),linked=stat()
        guard fstat(handle,&owned)==0,lstat(selected.path,&linked)==0,
              (owned.st_mode&S_IFMT)==S_IFDIR,(linked.st_mode&S_IFMT)==S_IFDIR,
              owned.st_dev==linked.st_dev,owned.st_ino==linked.st_ino else{Darwin.close(handle);throw ResourceError.stale}
        self.url=selected;fd=handle;identity=owned
    }
    private init(parent:ResourceDirectory,name:String)throws {
        try parent.check();let selected=parent.url.appendingPathComponent(name,isDirectory:true)
        let handle=openat(parent.fd,name,O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC)
        guard handle>=0 else{throw ResourceError.unsafePath}
        var checked=stat()
        guard fstat(handle,&checked)==0 else{Darwin.close(handle);throw ResourceError.io}
        do{try parent.check()}catch{Darwin.close(handle);throw error}
        url=selected;fd=handle;identity=checked
    }
    deinit{Darwin.close(fd)}
    static func name(_ name:String)throws {
        guard !name.isEmpty,name.utf8.count<=128,name != ".",name != "..",
              name.utf8.allSatisfy({(97...122).contains($0)||(48...57).contains($0)||[45,46,95].contains($0)}) else{throw ResourceError.unsafePath}
    }
    public func check()throws {
        var current=stat()
        guard lstat(url.path,&current)==0,(current.st_mode&S_IFMT)==S_IFDIR,
              current.st_dev==identity.st_dev,current.st_ino==identity.st_ino else{throw ResourceError.stale}
    }
    public func child(_ name:String)throws->ResourceDirectory {try Self.name(name);return try ResourceDirectory(parent:self,name:name)}
    public func names()throws->[String] {
        try check();let duplicate=fcntl(fd,F_DUPFD_CLOEXEC,0);guard duplicate>=0 else{throw ResourceError.io}
        guard let stream=fdopendir(duplicate) else{Darwin.close(duplicate);throw ResourceError.io};defer{closedir(stream)}
        rewinddir(stream);var names=[String]()
        while let entry=readdir(stream) {
            let name=withUnsafePointer(to:&entry.pointee.d_name){$0.withMemoryRebound(to:CChar.self,capacity:Int(MAXNAMLEN)+1){String(cString:$0)}}
            if name=="." || name==".."{continue};names.append(name)
            guard names.count<=128 else{throw ResourceError.limit}
        }
        try check();return names.sorted()
    }
    public func read(_ name:String,maximum:Int=ResourceContract.maximumFile)throws->Data {
        try Self.name(name);try check()
        let file=openat(fd,name,O_RDONLY|O_NOFOLLOW|O_NONBLOCK|O_CLOEXEC)
        guard file>=0 else{throw ResourceError.unsafePath};defer{Darwin.close(file)}
        var before=stat();guard fstat(file,&before)==0,(before.st_mode&S_IFMT)==S_IFREG,before.st_nlink==1 else{throw ResourceError.unsafePath}
        guard before.st_size>=0,before.st_size<=maximum else{throw ResourceError.limit}
        var bytes=Data(),buffer=[UInt8](repeating:0,count:8192)
        while true {
            let count=Darwin.read(file,&buffer,min(buffer.count,maximum-bytes.count+1))
            if count<0{if errno==EINTR{continue};throw ResourceError.io};if count==0{break}
            bytes.append(contentsOf:buffer.prefix(count));guard bytes.count<=maximum else{throw ResourceError.limit}
        }
        var after=stat(),linked=stat()
        guard fstat(file,&after)==0,fstatat(fd,name,&linked,AT_SYMLINK_NOFOLLOW)==0,
              (linked.st_mode&S_IFMT)==S_IFREG,linked.st_ino==before.st_ino,linked.st_dev==before.st_dev,
              after.st_nlink==1,after.st_size==before.st_size,bytes.count==before.st_size,
              after.st_mtimespec.tv_sec==before.st_mtimespec.tv_sec,after.st_mtimespec.tv_nsec==before.st_mtimespec.tv_nsec,
              after.st_ctimespec.tv_sec==before.st_ctimespec.tv_sec,after.st_ctimespec.tv_nsec==before.st_ctimespec.tv_nsec else{throw ResourceError.stale}
        try check();return bytes
    }
    public func readPath(_ path:String)throws->Data {
        let parts=path.split(separator:"/",omittingEmptySubsequences:false)
        if parts.count==1{return try read(path)}
        guard parts.count==2,parts[0]=="build" else{throw ResourceError.unsafePath}
        return try child("build").read(String(parts[1]))
    }
    public func optional(_ name:String,maximum:Int=ResourceContract.maximumJSON)throws->Data? {
        try Self.name(name);try check();var value=stat()
        if fstatat(fd,name,&value,AT_SYMLINK_NOFOLLOW) != 0 {if errno==ENOENT{return nil};throw ResourceError.io}
        return try read(name,maximum:maximum)
    }
    public func createDirectory(_ name:String)throws->ResourceDirectory {
        try Self.name(name);try check();guard mkdirat(fd,name,0o700)==0 else{throw ResourceError.io};return try child(name)
    }
    public func writeExclusive(_ name:String,_ data:Data,maximum:Int=ResourceContract.maximumFile,executable:Bool=false)throws {
        try Self.name(name);try check()
        guard maximum>0,maximum<=128*1024*1024,data.count<=maximum else{throw ResourceError.limit}
        let file=openat(fd,name,O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW|O_CLOEXEC,0o600)
        guard file>=0 else{throw ResourceError.io};defer{Darwin.close(file)}
        try data.withUnsafeBytes{bytes in
            var offset=0
            while offset<bytes.count {
                let count=Darwin.write(file,bytes.baseAddress!.advanced(by:offset),bytes.count-offset)
                if count<0{if errno==EINTR{continue};throw ResourceError.io};guard count>0 else{throw ResourceError.io};offset+=count
            }
        }
        if executable {guard fchmod(file,0o700)==0 else{throw ResourceError.io}}
        guard fcntl(file,F_FULLFSYNC)==0 else{throw ResourceError.io};try check()
    }
    public func sync()throws {try check();guard fsync(fd)==0 else{throw ResourceError.durabilityUnknown}}
    func rename(_ name:String,to other:ResourceDirectory,as destination:String,exclusive:Bool=false)throws {
        try Self.name(name);try Self.name(destination);try check();try other.check()
        let result=exclusive ? renameatx_np(fd,name,other.fd,destination,UInt32(RENAME_EXCL)):renameat(fd,name,other.fd,destination)
        guard result==0 else{throw ResourceError.io}
    }
}

public struct VerifiedResourcePack {
    public let manifest:ResourceManifest,manifestBytes:Data,files:[String:Data]
    public var reference:ResourceReference {ResourceReference(generation:manifest.generation,manifestSHA:ResourceContract.digest(manifestBytes))}
    public init(directory:ResourceDirectory,expected:ResourceReference)throws {
        try expected.validate()
        let bytes=try directory.read("manifest.json",maximum:ResourceContract.maximumJSON)
        guard ResourceContract.digest(bytes)==expected.manifestSHA else{throw ResourceError.integrity}
        let value=try ResourceContract.decode(ResourceManifest.self,bytes);try value.validate()
        guard value.generation==expected.generation,try directory.names()==["build","default.yaml","manifest.json"],
              try directory.child("build").names()==value.preset.requiredArtifacts.filter({$0.hasPrefix("build/")}).map({String($0.dropFirst(6))}).sorted() else{throw ResourceError.integrity}
        var copied=[String:Data]()
        for item in value.artifacts {
            let data=try directory.readPath(item.path)
            guard data.count==item.bytes,ResourceContract.digest(data)==item.sha256 else{throw ResourceError.integrity};copied[item.path]=data
        }
        guard try directory.read("manifest.json",maximum:ResourceContract.maximumJSON)==bytes else{throw ResourceError.stale}
        manifest=value;manifestBytes=bytes;files=copied
    }
    public static func write(manifest:ResourceManifest,files:[String:Data],to directory:ResourceDirectory)throws {
        try manifest.validate();guard files.keys.sorted()==manifest.preset.requiredArtifacts else{throw ResourceError.integrity}
        let build=try directory.createDirectory("build")
        for file in manifest.artifacts {
            guard let bytes=files[file.path],ResourceFile(path:file.path,data:bytes)==file else{throw ResourceError.integrity}
            if file.path.hasPrefix("build/"){try build.writeExclusive(String(file.path.dropFirst(6)),bytes)}else{try directory.writeExclusive(file.path,bytes)}
        }
        try build.sync();try directory.writeExclusive("manifest.json",ResourceContract.encode(manifest));try directory.sync()
    }
}

public final class ResourceSnapshot {
    public let root:URL,directory:URL,userDirectory:URL,pack:VerifiedResourcePack
    private let owner:ResourceDirectory
    private var closed=false
    public init(_ pack:VerifiedResourcePack)throws {
        self.pack=pack
        root=FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("paia-resources-"+UUID().uuidString.lowercased(),isDirectory:true)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
        owner=try ResourceDirectory(root)
        let selected=try owner.createDirectory("pack");directory=selected.url
        userDirectory=try owner.createDirectory("user").url
        try VerifiedResourcePack.write(manifest:pack.manifest,files:pack.files,to:selected)
        _=try VerifiedResourcePack(directory:selected,expected:pack.reference)
    }
    public func verify()throws {guard !closed else{throw ResourceError.stale};try owner.check();_=try VerifiedResourcePack(directory:ResourceDirectory(directory),expected:pack.reference)}
    public func close(){guard !closed else{return};closed=true;if (try? owner.check()) != nil{try? FileManager.default.removeItem(at:root)}}
    deinit{close()}
}
