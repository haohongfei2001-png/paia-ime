import Foundation
import CryptoKit

public enum SettingsSpelling:String,Codable,CaseIterable {case full,flypy,natural}
public enum InitialInputMode:String,Codable,CaseIterable {case chinese,literal}
// Explicit app identifiers are preferences, never document or permission authority.
public enum ApplicationPreference {
    public static let maximumCount=16,maximumIdentifierBytes=127
    public static func validIdentifier(_ value:String)->Bool {
        let bytes=Array(value.utf8.prefix(maximumIdentifierBytes+1))
        return !bytes.isEmpty && bytes.count<=maximumIdentifierBytes && bytes.allSatisfy{
            (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0==45 || $0==46
        } && !value.hasPrefix(".") && !value.hasSuffix(".") && !value.contains("..")
    }
}
// Closed ordinary preferences only. No text, documents, paths or permission state.
public struct SettingsValues:Codable,Equatable {
    public var spelling:SettingsSpelling = .full
    public var traditional=false,literal=false,chinesePunctuation=false
    public var fuzzyInitials=false,fullPinyinCorrection=true
    public var initialModes:[String:InitialInputMode]=[:]
    public func initialLiteral(for application:String?)->Bool {
        guard let application=application,ApplicationPreference.validIdentifier(application),let mode=initialModes[application] else{return literal}
        return mode == .literal
    }
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
    private struct Header:Decodable {let format:String}
    // Decode/verify the original exact v1 contract before adding defaults in memory.
    // Existing bytes and store marker stay unchanged until the user explicitly saves.
    private struct LegacyValues:Codable {let spelling:SettingsSpelling,traditional:Bool,literal:Bool,chinesePunctuation:Bool}
    private struct LegacyDocument:Codable {let revision:UInt64,values:LegacyValues}
    private struct LegacyEnvelope:Codable {let format:String,sha256:String,document:LegacyDocument}
    public static func validate(_ values:SettingsValues)throws {
        guard values.initialModes.count<=ApplicationPreference.maximumCount,
              values.initialModes.keys.allSatisfy(ApplicationPreference.validIdentifier) else{throw SettingsError.limit}
    }
    private static func encoder()->JSONEncoder {let e=JSONEncoder();e.outputFormatting=[.sortedKeys,.withoutEscapingSlashes];return e}
    public static func digest(_ bytes:Data)->String {SHA256.hash(data:bytes).map{String(format:"%02x",$0)}.joined()}
    public static func encode(_ document:SettingsDocument)throws->Data {
        guard document.revision>0,document.revision<=maximumRevision else{throw SettingsError.limit}
        try validate(document.values)
        let payload=try encoder().encode(document)
        let bytes=try encoder().encode(Envelope(format:"paia.settings.v2",sha256:digest(payload),document:document))
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
            let format=try JSONDecoder().decode(Header.self,from:bytes).format
            if format=="paia.settings.v1" {
                let envelope=try JSONDecoder().decode(LegacyEnvelope.self,from:bytes),legacy=envelope.document
                guard legacy.revision>0,legacy.revision<=maximumRevision else{throw SettingsError.limit}
                let payload=try encoder().encode(legacy)
                let canonical=try encoder().encode(LegacyEnvelope(format:format,sha256:digest(payload),document:legacy))
                guard canonical==bytes else{throw SettingsError.invalidFormat}
                var values=SettingsValues();values.spelling=legacy.values.spelling;values.traditional=legacy.values.traditional
                values.literal=legacy.values.literal;values.chinesePunctuation=legacy.values.chinesePunctuation
                return SettingsDocument(revision:legacy.revision,values:values)
            }
            let envelope=try JSONDecoder().decode(Envelope.self,from:bytes)
            guard format=="paia.settings.v2",try encode(envelope.document)==bytes else{throw SettingsError.invalidFormat}
            return envelope.document // Canonical equality checks digest, duplicate/unknown keys and exact types.
        }catch let error as SettingsError{throw error}catch{throw SettingsError.invalidFormat}
    }
}
