import Foundation
import CryptoKit

public enum ExpressionError:Error,Equatable {case invalidFormat,limit,unsafePath,busy,stale,io,durabilityUnknown,closed}
public struct ExpressionRecord:Codable,Equatable {
    public let id:UUID,revision:UInt64,recordCreatedAt:Int64,savedAt:Int64,updatedAt:Int64
    public let exactText:String?,aliases:[String],deletedAt:Int64?
    public var sourceType:String {"manualSaved"}
    // These are not message records. No observed creation or send event exists.
    private enum CodingKeys:String,CodingKey {case id,revision,recordCreatedAt,savedAt,updatedAt,exactText,aliases,deletedAt,sourceType,sourceCreatedAt,sentAt}
    public init(id:UUID,revision:UInt64,recordCreatedAt:Int64,savedAt:Int64,updatedAt:Int64,exactText:String?,aliases:[String],deletedAt:Int64?=nil){
        self.id=id;self.revision=revision;self.recordCreatedAt=recordCreatedAt;self.savedAt=savedAt;self.updatedAt=updatedAt;self.exactText=exactText;self.aliases=aliases;self.deletedAt=deletedAt
    }
    public init(from decoder:Decoder)throws {
        let c=try decoder.container(keyedBy:CodingKeys.self)
        guard try c.decode(String.self,forKey:.sourceType)=="manualSaved",c.contains(.sentAt),c.contains(.sourceCreatedAt),try c.decodeNil(forKey:.sentAt),try c.decodeNil(forKey:.sourceCreatedAt) else{throw ExpressionError.invalidFormat}
        id=try c.decode(UUID.self,forKey:.id);revision=try c.decode(UInt64.self,forKey:.revision)
        recordCreatedAt=try c.decode(Int64.self,forKey:.recordCreatedAt);savedAt=try c.decode(Int64.self,forKey:.savedAt);updatedAt=try c.decode(Int64.self,forKey:.updatedAt)
        exactText=try c.decodeIfPresent(String.self,forKey:.exactText);aliases=try c.decode([String].self,forKey:.aliases);deletedAt=try c.decodeIfPresent(Int64.self,forKey:.deletedAt)
    }
    public func encode(to encoder:Encoder)throws {
        var c=encoder.container(keyedBy:CodingKeys.self)
        try c.encode(id,forKey:.id);try c.encode(revision,forKey:.revision);try c.encode(recordCreatedAt,forKey:.recordCreatedAt);try c.encode(savedAt,forKey:.savedAt);try c.encode(updatedAt,forKey:.updatedAt)
        try c.encode(exactText,forKey:.exactText);try c.encode(aliases,forKey:.aliases);try c.encode(deletedAt,forKey:.deletedAt)
        try c.encode(sourceType,forKey:.sourceType);try c.encodeNil(forKey:.sourceCreatedAt);try c.encodeNil(forKey:.sentAt)
    }
}
public struct ExpressionDocument:Codable,Equatable {
    public let revision:UInt64,records:[ExpressionRecord]
    public init(revision:UInt64,records:[ExpressionRecord]){self.revision=revision;self.records=records}
}
public enum ExpressionCodec {
    public static let maximumBytes=8*1024*1024,maximumTextUTF16=16384,maximumRecords=2000,maximumRevision:UInt64=1_000_000_000
    private struct Envelope:Codable {let format:String,sha256:String,document:ExpressionDocument}
    private static func encoder()->JSONEncoder {let e=JSONEncoder();e.outputFormatting=[.sortedKeys,.withoutEscapingSlashes];return e}
    public static func digest(_ bytes:Data)->String {SHA256.hash(data:bytes).map{String(format:"%02x",$0)}.joined()}
    public static func validate(text:String,aliases:[String])throws {
        guard !text.isEmpty,text.utf16.count<=maximumTextUTF16,!text.unicodeScalars.contains(where:{$0.value==0}),aliases.count<=8,
              aliases.allSatisfy({!$0.isEmpty && $0.utf16.count<=128 && !$0.unicodeScalars.contains(where:{CharacterSet.controlCharacters.contains($0)})}) else{throw ExpressionError.limit}
    }
    public static func encode(_ document:ExpressionDocument)throws->Data {
        guard document.revision>0,document.revision<=maximumRevision,document.records.count<=maximumRecords,
              Set(document.records.map{$0.id}).count==document.records.count else{throw ExpressionError.limit}
        for r in document.records {
            guard r.revision>0,r.revision<=document.revision,r.recordCreatedAt>0,r.savedAt==r.recordCreatedAt,r.updatedAt>=r.savedAt else{throw ExpressionError.invalidFormat}
            if let deletion=r.deletedAt {guard r.exactText==nil,r.aliases.isEmpty,deletion==r.updatedAt else{throw ExpressionError.invalidFormat}}
            else{guard let text=r.exactText else{throw ExpressionError.invalidFormat};try validate(text:text,aliases:r.aliases)}
        }
        let payload=try encoder().encode(document),bytes=try encoder().encode(Envelope(format:"paia.expressions.v1",sha256:digest(payload),document:document))
        guard bytes.count<=maximumBytes else{throw ExpressionError.limit};return bytes
    }
    public static func decode(_ bytes:Data)throws->ExpressionDocument {
        guard !bytes.isEmpty,bytes.count<=maximumBytes else{throw ExpressionError.limit}
        guard String(data:bytes,encoding:.utf8) != nil else{throw ExpressionError.invalidFormat}
        var depth=0,quoted=false,escape=false
        for byte in bytes {
            if quoted {if escape{escape=false}else if byte==92{escape=true}else if byte==34{quoted=false};continue}
            if byte==34{quoted=true}else if byte==123 || byte==91{depth+=1;if depth>12{throw ExpressionError.limit}}
            else if byte==125 || byte==93{depth-=1;if depth<0{throw ExpressionError.invalidFormat}}
        }
        guard depth==0,!quoted else{throw ExpressionError.invalidFormat}
        do {let envelope=try JSONDecoder().decode(Envelope.self,from:bytes)
            guard envelope.format=="paia.expressions.v1",try encode(envelope.document)==bytes else{throw ExpressionError.invalidFormat};return envelope.document
        }catch let error as ExpressionError{throw error}catch{throw ExpressionError.invalidFormat}
    }
}
public struct ExpressionRef:Hashable {
    public let catalogEpoch:UUID,recordID:UUID,recordRevision:UInt64,contentDigest:String
}
public struct ExpressionMatch {
    public let ref:ExpressionRef,record:ExpressionRecord
}
// Immutable verified in-memory authority. Searching never reads a store or host.
public struct ExpressionCatalog {
    public let epoch=UUID(),document:ExpressionDocument?
    public init(document:ExpressionDocument?){self.document=document}
    private func key(_ text:String)->String {text.folding(options:[.caseInsensitive,.diacriticInsensitive],locale:Locale(identifier:"en_US_POSIX"))}
    public func search(_ query:String)->[ExpressionMatch] {
        guard query.utf16.count<=256 else{return []};let q=key(query)
        return (document?.records ?? []).filter {r in
            guard r.deletedAt==nil,let text=r.exactText else{return false}
            return q.isEmpty || key(text).contains(q) || r.aliases.contains(where:{key($0).contains(q)})
        }.sorted {a,b in
            let ae=a.aliases.contains(where:{key($0)==q}),be=b.aliases.contains(where:{key($0)==q})
            return ae != be ? ae : (a.savedAt != b.savedAt ? a.savedAt>b.savedAt:a.id.uuidString<b.id.uuidString)
        }.map {r in ExpressionMatch(ref:ExpressionRef(catalogEpoch:epoch,recordID:r.id,recordRevision:r.revision,contentDigest:ExpressionCodec.digest(Data(r.exactText!.utf8))),record:r)}
    }
    public func resolve(_ ref:ExpressionRef)->ExpressionRecord? {
        guard ref.catalogEpoch==epoch,let r=document?.records.first(where:{$0.id==ref.recordID && $0.revision==ref.recordRevision && $0.deletedAt==nil}),
              let text=r.exactText,ExpressionCodec.digest(Data(text.utf8))==ref.contentDigest else{return nil};return r
    }
}
