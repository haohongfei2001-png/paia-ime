#if os(macOS)
import AppKit

@MainActor private final class RepairPanelRoot:NSView {
    override var isOpaque:Bool {true}
    override func draw(_ dirtyRect:NSRect){NSColor.windowBackgroundColor.setFill();dirtyRect.fill()}
}
@MainActor private final class RepairActionButton:NSButton {
    var invoke:(()->Void)?
    init(_ title:String,_ callback:@escaping()->Void){super.init(frame:.zero);self.title=title;invoke=callback;target=self;action=#selector(run);bezelStyle = .rounded;refusesFirstResponder=true;setAccessibilityLabel(title)}
    required init?(coder:NSCoder){fatalError("Unsupported archive")}
    @objc private func run(){invoke?()}
}
// View-only, with immutable issuing tokens. No host or engine access.
@MainActor public final class SegmentRepairPanel:NSPanel {
    public var search:((UUID)->Void)?,review:((Int,UUID)->Void)?,apply:((UUID)->Void)?,cancel:((UUID)->Void)?
    public private(set) var renderedToken:UUID?,displayedOriginal:String?,displayedPreview:String?
    public let textView=NSTextView(),scroll=NSScrollView()
    public override var canBecomeKey:Bool {false}
    public override var canBecomeMain:Bool {false}
    public init(){
        super.init(contentRect:NSRect(x:0,y:0,width:650,height:490),styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
        isReleasedWhenClosed=false;isFloatingPanel=true;level = .floating;hidesOnDeactivate=true;hasShadow=true;isOpaque=true;backgroundColor = .windowBackgroundColor
        collectionBehavior=[.canJoinAllSpaces,.fullScreenAuxiliary]
    }
    @discardableResult public func show(_ state:SegmentRepairState,below rect:NSRect,screen:NSRect,isCurrent:()->Bool={true})->Bool {
        guard isCurrent(),screen.width>=500,screen.height>=514,screen.intersects(rect),
              [screen.minX,screen.minY,screen.maxX,screen.maxY,rect.minX,rect.minY,rect.maxX,rect.maxY].allSatisfy({$0.isFinite}) else{return false}
        renderedToken=state.token;displayedOriginal=state.original;displayedPreview=state.proposal?.preview
        let width=min(650,screen.width-24),height=min(490,screen.height-24)
        let root=RepairPanelRoot(frame:NSRect(x:0,y:0,width:width,height:height));contentView=root
        func label(_ text:String,_ y:CGFloat,_ h:CGFloat)->NSTextField {
            let view=NSTextField(wrappingLabelWithString:text);view.frame=NSRect(x:16,y:y,width:width-32,height:h);view.setAccessibilityLabel(text);root.addSubview(view);return view
        }
        _=label("Retained segment \(state.target.index+1) · raw bytes \(state.target.anchor.bytes.lowerBound)..<\(state.target.anchor.bytes.upperBound)",height-38,26)
        if let proposal=state.proposal {
            _=label("Review full engine result. Apply changes composition only. Return still inserts spelling.",height-80,38)
            scroll.frame=NSRect(x:16,y:78,width:width-32,height:height-166);scroll.hasVerticalScroller=true;scroll.hasHorizontalScroller=false;scroll.borderType = .bezelBorder
            textView.isEditable=false;textView.isSelectable=false;textView.isRichText=false;textView.font = .systemFont(ofSize:16)
            textView.string="Original confirmed composition\n"+state.original+"\n\nProposed engine composition\n"+proposal.preview
            textView.setAccessibilityLabel("Complete original and proposed engine composition")
            textView.textContainerInset=NSSize(width:8,height:8);textView.isVerticallyResizable=true;textView.isHorizontallyResizable=false;textView.autoresizingMask=[.width]
            textView.frame=NSRect(x:0,y:0,width:scroll.contentSize.width,height:scroll.contentSize.height)
            textView.textContainer?.widthTracksTextView=true;textView.textContainer?.containerSize=NSSize(width:scroll.contentSize.width,height:CGFloat.greatestFiniteMagnitude)
            scroll.documentView=textView;root.addSubview(scroll);textView.sizeToFit();textView.scrollToBeginningOfDocument(nil)
            let button=RepairActionButton("Apply repair to composition"){[weak self] in self?.apply?(state.token)};button.frame=NSRect(x:16,y:26,width:240,height:30);root.addSubview(button)
            _=label("Full text scrolls. Final Chinese commit is a separate input-menu action.",4,18)
        }else{
            let raw=Array(state.replacementRaw.utf8),first=max(0,state.caret-60),last=min(raw.count,state.caret+70)
            let left=String(decoding:raw[first..<state.caret],as:UTF8.self),right=String(decoding:raw[state.caret..<last],as:UTF8.self)
            _=label("Spelling \(state.caret)/\(raw.count): "+(first>0 ? "…":"")+left+"│"+right+(last<raw.count ? "…":""),height-78,34)
            _=label("Type spelling; arrows/edit keys change this draft. Space searches, then 1–5/Space reviews. Option ←/→ changes segment.",height-123,40)
            let rows=state.visibleRows
            for (offset,row) in rows.enumerated(){
                let absolute=state.page*5+offset,title=row.surface.isEmpty ? "Delete this segment":String(row.surface.prefix(90)).replacingOccurrences(of:"\n",with:" ↵ ")
                let button=RepairActionButton((absolute==state.selected ? "▶ ":"")+"\(offset+1). "+title){[weak self] in self?.review?(absolute,state.token)}
                button.alignment = .left;button.cell?.lineBreakMode = .byTruncatingTail;button.frame=NSRect(x:16,y:height-172-CGFloat(offset)*42,width:width-32,height:36);root.addSubview(button)
            }
            let button=RepairActionButton("Search this spelling"){[weak self] in self?.search?(state.token)};button.frame=NSRect(x:16,y:24,width:190,height:30);root.addSubview(button)
            _=label(state.notice ?? "No search yet. Original composition is unchanged.",64,52)
            _=label("Candidate snippets only; choosing opens full review. Page \(state.page+1) · \(state.rows.count) verified rows",4,18)
        }
        let button=RepairActionButton("Cancel repair"){[weak self] in self?.cancel?(state.token)};button.frame=NSRect(x:width-144,y:26,width:128,height:30);root.addSubview(button)
        let x=min(max(screen.minX+8,rect.minX),screen.maxX-width-8),below=rect.minY-height-4
        let y=below>=screen.minY+8 ? below:min(screen.maxY-height-8,rect.maxY+4)
        guard isCurrent(),renderedToken==state.token else{return false};setFrame(NSRect(x:x,y:max(screen.minY+8,y),width:width,height:height),display:true)
        guard isCurrent(),renderedToken==state.token else{return false};orderFrontRegardless()
        guard isCurrent(),renderedToken==state.token else{if renderedToken==state.token{orderOut(nil)};return false}
        return isVisible && !isKeyWindow
    }
    public func scrollReview(_ direction:Int,token:UUID){
        guard renderedToken==token,displayedPreview != nil else{return}
        let clip=scroll.contentView,limit=max(0,textView.bounds.height-clip.bounds.height)
        clip.scroll(to:NSPoint(x:0,y:min(limit,max(0,clip.bounds.minY+CGFloat(direction)*clip.bounds.height*0.8))));scroll.reflectScrolledClipView(clip)
    }
}
#endif
