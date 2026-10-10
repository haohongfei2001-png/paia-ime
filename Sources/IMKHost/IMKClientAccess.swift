#if os(macOS)
import AppKit
import InputMethodKit

// C0 only: read the span written by this activation, never the entire document.
// Object identity is a callback identity, not a claim of stable document identity.
@MainActor public protocol IMKClientAccess:AnyObject {
    var callbackIdentity:AnyObject {get}
    func selectedRange()->NSRange
    func markedRange()->NSRange
    func text(in range:NSRange)->String?
    func mark(_ text:String,selection:NSRange,replacing:NSRange)
    func insert(_ text:String,replacing:NSRange)
    func lineRect(at index:Int)->NSRect?
}

@MainActor public final class IMKTextInputBridge:IMKClientAccess {
    private let input:IMKTextInput
    public var callbackIdentity:AnyObject {input as AnyObject}
    public init?(_ sender:Any?) {
        guard let input=sender as? IMKTextInput else{return nil};self.input=input
    }
    public func selectedRange()->NSRange {input.selectedRange()}
    public func markedRange()->NSRange {input.markedRange()}
    public func text(in range:NSRange)->String? {
        guard range.location != NSNotFound,range.location>=0,range.length>=0,range.length<=16384,
              range.length<=Int.max-range.location else{return nil}
        guard let value=input.attributedSubstring(from:range),value.length==range.length else{return nil}
        return value.string
    }
    public func mark(_ text:String,selection:NSRange,replacing:NSRange) {
        input.setMarkedText(text,selectionRange:selection,replacementRange:replacing)
    }
    public func insert(_ text:String,replacing:NSRange) {input.insertText(text,replacementRange:replacing)}
    public func lineRect(at index:Int)->NSRect? {
        guard index>=0,index != NSNotFound else{return nil}
        var rect=NSRect.zero
        _=input.attributes(forCharacterIndex:index,lineHeightRectangle:&rect)
        guard [rect.minX,rect.minY,rect.maxX,rect.maxY].allSatisfy({$0.isFinite}),rect.width>=0,rect.height>0 else{return nil}
        return rect
    }
}
#endif
