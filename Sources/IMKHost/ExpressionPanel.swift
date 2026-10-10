#if os(macOS)
import AppKit
import ExpressionCore

@MainActor private final class ExpressionPanelRoot:NSView {
    override var isOpaque:Bool {true}
    override func draw(_ dirtyRect:NSRect){NSColor.windowBackgroundColor.setFill();dirtyRect.fill()}
}
@MainActor private final class ExpressionActionButton:NSButton {
    var invoke:(()->Void)?
    init(_ title:String,action:@escaping()->Void){super.init(frame:.zero);self.title=title;invoke=action;target=self;self.action=#selector(run);bezelStyle = .rounded;refusesFirstResponder=true;setAccessibilityLabel(title)}
    required init?(coder:NSCoder){fatalError("Unsupported archive")}
    @objc private func run(){invoke?()}
}
// Presentation only. Cannot become the key window, read host text, or insert it.
@MainActor public final class ExpressionPanel:NSPanel {
    public var review:((ExpressionRef,UUID)->Void)?,accept:((UUID)->Void)?,cancel:((UUID)->Void)?
    public private(set) var renderedToken:UUID?,displayedExactText:String?
    public let textView=NSTextView(),scroll=NSScrollView()
    public override var canBecomeKey:Bool {false}
    public override var canBecomeMain:Bool {false}
    public init(){
        super.init(contentRect:NSRect(x:0,y:0,width:600,height:430),styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
        isFloatingPanel=true;level = .floating;hidesOnDeactivate=true;hasShadow=true;isOpaque=true;backgroundColor = .windowBackgroundColor
        collectionBehavior=[.canJoinAllSpaces,.fullScreenAuxiliary];isReleasedWhenClosed=false
    }
    @discardableResult public func show(_ state:ExpressionRecallState,below rect:NSRect,screen:NSRect,isCurrent:()->Bool={true})->Bool {
        guard isCurrent(),screen.intersects(rect) else{return false}
        renderedToken=state.token;displayedExactText=state.review?.record.exactText
        let width=min(620,max(300,screen.width-24)),height=min(430,max(220,screen.height-24))
        let root=ExpressionPanelRoot(frame:NSRect(x:0,y:0,width:width,height:height));contentView=root
        func label(_ text:String,_ y:CGFloat,_ h:CGFloat)->NSTextField {
            let view=NSTextField(wrappingLabelWithString:text);view.frame=NSRect(x:16,y:y,width:width-32,height:h);root.addSubview(view);return view
        }
        if let selected=state.review,let text=selected.record.exactText {
            _=label("Review exact saved expression · Return uses once · Escape cancels",height-42,28)
            let record=selected.record,date=Date(timeIntervalSince1970:Double(record.savedAt)/1000),updated=Date(timeIntervalSince1970:Double(record.updatedAt)/1000)
            _=label("Manual save · First saved "+ISO8601DateFormatter().string(from:date)+" · Updated "+ISO8601DateFormatter().string(from:updated)+" · Revision \(record.revision) · Sent: unknown",height-86,40)
            scroll.frame=NSRect(x:16,y:62,width:width-32,height:height-154);scroll.hasVerticalScroller=true;scroll.hasHorizontalScroller=false;scroll.borderType = .bezelBorder
            textView.isEditable=false;textView.isSelectable=false;textView.isRichText=false;textView.font = .systemFont(ofSize:16);textView.string=text
            textView.textContainerInset=NSSize(width:8,height:8);textView.isVerticallyResizable=true;textView.isHorizontallyResizable=false
            textView.autoresizingMask=[.width];textView.frame=NSRect(x:0,y:0,width:scroll.contentSize.width,height:scroll.contentSize.height)
            textView.textContainer?.widthTracksTextView=true;textView.textContainer?.containerSize=NSSize(width:scroll.contentSize.width,height:CGFloat.greatestFiniteMagnitude)
            scroll.documentView=textView;root.addSubview(scroll);textView.sizeToFit();textView.scrollToBeginningOfDocument(nil)
            let use=ExpressionActionButton("Use exact text once"){[weak self] in self?.accept?(state.token)};use.frame=NSRect(x:16,y:18,width:180,height:30);root.addSubview(use)
            _=label("Full text is scrollable. Page Up/Down scrolls; no rewrite or send.",2,16)
        }else{
            _=label("Saved expressions · Type text or your alias · ↑↓ selects · Return reviews",height-44,30)
            _=label("Query: "+state.query,height-80,28)
            let visible=max(1,min(5,Int((height-190)/48))),first=max(0,min(state.selected-visible/2,max(0,state.rows.count-visible))),last=min(state.rows.count,first+visible)
            if first==last{_=label("No matching saved expression.",height-130,28)}
            for index in first..<last {
                let match=state.rows[index],text=match.record.exactText ?? ""
                let title=(index==state.selected ? "▶ ":"")+String(text.prefix(100)).replacingOccurrences(of:"\n",with:" ↵ ")
                let row=ExpressionActionButton(title){[weak self] in self?.review?(match.ref,state.token)}
                row.alignment = .left;row.cell?.lineBreakMode = .byTruncatingTail;row.frame=NSRect(x:16,y:height-132-CGFloat(index-first)*48,width:width-32,height:40);root.addSubview(row)
            }
            _=label("\(state.rows.count) matches. List snippets are previews; review shows the complete original.",52,40)
        }
        let close=ExpressionActionButton("Cancel"){[weak self] in self?.cancel?(state.token)};close.frame=NSRect(x:width-108,y:18,width:92,height:30);root.addSubview(close)
        let x=min(max(screen.minX+8,rect.minX),screen.maxX-width-8)
        let below=rect.minY-height-4,y=below>=screen.minY+8 ? below:min(screen.maxY-height-8,rect.maxY+4)
        guard isCurrent(),renderedToken==state.token else{return false}
        setFrame(NSRect(x:x,y:max(screen.minY+8,y),width:width,height:height),display:true)
        guard isCurrent(),renderedToken==state.token else{return false}
        orderFrontRegardless()
        guard isCurrent(),renderedToken==state.token else{if renderedToken==state.token{orderOut(nil)};return false}
        return isVisible && !isKeyWindow
    }
    public func scrollReview(_ direction:Int,token:UUID){
        guard renderedToken==token,displayedExactText != nil else{return}
        let clip=scroll.contentView,limit=max(0,textView.bounds.height-clip.bounds.height)
        clip.scroll(to:NSPoint(x:0,y:min(limit,max(0,clip.bounds.minY+CGFloat(direction)*clip.bounds.height*0.8))));scroll.reflectScrolledClipView(clip)
    }
}
#endif
