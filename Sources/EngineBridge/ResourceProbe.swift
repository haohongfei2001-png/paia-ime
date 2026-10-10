import Foundation
import Darwin
import ResourceCore

public enum ResourceHelper {
    private final class Output {
        let lock=NSLock();var bytes=Data(),overflow=false
        func append(_ value:Data)->Bool {lock.lock();defer{lock.unlock()};if bytes.count+value.count>4096{overflow=true;return false};bytes.append(value);return true}
        func result()throws->Data {lock.lock();defer{lock.unlock()};guard !overflow else{throw ResourceError.limit};return bytes}
    }
    // Isolated authored helper only, never an in-process C timeout. Reap before
    // return/fallback. Killing cannot promise an OS-level uninterruptible task ends.
    public static func run(executable:URL,arguments:[String],home:URL,timeout:TimeInterval=20)throws->Data {
        guard timeout>0,timeout<=120 else{throw ResourceError.limit}
        let child=Process(),pipe=Pipe(),output=Output(),ended=DispatchSemaphore(value:0),eof=DispatchSemaphore(value:0)
        child.executableURL=executable;child.arguments=arguments
        child.environment=["PATH":"/usr/bin:/bin","HOME":home.path,"TMPDIR":home.path+"/","LC_ALL":"en_US.UTF-8"]
        child.standardOutput=pipe;child.standardError=FileHandle.nullDevice
        child.terminationHandler={_ in ended.signal()}
        pipe.fileHandleForReading.readabilityHandler={handle in
            let data=handle.availableData
            if data.isEmpty{handle.readabilityHandler=nil;eof.signal()}
            else if !output.append(data),child.isRunning{child.terminate()}
        }
        defer{pipe.fileHandleForReading.readabilityHandler=nil;try? pipe.fileHandleForReading.close();try? pipe.fileHandleForWriting.close();child.terminationHandler=nil}
        try child.run();try? pipe.fileHandleForWriting.close()
        let timedOut=ended.wait(timeout:.now()+timeout) == .timedOut
        if timedOut {
            if child.isRunning{child.terminate()}
            if ended.wait(timeout:.now()+0.5) == .timedOut,child.isRunning{_ = kill(child.processIdentifier,SIGKILL)}
        }
        child.waitUntilExit()
        guard !timedOut else{throw ResourceError.timeout}
        guard eof.wait(timeout:.now()+2) == .success,child.terminationReason == .exit,child.terminationStatus==0 else{throw ResourceError.probe}
        let data=try output.result();guard data.last==10 else{throw ResourceError.probe};return data.dropLast()
    }
    public static func checkLibrary(_ library:URL)throws {
        let dir=try ResourceDirectory(library.deletingLastPathComponent())
        let data=try dir.read(library.lastPathComponent,maximum:128*1024*1024)
        guard ResourceContract.digest(data)==ResourceContract.engineSHA else{throw ResourceError.incompatible}
    }
    public static func checkExecutable(_ helper:URL,expectedSHA:String)throws {
        guard helper.lastPathComponent=="paia-resources",ResourceContract.hash(expectedSHA) else{throw ResourceError.incompatible}
        let dir=try ResourceDirectory(helper.deletingLastPathComponent())
        guard ResourceContract.digest(try dir.read(helper.lastPathComponent,maximum:64*1024*1024))==expectedSHA else{throw ResourceError.integrity}
    }
    public static func probe(_ snapshot:ResourceSnapshot,library:URL,helper:URL,helperSHA:String,timeout:TimeInterval=20)throws {
        try snapshot.verify();try checkLibrary(library);try checkExecutable(helper,expectedSHA:helperSHA)
        let reference=snapshot.pack.reference
        let output=try run(executable:helper,arguments:["probe",snapshot.directory.path,reference.generation,reference.manifestSHA,library.path],home:snapshot.root,timeout:timeout)
        let result=try ResourceContract.decode(ResourceProbeReceipt.self,output)
        guard result == (try ResourceProbeReceipt(snapshot.pack.manifest)) else{throw ResourceError.probe};try snapshot.verify()
    }
}

public struct ResourceProbeReceipt:Codable,Equatable {
    public let format:Int,reference:ResourceReference,schemas:[String],commits:Int,deployments:UInt64
    public init(_ manifest:ResourceManifest)throws {try manifest.validate();format=1;reference=try manifest.reference;schemas=manifest.schemas;commits=schemas.count*(manifest.preset == .baseline ? 1:2);deployments=0}
}

public enum ResourceNativeProbe {
    // Called in a separate helper process with a freshly isolated user directory.
    public static func exercise(_ snapshot:ResourceSnapshot,library:URL)throws->ResourceProbeReceipt {
        try snapshot.verify();try ResourceHelper.checkLibrary(library)
        let manifest=snapshot.pack.manifest
        let runtime=try RimeRuntime(library:library.path,shared:snapshot.directory.path,isolatedUser:snapshot.userDirectory.path,dictionaryRevision:manifest.dictionaryRevision,precompiled:true)
        defer{_ = runtime.close()}
        for schema in manifest.schemas {
            let probes=manifest.preset == .baseline ? [("nihao","你好")]:[("nihao","你好"),(manifest.preset.probeRaw,manifest.preset.probeText)]
            for (raw,text) in probes {
                let session=try runtime.makeSession(schema:schema);defer{session.end()}
                guard try session.refresh().commit==nil else{throw ResourceError.probe}
                for character in raw{_ = try session.process(.text(String(character)))}
                guard let first=session.snapshot?.rows.first,first.text==text,
                      let effect=try session.select(first.ref).commit,effect.text==text,
                      session.reserve(effect),!session.reserve(effect),try session.refresh().commit==nil else{throw ResourceError.probe}
            }
        }
        guard runtime.deploymentCalls==0 else{throw ResourceError.probe};try snapshot.verify()
        return try ResourceProbeReceipt(manifest)
    }
}

public final class PublicResourceEnvironment {
    public let runtime:RimeRuntime,selection:ResourceSelection
    public init(store:URL?,bundle:URL?,bundleReference:ResourceReference?,library:URL,helper:URL,helperSHA:String,
                probeOverride:((ResourceSnapshot)throws->Void)?=nil)throws {
        try ResourceHelper.checkLibrary(library);try ResourceHelper.checkExecutable(helper,expectedSHA:helperSHA)
        let probe=probeOverride ?? {try ResourceHelper.probe($0,library:library,helper:helper,helperSHA:helperSHA)}
        if let store=store {selection=try ResourceCatalog(directory:store).select(probe:probe)}
        else {
            guard let bundle=bundle,let reference=bundleReference else{throw ResourceError.unavailable}
            let snapshot=try ResourceSnapshot(VerifiedResourcePack(directory:ResourceDirectory(bundle),expected:reference))
            do{try probe(snapshot);try snapshot.verify()}catch{snapshot.close();throw error}
            selection=ResourceSelection(snapshot:snapshot,reason:.bundled)
        }
        let snapshot=selection.snapshot
        do {
            try snapshot.verify()
            runtime=try RimeRuntime(library:library.path,shared:snapshot.directory.path,isolatedUser:snapshot.userDirectory.path,
                                    dictionaryRevision:snapshot.pack.manifest.dictionaryRevision,precompiled:true,cleanup:{snapshot.close()})
        } catch {snapshot.close();throw error} // No second generation/runtime attempt.
    }
    public var status:String {"Verified authored precompiled fixture; "+selection.reason.rawValue+" generation "+selection.snapshot.pack.reference.generation+". Offline updates take effect on next independent launch; no personal overlay."}
}
