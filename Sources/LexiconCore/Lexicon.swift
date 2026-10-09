import Foundation
import CryptoKit

public enum LexiconError:Error,Equatable {case invalidFormat,invalidEntry,conflict,stale,deleted,overflow,limit,busy,unsafePath,io,durabilityUnknown}
public enum TermScope:String,Codable {case fullSimplified}
public struct PersonalTerm:Codable,Equatable,Identifiable {
    public let id:UUID
    public var surface:String,reading:String,aliases:[String],scope:TermScope,explicitPin:Bool
    public let createdAtMilliseconds:Int64
    public var revision:UInt64,deletedAtMilliseconds:Int64?,noRelearn:Bool
    public var isDeleted:Bool {deletedAtMilliseconds != nil}
    public var readings:[String] {[reading]+aliases}
    public var comparisonKey:String {surface.precomposedStringWithCanonicalMapping+"\u{0}"+reading+"\u{0}"+scope.rawValue}
    func sameContent(as other:PersonalTerm)->Bool {var rebased=other;rebased.revision=revision;return self==rebased}
}
public struct LexiconDocument:Codable,Equatable {
    public let formatVersion:Int
    public var revision:UInt64,terms:[PersonalTerm]
    public init(){formatVersion=1;revision=0;terms=[]}
    public var activeTerms:[PersonalTerm] {terms.filter{!$0.isDeleted}}
}
public enum LexiconRules {
    public static let maximumBytes=1_048_576,maximumTerms=1000
    public static let maximumRevision:UInt64=9_000_000_000_000_000
    public static func canonicalReading(_ value:String)throws->String {
        let words=value.split(separator:" ",omittingEmptySubsequences:true)
        guard !words.isEmpty,words.count<=12,words.allSatisfy({(1...6).contains($0.utf8.count) && $0.utf8.allSatisfy{(97...122).contains($0)}}) else{throw LexiconError.invalidEntry}
        return words.joined(separator:" ")
    }
    public static func validate(_ term:PersonalTerm)throws {
        guard !term.surface.isEmpty,term.surface.count<=80,term.surface.utf8.count<=1024,!term.surface.hasPrefix("#"),
              term.surface.unicodeScalars.allSatisfy({s in let x=s.value;return x>=32 && !(127...159).contains(x) && !(0x2028...0x202e).contains(x) && !(0x2066...0x2069).contains(x)}),
              term.reading == (try canonicalReading(term.reading)),term.aliases.count<=8,
              Set(term.readings).count==term.readings.count,term.createdAtMilliseconds>=0,
              term.revision<=maximumRevision,term.deletedAtMilliseconds.map({$0>=term.createdAtMilliseconds}) ?? true,
              !term.isDeleted || term.noRelearn else{throw LexiconError.invalidEntry}
        for alias in term.aliases {guard alias == (try canonicalReading(alias)) else{throw LexiconError.invalidEntry}}
    }
    public static func validate(_ document:LexiconDocument)throws {
        guard document.formatVersion==1,document.revision<=maximumRevision else{throw LexiconError.invalidFormat}
        guard document.terms.count<=maximumTerms else{throw LexiconError.limit}
        var ids=Set<UUID>(),keys=Set<String>(),effectivePairs=Set<String>(),pinnedReadings=Set<String>()
        for term in document.terms {
            try validate(term)
            guard term.revision<=document.revision,ids.insert(term.id).inserted,keys.insert(term.comparisonKey).inserted else{throw LexiconError.conflict}
            for reading in term.readings {
                guard effectivePairs.insert(term.surface.precomposedStringWithCanonicalMapping+"\u{0}"+reading+"\u{0}"+term.scope.rawValue).inserted else{throw LexiconError.conflict}
            }
            if !term.isDeleted && term.explicitPin {
                for reading in term.readings {guard pinnedReadings.insert(term.scope.rawValue+":"+reading).inserted else{throw LexiconError.conflict}}
            }
        }
    }
    static func nextRevision(_ document:LexiconDocument)throws->UInt64 {
        guard document.revision<maximumRevision else{throw LexiconError.overflow};return document.revision+1
    }
    static func timestamp()->Int64 {Int64(Date().timeIntervalSince1970*1000)}
}
public enum LexiconCodec {
    private struct Envelope:Codable {let format:String,sha256:String,document:LexiconDocument}
    public static func digest(_ data:Data)->String {SHA256.hash(data:data).map{String(format:"%02x",$0)}.joined()}
    private static func encoder()->JSONEncoder {let e=JSONEncoder();e.outputFormatting=[.sortedKeys,.withoutEscapingSlashes];return e}
    public static func encode(_ document:LexiconDocument)throws->Data {
        try LexiconRules.validate(document)
        let payload=try encoder().encode(document),data=try encoder().encode(Envelope(format:"paia.personal-lexicon.v1",sha256:digest(payload),document:document))
        // Reserve room for every active term's future tombstone and revision growth.
        // A full accepted format must not prevent deletion merely because metadata grows.
        let headroom=document.activeTerms.count*80+document.terms.count*16+document.activeTerms.filter{$0.explicitPin}.count*4+128
        guard data.count+headroom<=LexiconRules.maximumBytes else{throw LexiconError.limit};return data
    }
    public static func decode(_ data:Data)throws->LexiconDocument {
        guard data.count<=LexiconRules.maximumBytes else{throw LexiconError.limit}
        guard String(data:data,encoding:.utf8) != nil else{throw LexiconError.invalidFormat}
        // Bound nesting before asking Foundation to parse untrusted selected-file bytes.
        var depth=0,quoted=false,escaped=false
        for b in data {
            if quoted {if escaped{escaped=false}else if b==92{escaped=true}else if b==34{quoted=false};continue}
            if b==34{quoted=true}else if b==123 || b==91{depth+=1;if depth>8{throw LexiconError.limit}}
            else if b==125 || b==93{depth-=1;if depth<0{throw LexiconError.invalidFormat}}
        }
        guard depth==0,!quoted else{throw LexiconError.invalidFormat}
        do {
            guard let root=try JSONSerialization.jsonObject(with:data) as? [String:Any],Set(root.keys)==["format","sha256","document"],
                  let doc=root["document"] as? [String:Any],Set(doc.keys)==["formatVersion","revision","terms"],
                  let terms=doc["terms"] as? [[String:Any]] else{throw LexiconError.invalidFormat}
            let required:Set<String>=["id","surface","reading","aliases","scope","explicitPin","createdAtMilliseconds","revision","noRelearn"]
            for term in terms {guard required.isSubset(of:Set(term.keys)),Set(term.keys).isSubset(of:required.union(["deletedAtMilliseconds"])) else{throw LexiconError.invalidFormat}}
            let envelope=try JSONDecoder().decode(Envelope.self,from:data)
            guard envelope.format=="paia.personal-lexicon.v1",envelope.sha256==digest(try encoder().encode(envelope.document)) else{throw LexiconError.invalidFormat}
            try LexiconRules.validate(envelope.document)
            // Our export is canonical. Requiring those exact bytes also rejects duplicate JSON keys,
            // alternate interpretations and unknown encodings before import can change any state.
            guard try encode(envelope.document)==data else{throw LexiconError.invalidFormat}
            return envelope.document
        } catch let error as LexiconError {throw error} catch {throw LexiconError.invalidFormat}
    }
}

public struct LexiconImportPreview {
    public let baseRevision:UInt64,sha256:String,additions:[PersonalTerm],protectedDeletions:Int,unchanged:Int,conflicts:Int
    let store:UUID,bytes:Data
    public var canApply:Bool {conflicts==0 && !additions.isEmpty}
}
