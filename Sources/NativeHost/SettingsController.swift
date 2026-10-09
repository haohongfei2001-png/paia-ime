#if os(macOS)
import AppKit
import EngineBridge
import SettingsCore

@MainActor public final class SettingsController:NSObject {
    public let saveButton=NSButton(),defaultsButton=NSButton(),status=NSTextField(wrappingLabelWithString:"")
    public let root=NSStackView()
    private let lab:NativeLabController,store:SettingsStore?
    private var savedRevision:UInt64=0,persistenceSuspended=false,restored=false
    public init(lab:NativeLabController,store:SettingsStore?) {
        self.lab=lab;self.store=store;super.init()
        for (button,title,action) in [(saveButton,"Save current settings",#selector(save(_:))),(defaultsButton,"Restore session defaults",#selector(defaults(_:)))] {
            button.title=title;button.target=self;button.action=action;button.bezelStyle = .rounded;button.refusesFirstResponder=true;button.setAccessibilityLabel(title)
        }
        root.orientation = .vertical;root.alignment = .leading;root.spacing=6
        root.addArrangedSubview(NSStackView(views:[saveButton,defaultsButton]));root.addArrangedSubview(status)
        status.setAccessibilityLabel("Explicit settings persistence status")
        lab.root.addArrangedSubview(root);lab.registerIdleControl(defaultsButton)
        lab.registerIdleControl(saveButton,available:{[weak self] in self?.store != nil && self?.persistenceSuspended==false})
    }
    public func restoreAtStartup(){
        guard !restored else{return};restored=true
        guard !lab.isClosed,!lab.hasComposition,!lab.inspectorVisible else{status.stringValue="Settings restore refused during composition.";return}
        guard let store=store else{suspend("Saved settings unavailable. Verified session defaults remain; file unchanged.");return}
        do {
            guard let saved=try store.snapshot() else{status.stringValue="Session defaults. No settings have been saved; closing does not save.";return}
            savedRevision=saved.revision
            do{try lab.applyConfiguration(LabConfiguration(preferences:saved.values));status.stringValue="Saved settings restored through the current engine. Repair hold remains session-only."}
            catch{status.stringValue="Saved mode unavailable. Verified session defaults remain; saved file unchanged."}
        }catch{suspend("Saved settings authority unavailable. Session defaults remain; file unchanged.")}
    }
    private func suspend(_ message:String){persistenceSuspended=true;saveButton.isEnabled=false;status.stringValue=message}
    @objc private func save(_ sender:NSButton){
        guard !lab.isClosed,!lab.hasComposition,!lab.inspectorVisible else{status.stringValue="Commit or cancel composition before saving settings.";return}
        guard !persistenceSuspended,let store=store else{return}
        do{let saved=try store.save(lab.configuration.preferences,expectedRevision:savedRevision);savedRevision=saved.revision;status.stringValue="Current settings saved. Ordinary input and repair contents were not saved."}
        catch{suspend("Settings save not confirmed. Current session remains usable. Reopen to verify; no automatic retry.")}
    }
    @objc private func defaults(_ sender:NSButton){
        guard !lab.isClosed,!lab.hasComposition,!lab.inspectorVisible else{status.stringValue="Commit or cancel composition before restoring defaults.";return}
        do{try lab.applyConfiguration(LabConfiguration());status.stringValue="Session defaults applied. Saved settings unchanged until an explicit Save."}
        catch{status.stringValue="Defaults could not be prepared. Previous configuration and saved file retained."}
    }
}
#endif
