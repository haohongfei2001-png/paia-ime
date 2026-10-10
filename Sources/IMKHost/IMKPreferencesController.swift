#if os(macOS)
import AppKit
import EngineBridge
import NativeHost
import SettingsCore

@MainActor private final class IMKPreferencesStackView:NSStackView {
    override var isOpaque:Bool {true}
    override func draw(_ dirtyRect:NSRect){NSColor.windowBackgroundColor.setFill();dirtyRect.fill();super.draw(dirtyRect)}
}
// Explicit management UI, never a second input dispatcher or document editor.
@MainActor public final class IMKPreferencesController:NSObject,SettingsTarget,NSWindowDelegate {
    public let root:NSStackView=IMKPreferencesStackView()
    public let spelling=NSPopUpButton(frame:.zero,pullsDown:false),script=NSPopUpButton(frame:.zero,pullsDown:false)
    public let literal=NSButton(checkboxWithTitle:"Literal text",target:nil,action:nil)
    public let punctuation=NSButton(checkboxWithTitle:"Chinese , ? ! ;",target:nil,action:nil)
    public let fuzzy=NSButton(checkboxWithTitle:"Fuzzy initials: n/l, z/zh, c/ch, s/sh",target:nil,action:nil)
    public let correction=NSButton(checkboxWithTitle:"Full-Pinyin typo tolerance",target:nil,action:nil)
    public let applicationID=NSTextField(string:""),applicationMode=NSPopUpButton(frame:.zero,pullsDown:false)
    public let knownApplications=NSPopUpButton(frame:.zero,pullsDown:false),applyApplication=NSButton()
    public let termsButton=NSButton(),status=NSTextField(wrappingLabelWithString:"")
    public private(set) var settings:SettingsController!
    public private(set) var isClosed=false
    public var hasComposition:Bool {!workspace.isIdle}
    public var inspectorVisible:Bool {false}
    public var configuration:LabConfiguration {workspace.configuration}
    public let workspace:IMKWorkspace
    private var controls=[(NSControl,()->Bool)](),window:NSWindow?,termWindow:NSWindow?
    public private(set) var terms:PersonalLexiconController?
    public private(set) var expressions:ExpressionManager?
    public let expressionsButton=NSButton()
    public init(workspace:IMKWorkspace){
        self.workspace=workspace;super.init()
        root.orientation = .vertical;root.alignment = .leading;root.spacing=12;root.edgeInsets=NSEdgeInsets(top:20,left:20,bottom:20,right:20)
        let resources=NSTextField(wrappingLabelWithString:workspace.resourceDescription)
        root.addArrangedSubview(resources);resources.widthAnchor.constraint(equalTo:root.widthAnchor,constant:-40).isActive=true
        spelling.addItems(withTitles:["Full pinyin","Flypy","Natural"]);script.addItems(withTitles:["Simplified","Traditional"])
        spelling.setAccessibilityLabel("Spelling system");script.setAccessibilityLabel("Output script")
        root.addArrangedSubview(NSStackView(views:[spelling,script,literal,punctuation]))
        for control:NSControl in [spelling,script,literal,punctuation]{control.target=self;control.action=#selector(changeConfiguration(_:));registerIdleControl(control,available:{true})}
        for button in [literal,punctuation]{button.setAccessibilityLabel(button.title)}
        root.addArrangedSubview(NSStackView(views:[fuzzy,correction]))
        for button in [fuzzy,correction] {button.target=self;button.action=#selector(changeConfiguration(_:));button.setAccessibilityLabel(button.title)}
        registerIdleControl(fuzzy,available:{[weak workspace] in workspace?.supportsSpellingPolicies==true});registerIdleControl(correction,available:{[weak self] in self?.workspace.supportsSpellingPolicies==true && self?.configuration.spelling == .full})
        let policyHelp=NSTextField(wrappingLabelWithString:workspace.supportsSpellingPolicies ? "Fuzzy sound rules are separate from typo tolerance. Typo tolerance applies only to Full Pinyin; double-Pinyin keys are unchanged. Ordinary spelling uses v for ü; direct ü is literal, not normalized.":"Spelling policies require verified research resources. The tiny authored fixture does not supply them; these controls are unavailable.")
        root.addArrangedSubview(policyHelp);policyHelp.widthAnchor.constraint(equalTo:root.widthAnchor,constant:-40).isActive=true
        applicationID.placeholderString="Explicit app ID, e.g. com.apple.TextEdit";applicationID.setAccessibilityLabel("Explicit application identifier")
        applicationID.widthAnchor.constraint(equalToConstant:310).isActive=true
        applicationMode.addItems(withTitles:["Use global default","Start Chinese","Start literal"]);applicationMode.setAccessibilityLabel("Initial mode for this application")
        applyApplication.title="Set initial mode";applyApplication.target=self;applyApplication.action=#selector(setApplicationPreference(_:));applyApplication.bezelStyle = .rounded
        knownApplications.target=self;knownApplications.action=#selector(selectApplicationPreference(_:));knownApplications.setAccessibilityLabel("Saved explicit application identifiers")
        root.addArrangedSubview(NSStackView(views:[applicationID,applicationMode,applyApplication]));root.addArrangedSubview(knownApplications)
        for control:NSControl in [applicationID,applicationMode,applyApplication,knownApplications]{registerIdleControl(control,available:{true})}
        let help=NSTextField(wrappingLabelWithString:"Space chooses the real candidate; Return keeps spelling and is consumed. Modes change only when every input client is idle. No automatic learning or preference save.")
        root.addArrangedSubview(help);help.widthAnchor.constraint(equalTo:root.widthAnchor,constant:-40).isActive=true
        settings=SettingsController(lab:self,store:workspace.settingsStore)
        settings.root.widthAnchor.constraint(equalTo:root.widthAnchor,constant:-40).isActive=true
        settings.status.widthAnchor.constraint(equalTo:settings.root.widthAnchor).isActive=true
        termsButton.title="Manage explicit personal terms…";termsButton.target=self;termsButton.action=#selector(openTerms(_:));termsButton.bezelStyle = .rounded;termsButton.setAccessibilityLabel(termsButton.title)
        root.addArrangedSubview(termsButton);root.addArrangedSubview(status)
        status.widthAnchor.constraint(equalTo:root.widthAnchor,constant:-40).isActive=true
        registerIdleControl(termsButton,available:{[weak self] in self?.workspace.personalStore != nil})
        expressionsButton.title="Manage exact local expressions…";expressionsButton.target=self;expressionsButton.action=#selector(openExpressions(_:));expressionsButton.bezelStyle = .rounded
        root.addArrangedSubview(expressionsButton);registerIdleControl(expressionsButton,available:{[weak self] in self?.workspace.expressionStore != nil})
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
        literal.state=configuration.literal ? .on:.off;punctuation.state=configuration.chinesePunctuation ? .on:.off
        fuzzy.state=configuration.fuzzyInitials ? .on:.off;correction.state=workspace.supportsSpellingPolicies && configuration.fullPinyinCorrection ? .on:.off
        knownApplications.removeAllItems();knownApplications.addItem(withTitle:"Explicit app preferences (maximum 16)…")
        knownApplications.addItems(withTitles:configuration.initialModes.keys.sorted())
        refreshControls()
    }
    @objc private func changeConfiguration(_ sender:NSControl){
        guard !isClosed,LabSpelling.allCases.indices.contains(spelling.indexOfSelectedItem),(0...1).contains(script.indexOfSelectedItem) else{return}
        var next=configuration;next.spelling=LabSpelling.allCases[spelling.indexOfSelectedItem];next.traditional=script.indexOfSelectedItem==1
        next.literal=literal.state == .on;next.chinesePunctuation=punctuation.state == .on
        if workspace.supportsSpellingPolicies{next.fuzzyInitials=fuzzy.state == .on;next.fullPinyinCorrection=correction.state == .on}
        do{try applyConfiguration(next);status.stringValue="Session mode changed. Save explicitly to keep these preferences."}
        catch{reflect();status.stringValue="Mode unavailable or another client is busy. Previous configuration retained; no text committed."}
    }
    @objc private func selectApplicationPreference(_ sender:NSPopUpButton){
        guard sender.indexOfSelectedItem>0,let id=sender.titleOfSelectedItem,let mode=configuration.initialModes[id] else{return}
        applicationID.stringValue=id;applicationMode.selectItem(at:mode == .chinese ? 1:2)
    }
    @objc private func setApplicationPreference(_ sender:NSButton){
        let id=applicationID.stringValue
        guard !isClosed,ApplicationPreference.validIdentifier(id),(0...2).contains(applicationMode.indexOfSelectedItem) else{status.stringValue="Enter an exact bounded application identifier. No app discovery or document reading.";return}
        var next=configuration
        switch applicationMode.indexOfSelectedItem {case 1:next.initialModes[id] = .chinese;case 2:next.initialModes[id] = .literal;default:next.initialModes.removeValue(forKey:id)}
        do{try applyConfiguration(next);status.stringValue="Initial preference set for new sessions only. Save explicitly to persist; no other input was committed."}
        catch{reflect();status.stringValue="Application preference refused. All prior preferences and input remain unchanged."}
    }
    public func show(){
        guard workspace.isIdle else{status.stringValue="Finish every composition before opening settings.";return}
        isClosed=false
        if window==nil {
            let w=NSWindow(contentRect:NSRect(x:120,y:180,width:860,height:550),styleMask:[.titled,.closable],backing:.buffered,defer:false)
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
    @objc public func openExpressions(_ sender:Any?){
        guard !isClosed,workspace.isIdle,workspace.expressionStore != nil else{return}
        if expressions==nil{expressions=ExpressionManager(workspace:workspace)};expressions?.show()
    }
    public func close(){expressions?.close();termWindow?.close();window?.close();isClosed=true;refreshControls()}
}
#endif
