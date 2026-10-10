#if os(macOS)
import AppKit
import EngineBridge
import SettingsCore

@MainActor public protocol SettingsTarget:AnyObject {
    var root:NSStackView {get}
    var configuration:LabConfiguration {get}
    var isClosed:Bool {get}
    var hasComposition:Bool {get}
    var inspectorVisible:Bool {get}
    func applyConfiguration(_ next:LabConfiguration)throws
    func withSettingsAccess<T>(_ operation:()throws->T)throws->T
    func registerIdleControl(_ control:NSControl,available:@escaping()->Bool)
}
extension NativeLabController:SettingsTarget {
    public func withSettingsAccess<T>(_ operation:()throws->T)throws->T {
        guard !isClosed,!hasComposition,!inspectorVisible else{throw EngineError.closed};return try operation()
    }
}

@MainActor public final class SettingsController:NSObject {
    public let saveButton=NSButton(),defaultsButton=NSButton(),verifyButton=NSButton(),status=NSTextField(wrappingLabelWithString:"")
    public let root=NSStackView()
    private weak var lab:(any SettingsTarget)?
    private let store:SettingsStore?
    private var savedRevision:UInt64=0,persistenceSuspended=false,restored=false,saveFailed=false
    public init(lab:any SettingsTarget,store:SettingsStore?) {
        self.lab=lab;self.store=store;super.init()
        for (button,title,action) in [(saveButton,"Save current settings",#selector(save(_:))),(defaultsButton,"Restore session defaults",#selector(defaults(_:))),(verifyButton,"Verify last save",#selector(verifySave(_:)))] {
            button.title=title;button.target=self;button.action=action;button.bezelStyle = .rounded;button.refusesFirstResponder=true;button.setAccessibilityLabel(title)
        }
        root.orientation = .vertical;root.alignment = .leading;root.spacing=6
        root.addArrangedSubview(NSStackView(views:[saveButton,defaultsButton,verifyButton]));root.addArrangedSubview(status)
        status.setAccessibilityLabel("Explicit settings persistence status")
        lab.root.addArrangedSubview(root);lab.registerIdleControl(defaultsButton,available:{true})
        lab.registerIdleControl(saveButton,available:{[weak self] in self?.store != nil && self?.persistenceSuspended==false})
        lab.registerIdleControl(verifyButton,available:{[weak self] in self?.store?.hasUnverifiedSave==true && self?.saveFailed==true})
    }
    public func restoreAtStartup(){
        guard let lab=lab else{return}
        guard !restored else{return};restored=true
        guard !lab.isClosed,!lab.hasComposition,!lab.inspectorVisible else{status.stringValue="Settings restore refused during composition.";return}
        guard let store=store else{suspend("Saved settings unavailable. Verified session defaults remain; file unchanged.");return}
        do {
            guard let saved=try lab.withSettingsAccess({try store.snapshot()}) else{status.stringValue="Session defaults. No settings have been saved; closing does not save.";return}
            savedRevision=saved.revision
            do{try lab.applyConfiguration(LabConfiguration(preferences:saved.values));status.stringValue="Saved settings restored through the current engine. Repair hold remains session-only."}
            catch{status.stringValue="Saved mode unavailable. Verified session defaults remain; saved file unchanged."}
        }catch{suspend("Saved settings authority unavailable. Session defaults remain; file unchanged.")}
    }
    private func suspend(_ message:String){persistenceSuspended=true;saveButton.isEnabled=false;status.stringValue=message}
    @objc private func save(_ sender:NSButton){
        guard let lab=lab else{return}
        guard !lab.isClosed,!lab.hasComposition,!lab.inspectorVisible else{status.stringValue="Commit or cancel composition before saving settings.";return}
        guard !persistenceSuspended,let store=store else{return}
        do{let saved=try lab.withSettingsAccess {try store.save(lab.configuration.preferences,expectedRevision:savedRevision)};savedRevision=saved.revision;status.stringValue="Current settings saved. Ordinary input and repair contents were not saved."}
        catch{
            saveFailed=store.hasUnverifiedSave;verifyButton.isEnabled=saveFailed
            suspend(saveFailed ? "Settings save not confirmed. Use Verify last save; no automatic retry. Current session remains usable." : "Settings save refused without a verifiable attempt. Authority unavailable; current input remains usable.")
        }
    }
    @objc private func verifySave(_ sender:NSButton){
        guard let lab=lab else{return}
        guard !lab.isClosed,!lab.hasComposition,!lab.inspectorVisible else{status.stringValue="Commit or cancel composition before verifying settings.";return}
        guard saveFailed,let store=store else{return}
        do {
            let verified=try lab.withSettingsAccess {try store.verifyLastSave()};savedRevision=verified.document?.revision ?? 0
            saveFailed=false;persistenceSuspended=false;verifyButton.isEnabled=false;saveButton.isEnabled=true
            status.stringValue=verified.resolution == .published ? "Attempted settings save verified. Current mode unchanged; nothing retried." : "Previous saved state verified. Attempted changes were not saved; nothing retried."
        }catch{saveFailed=store.hasUnverifiedSave;verifyButton.isEnabled=saveFailed;status.stringValue="Saved outcome cannot be verified. Saving remains blocked; authority unchanged."}
    }
    @objc private func defaults(_ sender:NSButton){
        guard let lab=lab else{return}
        guard !lab.isClosed,!lab.hasComposition,!lab.inspectorVisible else{status.stringValue="Commit or cancel composition before restoring defaults.";return}
        do{try lab.applyConfiguration(LabConfiguration());status.stringValue="Session defaults applied. Saved settings unchanged until an explicit Save."}
        catch{status.stringValue="Defaults could not be prepared. Previous configuration and saved file retained."}
    }
}
#endif
