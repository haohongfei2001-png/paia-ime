#if os(macOS)
import AppKit
import SessionCore
import TextBoundary

public enum ContextEditKind {case knownCharacter,selectedText}
public struct ContextCapture {
    public let token:UUID,original:String,selection:NSRange,kind:ContextEditKind,canReplace:Bool
    let binding:ExpressionBinding,authority:ContextAuthority,evidence:ContextEvidence,rect:NSRect
}
public struct ContextMenuAction {
    let generation:UInt64,activation:UInt64,identity:ObjectIdentifier,kind:ContextEditKind
}
// The editor owns only a bounded in-memory draft. It is not another IME engine or
// an editable key window; injected Unicode events do not prove Chinese key input.
public struct ContextEditState {
    public let token:UUID,capture:ContextCapture,draft:String,caret:Int,reviewed:Bool,notice:String?
    public var replacement:String? {
        if capture.kind == .knownCharacter{return (try? KnownCharacter(draft))?.text}
        return draft
    }
    public var character:KnownCharacter? {capture.kind == .knownCharacter ? try? KnownCharacter(draft):nil}
    init(capture:ContextCapture,draft:String?=nil,caret:Int?=nil,reviewed:Bool=false,notice:String?=nil) {
        token=UUID();self.capture=capture;self.draft=draft ?? (capture.kind == .selectedText ? capture.original:"")
        self.caret=caret ?? self.draft.utf16.count;self.reviewed=reviewed;self.notice=notice
    }
    func editing(code:UInt16,text:String)->Self? {
        guard !reviewed,TextBoundary.validGraphemeRange(NSRange(location:caret,length:0),in:draft) else{return nil}
        let boundaries=draft.indices.map{$0.utf16Offset(in:draft)}+[draft.utf16.count]
        guard let position=boundaries.firstIndex(of:caret) else{return nil}
        var next=draft,offset=caret
        switch code {
        case 123:offset=boundaries[max(0,position-1)]
        case 124:offset=boundaries[min(boundaries.count-1,position+1)]
        case 115:offset=0
        case 119:offset=draft.utf16.count
        case 51:
            if position>0{let start=boundaries[position-1];next=(draft as NSString).replacingCharacters(in:NSRange(location:start,length:caret-start),with:"");offset=start}
        case 117:
            if position+1<boundaries.count{next=(draft as NSString).replacingCharacters(in:NSRange(location:caret,length:boundaries[position+1]-caret),with:"")}
        case 48,125,126,116,121:return nil
        default:
            guard !text.isEmpty,!text.unicodeScalars.contains(where:{CharacterSet.controlCharacters.contains($0) || (0xF700...0xF8FF).contains($0.value)}) else{return nil}
            if capture.kind == .knownCharacter {
                guard text.utf8.allSatisfy({(48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) || $0==85 || $0==117 || $0==43}) else{return nil}
            }
            next=(draft as NSString).replacingCharacters(in:NSRange(location:caret,length:0),with:text);offset+=text.utf16.count
        }
        let limit=capture.kind == .knownCharacter ? 8:ContextBudget.selection
        guard next.utf16.count<=limit else{return nil}
        // Typing a combining scalar can merge neighboring graphemes. Move to the
        // next real boundary rather than leave an invalid UTF-16 editing caret.
        let nextBoundaries=next.indices.map{$0.utf16Offset(in:next)}+[next.utf16.count]
        offset=nextBoundaries.first(where:{$0>=offset}) ?? next.utf16.count
        return Self(capture:capture,draft:next,caret:offset)
    }
}
#endif
