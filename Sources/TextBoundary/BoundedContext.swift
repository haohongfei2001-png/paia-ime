import Foundation

public enum ContextError:Error {case invalidRange,invalidUTF16,unprovenBoundary,stale,unsupported}
// A budget is not Unicode boundary evidence. These are deliberate product limits,
// not a promise to find a reset point by expanding or scanning the document.
public enum ContextBudget {
    public static let selection=1024,before=256,after=128,adjustment=1
    public static let read=selection+before+after+2*adjustment
    public static let document=1_073_741_824
    public static func end(_ range:NSRange)->Int? {
        guard range.location>=0,range.location != NSNotFound,range.length>=0,
              range.length<=Int.max-range.location else{return nil}
        return range.location+range.length
    }
    public static func request(selection:NSRange,length:Int)throws->NSRange {
        guard length>=0,length<=document,let end=end(selection),end<=length,selection.length<=self.selection else{throw ContextError.invalidRange}
        let start=max(0,selection.location-before),stop=end+min(after,length-end)
        return NSRange(location:start,length:stop-start)
    }
}
public struct BoundedTextRead {
    public let requested:NSRange,actual:NSRange,units:[UInt16],text:String
    public init(requested:NSRange,actual:NSRange,units:[UInt16])throws {
        guard let wantedEnd=ContextBudget.end(requested),let actualEnd=ContextBudget.end(actual),
              requested.length<=ContextBudget.read,units.count<=ContextBudget.read,actual.length==units.count,
              actual.location>=max(0,requested.location-ContextBudget.adjustment),
              actualEnd<=wantedEnd+min(ContextBudget.adjustment,Int.max-wantedEnd) else{throw ContextError.invalidRange}
        var index=0
        while index<units.count {
            let unit=units[index]
            if (0xD800...0xDBFF).contains(unit) {
                guard index+1<units.count,(0xDC00...0xDFFF).contains(units[index+1]) else{throw ContextError.invalidUTF16};index+=2
            }else{guard !(0xDC00...0xDFFF).contains(unit) else{throw ContextError.invalidUTF16};index+=1}
        }
        self.requested=requested;self.actual=actual;self.units=units;self.text=String(decoding:units,as:UTF16.self)
    }
    public func exactlyMatches(_ other:Self)->Bool {requested==other.requested && actual==other.actual && units==other.units}
}
// A short, explicitly captured neighborhood, never a stable document identity.
public struct ContextEvidence {
    public let read:BoundedTextRead,selection:NSRange,documentLength:Int,original:String
    private let relative:NSRange,reset:Int
    public init(read:BoundedTextRead,selection:NSRange,documentLength:Int)throws {
        guard let end=ContextBudget.end(selection),let actualEnd=ContextBudget.end(read.actual),
              documentLength>=0,documentLength<=ContextBudget.document,actualEnd<=documentLength,
              selection.length<=ContextBudget.selection,selection.location>=read.actual.location,end<=actualEnd else{throw ContextError.invalidRange}
        let local=NSRange(location:selection.location-read.actual.location,length:selection.length)
        // Only a document start or an observed LF in the retained LEFT prefix
        // resets arbitrarily long Extend/ZWJ/RI histories. Endpoint alone does not.
        let left=Array(read.units.prefix(local.location)),reset:Int
        if let lf=left.lastIndex(of:10){reset=lf+1}
        else if read.actual.location==0{reset=0}
        else{throw ContextError.unprovenBoundary}
        let evidenceText=String(decoding:read.units.dropFirst(reset),as:UTF16.self)
        let localRange=NSRange(location:local.location-reset,length:local.length)
        guard TextBoundary.validGraphemeRange(localRange,in:evidenceText),
              end<actualEnd || actualEnd==documentLength else{throw ContextError.unprovenBoundary}
        self.read=read;self.selection=selection;self.documentLength=documentLength;relative=local;self.reset=reset
        original=String(decoding:read.units[local.location..<(local.location+local.length)],as:UTF16.self)
    }
    public func exactlyMatches(_ other:Self)->Bool {
        selection==other.selection && documentLength==other.documentLength && read.exactlyMatches(other.read)
    }
    public func replacing(with text:String)throws->ContextReplacement {
        guard text.utf16.count<=ContextBudget.selection,!text.unicodeScalars.contains(where:{$0.value==0}),
              !text.isEmpty || selection.length>0 else{throw ContextError.invalidRange}
        var units=read.units;units.replaceSubrange(relative.location..<(relative.location+relative.length),with:text.utf16)
        let evidenceText=String(decoding:units.dropFirst(reset),as:UTF16.self)
        let inserted=NSRange(location:relative.location-reset,length:text.utf16.count)
        guard TextBoundary.validGraphemeRange(inserted,in:evidenceText) else{throw ContextError.unprovenBoundary}
        let delta=text.utf16.count-selection.length,newLength=documentLength+delta
        guard newLength>=0,newLength<=ContextBudget.document else{throw ContextError.invalidRange}
        let actual=NSRange(location:read.actual.location,length:units.count)
        let requested=NSRange(location:read.requested.location,length:read.requested.length+delta)
        guard requested.length>=0 else{throw ContextError.invalidRange}
        // The right neighborhood moves by delta. No old-coordinate readback.
        let expected=try BoundedTextRead(requested:requested,actual:actual,units:units)
        return ContextReplacement(text:text,expected:expected,documentLength:newLength,
            caret:NSRange(location:selection.location+text.utf16.count,length:0))
    }
}
public struct ContextReplacement {
    public let text:String,expected:BoundedTextRead,documentLength:Int,caret:NSRange
}
