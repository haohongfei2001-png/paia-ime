import Foundation
import TextBoundary

public enum MixedDraftError:Error {case invalid,limit,stale,requiresReopen,crossOriginGrapheme}
public enum MixedOrigin {
    case spelling, literal
    // A pure value projection of an EngineBridge-issued proof, not a decoder.
    // EngineBridge must own and validate the opaque proof before native replay.
    case engine(surface:String,proof:UUID)
}
public struct MixedSpan:Equatable {
    public let id:UUID,source:String,origin:MixedOrigin
    public init(id:UUID=UUID(),source:String,origin:MixedOrigin){self.id=id;self.source=source;self.origin=origin}
    public var display:String {if case .engine(let text,_)=origin{return text};return source}
    public static func ==(a:Self,b:Self)->Bool {
        guard a.id==b.id,a.source.utf8.elementsEqual(b.source.utf8) else{return false}
        switch(a.origin,b.origin){
        case(.spelling,.spelling),(.literal,.literal):return true
        case(.engine(let x,let p),.engine(let y,let q)):return p==q && x.utf8.elementsEqual(y.utf8)
        default:return false
        }
    }
}
public struct MixedSpanMap {
    public let span:MixedSpan,sourceUTF8:Range<Int>,displayUTF16:NSRange
}
// One bounded draft, to be owned by InputSession. No engine, host effect, disk or
// network. Unresolved spelling remains verbatim; there is no reverse inference
// from Chinese character counts to Pinyin offsets.
public struct MixedDraft:Equatable {
    public static let maximumSourceBytes=4096,maximumSpans=256,maximumDisplayUnits=16384,maximumDisplayBytes=65536
    public private(set) var spans:[MixedSpan],caretUTF8:Int,revision:UInt64=0
    public init(spans:[MixedSpan]=[],caretUTF8:Int=0)throws {
        self.spans=spans;self.caretUTF8=caretUTF8;try validate()
    }
    public var source:String {spans.map(\.source).joined()}
    public var display:String {spans.map(\.display).joined()}
    public var isEmpty:Bool {spans.isEmpty}
    public var isResolved:Bool {!spans.contains{if case .spelling=$0.origin{return true};return false}}
    public var map:[MixedSpanMap] {
        var raw=0,text=0
        return spans.map{span in
            let item=MixedSpanMap(span:span,sourceUTF8:raw..<(raw+span.source.utf8.count),displayUTF16:NSRange(location:text,length:span.display.utf16.count))
            raw+=span.source.utf8.count;text+=span.display.utf16.count;return item
        }
    }
    public var displayCaretUTF16:Int {
        get throws {
            for item in map where item.sourceUTF8.contains(caretUTF8) || caretUTF8==item.sourceUTF8.upperBound {
                let local=caretUTF8-item.sourceUTF8.lowerBound
                if case .engine=item.span.origin {
                    guard local==0 || local==item.span.source.utf8.count else{throw MixedDraftError.requiresReopen}
                    return item.displayUTF16.location+(local==0 ? 0:item.displayUTF16.length)
                }
                return item.displayUTF16.location+(try TextBoundary.utf16Offset(in:item.span.source,utf8:local))
            }
            guard spans.isEmpty && caretUTF8==0 else{throw MixedDraftError.invalid};return 0
        }
    }
    public func validate()throws {
        guard spans.count<=Self.maximumSpans else{throw MixedDraftError.limit}
        var sourceBytes=0,displayUnits=0,displayBytes=0
        for span in spans {
            let bytes=span.source.utf8.count,units=span.display.utf16.count,utf8=span.display.utf8.count
            guard bytes<=Self.maximumSourceBytes-sourceBytes,units<=Self.maximumDisplayUnits-displayUnits,utf8<=Self.maximumDisplayBytes-displayBytes else{throw MixedDraftError.limit}
            sourceBytes+=bytes;displayUnits+=units;displayBytes+=utf8
        }
        var ids=Set<UUID>(),proofs=Set<UUID>()
        for span in spans {
            guard ids.insert(span.id).inserted,!span.source.isEmpty,
                  !span.source.unicodeScalars.contains(where:{$0.value==0}) else{throw MixedDraftError.invalid}
            switch span.origin {
            case .spelling:
                guard span.source.utf8.allSatisfy({(97...122).contains($0) || $0==39}) else{throw MixedDraftError.invalid}
            case .literal:break
            case .engine(let surface,let proof):
                guard !surface.isEmpty,!surface.unicodeScalars.contains(where:{$0.value==0}),
                      span.source.utf8.allSatisfy({(97...122).contains($0) || $0==39}),
                      proofs.insert(proof).inserted else{throw MixedDraftError.invalid}
            }
        }
        _=try TextBoundary.utf16Offset(in:source,utf8:caretUTF8)
        // Cross-origin combining/ZWJ joins have no proven source/display map.
        // Adjacent literals are merged before edits are validated.
        for item in map {
            do {
                _=try TextBoundary.range(in:source,startUTF8:item.sourceUTF8.lowerBound,endUTF8:item.sourceUTF8.upperBound)
                guard TextBoundary.validGraphemeRange(item.displayUTF16,in:display) else{throw MixedDraftError.crossOriginGrapheme}
            }catch{throw MixedDraftError.crossOriginGrapheme}
        }
        _=try displayCaretUTF16
    }
    private func substring(_ text:String,_ bytes:Range<Int>)throws->String {
        let range=try TextBoundary.range(in:text,startUTF8:bytes.lowerBound,endUTF8:bytes.upperBound)
        guard let swift=Range(range,in:text) else{throw MixedDraftError.invalid};return String(text[swift])
    }
    private func checked(_ parts:[MixedSpan],caret:Int)throws->Self {
        guard revision<UInt64.max else{throw MixedDraftError.limit}
        var next=try Self(spans:parts,caretUTF8:caret);next.revision=revision+1;return next
    }
    public func movingCaret(to offset:Int)throws->Self {try checked(spans,caret:offset)}
    public func reopening(_ id:UUID)throws->Self {
        guard let index=spans.firstIndex(where:{$0.id==id}),case .engine=spans[index].origin else{throw MixedDraftError.stale}
        var parts=spans;parts[index]=MixedSpan(source:parts[index].source,origin:.spelling)
        return try checked(normalized(parts),caret:caretUTF8)
    }
    private func normalized(_ input:[MixedSpan])->[MixedSpan] {
        var output=[MixedSpan]()
        for span in input where !span.source.isEmpty {
            if let last=output.last {
                switch(last.origin,span.origin){
                case(.literal,.literal):output.removeLast();output.append(MixedSpan(source:last.source+span.source,origin:.literal));continue
                case(.spelling,.spelling):output.removeLast();output.append(MixedSpan(source:last.source+span.source,origin:.spelling));continue
                default:break
                }
            }
            output.append(span)
        }
        return output
    }
    public func replacing(_ bytes:Range<Int>,with text:String,literal:Bool)throws->Self {
        guard bytes.lowerBound>=0,bytes.upperBound<=source.utf8.count else{throw MixedDraftError.invalid}
        _=try TextBoundary.range(in:source,startUTF8:bytes.lowerBound,endUTF8:bytes.upperBound)
        var before=[MixedSpan](),after=[MixedSpan]()
        for item in map {
            let range=item.sourceUTF8,span=item.span
            if range.upperBound<=bytes.lowerBound{before.append(span);continue}
            if range.lowerBound>=bytes.upperBound{after.append(span);continue}
            let start=max(0,bytes.lowerBound-range.lowerBound),end=min(span.source.utf8.count,bytes.upperBound-range.lowerBound)
            if case .engine=span.origin, start>0 || end<span.source.utf8.count{throw MixedDraftError.requiresReopen}
            if start>0{before.append(MixedSpan(source:try substring(span.source,0..<start),origin:span.origin))}
            if end<span.source.utf8.count{after.append(MixedSpan(source:try substring(span.source,end..<span.source.utf8.count),origin:span.origin))}
        }
        if !text.isEmpty{before.append(MixedSpan(source:text,origin:literal ? .literal:.spelling))}
        // Byte limits are checked before adding offsets, avoiding overflow from a
        // caller-provided huge insertion. Failed edits never publish partial state.
        guard text.utf8.count<=Self.maximumSourceBytes else{throw MixedDraftError.limit}
        return try checked(normalized(before+after),caret:bytes.lowerBound+text.utf8.count)
    }
    public func confirming(_ id:UUID,coverage:Range<Int>,surface:String,proof:UUID)throws->Self {
        guard let index=spans.firstIndex(where:{$0.id==id}),case .spelling=spans[index].origin,
              coverage.lowerBound>=0,!coverage.isEmpty,coverage.upperBound<=spans[index].source.utf8.count else{throw MixedDraftError.stale}
        let span=spans[index],item=map[index];var replacement=[MixedSpan]()
        if coverage.lowerBound>0{replacement.append(MixedSpan(source:try substring(span.source,0..<coverage.lowerBound),origin:.spelling))}
        replacement.append(MixedSpan(source:try substring(span.source,coverage),origin:.engine(surface:surface,proof:proof)))
        if coverage.upperBound<span.source.utf8.count{replacement.append(MixedSpan(source:try substring(span.source,coverage.upperBound..<span.source.utf8.count),origin:.spelling))}
        var parts=spans;parts.replaceSubrange(index...index,with:replacement)
        return try checked(parts,caret:item.sourceUTF8.lowerBound+coverage.upperBound)
    }
}
