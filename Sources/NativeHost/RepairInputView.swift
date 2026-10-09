#if os(macOS)
import AppKit

// An explicitly owned text view avoids NSWindow's shared, transient field-editor identity.
@MainActor public final class RepairInputView:NSTextView {
    public var stringValue:String {get{string} set{string=newValue}}
    public init(){
        super.init(frame:NSRect(x:0,y:0,width:300,height:30))
        isRichText=false;isFieldEditor=false;isVerticallyResizable=false;isHorizontallyResizable=false
        font = .systemFont(ofSize:14);drawsBackground=true;backgroundColor = .textBackgroundColor
        textContainerInset=NSSize(width:6,height:5);textContainer?.widthTracksTextView=true
        isAutomaticQuoteSubstitutionEnabled=false;isAutomaticDashSubstitutionEnabled=false
        isAutomaticTextReplacementEnabled=false;isAutomaticSpellingCorrectionEnabled=false
        widthAnchor.constraint(equalToConstant:300).isActive=true
        heightAnchor.constraint(equalToConstant:30).isActive=true
    }
    required init?(coder:NSCoder){fatalError("not used")}
    public override func keyDown(with event:NSEvent){
        // Marked surface input and modified keys stay with the standard text system.
        if event.keyCode==48,!hasMarkedText(),event.modifierFlags.intersection([.command,.option,.control]).isEmpty {
            if event.modifierFlags.contains(.shift){window?.selectPreviousKeyView(self)}
            else{window?.selectNextKeyView(self)}
            return
        }
        super.keyDown(with:event)
    }
}
#endif
