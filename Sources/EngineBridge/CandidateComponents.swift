import Foundation
import ResourceCore

// Snapshot verified bundle bytes into a private, nonshared generation before
// dlopen/exec. This is integrity of an unsigned engineering build, not a new
// signing/authenticity claim. Loader paths are checked by the packaging build.
public final class CandidateComponents {
    public let root:URL,library:URL,extensionLibrary:URL,helper:URL,extensionSHA:String,helperSHA:String
    private let owner:ResourceDirectory
    private var closed=false
    public init(library:URL,extensionLibrary:URL,helper:URL,extensionSHA:String,helperSHA:String)throws {
        guard ResourceContract.hash(extensionSHA),ResourceContract.hash(helperSHA) else{throw ResourceError.incompatible}
        func read(_ url:URL,_ digest:String,_ maximum:Int)throws->Data {
            let data=try ResourceDirectory(url.deletingLastPathComponent()).read(url.lastPathComponent,maximum:maximum)
            guard ResourceContract.digest(data)==digest else{throw ResourceError.integrity};return data
        }
        let engine=try read(library,ResourceContract.engineSHA,128*1024*1024)
        let bridge=try read(extensionLibrary,extensionSHA,64*1024*1024)
        let tool=try read(helper,helperSHA,64*1024*1024)
        root=FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("paia-components-"+UUID().uuidString.lowercased())
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
        owner=try ResourceDirectory(root)
        self.library=root.appendingPathComponent("librime.1.dylib");self.extensionLibrary=root.appendingPathComponent("paia-g01.dylib");self.helper=root.appendingPathComponent("paia-resources")
        self.extensionSHA=extensionSHA;self.helperSHA=helperSHA
        do {
            try owner.writeExclusive("librime.1.dylib",engine,maximum:128*1024*1024)
            try owner.writeExclusive("paia-g01.dylib",bridge,maximum:64*1024*1024)
            try owner.writeExclusive("paia-resources",tool,maximum:64*1024*1024,executable:true)
            try owner.sync();try verify()
        } catch {close();throw error}
    }
    public func verify()throws {
        guard !closed,try owner.names()==["librime.1.dylib","paia-g01.dylib","paia-resources"] else{throw ResourceError.stale}
        try ResourceHelper.checkLibrary(library)
        guard ResourceContract.digest(try owner.read("paia-g01.dylib",maximum:64*1024*1024))==extensionSHA else{throw ResourceError.integrity}
        try ResourceHelper.checkExecutable(helper,expectedSHA:helperSHA)
    }
    public func close(){guard !closed else{return};closed=true;if (try? owner.check()) != nil{try? FileManager.default.removeItem(at:root)}}
    deinit{close()}
}
