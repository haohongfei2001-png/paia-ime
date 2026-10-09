import Foundation
import CryptoKit

public enum SettingsSpelling:String,Codable,CaseIterable {case full,flypy,natural}
// Closed ordinary preferences only. No input, target, resource paths or permission state.
public struct SettingsValues:Codable,Equatable {
    public var spelling:SettingsSpelling = .full
    public var traditional=false,literal=false,chinesePunctuation=false
    public init(){}
}
public struct SettingsDocument:Codable,Equatable {
    public let revision:UInt64,values:SettingsValues
    public init(revision:UInt64,values:SettingsValues){self.revision=revision;self.values=values}
}
public enum SettingsError:Error,Equatable {case invalidFormat,limit,unsafePath,busy,stale,io,durabilityUnknown,closed}
public enum SettingsCodec {
    public static let maximumBytes=4096,maximumRevision:UInt64=1_000_000_000
    private struct Envelope:Codable {let format:String,sha256:String,document:SettingsDocument}
    private static func encoder()->JSONEncoder {let e=JSONEncoder();e.outputFormatting=[.sortedKeys,.withoutEscapingSlashes];return e}
    public static func digest(_ bytes:Data)->String {SHA256.hash(data:bytes).map{String(format:"%02x",$0)}.joined()}
    public static func encode(_ document:SettingsDocument)throws->Data {
        guard document.revision>0,document.revision<=maximumRevision else{throw SettingsError.limit}
        let payload=try encoder().encode(document)
        let bytes=try encoder().encode(Envelope(format:"paia.settings.v1",sha256:digest(payload),document:document))
        guard bytes.count<=maximumBytes else{throw SettingsError.limit};return bytes
    }
    public static func decode(_ bytes:Data)throws->SettingsDocument {
        guard !bytes.isEmpty,bytes.count<=maximumBytes else{throw SettingsError.limit}
        guard String(data:bytes,encoding:.utf8) != nil else{throw SettingsError.invalidFormat}
        var depth=0,quoted=false,escape=false
        for byte in bytes {
            if quoted {if escape{escape=false}else if byte==92{escape=true}else if byte==34{quoted=false};continue}
            if byte==34{quoted=true}else if byte==123 || byte==91{depth+=1;if depth>8{throw SettingsError.limit}}
            else if byte==125 || byte==93{depth-=1;if depth<0{throw SettingsError.invalidFormat}}
        }
        guard depth==0,!quoted else{throw SettingsError.invalidFormat}
        do {
            let envelope=try JSONDecoder().decode(Envelope.self,from:bytes)
            guard envelope.format=="paia.settings.v1",try encode(envelope.document)==bytes else{throw SettingsError.invalidFormat}
            return envelope.document // Canonical equality also checks digest, duplicate/unknown keys and exact types.
        }catch let error as SettingsError{throw error}catch{throw SettingsError.invalidFormat}
    }
}
