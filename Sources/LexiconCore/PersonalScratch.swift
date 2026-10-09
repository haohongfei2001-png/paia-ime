import Foundation
import Darwin

// Managed derived data only. Never scans outside the explicitly selected store's own namespace.
public final class PersonalScratch {
    public let directory:URL
    private struct Marker:Codable {let format:Int,id:String,pid:Int32}
    public init(storeDirectory:URL)throws {
        let root=storeDirectory.appendingPathComponent(".paia-b2-derived-v1",isDirectory:true)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        let properties=try root.resourceValues(forKeys:[.isDirectoryKey,.isSymbolicLinkKey])
        guard properties.isDirectory==true,properties.isSymbolicLink != true else{throw LexiconError.unsafePath}
        // At most sixteen verified, inactive generations per explicit startup. Live/reused PIDs are untouched.
        guard let children=FileManager.default.enumerator(at:root,includingPropertiesForKeys:[.isDirectoryKey,.isSymbolicLinkKey],options:[.skipsSubdirectoryDescendants]) else{throw LexiconError.io}
        var removed=0,examined=0
        for case let child as URL in children {
            if removed>=16 || examined>=128{break};examined+=1
            guard UUID(uuidString:child.lastPathComponent) != nil,
                  let values=try? child.resourceValues(forKeys:[.isDirectoryKey,.isSymbolicLinkKey]),values.isDirectory==true,values.isSymbolicLink != true,
                  let data=try? SelectedLexiconFile.read(child.appendingPathComponent(".owner.json"),maximumBytes:512),
                  let marker=try? JSONDecoder().decode(Marker.self,from:data),marker.format==1,marker.id==child.lastPathComponent,marker.pid>0 else{continue}
            if kill(marker.pid,0) == -1 && errno==ESRCH {try FileManager.default.removeItem(at:child);removed+=1}
        }
        let id=UUID().uuidString;directory=root.appendingPathComponent(id,isDirectory:true)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
        do {
            let marker=directory.appendingPathComponent(".owner.json")
            try JSONEncoder().encode(Marker(format:1,id:id,pid:getpid())).write(to:marker,options:.atomic)
            let fd=Darwin.open(marker.path,O_RDWR|O_NOFOLLOW|O_CLOEXEC),dir=Darwin.open(directory.path,O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC),parent=Darwin.open(root.path,O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC)
            defer{if fd>=0{Darwin.close(fd)};if dir>=0{Darwin.close(dir)};if parent>=0{Darwin.close(parent)}}
            guard fd>=0,dir>=0,parent>=0,fcntl(fd,F_FULLFSYNC)==0,fsync(dir)==0,fsync(parent)==0 else{throw LexiconError.io}
        }
        catch{try? FileManager.default.removeItem(at:directory);throw error}
    }
    public func remove()throws {if FileManager.default.fileExists(atPath:directory.path){try FileManager.default.removeItem(at:directory)}}
}
