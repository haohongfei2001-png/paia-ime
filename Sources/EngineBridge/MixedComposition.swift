import Foundation
import CRimeShim
import SessionCore
import TextBoundary

// Internal engine authority. The public pure draft cannot issue Chinese proofs.
// One native owner and one active projection, never a session per source span.
enum MixedValidationPoint:Equatable {case projection,selection,commit,sourceClear}
final class MixedComposition {
    struct Row {let text:String,coverage:Range<Int>,engineIndex:Int}
    struct State {
        let draft:MixedDraft,active:UUID?,projection:UInt64,rows:[Row],complete:Bool,page:Int
        var highlighted:Int=0
    }
    let identity=UUID()
    private let validateResult:(MixedValidationPoint)throws->Void
    private var owner:UInt64=0
    private var proofs=[UUID:UInt64]()
    private(set) var state:State
    var literalIntent=false
    private(set) var sealed=false
    private(set) var unsafeTransition=false
    init(source:UInt64,snapshot:CandidateSnapshot,validateResult:@escaping(MixedValidationPoint)throws->Void={_ in})throws {
        self.validateResult=validateResult
        state=State(draft:try MixedDraft(),active:nil,projection:0,rows:[],complete:true,page:0)
        let rc=paia_rime_mixed_open(source,&owner)
        guard rc==PG_OK,owner != 0 else{throw EngineError.code(rc)}
        do{
            var imported=PaiaMixedImport();let result=paia_rime_mixed_adopt(owner,source,&imported)
            defer{paia_rime_mixed_free_import(&imported)}
            guard result==PG_OK,imported.count<=256,imported.count==0 || imported.anchors != nil else{throw EngineError.code(result)}
            let raw=try string(imported.raw)
            guard raw.utf8.elementsEqual(snapshot.sourceText.utf8),imported.caret_utf8==snapshot.caretUTF8 else{throw MixedDraftError.stale}
            let bytes=Array(raw.utf8);var spans=[MixedSpan](),offset=0
            for index in 0..<Int(imported.count){
                let anchor=imported.anchors![index],end=Int(anchor.end_utf8)
                guard Int(anchor.start_utf8)==offset,end>offset,end<=bytes.count,anchor.proof != 0 else{throw MixedDraftError.invalid}
                let source=String(decoding:bytes[offset..<end],as:UTF8.self),surface=try string(anchor.surface),token=UUID()
                spans.append(MixedSpan(source:source,origin:.engine(surface:surface,proof:token)));proofs[token]=anchor.proof;offset=end
            }
            if offset<bytes.count{spans.append(MixedSpan(source:String(decoding:bytes[offset...],as:UTF8.self),origin:.spelling))}
            let draft=try MixedDraft(spans:spans,caretUTF8:Int(imported.caret_utf8))
            state=try prepared(draft)
        }catch{close();throw error}
    }
    deinit{close()}
    func close(){if owner != 0{paia_rime_mixed_close(owner);owner=0};proofs.removeAll()}
    private func string(_ pointer:UnsafeMutablePointer<CChar>?)throws->String {
        guard let pointer=pointer,let value=String(validatingUTF8:pointer) else{throw EngineError.invalidUTF8};return value
    }
    func prepared(_ draft:MixedDraft,active requested:UUID?=nil)throws->State {
        try draft.validate();guard owner != 0 else{throw EngineError.closed}
        let items=draft.map.filter{if case .spelling=$0.span.origin{return true};return false}
        let active=items.first{$0.span.id==requested} ?? items.first{$0.sourceUTF8.contains(draft.caretUTF8)} ?? items.last{$0.sourceUTF8.upperBound==draft.caretUTF8}
        guard let active=active else{return State(draft:draft,active:nil,projection:0,rows:[],complete:true,page:0)}
        var page=PaiaMixedPage();let rc=active.span.source.withCString{paia_rime_mixed_project(owner,$0,active.span.source.utf8.count,2048,&page)}
        defer{paia_rime_g01_free_list(&page.result)}
        if rc==PG_OK{unsafeTransition=true;try validateResult(.projection)}
        guard rc==PG_OK,page.projection != 0,page.result.count<=64,page.result.count==0 || page.result.items != nil,
              try string(page.result.raw).utf8.elementsEqual(active.span.source.utf8) else{throw EngineError.code(rc)}
        let rows=try (0..<Int(page.result.count)).map{index -> Row in
            let row=page.result.items![index],start=Int(row.start_utf8),end=Int(row.end_utf8)
            guard start==0,end>start,end<=active.span.source.utf8.count,row.index<2048 else{throw MixedDraftError.invalid}
            let text=try string(row.text);guard !text.isEmpty,text.utf16.count<=16384 else{throw MixedDraftError.limit}
            return Row(text:text,coverage:(active.sourceUTF8.lowerBound+start)..<(active.sourceUTF8.lowerBound+end),engineIndex:Int(row.index))
        }
        return State(draft:draft,active:active.span.id,projection:page.projection,rows:rows,complete:page.result.complete != 0,page:0)
    }
    func publish(_ next:State,core:inout SessionCore)throws->SessionUpdate {
        let visible=Array(next.rows.dropFirst(next.page*5).prefix(5))
        let update=try core.receiveMixed(next.draft,owner:identity,span:next.active,projection:next.projection,
            rows:visible.map{MixedCandidateValue(text:$0.text,coverage:$0.coverage)},page:next.page,highlighted:next.highlighted,hasMore:(next.page+1)*5<next.rows.count,complete:next.complete)
        state=next;unsafeTransition=false
        let retained=Set(next.draft.spans.compactMap{span -> UUID? in if case .engine(_,let proof)=span.origin{return proof};return nil})
        for (proof,native) in proofs where !retained.contains(proof){paia_rime_mixed_forget(owner,native);proofs.removeValue(forKey:proof)}
        return update
    }
    func republish(core:inout SessionCore)throws->SessionUpdate {try publish(state,core:&core)}
    func page(_ delta:Int,core:inout SessionCore)throws->SessionUpdate {
        let page=min(max(0,state.page+delta),max(0,(state.rows.count-1)/5))
        let next=State(draft:state.draft,active:state.active,projection:state.projection,rows:state.rows,complete:state.complete,page:page)
        return try publish(next,core:&core)
    }
    func highlight(_ delta:Int,core:inout SessionCore)throws->SessionUpdate {
        let position=min(max(0,state.page*5+state.highlighted+delta),max(0,state.rows.count-1))
        var next=State(draft:state.draft,active:state.active,projection:state.projection,rows:state.rows,complete:state.complete,page:position/5)
        next.highlighted=position%5;return try publish(next,core:&core)
    }
    func select(_ ref:CandidateRef,core:inout SessionCore)throws->SessionUpdate {
        try core.validate(ref);guard let binding=ref.mixed,binding.owner==identity,binding.span==state.active,
              binding.revision==state.draft.revision,binding.projection==state.projection,ref.page==state.page else{throw SessionError.staleCandidate}
        let index=state.page*5+ref.engineIndexOnPage
        guard state.rows.indices.contains(index),let active=state.draft.map.first(where:{$0.span.id==state.active}) else{throw SessionError.staleCandidate}
        let row=state.rows[index];guard row.coverage==binding.coverage else{throw SessionError.staleCandidate}
        let token=UUID()
        // Pure validation precedes native selection, whose projection is consumed.
        let draft=try state.draft.confirming(active.span.id,coverage:0..<row.coverage.count,surface:row.text,proof:token)
        var selected=PaiaMixedSelection();let rc=paia_rime_mixed_select(owner,state.projection,row.engineIndex,&selected)
        defer{paia_rime_mixed_free_selection(&selected)}
        if rc==PG_OK{unsafeTransition=true;try validateResult(.selection)}
        guard rc==PG_OK,selected.proof != 0 else{throw EngineError.code(rc)}
        let native=selected.proof;var adopted=false
        defer{if !adopted{paia_rime_mixed_forget(owner,native)}}
        guard selected.start_utf8==0,Int(selected.end_utf8)==row.coverage.count,
              try string(selected.surface).utf8.elementsEqual(row.text.utf8) else{throw MixedDraftError.invalid}
        let next=try prepared(draft);proofs[token]=native
        let update=try publish(next,core:&core);adopted=true;return update
    }
    func commit()throws->String {
        let draft=state.draft
        guard owner != 0,!draft.isEmpty,draft.isResolved else{throw MixedDraftError.invalid}
        try draft.validate()
        let strings=draft.spans.map{Array($0.source.utf8)+[0]}
        // Every pointer lives through the synchronous owner-serialized call.
        var allocations=[UnsafeMutablePointer<CChar>](),parts=[PaiaMixedPart]()
        defer{for pointer in allocations{pointer.deallocate()}}
        for (index,span) in draft.spans.enumerated(){
            let bytes=strings[index],pointer=UnsafeMutablePointer<CChar>.allocate(capacity:bytes.count)
            for (offset,byte) in bytes.enumerated(){pointer[offset]=CChar(bitPattern:byte)};allocations.append(pointer)
            let native:UInt64
            switch span.origin {
            case .literal:native=0
            case .engine(_,let proof):guard let issued=proofs[proof] else{throw MixedDraftError.stale};native=issued
            case .spelling:throw MixedDraftError.invalid
            }
            parts.append(PaiaMixedPart(source:UnsafePointer(pointer),source_bytes:span.source.utf8.count,proof:native))
        }
        var pointer:UnsafeMutablePointer<CChar>?
        let rc=parts.withUnsafeBufferPointer{paia_rime_mixed_commit(owner,$0.baseAddress,$0.count,2048,&pointer)}
        defer{paia_rime_mixed_free_text(pointer)}
        guard rc==PG_OK else{throw EngineError.code(rc)}
        sealed=true;try validateResult(.commit)
        // This owner is now sealed. A mismatch must retire it, never retry.
        let value=try string(pointer)
        guard value.utf8.elementsEqual(draft.display.utf8) else{throw MixedDraftError.invalid}
        return value
    }
}
