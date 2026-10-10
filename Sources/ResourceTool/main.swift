import Foundation
import Darwin
import ResourceCore
import EngineBridge

// Offline, fixed authored data only. No network, user/profile discovery, scripts,
// package import, signatures, registration, or active-engine hot replacement.
func emit<T:Encodable>(_ value:T)throws {FileHandle.standardOutput.write(try ResourceContract.encode(value));FileHandle.standardOutput.write(Data([10]))}
func scratch()throws->URL {
    let path=FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("paia-compiler-"+UUID().uuidString.lowercased())
    try FileManager.default.createDirectory(at:path,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700]);return path
}
func compile(output:URL,preset:ResourcePreset,library:URL)throws->ResourceReference {
    try ResourceHelper.checkLibrary(library)
    let root=try scratch();defer{try? FileManager.default.removeItem(at:root)}
    let owner=try ResourceDirectory(root),shared=try owner.createDirectory("shared"),user=try owner.createDirectory("user")
    for (name,data) in preset.sources{try shared.writeExclusive(name,data)}
    let runtime=try RimeRuntime(library:library.path,shared:shared.url.path,isolatedUser:user.url.path,dictionaryRevision:"offline-compilation",schemas:Array(preset.schemas.dropFirst()))
    guard runtime.close() else{throw ResourceError.io}
    let build=try user.child("build");var files=[String:Data]()
    for path in preset.requiredArtifacts {
        files[path]=path=="default.yaml" ? preset.sources[path]! : try build.read(String(path.dropFirst(6)))
    }
    let manifest=try ResourceManifest(generation:UUID().uuidString.lowercased(),preset:preset,artifacts:files)
    try FileManager.default.createDirectory(at:output,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
    let destination=try ResourceDirectory(output);try VerifiedResourcePack.write(manifest:manifest,files:files,to:destination)
    _=try VerifiedResourcePack(directory:destination,expected:manifest.reference)
    return try manifest.reference
}
do {
    let args=Array(CommandLine.arguments.dropFirst())
    switch args.first {
    case "compile":
        guard args.count==4,let preset=ResourcePreset(rawValue:args[2]) else{throw ResourceError.format}
        try emit(compile(output:URL(fileURLWithPath:args[1]),preset:preset,library:URL(fileURLWithPath:args[3])))
    case "probe":
        guard args.count==5 else{throw ResourceError.format}
        let expected=ResourceReference(generation:args[2],manifestSHA:args[3])
        let pack=try VerifiedResourcePack(directory:ResourceDirectory(URL(fileURLWithPath:args[1])),expected:expected)
        let copy=try ResourceSnapshot(pack);defer{copy.close()}
        try emit(ResourceNativeProbe.exercise(copy,library:URL(fileURLWithPath:args[4])))
    case "publish":
        guard args.count==6,let preset=ResourcePreset(rawValue:args[2]),let revision=UInt64(args[4]),["create","existing"].contains(args[5]) else{throw ResourceError.format}
        let storeURL=URL(fileURLWithPath:args[1]),library=URL(fileURLWithPath:args[3])
        let helper=URL(fileURLWithPath:CommandLine.arguments[0]).standardizedFileURL
        let helperSHA=ResourceContract.digest(try ResourceDirectory(helper.deletingLastPathComponent()).read(helper.lastPathComponent,maximum:64*1024*1024))
        let root=try scratch();defer{try? FileManager.default.removeItem(at:root)}
        let compiled=root.appendingPathComponent("compiled")
        let receipt=try ResourceHelper.run(executable:helper,arguments:["compile",compiled.path,preset.rawValue,library.path],home:root,timeout:120)
        let reference=try ResourceContract.decode(ResourceReference.self,receipt)
        let pack=try VerifiedResourcePack(directory:ResourceDirectory(compiled),expected:reference)
        let store=try ResourceStore(directory:storeURL,create:args[5]=="create");defer{store.close()}
        let result=try store.publish(pack,expectedRevision:revision){try ResourceHelper.probe($0,library:library,helper:helper,helperSHA:helperSHA)}
        try emit(result.index)
    default:throw ResourceError.format
    }
} catch {
    // No raw paths, inputs, schema parser diagnostics or arbitrary errors in logs.
    let unknown:Bool;if case ResourceError.durabilityUnknown=error{unknown=true}else{unknown=false}
    fputs(unknown ? "RESOURCE_PUBLICATION_DURABILITY_UNKNOWN; no automatic retry.\n":"RESOURCE_OPERATION_FAILED; prior publication retained where available.\n",stderr)
    exit(unknown ? 3:1)
}
