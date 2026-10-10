#if os(macOS)
import AppKit
import InputMethodKit
import TextBoundary
import CIMKContext

// C0 only: read the span written by this activation, never the entire document.
// Object identity is a callback identity, not a claim of stable document identity.
@MainActor public protocol IMKClientAccess:AnyObject {
    var callbackIdentity:AnyObject {get}
    var applicationIdentifier:String? {get}
    func selectedRange()->NSRange
    func markedRange()->NSRange
    func text(in range:NSRange)->String?
    func mark(_ text:String,selection:NSRange,replacing:NSRange)
    func insert(_ text:String,replacing:NSRange)
    func lineRect(at index:Int)->NSRect?
    var offersContext:Bool {get}
    func contextAuthority()->ContextAuthority?
    func contextualLength()->Int?
    func boundedText(in range:NSRange)->BoundedTextRead?
}

// No automatic qualification based on bundle ID, selector presence or successful
// reads. The production controller uses the default nil provider. At present only
// authored test adapters supply a revocable, cost-qualified metadata contract.
public struct ContextAuthority:Equatable {
    public let permissionEpoch:UInt64,documentRevision:UInt64,canRead:Bool,canReplace:Bool,cheapReliableLength:Bool
    public init(permissionEpoch:UInt64,documentRevision:UInt64,canRead:Bool=true,canReplace:Bool=true,cheapReliableLength:Bool=true) {
        self.permissionEpoch=permissionEpoch;self.documentRevision=documentRevision;self.canRead=canRead;self.canReplace=canReplace;self.cheapReliableLength=cheapReliableLength
    }
}
public extension IMKClientAccess {
    var applicationIdentifier:String? {nil}
    var offersContext:Bool {false}
    func contextAuthority()->ContextAuthority? {nil}
    func contextualLength()->Int? {nil}
    func boundedText(in range:NSRange)->BoundedTextRead? {nil}
}
@MainActor public final class IMKTextInputBridge:IMKClientAccess {
    private let input:IMKTextInput
    public var callbackIdentity:AnyObject {input as AnyObject}
    public var applicationIdentifier:String? {input.bundleIdentifier()}
    private let qualifiedContext:(()->ContextAuthority?)?
    public var offersContext:Bool {qualifiedContext != nil}
    public init?(_ sender:Any?,qualifiedContext:(()->ContextAuthority?)?=nil) {
        guard let input=sender as? IMKTextInput else{return nil};self.input=input;self.qualifiedContext=qualifiedContext
    }
    public func contextAuthority()->ContextAuthority? {qualifiedContext?()}
    public func contextualLength()->Int? {
        guard offersContext,let value=PAIAReadIMKLength(input) else{return nil}
        let length=value.intValue;return length>=0 && length<=ContextBudget.document ? length:nil
    }
    public func boundedText(in range:NSRange)->BoundedTextRead? {
        guard offersContext,let value=PAIAReadIMKContext(input,range,UInt(ContextBudget.read)) else{return nil}
        let bytes=Array(value.utf16LE);guard bytes.count%2==0 else{return nil}
        let units=stride(from:0,to:bytes.count,by:2).map{UInt16(bytes[$0]) | (UInt16(bytes[$0+1])<<8)}
        return try? BoundedTextRead(requested:range,actual:value.actualRange,units:units)
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
