import Foundation
import SessionCore
import TextBoundary

public struct RepairLease: Hashable {
    public let session: SessionKey, targetEpoch: UInt64, generation: UInt64, privacyEpoch: UInt64
    public let revision: String, raw: String, request: UInt64
    public init(snapshot: CandidateSnapshot, revision: String, request: UInt64) {
        session=snapshot.session; targetEpoch=snapshot.targetEpoch; generation=snapshot.inputGeneration
        privacyEpoch=snapshot.privacyEpoch; raw=snapshot.rawASCII; self.revision=revision; self.request=request
    }
    public func matches(_ snapshot: CandidateSnapshot?, revision: String, request: UInt64) -> Bool {
        guard let s=snapshot else{return false}
        return session==s.session && targetEpoch==s.targetEpoch && generation==s.inputGeneration &&
          privacyEpoch==s.privacyEpoch && raw==s.rawASCII && self.revision==revision && self.request==request
    }
}
public enum ConstraintError: Error {case stale, invalidSpan, consumed, native(code:Int32,examined:Int)}
public struct RawAnchor: Equatable {
    public let bytes: Range<Int>, text: String, engineIndex: Int
    public init(bytes:Range<Int>,text:String,engineIndex:Int){self.bytes=bytes;self.text=text;self.engineIndex=engineIndex}
    public func validate(in raw:String) throws {
        guard !bytes.isEmpty,bytes.lowerBound>=0,bytes.upperBound<=raw.utf8.count else{throw ConstraintError.invalidSpan}
        _ = try TextBoundary.range(in:raw,startUTF8:bytes.lowerBound,endUTF8:bytes.upperBound)
    }
}
public struct RepairChoice {
    public let lease:RepairLease, anchor:RawAnchor
    public init(lease:RepairLease,anchor:RawAnchor){self.lease=lease;self.anchor=anchor}
}
