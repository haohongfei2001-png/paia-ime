#if os(macOS)
import Foundation
import ResourceCore
import EngineBridge
import SettingsCore
import LexiconCore
import ExpressionCore

struct ProductAuthorityBytes:Equatable {
    let settings:Data?,personal:Data,expressions:Data?
}
// Separate strict orchestration, not the ordinary fail-soft startup initializer.
// Existing validators take locks and flush barriers; they do not create/change
// authority bytes here. These handles remain held through the complete check.
@MainActor final class ExistingProductLease {
    let root:ProductDataRoot,settings:SettingsStore,personal:LexiconStore,expressions:ExpressionStore
    init(parent:URL)throws {
        let root=try ProductDataRoot(parent:parent,create:false)
        var settings:SettingsStore?,personal:LexiconStore?,expressions:ExpressionStore?
        do {
            settings=try ProductStoreFactory.settings(root)
            personal=try ProductStoreFactory.personal(root)
            expressions=try ProductStoreFactory.expressions(root)
            self.root=root;self.settings=settings!;self.personal=personal!;self.expressions=expressions!
        } catch {settings?.close();personal?.close();expressions?.close();root.close();throw error}
    }
    func bytes()throws->ProductAuthorityBytes {
        try root.verify()
        let value=ProductAuthorityBytes(settings:try settings.exportData(),personal:try personal.exportData(),expressions:try expressions.exportData())
        try root.verify();return value
    }
    func close(){settings.close();personal.close();expressions.close();root.close()}
}

public struct ProductStoreReadability:Codable,Equatable {
    public let slot:String,storedFormat:String?,revision:UInt64?
}
public struct ProductCompatibilityReceipt:Codable,Equatable {
    public let format:Int,releaseVersion:String,releaseBuild:String,qualificationBaselineSource:String
    public let publicSourceContract:String,publicReference:ResourceReference,selectionReason:String
    public let stores:[ProductStoreReadability],mainAttempts:Int,authorityBytesChanged:Bool
}

@MainActor public enum ProductCompatibility {
    public static let releaseVersion="0.3.1",releaseBuild="2"
    // Qualification window, not permission to execute arbitrary incoming apps.
    public static let baselineSource="d2f9d62b3d34dba79e958aa1b42e2437691f8d19"
    private struct Header:Decodable {let format:String}
    private static func readability(_ bytes:ProductAuthorityBytes)throws->[ProductStoreReadability] {
        let settings=try bytes.settings.map{try SettingsCodec.decode($0)}
        let personal=try LexiconCodec.decode(bytes.personal)
        let expressions=try bytes.expressions.map{try ExpressionCodec.decode($0)}
        func format(_ data:Data?)throws->String? {try data.map{try JSONDecoder().decode(Header.self,from:$0).format}}
        return [ProductStoreReadability(slot:"settings",storedFormat:try format(bytes.settings),revision:settings?.revision),
                ProductStoreReadability(slot:"personal",storedFormat:try format(bytes.personal),revision:personal.revision),
                ProductStoreReadability(slot:"expressions",storedFormat:try format(bytes.expressions),revision:expressions?.revision)]
    }
    // Explicit existing parent only: no HOME discovery, initial creation, data
    // migration, installation transaction, retry or future compare-and-swap.
    // Private component/snapshot scratch and isolated native helper probes are
    // allowed; no NSApplication, IMKServer or main engine entry is needed.
    public static func assessExisting(parent:URL,bundle:Bundle)throws->ProductCompatibilityReceipt {
        guard RimeRuntime.startupAttempts==0,
              bundle.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String==releaseVersion,
              bundle.object(forInfoDictionaryKey:"CFBundleVersion") as? String==releaseBuild else{throw ResourceError.incompatible}
        let lease=try ExistingProductLease(parent:parent);defer{lease.close()}
        let before=try lease.bytes(),readable=try readability(before)
        let (directory,reference,components)=try CandidateUpdate.bundleInputs(bundle);defer{components.close()}
        let base=try VerifiedCandidatePack(directory:ResourceDirectory(directory),expected:reference)
        let policy=try CandidateSourcePolicy(bundle:base,expectedBundle:reference)
        let catalog=try CandidateUpdate.selectedCatalog(parent:parent)
        let store=try catalog.map{try CandidateResourceStore(directory:$0,policy:policy,create:false)};defer{store?.close()}
        let probe:(CandidateResourceSnapshot,CandidatePublicPreset)throws->Void={snapshot,preset in
            try CandidateHelper.probe(snapshot,components:components,timeout:120)
            try CandidateHelper.probeUpdate(snapshot,preset:preset,components:components)
            guard try lease.bytes()==before else{throw ResourceError.stale}
        }
        let selected:CandidateResourceSelection
        if let store=store {selected=try store.selectForInspection(probe:probe)}
        else {selected=try CandidateUpdate.selectPublic(pack:directory,reference:reference,components:components,catalog:nil,probeOverride:probe)}
        defer{selected.snapshot.close()}
        guard try lease.bytes()==before,try CandidateUpdate.selectedCatalog(parent:parent)==catalog,
              RimeRuntime.startupAttempts==0 else{throw ResourceError.stale}
        try selected.snapshot.verify();try components.verify()
        return ProductCompatibilityReceipt(format:1,releaseVersion:releaseVersion,releaseBuild:releaseBuild,qualificationBaselineSource:baselineSource,
            publicSourceContract:policy.contractSHA,publicReference:selected.snapshot.pack.reference,selectionReason:selected.reason.rawValue,
            stores:readable,mainAttempts:0,authorityBytesChanged:false)
    }
}
#endif
