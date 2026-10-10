import Foundation

public enum CharacterInputError:Error,Equatable {case invalidInput,unsupportedScalar}
// One explicit, standalone scalar. This is identification/input, not character discovery or
// proof that the current system font has a readable glyph. No trimming or normalization.
public struct KnownCharacter:Equatable {
    public let scalar:Unicode.Scalar
    public var text:String {String(scalar)}
    public var identifier:String {let hex=String(scalar.value,radix:16).uppercased();return "U+"+String(repeating:"0",count:max(0,4-hex.count))+hex}
    public var name:String {scalar.properties.name ?? "NAME UNAVAILABLE"}
    // The explicit scalar must stay a complete grapheme at this caret. Regional
    // indicators, Hangul jamo, or a following combining mark can otherwise join it.
    public func canInsert(at caret:NSRange,in text:String)->Bool {
        guard caret.length==0,TextBoundary.validGraphemeRange(caret,in:text) else{return false}
        let result=(text as NSString).replacingCharacters(in:caret,with:self.text)
        return TextBoundary.validGraphemeRange(NSRange(location:caret.location,length:self.text.utf16.count),in:result)
    }
    public init(_ input:String)throws {
        guard !input.isEmpty,input.utf8.count<=8 else{throw CharacterInputError.invalidInput}
        let bytes=Array(input.utf8),value:Unicode.Scalar
        if bytes.count>=2,(bytes[0]==85 || bytes[0]==117),bytes[1]==43 {
            let digits=bytes.dropFirst(2)
            guard (1...6).contains(digits.count),digits.allSatisfy({(48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0)}),
                  let code=UInt32(String(decoding:digits,as:UTF8.self),radix:16),let parsed=Unicode.Scalar(code) else{throw CharacterInputError.invalidInput}
            value=parsed
        } else {
            guard input.unicodeScalars.count==1,let parsed=input.unicodeScalars.first else{throw CharacterInputError.invalidInput}
            value=parsed
        }
        let allowed:Bool
        switch value.properties.generalCategory {
        case .uppercaseLetter,.lowercaseLetter,.titlecaseLetter,.modifierLetter,.otherLetter,
             .decimalNumber,.letterNumber,.otherNumber,
             .connectorPunctuation,.dashPunctuation,.openPunctuation,.closePunctuation,.initialPunctuation,.finalPunctuation,.otherPunctuation,
             .mathSymbol,.currencySymbol,.modifierSymbol,.otherSymbol:allowed=true
        default:allowed=false
        }
        guard allowed,!value.properties.isDefaultIgnorableCodePoint,!value.properties.isNoncharacterCodePoint,
              !value.properties.isGraphemeExtend,!value.properties.isEmojiModifier,
              value.value != 0x2800,value.value != 0x1D159 else{throw CharacterInputError.unsupportedScalar}
        scalar=value
    }
}
