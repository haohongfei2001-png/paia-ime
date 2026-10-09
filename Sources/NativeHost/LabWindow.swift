#if os(macOS)
import AppKit
@MainActor public final class LabWindow:NSWindow {
    public var beforeFocusChange:((NSResponder?)->Void)?
    public var afterFocusChange:(()->Void)?
    public private(set) var primaryFocusRequest:NSResponder?
    public private(set) var focusTransitionDepth=0
    public override func makeFirstResponder(_ responder:NSResponder?)->Bool {
        if focusTransitionDepth==0 {primaryFocusRequest=responder}
        focusTransitionDepth += 1
        beforeFocusChange?(responder)
        let result=super.makeFirstResponder(responder)
        focusTransitionDepth -= 1
        if focusTransitionDepth==0 {afterFocusChange?();primaryFocusRequest=nil}
        return result
    }
}
#endif
