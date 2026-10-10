#if os(macOS)
import AppKit
import EngineBridge
import NativeHost
import SettingsCore

// Explicit management UI, never a second input dispatcher or document editor.
@MainActor public final class IMKPreferencesController:NSObject,SettingsTarget,NSWindowDelegate {
    public let root=NSStackView()
    public let spelling=NSPopUpButton(frame:.zero,pullsDown:false),script=NSPopUpButton(frame:.zero,pullsDown:false)
    public let literal=NSButton(checkboxWithTitle:"Literal text",target:nil,action:nil)
    public let punctuation=NSButton(checkboxWithTitle:"Chinese , ? ! ;",target:nil,action:nil)
    public let termsButton=NSButton(),status=NSTextField(wrappingLabelWithString:"")
    public private(set) var settings:SettingsController!
    public private(set) var isClosed=false
    public var hasComposition:Bool {!workspace.isIdle}
    public var inspectorVisible:Bool {false}
    public var configuration:LabConfiguration {workspace.configuration}
    public let workspace:IMKWorkspace
    private var controls=[(NSControl,()->Bool)](),window:NSWindow?,termWindow:NSWindow?
    public private(set) var terms:PersonalLexiconController?
    public init(workspace:IMKWorkspace){
        self.workspace=workspace;super.init()
        root.orientation = .vertical;root.alignment = .leading;root.spacing=12;root.edgeInsets=NSEdgeInsets(top:20,left:20,bottom:20,right:20)
        root.addArrangedSubview(NSTextField(wrappingLabelWithString:workspace.resourceDescription))
        spelling.addItems(withTitles:["Full pinyin","Flypy","Natural"]);script.addItems(withTitles:["Simplified","Traditional"])
        spelling.setAccessibilityLabel("Spelling system");script.setAccessibilityLabel("Output script")
        root.addArrangedSubview(NSStackView(views:[spelling,script,literal,punctuation]))
        for control:NSControl in [spelling,script,literal,punctuation]{control.target=self;control.action=#selector(changeConfiguration(_:));registerIdleControl(control,available:{true})}
        for button in [literal,punctuation]{button.setAccessibilityLabel(button.title)}
        root.addArrangedSubview(NSTextField(wrappingLabelWithString:"Space chooses the real candidate; Return keeps spelling and is consumed. Modes change only when every input client is idle. No automatic learning or preference save."))
        settings=SettingsController(lab:self,store:workspace.settingsStore)
        termsButton.title="Manage explicit personal terms…";termsButton.target=self;termsButton.action=#selector(openTerms(_:));termsButton.bezelStyle = .rounded;termsButton.setAccessibilityLabel(termsButton.title)
        root.addArrangedSubview(termsButton);root.addArrangedSubview(status)
        registerIdleControl(termsButton,available:{[weak self] in self?.workspace.personalStore != nil})
        settings.restoreAtStartup();reflect()
    }
    public func registerIdleControl(_ control:NSControl,available:@escaping()->Bool){controls.append((control,available));refreshControls()}
    public func withSettingsAccess<T>(_ operation:()throws->T)throws->T {
        guard !isClosed else{throw IMKManagementError.unavailable};return try workspace.withIdleAccess(operation)
    }
    public func applyConfiguration(_ next:LabConfiguration)throws {
        guard !isClosed else{throw IMKManagementError.unavailable}
        try workspace.applyConfiguration(next);reflect()
    }
    public func refreshControls(){for (control,available) in controls{control.isEnabled = !isClosed && workspace.isIdle && available()}}
    private func reflect(){
        spelling.selectItem(at:LabSpelling.allCases.firstIndex(of:configuration.spelling)!);script.selectItem(at:configuration.traditional ? 1:0)
        literal.state=configuration.literal ? .on:.off;punctuation.state=configuration.chinesePunctuation ? .on:.off;refreshControls()
    }
    @objc private func changeConfiguration(_ sender:NSControl){
        guard !isClosed,LabSpelling.allCases.indices.contains(spelling.indexOfSelectedItem),(0...1).contains(script.indexOfSelectedItem) else{return}
        var next=configuration;next.spelling=LabSpelling.allCases[spelling.indexOfSelectedItem];next.traditional=script.indexOfSelectedItem==1
        next.literal=literal.state == .on;next.chinesePunctuation=punctuation.state == .on
        do{try applyConfiguration(next);status.stringValue="Session mode changed. Save explicitly to keep these preferences."}
        catch{reflect();status.stringValue="Mode unavailable or another client is busy. Previous configuration retained; no text committed."}
    }
    public func show(){
        guard workspace.isIdle else{status.stringValue="Finish every composition before opening settings.";return}
        isClosed=false
        if window==nil {
            let w=NSWindow(contentRect:NSRect(x:120,y:180,width:860,height:340),styleMask:[.titled,.closable],backing:.buffered,defer:false)
            w.isReleasedWhenClosed=false;w.title="PAIA input settings · Explicit storage";w.contentView=root;w.delegate=self;window=w
        }
        reflect();window?.makeKeyAndOrderFront(nil)
    }
    public func windowDidBecomeKey(_ notification:Notification){reflect()}
    public func windowWillClose(_ notification:Notification){isClosed=true;refreshControls()}
    @objc public func openTerms(_ sender:Any?){
        guard !isClosed,workspace.isIdle,let store=workspace.personalStore else{return}
        if let w=termWindow,terms?.isOpen==true{w.makeKeyAndOrderFront(nil);return}
        let manager=PersonalLexiconController(store:store,access:{[weak self] action in
            guard let self=self else{throw IMKManagementError.unavailable};try self.workspace.withIdleAccess(action)
        },onChange:{[weak workspace] in workspace?.personalAuthorityChanged()})
        let w=NSWindow(contentRect:NSRect(x:140,y:80,width:900,height:850),styleMask:[.titled,.closable,.resizable],backing:.buffered,defer:false)
        w.isReleasedWhenClosed=false;w.title="Explicit personal terms · No automatic learning"
        do{try manager.attach(to:w);terms=manager;termWindow=w;w.makeKeyAndOrderFront(nil)}
        catch{status.stringValue="Personal terms could not be opened. No automatic retry."}
    }
    public func close(){termWindow?.close();window?.close();isClosed=true;refreshControls()}
}
#endif
