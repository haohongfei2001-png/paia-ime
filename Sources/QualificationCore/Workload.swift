import Foundation

// Authored endurance schedule, not a language-quality test set. No input data,
// network, engine or million-element event array lives in this pure generator.
public struct QualificationSchedule {
    public static let seed:UInt64=0x5041494132303236
    public static let minimumEvents=1_000_000
    public static let calibrationEvents=10_000
    public private(set) var episode=0
    private var order=Array(0..<8)
    private var state:UInt64
    public init(seed:UInt64=Self.seed){precondition(seed != 0);state=seed}
    public mutating func next()->(schema:Int,scenario:Int) {
        if episode%8==0 {
            order=Array(0..<8)
            for index in stride(from:7,through:1,by:-1) {
                state ^= state << 13;state ^= state >> 7;state ^= state << 17
                order.swapAt(index,Int(state%UInt64(index+1)))
            }
        }
        let result=(schema:(episode/8)%32,scenario:order[episode%8]);episode+=1;return result
    }
}

// Explicit little-endian fixed-width records; only one bounded block in the
// measured process. Analysis/percentiles run in the supervisor after shutdown.
public struct QualificationTimingRecord:Equatable {
    public static let bytes=32
    public let operation,owner,nativeAction,contextCopy:UInt64
    public init(operation:UInt64,owner:UInt64,nativeAction:UInt64,contextCopy:UInt64){self.operation=operation;self.owner=owner;self.nativeAction=nativeAction;self.contextCopy=contextCopy}
    public var data:Data {
        var result=Data();result.reserveCapacity(Self.bytes)
        for value in [operation,owner,nativeAction,contextCopy] {var little=value.littleEndian;withUnsafeBytes(of:&little){result.append(contentsOf:$0)}}
        return result
    }
}
