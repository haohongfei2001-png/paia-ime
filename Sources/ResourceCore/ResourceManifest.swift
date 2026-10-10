import Foundation
import CryptoKit

public enum ResourceError:Error {case format,limit,unsafePath,integrity,incompatible,io,busy,stale,unavailable,probe,timeout,durabilityUnknown}
public enum ResourceContract {
    public static let version="librime-1.16.0/paia-public-fixture-1"
    public static let engineSHA="922aad7de56473dd13e25836b0eecfa3698e07506154f418cf27e1f5e268e8b3"
    public static let headerSHA="6eb5629162c44761e7b878f1b122f464de5c8685bd3cd5ac1e8519badc6d6424"
    public static let provenance="Authored integration fixture only; no user history or external corpus. No general repository license grant; not a production language model."
    public static let maximumFile=8*1024*1024,maximumPack=24*1024*1024,maximumJSON=32768
    public static func digest(_ data:Data)->String {SHA256.hash(data:data).map{String(format:"%02x",$0)}.joined()}
    public static func hash(_ value:String)->Bool {value.utf8.count==64 && value.utf8.allSatisfy{(48...57).contains($0)||(97...102).contains($0)}}
    public static func generation(_ value:String)->Bool {UUID(uuidString:value)?.uuidString.lowercased()==value}
    public static func encode<T:Encodable>(_ value:T)throws->Data {
        let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys,.withoutEscapingSlashes]
        let data=try encoder.encode(value);guard data.count<=maximumJSON else{throw ResourceError.limit};return data
    }
    // Round-trip exactness also rejects unknown/duplicate keys and noncanonical
    // encodings instead of trusting JSONDecoder's ignored fields/last key wins.
    public static func decode<T:Codable>(_ type:T.Type,_ data:Data)throws->T {
        guard !data.isEmpty,data.count<=maximumJSON else{throw ResourceError.limit}
        let value=try JSONDecoder().decode(type,from:data)
        guard try encode(value)==data else{throw ResourceError.format};return value
    }
}
public struct ResourceFile:Codable,Equatable {
    public let path:String,bytes:Int,sha256:String
    public init(path:String,data:Data){self.path=path;bytes=data.count;sha256=ResourceContract.digest(data)}
}
public struct ResourceReference:Codable,Equatable {
    public let generation:String,manifestSHA:String
    public init(generation:String,manifestSHA:String){self.generation=generation;self.manifestSHA=manifestSHA}
    public func validate()throws {guard ResourceContract.generation(generation),ResourceContract.hash(manifestSHA) else{throw ResourceError.format}}
}
public struct ResourceManifest:Codable,Equatable {
    public let format:Int,generation:String,preset:ResourcePreset,contract:String,engineSHA:String,headerSHA:String
    public let dictionaryRevision:String,schemas:[String],inputs:[ResourceFile],artifacts:[ResourceFile],provenance:String
    public init(generation:String,preset:ResourcePreset,artifacts:[String:Data])throws {
        self.format=1;self.generation=generation;self.preset=preset;contract=ResourceContract.version
        engineSHA=ResourceContract.engineSHA;headerSHA=ResourceContract.headerSHA;provenance=ResourceContract.provenance
        schemas=preset.schemas;inputs=preset.sources.map{ResourceFile(path:$0.key,data:$0.value)}.sorted{$0.path<$1.path}
        dictionaryRevision=ResourceContract.digest(try ResourceContract.encode(inputs))
        self.artifacts=artifacts.map{ResourceFile(path:$0.key,data:$0.value)}.sorted{$0.path<$1.path};try validate()
    }
    public func validate()throws {
        guard format==1,ResourceContract.generation(generation),contract==ResourceContract.version,
              engineSHA==ResourceContract.engineSHA,headerSHA==ResourceContract.headerSHA,provenance==ResourceContract.provenance,
              schemas==preset.schemas else{throw ResourceError.incompatible}
        let expected=preset.sources.map{ResourceFile(path:$0.key,data:$0.value)}.sorted{$0.path<$1.path}
        guard inputs==expected,dictionaryRevision==ResourceContract.digest(try ResourceContract.encode(expected)),
              artifacts.map(\.path)==preset.requiredArtifacts else{throw ResourceError.integrity}
        var total=0
        for item in artifacts {
            guard item.bytes>0,item.bytes<=ResourceContract.maximumFile,ResourceContract.hash(item.sha256) else{throw ResourceError.limit}
            total+=item.bytes;guard total<=ResourceContract.maximumPack else{throw ResourceError.limit}
        }
        guard let original=artifacts.first(where:{$0.path=="default.yaml"}),
              original==ResourceFile(path:"default.yaml",data:preset.sources["default.yaml"]!) else{throw ResourceError.integrity}
    }
    public var reference:ResourceReference {get throws {ResourceReference(generation:generation,manifestSHA:ResourceContract.digest(try ResourceContract.encode(self)))}}
}
public struct ResourceIndex:Codable,Equatable {
    public let format:Int,revision:UInt64,current:ResourceReference,lastGood:ResourceReference?
    public init(revision:UInt64,current:ResourceReference,lastGood:ResourceReference?){format=1;self.revision=revision;self.current=current;self.lastGood=lastGood}
    public func validate()throws {guard format==1,revision>0,revision<UInt64.max,lastGood != current else{throw ResourceError.format};try current.validate();try lastGood?.validate()}
}
