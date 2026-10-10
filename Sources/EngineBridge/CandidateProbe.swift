import Foundation
import ResourceCore
import LexiconCore
import SessionCore

public struct CandidateProbeReceipt:Codable,Equatable {
    public let format:Int,reference:ResourceReference,schemas:Int,commits:Int,negativePolicies:Int,punctuationCases:Int,personalSamples:Int,g01:Bool,mixed:Bool,deployments:UInt64
    public init(pack:VerifiedCandidatePack,personalSamples:Int){format=1;reference=pack.reference;schemas=pack.manifest.personal==nil ? 32:40;commits=pack.manifest.personal==nil ? 106:98+personalSamples;negativePolicies=pack.manifest.personal==nil ? 24:8;punctuationCases=32;self.personalSamples=personalSamples;g01=true;mixed=true;deployments=0}
}

public enum CandidateNativeProbe {
    private static func reserve(_ session:InputSession,_ effect:CommitEffect?,_ text:String)throws {
        guard let effect=effect,effect.text.utf8.elementsEqual(text.utf8),session.reserve(effect),!session.reserve(effect),try session.refresh().commit==nil else{throw ResourceError.probe}
    }
    private static func type(_ raw:String,_ session:InputSession)throws {
        guard try session.refresh().commit==nil else{throw ResourceError.probe}
        for character in raw {guard try session.process(.text(String(character))).commit==nil else{throw ResourceError.probe}}
    }
    private static func ordinary(_ raw:String,_ text:String,schema:String,runtime:RimeRuntime)throws {
        let session=try runtime.makeSession(schema:schema);defer{session.end()};try type(raw,session)
        for _ in 0..<410 {
            guard let snapshot=session.snapshot else{throw ResourceError.probe}
            if let row=snapshot.rows.first(where:{$0.text.utf8.elementsEqual(text.utf8)}) {
                try reserve(session,session.select(row.ref).commit,text);return
            }
            if !snapshot.hasMore{break};_ = try session.process(.code(0xff56))
        }
        throw ResourceError.probe
    }
    private static func policy(_ raw:String,_ text:String,present:Bool,schema:String,runtime:RimeRuntime)throws {
        let session=try runtime.makeSession(schema:schema,deferredCommit:true);defer{session.end()};try type(raw,session)
        let choices=try session.repairChoices(limit:2048)
        let choice=choices.rows.first{$0.anchor.bytes==(0..<raw.utf8.count) && $0.anchor.text.utf8.elementsEqual(text.utf8)}
        guard choices.complete,(choice != nil)==present else{throw ResourceError.probe}
        if let choice=choice {
            guard try session.selectForRepair(choice).commit==nil else{throw ResourceError.probe}
            try reserve(session,session.commitEngineComposition().commit,text)
        }
    }
    public static func exerciseUpdate(_ snapshot:CandidateResourceSnapshot,preset:CandidatePublicPreset,components:CandidateComponents)throws->CandidateUpdateProbeReceipt {
        try snapshot.verify();try components.verify()
        guard snapshot.pack.manifest.personal==nil else{throw ResourceError.incompatible}
        let runtime=try RimeRuntime(candidate:snapshot,components:components);defer{_ = runtime.close()}
        let schemas=CandidateContract.schemas.filter{$0.hasPrefix("paia_candidate_full_") && !$0.contains("_traditional_")}
        guard schemas.count==8 else{throw ResourceError.incompatible}
        for schema in schemas {
            try policy(CandidateSourcePolicy.updateRaw,CandidateSourcePolicy.updateSurface,present:preset == .updated,schema:schema,runtime:runtime)
            try policy("ni","呢",present:preset == .baseline,schema:schema,runtime:runtime)
        }
        guard runtime.deploymentCalls==0,RimeRuntime.startupAttempts==1 else{throw ResourceError.probe}
        try snapshot.verify();try components.verify()
        return CandidateUpdateProbeReceipt(reference:snapshot.pack.reference,preset:preset)
    }
    public static func exercise(_ snapshot:CandidateResourceSnapshot,components:CandidateComponents,document:LexiconDocument?=nil)throws->CandidateProbeReceipt {
        try snapshot.verify();try components.verify()
        let pack=snapshot.pack,personal=pack.manifest.personal
        if let personal=personal {
            guard let document=document,LexiconCodec.digest(try LexiconCodec.encode(document))==personal.authoritySHA,document.revision==personal.revision else{throw ResourceError.integrity}
        } else if document != nil {throw ResourceError.incompatible}
        let overlays=personal==nil ? Set<String>():Set(CandidateContract.schemas.filter{$0.hasPrefix("paia_candidate_full_") && !$0.contains("_traditional_")})
        let runtime=try RimeRuntime(candidate:snapshot,components:components,repairDisabledSchemas:overlays);defer{_ = runtime.close()}
        for schema in CandidateContract.schemas {
            let full=schema.hasPrefix("paia_candidate_full_"),traditional=schema.contains("_traditional_")
            try ordinary(full ? "shurufa":"uurufa",traditional ? "輸入法":"输入法",schema:schema,runtime:runtime)
            try ordinary(full ? "shijie":schema.hasPrefix("paia_candidate_flypy_") ? "uijp":"uijx","世界",schema:schema,runtime:runtime)
            do {
                let punct=schema.contains("_punct"),session=try runtime.makeSession(schema:schema,chinesePunctuation:punct);defer{session.end()}
                _ = try session.refresh();let result=try session.process(.text(","))
                if punct{try reserve(session,result.commit,"，")}
                else{guard !result.handled,result.commit==nil else{throw ResourceError.probe}}
            }
            if personal==nil {
                try policy(full ? "zongguo":"zsgo",traditional ? "中國":"中国",present:schema.contains("_fuzzy"),schema:schema,runtime:runtime)
                if full{try policy("hzi","知",present:!schema.hasSuffix("_strict"),schema:schema,runtime:runtime)}
            }
        }
        if personal != nil {
            // These eight aliases are selected only after explicit management
            // retires the active personal overlay; verify their real fallback now.
            for schema in CandidateContract.baselineSchemas {
                try ordinary("shurufa","输入法",schema:schema,runtime:runtime)
                try policy("zongguo","中国",present:schema.contains("_fuzzy"),schema:schema,runtime:runtime)
                try policy("hzi","知",present:!schema.hasSuffix("_strict"),schema:schema,runtime:runtime)
            }
        }
        // Use the unchanged authored A1 schema for extension semantics. Both are
        // genuine engine proofs, independent of public/overlay ranking.
        do {
            let session=try runtime.makeSession(deferredCommit:true);defer{session.end()};try type("nihaoshijie",session)
            for word in ["你好","世界"] {
                guard let choice=try session.repairChoices().rows.first(where:{$0.anchor.text==word}),try session.selectForRepair(choice).commit==nil else{throw ResourceError.probe}
            }
            guard let target=try session.repairAnchors().targets.first else{throw ResourceError.probe}
            let proposal=try session.prepareRepair(target:target,replacementRaw:"nihao",surface:"拟好")
            guard try session.applyRepair(proposal).commit==nil else{throw ResourceError.probe}
            try reserve(session,session.commitEngineComposition().commit,"拟好世界")
        }
        do {
            let session=try runtime.makeSession();defer{session.end()};_ = try session.refresh()
            guard let binding=session.idleExpressionBinding else{throw ResourceError.probe}
            _ = try session.beginMixed(binding:binding);_ = try session.process(.text("nihao"))
            guard let row=session.snapshot?.rows.first(where:{$0.text=="你好"}),try session.select(row.ref).commit==nil else{throw ResourceError.probe}
            _ = try session.setMixedLiteralIntent(true);_ = try session.process(.text("RAG👩🏽‍💻"))
            try reserve(session,session.commitEngineComposition().commit,"你好RAG👩🏽‍💻")
        }
        var samples=0
        if let document=document {
            // Bounded smoke for one explicit ordinary/pinned entry in all eight
            // overlay modes; compilation validates every row, not general quality.
            for pin in [false,true] {
                guard let term=document.activeTerms.first(where:{$0.explicitPin==pin}) else{continue}
                for schema in overlays.sorted() {
                    let session=try runtime.makeSession(schema:schema);defer{session.end()}
                    guard !session.canRetainForRepair,!session.canUseMixed else{throw ResourceError.probe}
                    try ordinary(term.reading.replacingOccurrences(of:" ",with:"'"),term.surface,schema:schema,runtime:runtime);samples+=1
                }
            }
        }
        guard runtime.deploymentCalls==0,RimeRuntime.startupAttempts==1,runtime.repairExtensionLoaded,runtime.mixedExtensionLoaded else{throw ResourceError.probe}
        try snapshot.verify();try components.verify()
        return CandidateProbeReceipt(pack:pack,personalSamples:samples)
    }
}

