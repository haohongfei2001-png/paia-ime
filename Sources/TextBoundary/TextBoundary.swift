import Foundation

public enum BoundaryError: Error { case invalidUTF8, invalidOffset, splitGrapheme }
public enum TextBoundary {
    // librime uses UTF-8 offsets; AppKit uses UTF-16 units. Neither is String.count.
    public static func utf16Offset(in text: String, utf8 offset: Int, requireGrapheme: Bool = true) throws -> Int {
        guard offset >= 0, offset <= text.utf8.count else { throw BoundaryError.invalidOffset }
        let byte = text.utf8.index(text.utf8.startIndex, offsetBy: offset)
        guard let index = String.Index(byte, within: text) else { throw BoundaryError.invalidOffset }
        if requireGrapheme && index != text.endIndex && !text.indices.contains(index) { throw BoundaryError.splitGrapheme }
        return index.utf16Offset(in: text)
    }
    public static func range(in text: String, startUTF8: Int, endUTF8: Int) throws -> NSRange {
        let start = try utf16Offset(in: text, utf8: startUTF8)
        let end = try utf16Offset(in: text, utf8: endUTF8)
        guard end >= start else { throw BoundaryError.invalidOffset }
        return NSRange(location: start, length: end-start)
    }
    public static func validGraphemeRange(_ range: NSRange, in text: String) -> Bool {
        guard range.location != NSNotFound, range.location >= 0, range.length >= 0,
              range.location <= text.utf16.count, range.length <= text.utf16.count-range.location,
              let swiftRange = Range(range, in: text) else { return false }
        let boundaries = Set(text.indices).union([text.endIndex])
        return boundaries.contains(swiftRange.lowerBound) && boundaries.contains(swiftRange.upperBound)
    }
}
