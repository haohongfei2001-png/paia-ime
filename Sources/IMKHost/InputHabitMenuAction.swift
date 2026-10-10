#if os(macOS)
import Foundation
public enum InputHabitActionKind:Equatable {case chinese,literal,characters}
public struct InputHabitMenuAction {
    public let kind:InputHabitActionKind
    let owner:UUID
    let generation:UInt64,activation:UInt64
}
#endif
