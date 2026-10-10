#if os(macOS)
import Foundation
import SessionCore
public enum MixedActionKind:Equatable {case begin,literal,spelling,commit,reopen}
public struct MixedMenuAction {
    public let kind:MixedActionKind
    let driverGeneration:UInt64,activation:UInt64,session:SessionKey,inputGeneration:UInt64,span:UUID?
}
#endif
