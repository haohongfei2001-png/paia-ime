#if os(macOS)
import AppKit
import SessionCore

@MainActor private final class CandidateButton:NSButton {
    let candidate:CandidateRef
    init(row:CandidateRow,title:String,target:AnyObject?,action:Selector?) {
        candidate=row.ref
        super.init(frame:.zero)
        self.title=title;self.target=target;self.action=action
    }
    required init?(coder:NSCoder) {fatalError("not used")}
}
@MainActor public final class CandidatePanel: NSPanel {
    private var rows:[CandidateRow]=[]
    public var choose: ((CandidateRef)->Void)?
    public init() {
        super.init(contentRect:NSRect(x:0,y:0,width:420,height:48),styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
        isReleasedWhenClosed=false
        isFloatingPanel=true; level = .floating; hidesOnDeactivate=true; hasShadow=true
        backgroundColor = .windowBackgroundColor
    }
    public override var canBecomeKey: Bool { false }
    public func show(_ snapshot:CandidateSnapshot, below rect:NSRect, screen:NSRect) {
        rows=snapshot.rows
        guard !rows.isEmpty else {orderOut(nil);return}
        let stack=NSStackView(); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing=4
        for (i,row) in rows.enumerated() {
            let button=CandidateButton(row:row,title:"\(i+1). \(row.text)",target:self,action:#selector(pick(_:)))
            button.tag=i; button.bezelStyle = .inline; button.font = .systemFont(ofSize:16)
            button.setAccessibilityLabel("Candidate \(i+1), \(row.text)")
            button.setAccessibilityValue(i==snapshot.highlighted ? "selected" : "")
            stack.addArrangedSubview(button)
        }
        let width=max(240,min(640,stack.fittingSize.width+24)), height=stack.fittingSize.height+20
        stack.frame=NSRect(x:12,y:10,width:width-24,height:height-20)
        let container=NSView(frame:NSRect(x:0,y:0,width:width,height:height));container.addSubview(stack);contentView=container
        let x=max(screen.minX,min(rect.minX,screen.maxX-width))
        let preferred=rect.minY-height-4
        let y=max(screen.minY,min(preferred>=screen.minY ? preferred : rect.maxY+4,screen.maxY-height))
        setFrame(NSRect(x:x,y:y,width:width,height:height),display:true);orderFront(nil)
    }
    @objc private func pick(_ sender:CandidateButton) {
        // The clicked control retains the snapshot it displayed, even if a queued click outlives a render.
        choose?(sender.candidate)
    }
}
#endif
