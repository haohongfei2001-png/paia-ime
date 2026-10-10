import Foundation
import ResourceCore
import LexiconCore

@MainActor public final class CandidateEnvironment {
    public let runtime:RimeRuntime,snapshot:CandidateResourceSnapshot,components:CandidateComponents
    public let personalActive:Bool,personalPreparationFailed:Bool
    public private(set) var pendingRestart=false
    private final class WeakSession {weak var value:InputSession?;init(_ value:InputSession){self.value=value}}
    private var sessions=[WeakSession]()
    // Helper override is a test seam; production always uses the verified bundled
    // helper. All preparation/fallback occurs before the sole main engine entry.
    public init(pack:URL,reference:ResourceReference,components:CandidateComponents,personalStore:LexiconStore?,
                helperRun:((URL,[String],URL,TimeInterval)throws->Data)?=nil,beforeAuthorityCheck:(()throws->Void)?=nil)throws {
        self.components=components;try components.verify()
        let base=try VerifiedCandidatePack(directory:ResourceDirectory(pack),expected:reference)
        let original=try CandidateResourceSnapshot(base)
        var selected=original,active=false,failed=false
        do {
            try CandidateHelper.probe(original,components:components)
            if let store=personalStore {
                do {
                    let bytes=try store.exportData(),document=try LexiconCodec.decode(bytes)
                    if !document.activeTerms.isEmpty {
                        let binding=try CandidateCompiler.binding(base:base,document:document)
                        let root=try CandidateCompiler.scratch();defer{try? FileManager.default.removeItem(at:root)}
                        let owner=try ResourceDirectory(root),input=root.appendingPathComponent("lexicon-snapshot.json"),output=root.appendingPathComponent("derived")
                        try owner.writeExclusive(input.lastPathComponent,bytes);try owner.sync()
                        let run=helperRun ?? {try ResourceHelper.run(executable:$0,arguments:$1,home:$2,timeout:$3)}
                        let receipt=try run(components.helper,["candidate-personal",original.directory.path,base.reference.generation,base.reference.manifestSHA,input.path,output.path,components.library.path],root,120)
                        let reference=try ResourceContract.decode(ResourceReference.self,receipt)
                        let derived=try VerifiedCandidatePack(directory:ResourceDirectory(output),expected:reference,personal:binding)
                        try derived.validateDerived(from:base,binding:binding)
                        let candidate=try CandidateResourceSnapshot(derived)
                        do {
                            try CandidateHelper.probe(candidate,components:components,documentFile:input,timeout:120)
                            try beforeAuthorityCheck?()
                            guard try store.exportData()==bytes else{throw ResourceError.stale}
                            try original.verify();try candidate.verify();try components.verify()
                            selected=candidate;active=true
                        } catch {candidate.close();throw error}
                    } else {try beforeAuthorityCheck?();guard try store.exportData()==bytes else{throw ResourceError.stale}}
                } catch {failed=true} // No stale derived pack, authority write, retry, or second main runtime.
            }
            try selected.verify();try components.verify()
            let disabled=active ? Set(CandidateContract.schemas.filter{$0.hasPrefix("paia_candidate_full_") && !$0.contains("_traditional_")}):Set<String>()
            let chosen=selected
            runtime=try RimeRuntime(candidate:chosen,components:components,repairDisabledSchemas:disabled,cleanup:{chosen.close();components.close()})
            snapshot=chosen;personalActive=active;personalPreparationFailed=failed
            if selected !== original{original.close()}
        } catch {selected.close();original.close();components.close();throw error}
    }
    public func disableOverlayUntilRestart(){pendingRestart=true;for session in sessions{session.value?.end()};sessions=[]}
    public func makeSession(configuration:LabConfiguration)throws->InputSession {
        var schema=configuration.schema.replacingOccurrences(of:"paia_b1_",with:"paia_candidate_")
        if personalActive && pendingRestart && configuration.spelling == .full && !configuration.traditional {
            schema=PersonalSchemaProfile.candidate.baselineSchema(punctuation:configuration.chinesePunctuation,fuzzy:configuration.fuzzyInitials,correction:configuration.fullPinyinCorrection)
        }
        let session=try runtime.makeSession(schema:schema,deferredCommit:configuration.deferredCommit,chinesePunctuation:configuration.chinesePunctuation)
        sessions.removeAll{$0.value==nil};sessions.append(WeakSession(session));return session
    }
    public var status:String {
        let personal=personalPreparationFailed ? "Personal preparation refused; public authored resources selected without restoring older terms.":personalActive ? "Explicit personal Full/Simplified snapshot active; its repair/mixed mode is unavailable.":"Public authored snapshot; no personal overlay."
        return "Integrated offline candidate: 32 spelling/script/punctuation policies, G01 and mixed native components. 46 authored rows, not a daily-use language model. "+personal
    }
}