public enum CandidateHelper {
    public static func probeUpdate(_ snapshot:CandidateResourceSnapshot,preset:CandidatePublicPreset,components:CandidateComponents,timeout:TimeInterval=30)throws {
        try snapshot.verify();try components.verify()
        let reference=snapshot.pack.reference
        let args=["candidate-update-probe",snapshot.directory.path,reference.generation,reference.manifestSHA,components.library.path,components.extensionLibrary.path,components.extensionSHA,components.helperSHA,preset.rawValue]
        let output=try ResourceHelper.run(executable:components.helper,arguments:args,home:snapshot.root,timeout:timeout)
        guard try ResourceContract.decode(CandidateUpdateProbeReceipt.self,output)==CandidateUpdateProbeReceipt(reference:reference,preset:preset) else{throw ResourceError.probe}
        try snapshot.verify();try components.verify()
    }
    public static func probe(_ snapshot:CandidateResourceSnapshot,components:CandidateComponents,documentFile:URL?=nil,timeout:TimeInterval=30)throws {
        try snapshot.verify();try components.verify()
        let reference=snapshot.pack.reference
        var args=["candidate-probe",snapshot.directory.path,reference.generation,reference.manifestSHA,components.library.path,components.extensionLibrary.path,components.extensionSHA,components.helperSHA]
        if let file=documentFile{args.append(file.path)}
        let output=try ResourceHelper.run(executable:components.helper,arguments:args,home:snapshot.root,timeout:timeout)
        let receipt=try ResourceContract.decode(CandidateProbeReceipt.self,output)
        guard receipt==CandidateProbeReceipt(pack:snapshot.pack,personalSamples:(snapshot.pack.manifest.personal?.tiers.count ?? 0)*8) else{throw ResourceError.probe}
        try snapshot.verify();try components.verify()
    }
}
