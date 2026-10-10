#if os(macOS)
import AppKit
import SessionCore

@MainActor private final class CandidateContentView:NSView {
    override var isOpaque:Bool {true}
    override func draw(_ dirtyRect:NSRect){NSColor.windowBackgroundColor.setFill();dirtyRect.fill();super.draw(dirtyRect)}
}
@MainActor private final class CandidateDocumentView:NSView {override var isFlipped:Bool {true}}
@MainActor private final class CandidateScrollView:NSScrollView {override var acceptsFirstResponder:Bool {false}}

// The same TextKit layout measures and draws every glyph. Button-cell intrinsic sizing and
// single-line truncation do not participate; the complete title remains the accessibility value.
@MainActor final class CandidateTextLayout {
    let storage:NSTextStorage,manager=NSLayoutManager(),container:NSTextContainer
    init(_ text:NSAttributedString,width:CGFloat) {
        storage=NSTextStorage(attributedString:text)
        container=NSTextContainer(size:NSSize(width:width,height:CGFloat.greatestFiniteMagnitude))
        container.lineFragmentPadding=0;container.maximumNumberOfLines=0;container.lineBreakMode = .byWordWrapping
        storage.addLayoutManager(manager);manager.addTextContainer(container);manager.ensureLayout(for:container)
    }
    var height:CGFloat {ceil(manager.usedRect(for:container).height)}
    var glyphs:NSRange {manager.glyphRange(for:container)}
    func draw(){manager.drawBackground(forGlyphRange:glyphs,at:NSPoint(x:4,y:4));manager.drawGlyphs(forGlyphRange:glyphs,at:NSPoint(x:4,y:4))}
}
@MainActor final class CandidateButton:NSButton {
    let candidate:CandidateRef,textLayout:CandidateTextLayout
    override var isFlipped:Bool {true}
    static func title(_ text:String,selected:Bool)->NSAttributedString {
        let paragraph=NSMutableParagraphStyle();paragraph.lineBreakMode = .byWordWrapping
        return NSAttributedString(string:text,attributes:[.font:NSFont.systemFont(ofSize:16,weight:selected ? .semibold:.regular),.foregroundColor:selected ? NSColor.controlAccentColor:NSColor.labelColor,.paragraphStyle:paragraph])
    }
    init(row:CandidateRow,index:Int,selected:Bool,width:CGFloat,target:AnyObject?,action:Selector?) {
        candidate=row.ref
        let title="\(selected ? "▶" : "  ") \(index+1). \(row.text)",attributed=Self.title(title,selected:selected)
        textLayout=CandidateTextLayout(attributed,width:width-8)
        // Reserve both states so highlighting cannot change row height or panel geometry.
        let selectedLayout=CandidateTextLayout(Self.title("▶ \(index+1). \(row.text)",selected:true),width:width-8)
        let normalLayout=CandidateTextLayout(Self.title("   \(index+1). \(row.text)",selected:false),width:width-8)
        super.init(frame:NSRect(x:0,y:0,width:width,height:max(textLayout.height,selectedLayout.height,normalLayout.height)+8))
        self.title=title;self.attributedTitle=attributed;self.target=target;self.action=action;tag=index
        bezelStyle = .regularSquare;isBordered=false;refusesFirstResponder=true
        font=NSFont.systemFont(ofSize:16,weight:selected ? .semibold:.regular)
        setAccessibilityIdentifier("candidate-row-\(index)")
        setAccessibilityLabel("Candidate \(index+1), \(row.text)");setAccessibilityValue(selected ? "selected":"")
    }
    required init?(coder:NSCoder) {fatalError("not used")}
    override func draw(_ dirtyRect:NSRect) {
        if isHighlighted {NSColor.controlAccentColor.withAlphaComponent(0.12).setFill();bounds.fill()}
        textLayout.draw()
    }
}
@MainActor public final class CandidatePanel:NSPanel {
    public var choose:((CandidateRef)->Void)?
    private struct Presentation:Equatable {
        let refs:[CandidateRef],texts:[String],highlighted:Int,page:Int,more:Bool,screenSize:NSSize
    }
    private var presentation:Presentation?
    public init() {
        super.init(contentRect:NSRect(x:0,y:0,width:420,height:48),styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
        isReleasedWhenClosed=false
        isFloatingPanel=true;level = .floating;hidesOnDeactivate=true;hasShadow=true
        backgroundColor = .windowBackgroundColor
    }
    public override var canBecomeKey:Bool {false}
    public func show(_ snapshot:CandidateSnapshot,below rect:NSRect,screen:NSRect,notice:String?=nil) {
        // A smaller/invalid rectangle cannot honestly show readable text plus status. Hide rather
        // than produce negative geometry or invent a pointer-based anchor. Normal screens scroll.
        guard !snapshot.rows.isEmpty,screen.width>=120,screen.height>=96,rect.width>=0,rect.height>0,
              [screen.minX,screen.minY,screen.maxX,screen.maxY,rect.minX,rect.minY,rect.maxX,rect.maxY].allSatisfy({$0.isFinite}) else {
            presentation=nil;orderOut(nil);return
        }
        let next=Presentation(refs:snapshot.rows.map{$0.ref},texts:snapshot.rows.map{$0.text},highlighted:snapshot.highlighted,page:snapshot.pageIndex,more:snapshot.hasMore,screenSize:screen.size)
        let previousOffset=(contentView?.subviews.compactMap{$0 as? NSScrollView}.first)?.contentView.bounds.origin.y
        let preserveOffset=presentation==next;presentation=next
        let natural=snapshot.rows.enumerated().map{CandidateButton.title("▶ \($0.offset+1). \($0.element.text)",selected:true).size().width+8}.max() ?? 0
        let width=min(screen.width,max(240,min(640,natural+24)))
        let contentWidth=width-24
        let scroll=CandidateScrollView(frame:NSRect(x:12,y:10,width:contentWidth,height:1))
        scroll.borderType = .noBorder;scroll.drawsBackground=false;scroll.scrollerStyle = .legacy
        scroll.hasVerticalScroller=true;scroll.hasHorizontalScroller=false;scroll.autohidesScrollers=false
        scroll.horizontalScrollElasticity = .none;scroll.verticalScrollElasticity = .none
        scroll.setAccessibilityIdentifier("candidate-scroll");scroll.setAccessibilityLabel("Candidate text; scroll to read complete rows")
        scroll.tile()
        // Measure at the actual content width with the legacy scroller reserved. Keep that width
        // even when the scroller is hidden, avoiding width/overflow feedback and clipped glyphs.
        let rowWidth=scroll.contentSize.width
        let document=CandidateDocumentView(frame:.zero);var buttons=[CandidateButton](),top:CGFloat=0
        for (i,row) in snapshot.rows.enumerated() {
            let button=CandidateButton(row:row,index:i,selected:i==snapshot.highlighted,width:rowWidth,target:self,action:#selector(pick(_:)))
            button.frame.origin.y=top;document.addSubview(button);buttons.append(button);top+=button.frame.height+4
        }
        let documentHeight=max(0,top-4)
        func footer(_ overflow:Bool)->NSTextField {
            let text="Page \(snapshot.pageIndex+1) · \(snapshot.hasMore ? "More candidates":"End of candidates")"+(overflow ? "\nScroll to read complete candidates":"")+(notice.map{"\n"+$0} ?? "")
            let label=NSTextField(wrappingLabelWithString:text);label.font = .systemFont(ofSize:12);label.textColor = .secondaryLabelColor
            label.setAccessibilityIdentifier("candidate-page-status");label.setAccessibilityLabel(text)
            let h=ceil(label.attributedStringValue.boundingRect(with:NSSize(width:contentWidth-4,height:10000),options:[.usesLineFragmentOrigin,.usesFontLeading]).height)+4
            label.frame=NSRect(x:12,y:10,width:contentWidth,height:h);return label
        }
        var label=footer(false)
        let overflow=documentHeight+label.frame.height+28>screen.height
        if overflow{label=footer(true)}else{scroll.hasVerticalScroller=false}
        let height=min(screen.height,documentHeight+label.frame.height+28)
        guard height-label.frame.height-28>=24 else{presentation=nil;orderOut(nil);return}
        scroll.frame=NSRect(x:12,y:label.frame.maxY+8,width:contentWidth,height:height-label.frame.height-28)
        document.frame=NSRect(x:0,y:0,width:rowWidth,height:max(documentHeight,scroll.contentSize.height));scroll.documentView=document
        let container=CandidateContentView(frame:NSRect(x:0,y:0,width:width,height:height))
        container.addSubview(scroll);container.addSubview(label);contentView=container
        let x=max(screen.minX,min(rect.minX,screen.maxX-width)),preferred=rect.minY-height-4
        let y=max(screen.minY,min(preferred>=screen.minY ? preferred:rect.maxY+4,screen.maxY-height))
        setFrame(NSRect(x:x,y:y,width:width,height:height),display:true)
        let selected=buttons[snapshot.highlighted]
        if preserveOffset,let offset=previousOffset {
            scroll.contentView.scroll(to:NSPoint(x:0,y:min(max(0,offset),max(0,document.frame.height-scroll.contentSize.height))))
        } else if selected.frame.height>scroll.contentSize.height {
            scroll.contentView.scroll(to:NSPoint(x:0,y:selected.frame.minY))
        } else {document.scrollToVisible(selected.frame)}
        scroll.reflectScrolledClipView(scroll.contentView);orderFront(nil)
    }
    @objc private func pick(_ sender:CandidateButton) {
        // The clicked control retains its snapshot even if a queued click outlives a render.
        choose?(sender.candidate)
    }
    public func showNotice(_ text:String,below rect:NSRect,screen:NSRect) {
        presentation=nil
        guard screen.width>=180,screen.height>=96,rect.width>=0,rect.height>0,
              [screen.minX,screen.minY,screen.maxX,screen.maxY,rect.minX,rect.minY,rect.maxX,rect.maxY].allSatisfy({$0.isFinite}) else{orderOut(nil);return}
        let width=min(560,screen.width),label=NSTextField(wrappingLabelWithString:text)
        label.font = .systemFont(ofSize:13);label.setAccessibilityLabel(text)
        let height=ceil(label.attributedStringValue.boundingRect(with:NSSize(width:width-24,height:10000),options:[.usesLineFragmentOrigin,.usesFontLeading]).height)+24
        guard height<=screen.height else{orderOut(nil);return}
        label.frame=NSRect(x:12,y:12,width:width-24,height:height-24)
        let view=CandidateContentView(frame:NSRect(x:0,y:0,width:width,height:height));view.addSubview(label);contentView=view
        let x=max(screen.minX,min(rect.minX,screen.maxX-width)),y=max(screen.minY,min(rect.minY-height-4,screen.maxY-height))
        setFrame(NSRect(x:x,y:y,width:width,height:height),display:true);orderFront(nil)
    }
}
#endif
