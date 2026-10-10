#if os(macOS)
import Foundation
import Darwin
import ResourceCore
import SettingsCore
import LexiconCore
import ExpressionCore

@MainActor public final class ProductStores {
    public let root:ProductDataRoot?,settings:SettingsStore?,personal:LexiconStore?,expressions:ExpressionStore?
    public let unavailable:[String]
    private let temporaryParent:URL?
    private let temporaryOwner:ResourceDirectory?
    // Tests/preflight supply an explicit isolated parent or create a new private
    // one. Only the normal service asks for the fixed application-support root.
    public convenience init(parent:URL?){self.init(parent:parent,temporaryParent:nil)}
    private init(parent:URL?,temporaryParent:URL?) {
        self.temporaryParent=temporaryParent
        temporaryOwner=temporaryParent.flatMap{try? ResourceDirectory($0)}
        guard let parent=parent,let root=try? ProductDataRoot(parent:parent,create:true) else {
            self.root=nil;self.settings=nil;self.personal=nil;self.expressions=nil;unavailable=["product data root"];return
        }
        self.root=root
        func settings()throws->SettingsStore {let slot=try root.slot(.settings);return try slot.withDescriptor{try SettingsStore(directory:slot.directory,preopenedDirectory:$0,authorityGuard:{try slot.verify()})}}
        func personal()throws->LexiconStore {let slot=try root.slot(.personal);return try slot.withDescriptor{try LexiconStore(directory:slot.directory,preopenedDirectory:$0,authorityGuard:{try slot.verify()})}}
        func expressions()throws->ExpressionStore {let slot=try root.slot(.expressions);return try slot.withDescriptor{try ExpressionStore(directory:slot.directory,preopenedDirectory:$0,authorityGuard:{try slot.verify()})}}
        self.settings=try? settings();self.personal=try? personal();self.expressions=try? expressions()
        var missing=[String]();if self.settings==nil{missing.append("settings")};if self.personal==nil{missing.append("personal terms")};if self.expressions==nil{missing.append("expressions")};unavailable=missing
    }
    public static func preflight(parent:URL?=nil)throws->ProductStores {
        if let parent=parent{return ProductStores(parent:parent)}
        let temporary=try CandidateProductScratch.create()
        return ProductStores(parent:temporary,temporaryParent:temporary)
    }
    public var status:String {unavailable.isEmpty ? "Private settings, explicit terms and expressions are available; saves remain explicit.":"Unavailable stores: "+unavailable.joined(separator:", ")+". Public input remains available; no lost authority is recreated."}
    public func close(){settings?.close();personal?.close();expressions?.close();root?.close();if let path=temporaryParent,let owner=temporaryOwner,(try? owner.check()) != nil{try? FileManager.default.removeItem(at:path)}}
}
public enum CandidateProductScratch {
    public static func create()throws->URL {
        let value=FileManager.default.temporaryDirectory.appendingPathComponent("paia-product-preflight-"+UUID().uuidString.lowercased())
        try FileManager.default.createDirectory(at:value,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
        guard let path=realpath(value.path,nil) else{try? FileManager.default.removeItem(at:value);throw ResourceError.io};defer{free(path)}
        return URL(fileURLWithPath:String(cString:path),isDirectory:true)
    }
}
#endif
