#if os(macOS)
import AppKit
import EngineBridge
import ConstraintCore

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
@MainActor public final class NativeLabController:NSObject,NSTextFieldDelegate {
    public let editor=LabTextView(frame:.zero)
    public let root=NSStackView(),spelling=NSPopUpButton(frame:.zero,pullsDown:false),script=NSPopUpButton(frame:.zero,pullsDown:false)
    public let literal=NSButton(checkboxWithTitle:"Literal text",target:nil,action:nil)
    public let punctuation=NSButton(checkboxWithTitle:"Chinese , ? ! ;",target:nil,action:nil)
    public let hold=NSButton(checkboxWithTitle:"Keep composition for repair",target:nil,action:nil)
    public let commitButton=NSButton(),cancelCompositionButton=NSButton(),repairButton=NSButton()
    public let rawField=NSTextField(),surfaceField=NSTextField(),previewButton=NSButton(),cancelRepairButton=NSButton()
    public let status=NSTextField(wrappingLabelWithString:""),previewLabel=NSTextField(wrappingLabelWithString:"")
    public let targetStack=NSStackView(),acceptStack=NSStackView()
    public private(set) var configuration=LabConfiguration()
    public var inspectorVisible:Bool {focusLease != nil}
    private let runtime:RimeRuntime
    private let inspector=NSStackView(),targetScroll=NSScrollView()
    private weak var window:LabWindow?
    private var focusLease:UUID?,selectedTarget:RepairTarget?,proposal:RepairProposal?
    private var targetRenderID=UUID(),observers=[NSObjectProtocol]()
    public init(runtime:RimeRuntime) {
        self.runtime=runtime;super.init()
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
        rawField.placeholderString="Replacement raw spelling";surfaceField.placeholderString="Desired engine text"
        rawField.setAccessibilityLabel("Replacement raw spelling");surfaceField.setAccessibilityLabel("Desired engine text")
        rawField.delegate=self;surfaceField.delegate=self
        rawField.widthAnchor.constraint(equalToConstant:300).isActive=true;surfaceField.widthAnchor.constraint(equalToConstant:300).isActive=true
        inspector.addArrangedSubview(NSStackView(views:[rawField,surfaceField]))
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
            catch {self.status.stringValue="Stale candidate rejected.";self.editor.candidates.orderOut(nil)}
        }
        updateControls()
    }
    deinit {for observer in observers {NotificationCenter.default.removeObserver(observer)}}
    private func configure(_ button:NSButton,_ title:String,_ action:Selector,refusesFocus:Bool=false){
        button.title=title;button.target=self;button.action=action;button.bezelStyle = .rounded;button.refusesFirstResponder=refusesFocus;button.setAccessibilityLabel(title)
    }
    public func attach(to window:LabWindow)throws {
        self.window=window;window.contentView=root
        guard window.makeFirstResponder(editor) else{throw EngineError.closed}
        editor.dispatcher=try newDispatcher()
        window.beforeFocusChange={ [weak self,weak window] responder in
            guard let self=self,let window=window else{return}
            // AppKit installs its shared field editor before assigning its delegate.
            // Permit that exact nested transition only under an already-approved owned field request.
            if window.focusTransitionDepth>1,let field=window.primaryFocusRequest as? NSTextField,
               self.editor.dispatcher?.permitsInspectorFocus(field)==true,
               let fieldEditor=responder as? NSTextView,fieldEditor.isFieldEditor,
               window.fieldEditor(false,for:field)===fieldEditor {return}
            self.editor.dispatcher?.validateFocusChange(to:responder)
            if self.inspectorVisible && self.editor.dispatcher?.isInspectorSuspended != true {self.dismissInspector(resume:false)}
        }
        window.afterFocusChange={ [weak self,weak window] in
            guard let self=self,self.inspectorVisible,let host=self.editor.dispatcher,
                  host.isInspectorSuspended else{return}
            if !host.permitsInspectorFocus(window?.firstResponder){host.invalidate();self.dismissInspector(resume:false)}
        }
        for (name,object) in [(NSWindow.didResignKeyNotification,window as AnyObject?),(NSWindow.willCloseNotification,window as AnyObject?),(NSApplication.didResignActiveNotification,nil)] {
            observers.append(NotificationCenter.default.addObserver(forName:name,object:object,queue:.main){[weak self] _ in MainActor.assumeIsolated {self?.dismissInspector(resume:false);self?.editor.dispatcher?.invalidate();self?.editor.candidates.orderOut(nil)}})
        }
        updateControls()
    }
    private func newDispatcher()throws->HostDispatcher {
        let session=try runtime.makeSession(schema:configuration.schema,deferredCommit:configuration.deferredCommit,chinesePunctuation:configuration.chinesePunctuation)
        return HostDispatcher(client:editor,session:session)
    }
    public var hasComposition:Bool {guard let s=editor.dispatcher?.session.snapshot else{return false};return !s.rawASCII.isEmpty || !s.preedit.isEmpty}
    private func updateControls(){
        let idle = !hasComposition && !inspectorVisible
        for control:NSControl in [spelling,script,literal,punctuation,hold]{control.isEnabled=idle}
        commitButton.isEnabled=hasComposition && !inspectorVisible
        cancelCompositionButton.isEnabled=hasComposition && !inspectorVisible
        repairButton.isEnabled=hasComposition && configuration.deferredCommit && !inspectorVisible
    }
    @objc private func changeConfiguration(_ sender:NSControl){
        guard !hasComposition,!inspectorVisible else{reflectConfiguration();status.stringValue="Commit or cancel composition before changing modes.";return}
        guard LabSpelling.allCases.indices.contains(spelling.indexOfSelectedItem),(0...1).contains(script.indexOfSelectedItem) else{reflectConfiguration();return}
        var next=configuration
        next.spelling=LabSpelling.allCases[spelling.indexOfSelectedItem];next.traditional=script.indexOfSelectedItem==1
        next.literal=literal.state == .on;next.chinesePunctuation=punctuation.state == .on;next.deferredCommit=hold.state == .on
        editor.dispatcher?.invalidate();configuration=next;editor.literalMode=next.literal
        do {guard window?.makeFirstResponder(editor)==true else{throw EngineError.closed};editor.dispatcher=try newDispatcher();status.stringValue="Mode changed in the isolated native session."}
        catch {status.stringValue="Engine configuration failed; no fallback dictionary loaded."}
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
        guard configuration.deferredCommit,let host=editor.dispatcher,host.isCurrentTarget,!inspectorVisible else{return}
        do {
            try refreshTargets(preserving:nil);guard selectedTarget != nil else{throw ConstraintError.invalidSpan}
            inspector.isHidden=false;focusLease=host.beginInspector(views:ownedInspectorViews())
            guard focusLease != nil else{throw ConstraintError.stale}
            editor.candidates.orderOut(nil);guard window?.makeFirstResponder(rawField)==true,host.isInspectorSuspended else{throw ConstraintError.stale};status.stringValue="Preview searches real engine paths. The document is unchanged until Accept.";updateControls()
        } catch {dismissInspector(resume:true);status.stringValue=message(error)}
    }
    private func ownedInspectorViews()->[NSView] {[rawField,surfaceField,previewButton,cancelRepairButton]+targetStack.arrangedSubviews+acceptStack.arrangedSubviews}
    private func refreshTargets(preserving old:RawAnchor?)throws {
        guard let host=editor.dispatcher else{throw ConstraintError.stale}
        let targets=try host.session.repairAnchors().targets
        selectedTarget=old == nil ? targets.first : targets.first(where:{$0.anchor==old})
        targetRenderID=UUID();for view in targetStack.arrangedSubviews {targetStack.removeArrangedSubview(view);view.removeFromSuperview()}
        for target in targets {targetStack.addArrangedSubview(TargetButton(target,renderID:targetRenderID,target:self,action:#selector(selectTarget(_:))))}
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
    public func controlTextDidChange(_ notification:Notification){discardProposal();status.stringValue="Edit changed. Preview again before accepting."}
    private func discardProposal(){proposal?.cancel();proposal=nil;previewLabel.stringValue="";for view in acceptStack.arrangedSubviews {acceptStack.removeArrangedSubview(view);view.removeFromSuperview()}}
    @objc private func preparePreview(_ sender:NSButton){
        guard let host=editor.dispatcher,let token=focusLease,let target=selectedTarget,host.permitsInspectorFocus(window?.firstResponder) else{editor.dispatcher?.invalidate();dismissInspector(resume:false);return}
        discardProposal()
        do {
            let p=try host.session.prepareRepair(target:target,replacementRaw:rawField.stringValue,surface:surfaceField.stringValue)
            proposal=p;previewLabel.stringValue=p.preview
            acceptStack.addArrangedSubview(AcceptButton(p,target:self,action:#selector(acceptPreview(_:))))
            try refreshTargets(preserving:target.anchor)
            guard host.updateInspectorViews(token,views:ownedInspectorViews()) else{throw ConstraintError.stale}
            status.stringValue="Verified engine preview. Accept changes marked text only; Commit is separate."
        } catch {discardProposal();status.stringValue=message(error);try? refreshTargets(preserving:target.anchor)}
    }
    @objc private func acceptPreview(_ sender:AcceptButton){
        guard let current=proposal,current===sender.proposal else{return}
        guard let token=focusLease,let host=editor.dispatcher,host.resumeInspector(token) else{
            editor.dispatcher?.invalidate();dismissInspector(resume:false);status.stringValue="Changed target rejected; repair closed.";return
        }
        do {
            let update=try host.session.applyRepair(sender.proposal)
            guard host.apply(update) else{throw ConstraintError.stale}
            dismissInspector(resume:false);editor.renderCandidates();status.stringValue="Marked text updated. Commit Chinese when ready.";updateControls()
        } catch {discardProposal();focusLease=nil;inspector.isHidden=true;status.stringValue=message(error);updateControls()}
    }
    @objc private func cancelRepair(_ sender:NSButton){dismissInspector(resume:true);status.stringValue="Repair cancelled; original composition retained."}
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
