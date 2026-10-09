#if os(macOS)
import AppKit
@MainActor public final class LabWindow:NSWindow {
    public var beforeFocusChange:((NSResponder?)->Void)?
    public override func makeFirstResponder(_ responder:NSResponder?)->Bool {
        beforeFocusChange?(responder)
        return super.makeFirstResponder(responder)
    }
}
#endif
