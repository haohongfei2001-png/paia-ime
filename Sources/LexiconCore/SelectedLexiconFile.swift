import Foundation
import Darwin

// Called only with a file explicitly chosen for this operation. No profile/path discovery.
public enum SelectedLexiconFile {
    public static func read(_ url:URL,maximumBytes:Int=LexiconRules.maximumBytes)throws->Data {
        guard maximumBytes>0,maximumBytes<=LexiconRules.maximumBytes else{throw LexiconError.limit}
        let fd=Darwin.open(url.path,O_RDONLY|O_NOFOLLOW|O_NONBLOCK|O_CLOEXEC)
        guard fd>=0 else{throw LexiconError.unsafePath};defer{Darwin.close(fd)}
        var info=stat();guard fstat(fd,&info)==0,(info.st_mode & S_IFMT)==S_IFREG else{throw LexiconError.unsafePath}
        guard info.st_size>=0,info.st_size<=maximumBytes else{throw LexiconError.limit}
        var data=Data(),buffer=[UInt8](repeating:0,count:8192)
        while true {
            let n=Darwin.read(fd,&buffer,buffer.count)
            if n<0{if errno==EINTR{continue};throw LexiconError.io};if n==0{break}
            data.append(contentsOf:buffer.prefix(n));guard data.count<=maximumBytes else{throw LexiconError.limit}
        }
        return data
    }
    public static func write(_ data:Data,to url:URL)throws {
        _ = try LexiconCodec.decode(data)
        let parent=Darwin.open(url.deletingLastPathComponent().path,O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC)
        guard parent>=0 else{throw LexiconError.unsafePath};defer{Darwin.close(parent)}
        let name=url.lastPathComponent;guard !name.isEmpty,name != ".",name != ".." else{throw LexiconError.unsafePath}
        var existing=stat()
        if fstatat(parent,name,&existing,AT_SYMLINK_NOFOLLOW)==0 {
            guard (existing.st_mode & S_IFMT)==S_IFREG,existing.st_nlink==1 else{throw LexiconError.unsafePath}
        } else if errno != ENOENT {throw LexiconError.io}
        let temporary=".paia-export-"+UUID().uuidString
        let fd=openat(parent,temporary,O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW|O_CLOEXEC,0o600)
        guard fd>=0 else{throw LexiconError.io};defer{Darwin.close(fd);unlinkat(parent,temporary,0)}
        try data.withUnsafeBytes{bytes in
            var offset=0
            while offset<bytes.count {
                let n=Darwin.write(fd,bytes.baseAddress!.advanced(by:offset),bytes.count-offset)
                if n<0{if errno==EINTR{continue};throw LexiconError.io};guard n>0 else{throw LexiconError.io};offset+=n
            }
        }
        guard fcntl(fd,F_FULLFSYNC)==0,renameat(parent,temporary,parent,name)==0 else{throw LexiconError.io}
        guard fsync(parent)==0 else{throw LexiconError.durabilityUnknown}
    }
}
