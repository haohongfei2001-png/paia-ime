#if os(macOS)
import AppKit

@MainActor private final class ContextPanelRoot:NSView {
    override var isOpaque:Bool {true}
    override func draw(_ dirtyRect:NSRect){NSColor.windowBackgroundColor.setFill();dirtyRect.fill()}
}
@MainActor private final class ContextActionButton:NSButton {
    var invoke:(()->Void)?
    init(_ title:String,_ callback:@escaping()->Void){super.init(frame:.zero);self.title=title;invoke=callback;target=self;action=#selector(run);bezelStyle = .rounded;refusesFirstResponder=true;setAccessibilityLabel(title)}
    required init?(coder:NSCoder){fatalError("Unsupported archive")}
    @objc private func run(){invoke?()}
}
@MainActor public final class ContextEditPanel:NSPanel {
    public var review:((UUID)->Void)?,apply:((UUID)->Void)?,cancel:((UUID)->Void)?
    public private(set) var renderedToken:UUID?,displayedOriginal:String?,displayedReplacement:String?
    public let textView=NSTextView(),scroll=NSScrollView()
    public override var canBecomeKey:Bool {false}
    public override var canBecomeMain:Bool {false}
    public init(){
        super.init(contentRect:NSRect(x:0,y:0,width:650,height:490),styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
        isReleasedWhenClosed=false;isFloatingPanel=true;level = .floating;hidesOnDeactivate=true;hasShadow=true;isOpaque=true;backgroundColor = .windowBackgroundColor
        collectionBehavior=[.canJoinAllSpaces,.fullScreenAuxiliary]
    }
    @discardableResult public func show(_ state:ContextEditState,below rect:NSRect,screen:NSRect,isCurrent:()->Bool={true})->Bool {
        guard isCurrent(),screen.width>=500,screen.height>=514,screen.intersects(rect),
              [screen.minX,screen.minY,screen.maxX,screen.maxY,rect.minX,rect.minY,rect.maxX,rect.maxY].allSatisfy({$0.isFinite}) else{return false}
        renderedToken=state.token;displayedOriginal=state.capture.original;displayedReplacement=state.reviewed ? state.replacement:nil
        let width=min(650,screen.width-24),height=min(490,screen.height-24)
        let root=ContextPanelRoot(frame:NSRect(x:0,y:0,width:width,height:height));contentView=root
        func label(_ text:String,_ y:CGFloat,_ h:CGFloat){let v=NSTextField(wrappingLabelWithString:text);v.frame=NSRect(x:16,y:y,width:width-32,height:h);v.setAccessibilityLabel(text);root.addSubview(v)}
        label(state.capture.kind == .knownCharacter ? "Explicit known Unicode character":"Explicit bounded selection edit",height-38,26)
        let instruction=state.reviewed ? "Review the complete original and replacement. Apply once, or Cancel. Editing revokes this preview.":
            (state.capture.kind == .knownCharacter ? "Type U+ and hexadecimal digits. Return opens review; no character guessing.":"Edit this in-memory draft with literal keys and arrows/delete. Return reviews. This draft does not compose Pinyin.")
        label(instruction,height-88,46)
        scroll.frame=NSRect(x:16,y:94,width:width-32,height:height-188);scroll.hasVerticalScroller=true;scroll.hasHorizontalScroller=false;scroll.borderType = .bezelBorder
        textView.isEditable=false;textView.isSelectable=false;textView.isRichText=false;textView.font = .systemFont(ofSize:16)
        let body:String
        if state.reviewed {
            let detail=state.character.map{"\n\($0.identifier) · \($0.name)\nGlyph availability depends on the current system font."} ?? ""
            body="Complete original selection\n"+state.capture.original+"\n\nComplete replacement\n"+(state.replacement ?? "")+detail
        }else{
            let units=Array(state.draft.utf16),left=String(decoding:units.prefix(state.caret),as:UTF16.self),right=String(decoding:units.dropFirst(state.caret),as:UTF16.self)
            body="Original selection (unchanged)\n"+state.capture.original+"\n\nIn-memory draft · caret \(state.caret) UTF-16\n"+left+"│"+right
        }
        textView.string=body;textView.setAccessibilityLabel("Complete selected original and in-memory edit")
        textView.textContainerInset=NSSize(width:8,height:8);textView.isVerticallyResizable=true;textView.isHorizontallyResizable=false;textView.autoresizingMask=[.width]
        textView.frame=NSRect(x:0,y:0,width:scroll.contentSize.width,height:scroll.contentSize.height)
        textView.textContainer?.widthTracksTextView=true;textView.textContainer?.containerSize=NSSize(width:scroll.contentSize.width,height:CGFloat.greatestFiniteMagnitude)
        scroll.documentView=textView;root.addSubview(scroll);textView.sizeToFit();textView.scrollToBeginningOfDocument(nil)
        let action=ContextActionButton(state.reviewed ? "Apply once":"Review full replacement"){[weak self] in if state.reviewed{self?.apply?(state.token)}else{self?.review?(state.token)}}
        action.frame=NSRect(x:16,y:30,width:220,height:30);action.isEnabled = !state.reviewed || state.capture.canReplace;root.addSubview(action)
        let cancel=ContextActionButton("Cancel"){[weak self] in self?.cancel?(state.token)};cancel.frame=NSRect(x:width-130,y:30,width:114,height:30);root.addSubview(cancel)
        label(state.notice ?? (state.capture.canReplace ? "No clipboard, model call, automatic learning or background context read.":"Read-only qualified capture. This client has no replacement capability."),3,26)
        let x=min(max(screen.minX+8,rect.minX),screen.maxX-width-8),below=rect.minY-height-4
        let y=below>=screen.minY+8 ? below:min(screen.maxY-height-8,rect.maxY+4)
        guard isCurrent(),renderedToken==state.token else{return false};setFrame(NSRect(x:x,y:max(screen.minY+8,y),width:width,height:height),display:true)
        guard isCurrent(),renderedToken==state.token else{return false};orderFrontRegardless()
        guard isCurrent(),renderedToken==state.token else{if renderedToken==state.token{orderOut(nil)};return false}
        return isVisible && !isKeyWindow
    }
    public func scrollReview(_ direction:Int,token:UUID){
        guard renderedToken==token else{return};let clip=scroll.contentView,limit=max(0,textView.bounds.height-clip.bounds.height)
        clip.scroll(to:NSPoint(x:0,y:min(limit,max(0,clip.bounds.minY+CGFloat(direction)*clip.bounds.height*0.8))));scroll.reflectScrolledClipView(clip)
    }
}
#endif
