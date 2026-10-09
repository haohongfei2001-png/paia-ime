#if os(macOS)
import AppKit
import EngineBridge
import ConstraintCore

@MainActor final class LabStackView:NSStackView {
    override var isOpaque:Bool {true}
    override func draw(_ dirtyRect:NSRect){NSColor.windowBackgroundColor.setFill();dirtyRect.fill();super.draw(dirtyRect)}
}
@MainActor private final class TargetButton:NSButton {
    let binding:RepairTarget,renderID:UUID
    init(_ binding:RepairTarget,renderID:UUID,target:AnyObject,action:Selector){
        self.binding=binding;self.renderID=renderID;super.init(frame:.zero)
        title="\(binding.anchor.text) [\(binding.anchor.bytes.lowerBound)..<\(binding.anchor.bytes.upperBound)]"
        self.target=target;self.action=action;bezelStyle = .rounded
        setAccessibilityLabel("Repair target "+title)
    }
    required init?(coder:NSCoder){fatalError("not used")}
}
@MainActor private final class AcceptButton:NSButton {
    let proposal:RepairProposal
    init(_ proposal:RepairProposal,target:AnyObject,action:Selector){
        self.proposal=proposal;super.init(frame:.zero);title="Accept marked preview";self.target=target;self.action=action
        bezelStyle = .rounded;setAccessibilityLabel(title)
    }
    required init?(coder:NSCoder){fatalError("not used")}
}
@MainActor public final class NativeLabController:NSObject,NSTextViewDelegate {
    public let editor=LabTextView(frame:.zero)
    public let root:NSStackView=LabStackView()
    public let spelling=NSPopUpButton(frame:.zero,pullsDown:false),script=NSPopUpButton(frame:.zero,pullsDown:false)
    public let literal=NSButton(checkboxWithTitle:"Literal text",target:nil,action:nil)
    public let punctuation=NSButton(checkboxWithTitle:"Chinese , ? ! ;",target:nil,action:nil)
    public let hold=NSButton(checkboxWithTitle:"Keep composition for repair",target:nil,action:nil)
    public let commitButton=NSButton(),cancelCompositionButton=NSButton(),repairButton=NSButton()
    public let rawField=RepairInputView(),surfaceField=RepairInputView(),previewButton=NSButton(),cancelRepairButton=NSButton()
    public let status=NSTextField(wrappingLabelWithString:""),previewLabel=NSTextField(wrappingLabelWithString:"")
    public let targetStack=NSStackView(),acceptStack=NSStackView()
    public private(set) var configuration=LabConfiguration()
    public private(set) var isClosed=false
    public var inspectorVisible:Bool {focusLease != nil}
    private let runtime:RimeRuntime
    private let configuredSession:((LabConfiguration)throws->InputSession)?
    private let inspector=NSStackView(),targetScroll=NSScrollView()
    private weak var window:LabWindow?
    private var focusLease:UUID?,selectedTarget:RepairTarget?,proposal:RepairProposal?
    private var previewParameters:(raw:String,surface:String)?
    private var targetRenderID=UUID(),observers=[NSObjectProtocol]()
    private var idleControls=[(control:NSControl,available:()->Bool)]()
    public func registerIdleControl(_ control:NSControl,available:@escaping()->Bool={true}){idleControls.append((control,available));updateControls()}
    public init(runtime:RimeRuntime,configuredSession:((LabConfiguration)throws->InputSession)?=nil) {
        self.runtime=runtime;self.configuredSession=configuredSession;super.init()
        root.orientation = .vertical;root.alignment = .leading;root.spacing=10;root.edgeInsets=NSEdgeInsets(top:16,left:16,bottom:16,right:16)
        spelling.addItems(withTitles:["Full pinyin","Flypy","Natural"]);script.addItems(withTitles:["Simplified","Traditional"])
        spelling.setAccessibilityLabel("Spelling system");script.setAccessibilityLabel("Output script")
        for control:NSControl in [spelling,script,literal,punctuation,hold] {control.target=self;control.action=#selector(changeConfiguration(_:))}
        for control in [literal,punctuation,hold] {control.setAccessibilityLabel(control.title)}
        let settings=NSStackView(views:[spelling,script,literal,punctuation,hold]);settings.spacing=12
        root.addArrangedSubview(settings)
        let note=NSTextField(wrappingLabelWithString:"Research-only native host. The corpus stays in the prepared cache; nothing is registered as a system input source.")
        root.addArrangedSubview(note)
        editor.font = .systemFont(ofSize:22);editor.isRichText=false;editor.setAccessibilityLabel("Composition test document")
        let scroll=NSScrollView();scroll.hasVerticalScroller=true;scroll.borderType = .bezelBorder;scroll.documentView=editor
        editor.frame=NSRect(x:0,y:0,width:900,height:260);editor.autoresizingMask=[.width,.height]
        root.addArrangedSubview(scroll);scroll.heightAnchor.constraint(greaterThanOrEqualToConstant:260).isActive=true
        scroll.widthAnchor.constraint(equalTo:root.widthAnchor,constant:-32).isActive=true
        configure(commitButton,"Commit Chinese",#selector(commitComposition(_:)),refusesFocus:true)
        configure(cancelCompositionButton,"Cancel composition",#selector(cancelComposition(_:)),refusesFocus:true)
        configure(repairButton,"Repair confirmed segment",#selector(beginRepair(_:)),refusesFocus:true)
        commitButton.keyEquivalent="\r";commitButton.keyEquivalentModifierMask=[.control]
        repairButton.keyEquivalent="r";repairButton.keyEquivalentModifierMask=[.control,.option]
        root.addArrangedSubview(NSStackView(views:[commitButton,cancelCompositionButton,repairButton]))
        inspector.orientation = .vertical;inspector.alignment = .leading;inspector.spacing=8;inspector.isHidden=true
        targetStack.orientation = .horizontal;targetStack.spacing=6
        targetScroll.hasHorizontalScroller=true;targetScroll.hasVerticalScroller=false;targetScroll.documentView=targetStack
        targetScroll.heightAnchor.constraint(equalToConstant:52).isActive=true
        inspector.addArrangedSubview(targetScroll)
        rawField.setAccessibilityLabel("Replacement raw spelling");surfaceField.setAccessibilityLabel("Desired engine text")
        rawField.delegate=self;surfaceField.delegate=self
        let rawColumn=NSStackView(views:[NSTextField(labelWithString:"Replacement raw spelling"),rawField])
        let surfaceColumn=NSStackView(views:[NSTextField(labelWithString:"Desired engine text"),surfaceField])
        for column in [rawColumn,surfaceColumn]{column.orientation = .vertical;column.alignment = .leading}
        inspector.addArrangedSubview(NSStackView(views:[rawColumn,surfaceColumn]))
        configure(previewButton,"Preview without committing",#selector(preparePreview(_:)))
        configure(cancelRepairButton,"Cancel repair",#selector(cancelRepair(_:)))
        inspector.addArrangedSubview(NSStackView(views:[previewButton,cancelRepairButton]))
        previewLabel.setAccessibilityLabel("Verified engine preview");inspector.addArrangedSubview(previewLabel);inspector.addArrangedSubview(acceptStack)
        root.addArrangedSubview(inspector);root.addArrangedSubview(status)
        // Activate cross-view constraints only after both views share an ancestor.
        targetScroll.widthAnchor.constraint(equalTo:root.widthAnchor,constant:-32).isActive=true
        status.setAccessibilityLabel("Input status")
        editor.makeSession={ [weak self] in guard let self=self else{return nil};return try? self.newDispatcher() }
        editor.willEdit={ [weak self] in if self?.inspectorVisible==true {self?.dismissInspector(resume:true)} }
        editor.didChangeState={ [weak self] in self?.updateControls() }
        editor.candidates.choose={ [weak self] ref in
            guard let self=self,let host=self.editor.dispatcher,host.isCurrentTarget else{return}
            do {_=host.apply(try host.session.select(ref));self.editor.renderCandidates();self.updateControls()}
            catch {self.status.stringValue="Candidate rejected for the current snapshot.";self.editor.renderCandidates()}
        }
        updateControls()
    }
    deinit {for observer in observers {NotificationCenter.default.removeObserver(observer)}}
    private func configure(_ button:NSButton,_ title:String,_ action:Selector,refusesFocus:Bool=false){
        button.title=title;button.target=self;button.action=action;button.bezelStyle = .rounded;button.refusesFirstResponder=refusesFocus;button.setAccessibilityLabel(title)
    }
    public func attach(to window:LabWindow)throws {
        guard self.window==nil,!isClosed else{throw EngineError.closed}
        self.window=window;window.contentView=root
        guard window.makeFirstResponder(editor) else{throw EngineError.closed}
        editor.dispatcher=try newDispatcher()
        window.beforeFocusChange={ [weak self] responder in
            guard let self=self else{return}
            self.editor.dispatcher?.validateFocusChange(to:responder)
            if self.inspectorVisible && self.editor.dispatcher?.isInspectorSuspended != true {self.dismissInspector(resume:false)}
        }
        window.afterFocusChange={ [weak self,weak window] in
            guard let self=self,self.inspectorVisible,let host=self.editor.dispatcher,
                  host.isInspectorSuspended else{return}
            if !host.permitsInspectorFocus(window?.firstResponder){host.invalidate();self.dismissInspector(resume:false)}
        }
        for (name,object) in [(NSWindow.didResignKeyNotification,window as AnyObject?),(NSWindow.willCloseNotification,window as AnyObject?),(NSApplication.didResignActiveNotification,nil)] {
            observers.append(NotificationCenter.default.addObserver(forName:name,object:object,queue:.main){[weak self] _ in MainActor.assumeIsolated {if name==NSWindow.willCloseNotification{self?.isClosed=true};self?.dismissInspector(resume:false);self?.editor.dispatcher?.invalidate();self?.editor.candidates.orderOut(nil);self?.updateControls()}})
        }
        updateControls()
    }
    private func preparedSession(_ next:LabConfiguration)throws->InputSession {
        let session:InputSession
        if let configuredSession=configuredSession{session=try configuredSession(next)}
        else{session=try runtime.makeSession(schema:next.schema,deferredCommit:next.deferredCommit,chinesePunctuation:next.chinesePunctuation)}
        do {
            let update=try session.refresh()
            guard update.commit==nil,let snapshot=update.snapshot,snapshot.rawASCII.isEmpty,snapshot.preedit.isEmpty else{throw EngineError.closed}
            return session
        }catch{session.end();throw error}
    }
    private func newDispatcher()throws->HostDispatcher {guard !isClosed,!editor.hasMarkedText() else{throw EngineError.closed};return HostDispatcher(client:editor,session:try preparedSession(configuration))}
    public func applyConfiguration(_ next:LabConfiguration)throws {
        guard !isClosed,!hasComposition,!inspectorVisible else{throw EngineError.closed}
        let prepared=try preparedSession(next)
        do{guard window?.makeFirstResponder(editor)==true,!hasComposition else{throw EngineError.closed}}
        catch{prepared.end();throw error}
        // Publish only after successful real-engine preparation and owned-focus restoration.
        editor.dispatcher?.invalidate();editor.candidates.orderOut(nil)
        configuration=next;editor.literalMode=next.literal;editor.dispatcher=HostDispatcher(client:editor,session:prepared)
        reflectConfiguration();status.stringValue="Mode applied for this session. Preferences are not saved automatically.";updateControls()
    }
    private var hasEngineComposition:Bool {guard let s=editor.dispatcher?.session.snapshot else{return false};return !s.rawASCII.isEmpty || !s.preedit.isEmpty}
    public var hasComposition:Bool {editor.hasMarkedText() || hasEngineComposition}
    private func updateControls(){
        let idle = !isClosed && !hasComposition && !inspectorVisible
        for control:NSControl in [spelling,script,literal,punctuation,hold]{control.isEnabled=idle}
        for item in idleControls{item.control.isEnabled=idle && item.available()}
        commitButton.isEnabled=hasEngineComposition && editor.dispatcher?.isCurrentTarget==true && !inspectorVisible
        cancelCompositionButton.isEnabled=hasEngineComposition && editor.dispatcher?.isCurrentTarget==true && !inspectorVisible
        repairButton.isEnabled=hasEngineComposition && editor.dispatcher?.isCurrentTarget==true && configuration.deferredCommit && !inspectorVisible && editor.dispatcher?.session.supportsRepair==true
    }
    @objc private func changeConfiguration(_ sender:NSControl){
        guard !hasComposition,!inspectorVisible else{reflectConfiguration();status.stringValue="Commit or cancel composition before changing modes.";return}
        guard LabSpelling.allCases.indices.contains(spelling.indexOfSelectedItem),(0...1).contains(script.indexOfSelectedItem) else{reflectConfiguration();return}
        var next=configuration
        next.spelling=LabSpelling.allCases[spelling.indexOfSelectedItem];next.traditional=script.indexOfSelectedItem==1
        next.literal=literal.state == .on;next.chinesePunctuation=punctuation.state == .on;next.deferredCommit=hold.state == .on
        do {try applyConfiguration(next);status.stringValue="Mode applied for this session. Preferences are not saved automatically."}
        catch {reflectConfiguration();status.stringValue="Mode change failed. Previous configuration retained; no preference was saved."}
        updateControls()
    }
    private func reflectConfiguration(){
        spelling.selectItem(at:LabSpelling.allCases.firstIndex(of:configuration.spelling)!);script.selectItem(at:configuration.traditional ? 1 : 0)
        literal.state=configuration.literal ? .on:.off;punctuation.state=configuration.chinesePunctuation ? .on:.off;hold.state=configuration.deferredCommit ? .on:.off
    }
    @objc private func commitComposition(_ sender:NSButton){
        guard let host=editor.dispatcher,host.isCurrentTarget,!inspectorVisible else{return}
        do {_=host.apply(try host.session.commitEngineComposition());editor.renderCandidates();updateControls()}catch{status.stringValue="Commit rejected for an invalid session."}
    }
    @objc private func cancelComposition(_ sender:NSButton){
        guard let host=editor.dispatcher,host.isCurrentTarget,!inspectorVisible else{return}
        do {_=host.apply(try host.session.process(.escape));editor.renderCandidates();updateControls()}catch{status.stringValue="Cancellation rejected for an invalid session."}
    }
    @objc private func beginRepair(_ sender:NSButton){
        guard configuration.deferredCommit,let host=editor.dispatcher,host.session.supportsRepair,host.isCurrentTarget,!inspectorVisible else{return}
        do {
            try refreshTargets(preserving:nil);guard selectedTarget != nil else{throw ConstraintError.invalidSpan}
            inspector.isHidden=false;focusLease=host.beginInspector(views:ownedInspectorViews())
            guard focusLease != nil else{throw ConstraintError.stale}
            editor.candidates.orderOut(nil);guard window?.makeFirstResponder(rawField)==true,host.isInspectorSuspended else{throw ConstraintError.stale};status.stringValue="Preview searches real engine paths. The document is unchanged until Accept.";updateControls()
        } catch {dismissInspector(resume:true);status.stringValue=message(error)}
    }
    private func ownedInspectorViews()->[NSView] {[rawField,surfaceField,previewButton,cancelRepairButton]+targetStack.arrangedSubviews+acceptStack.arrangedSubviews}
    private func rebuildInspectorKeyLoop(){
        let views=targetStack.arrangedSubviews+[rawField,surfaceField,previewButton]+acceptStack.arrangedSubviews+[cancelRepairButton]
        for (index,view) in views.enumerated(){view.nextKeyView=views[(index+1)%views.count]}
    }
    private func refreshTargets(preserving old:RawAnchor?)throws {
        guard let host=editor.dispatcher else{throw ConstraintError.stale}
        let targets=try host.session.repairAnchors().targets
        selectedTarget=old == nil ? targets.first : targets.first(where:{$0.anchor==old})
        targetRenderID=UUID();for view in targetStack.arrangedSubviews {targetStack.removeArrangedSubview(view);view.removeFromSuperview()}
        for target in targets {targetStack.addArrangedSubview(TargetButton(target,renderID:targetRenderID,target:self,action:#selector(selectTarget(_:))))}
        rebuildInspectorKeyLoop()
        targetStack.layoutSubtreeIfNeeded();targetStack.setFrameSize(NSSize(width:max(1,targetStack.fittingSize.width),height:32))
        if old==nil,let target=selectedTarget,let raw=host.session.snapshot?.rawASCII {
            rawField.stringValue=String(decoding:Array(raw.utf8)[target.anchor.bytes],as:UTF8.self);surfaceField.stringValue=target.anchor.text
        }
        if let token=focusLease {_=host.updateInspectorViews(token,views:ownedInspectorViews())}
    }
    @objc private func selectTarget(_ sender:TargetButton){
        guard inspectorVisible,sender.renderID==targetRenderID else{return}
        guard let host=editor.dispatcher,host.permitsInspectorFocus(window?.firstResponder),
              sender.binding.lease.matches(host.session.snapshot,revision:runtime.dictionaryRevision,request:sender.binding.lease.request) else{
            editor.dispatcher?.invalidate();dismissInspector(resume:false);return
        }
        discardProposal();selectedTarget=sender.binding
        if let raw=editor.dispatcher?.session.snapshot?.rawASCII {
            rawField.stringValue=String(decoding:Array(raw.utf8)[sender.binding.anchor.bytes],as:UTF8.self);surfaceField.stringValue=sender.binding.anchor.text
        }
    }
    public func textDidChange(_ notification:Notification){discardProposal();status.stringValue="Edit changed. Preview again before accepting."}
    private func discardProposal(){proposal?.cancel();proposal=nil;previewParameters=nil;previewLabel.stringValue="";for view in acceptStack.arrangedSubviews {acceptStack.removeArrangedSubview(view);view.removeFromSuperview()};rebuildInspectorKeyLoop()}
    @objc private func preparePreview(_ sender:NSButton){
        guard let host=editor.dispatcher,let token=focusLease,let target=selectedTarget,host.permitsInspectorFocus(window?.firstResponder) else{editor.dispatcher?.invalidate();dismissInspector(resume:false);return}
        discardProposal()
        guard !rawField.hasMarkedText(),!surfaceField.hasMarkedText() else{status.stringValue="Finish editing the repair inputs before previewing.";return}
        do {
            let p=try host.session.prepareRepair(target:target,replacementRaw:rawField.stringValue,surface:surfaceField.stringValue)
            proposal=p;previewParameters=(rawField.stringValue,surfaceField.stringValue);previewLabel.stringValue=p.preview
            acceptStack.addArrangedSubview(AcceptButton(p,target:self,action:#selector(acceptPreview(_:))))
            try refreshTargets(preserving:target.anchor)
            guard host.updateInspectorViews(token,views:ownedInspectorViews()) else{throw ConstraintError.stale}
            status.stringValue="Verified engine preview. Accept changes marked text only; Commit is separate."
        } catch {discardProposal();status.stringValue=message(error);try? refreshTargets(preserving:target.anchor)}
    }
    @objc private func acceptPreview(_ sender:AcceptButton){
        guard let current=proposal,current===sender.proposal else{return}
        guard let parameters=previewParameters,parameters.raw==rawField.stringValue,parameters.surface==surfaceField.stringValue,
              !rawField.hasMarkedText(),!surfaceField.hasMarkedText() else{discardProposal();status.stringValue="Repair inputs changed; preview again.";return}
        guard let token=focusLease,let host=editor.dispatcher,host.resumeInspector(token) else{
            editor.dispatcher?.invalidate();dismissInspector(resume:false);status.stringValue="Changed target rejected; repair closed.";return
        }
        do {
            let update=try host.session.applyRepair(sender.proposal)
            guard host.apply(update) else{throw ConstraintError.stale}
            dismissInspector(resume:false);editor.renderCandidates();status.stringValue="Marked text updated. Commit Chinese when ready.";updateControls()
        } catch {discardProposal();focusLease=nil;inspector.isHidden=true;status.stringValue=message(error);updateControls()}
    }
    @objc private func cancelRepair(_ sender:NSButton){
        dismissInspector(resume:true)
        status.stringValue=editor.dispatcher?.isCurrentTarget==true ? "Repair cancelled; original composition retained." : "Repair closed after a target change; no commit was made."
    }
    private func dismissInspector(resume:Bool){
        discardProposal();if resume,let token=focusLease {_=editor.dispatcher?.resumeInspector(token)}
        focusLease=nil;selectedTarget=nil;inspector.isHidden=true;updateControls()
    }
    private func message(_ error:Error)->String {
        if case ConstraintError.native(let code,_)=error {
            switch code {case 20:return "Constraint conflict in the emitted paths. Original retained; no automatic unlock."
            case 21:return "Search incomplete at the operation budget. Original retained."
            case 22:return "This segmentation/filter boundary cannot be safely replayed. Original retained."
            default:break}
        }
        return "Repair rejected or stale. No document commit was made."
    }
}
#endif
