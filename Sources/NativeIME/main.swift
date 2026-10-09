#if os(macOS)
import AppKit
import InputMethodKit
import NativeHost
import EngineBridge

// Compilation-only InputMethodKit lifecycle skeleton. Never instantiate an IMKServer or register a service in this lab.
@objc(PAIAInputController) final class InputController: IMKInputController {}

@MainActor final class AppDelegate:NSObject,NSApplicationDelegate,NSWindowDelegate {
    var lab:LabEnvironment?,research:ResearchLabEnvironment?,window:NSWindow?,view:LabTextView?,controls:NativeLabController?
    var personal:PersonalLabEnvironment?,personalManager:PersonalLexiconController?,managerWindow:NSWindow?
    func applicationDidFinishLaunching(_ notification:Notification) {
        do {
            if ProcessInfo.processInfo.environment["PAIA_B2_RESEARCH"]=="1" {
                let environment=try PersonalLabEnvironment();personal=environment
                let controls=NativeLabController(runtime:environment.runtime,configuredSession:{configuration in try environment.makeSession(configuration:configuration)})
                let window=LabWindow(contentRect:NSRect(x:100,y:100,width:1040,height:760),styleMask:[.titled,.closable,.resizable],backing:.buffered,defer:false)
                window.isReleasedWhenClosed=false;window.delegate=self;window.title="PAIA B2 · Explicit personal lexicon · Not installed"
                try controls.attach(to:window);self.controls=controls;self.window=window;self.view=controls.editor
                if environment.store != nil {
                    let button=NSButton(title:"Manage explicit personal terms…",target:self,action:#selector(openPersonalTerms(_:)))
                    button.bezelStyle = .rounded;button.refusesFirstResponder=true;button.setAccessibilityLabel(button.title)
                    controls.root.addArrangedSubview(button);controls.registerIdleControl(button)
                }
                controls.status.stringValue=environment.status
                window.makeKeyAndOrderFront(nil);window.makeFirstResponder(controls.editor);NSApp.activate(ignoringOtherApps:true)
                return
            }
            if ProcessInfo.processInfo.environment["PAIA_B1_RESEARCH"]=="1" {
                let environment=try ResearchLabEnvironment();research=environment
                let controls=NativeLabController(runtime:environment.runtime)
                let window=LabWindow(contentRect:NSRect(x:100,y:100,width:1040,height:720),styleMask:[.titled,.closable,.resizable],backing:.buffered,defer:false)
                window.isReleasedWhenClosed=false;window.delegate=self
                window.title="PAIA B1 · Native research lab · Not installed"
                try controls.attach(to:window);self.controls=controls;self.window=window;self.view=controls.editor
                window.makeKeyAndOrderFront(nil);window.makeFirstResponder(controls.editor);NSApp.activate(ignoringOtherApps:true)
                return
            }
            let env=try LabEnvironment();lab=env
            let window=NSWindow(contentRect:NSRect(x:200,y:250,width:760,height:420),styleMask:[.titled,.closable,.resizable],backing:.buffered,defer:false)
            window.isReleasedWhenClosed=false
            window.delegate=self
            window.title="PAIA A1 · Synthetic AppKit host · Not a system input source"
            let scroll=NSScrollView(frame:window.contentView!.bounds);scroll.autoresizingMask=[.width,.height];scroll.hasVerticalScroller=true
            let view=LabTextView(frame:scroll.bounds);view.font = .systemFont(ofSize:22);view.isRichText=false;view.autoresizingMask=[.width,.height]
            view.makeSession={ [weak view] in
                guard let view=view,let session=try? env.runtime.makeSession() else{return nil}
                return HostDispatcher(client:view,session:session)
            }
            view.dispatcher=HostDispatcher(client:view,session:try env.runtime.makeSession())
            view.candidates.choose={ [weak view] ref in
                guard let view=view,view.dispatcher?.isCurrentTarget==true else{return}
                do {_=view.dispatcher!.apply(try view.dispatcher!.session.select(ref));view.renderCandidates()} catch {view.candidates.orderOut(nil)}
            }
            scroll.documentView=view;window.contentView?.addSubview(scroll);self.window=window;self.view=view
            window.makeKeyAndOrderFront(nil);window.makeFirstResponder(view);NSApp.activate(ignoringOtherApps:true)
        } catch { fputs("Native lab startup failed; verified resource configuration is required.\n",stderr);NSApp.terminate(nil) }
    }
    @objc func openPersonalTerms(_ sender:NSButton){
        guard let environment=personal,let store=environment.store,let controls=controls,!controls.hasComposition,!controls.inspectorVisible else{return}
        if let existing=managerWindow,personalManager?.isOpen==true{existing.makeKeyAndOrderFront(nil);return}
        let invalidatePersonal:()->Void = {[weak self] in
            environment.disableOverlayUntilRestart();self?.view?.dispatcher?.invalidate();self?.view?.candidates.orderOut(nil);self?.controls?.status.stringValue=environment.status
        }
        do {
            let manager=PersonalLexiconController(store:store,onChange:invalidatePersonal)
            let window=NSWindow(contentRect:NSRect(x:150,y:100,width:900,height:850),styleMask:[.titled,.closable,.resizable],backing:.buffered,defer:false)
            window.isReleasedWhenClosed=false;window.title="Explicit personal terms · No automatic learning"
            try manager.attach(to:window);personalManager=manager;managerWindow=window;window.makeKeyAndOrderFront(nil)
        }catch{invalidatePersonal();controls.status.stringValue="Personal authority unavailable. Overlay disabled; restart the lab to verify."}
    }
    func windowDidResignKey(_ notification:Notification) {view?.dispatcher?.invalidate();view?.candidates.orderOut(nil)}
    func applicationDidResignActive(_ notification:Notification) {view?.dispatcher?.invalidate();view?.candidates.orderOut(nil)}
    func applicationShouldTerminateAfterLastWindowClosed(_ sender:NSApplication)->Bool {true}
    func applicationWillTerminate(_ notification:Notification) {
        view?.dispatcher?.invalidate()
        if let personal=personal {if !personal.runtime.close(){fputs("Personal derived-data cleanup was incomplete.\n",stderr)};personal.store?.close()}
    }
}
MainActor.assumeIsolated {
    let app=NSApplication.shared
    let delegate=AppDelegate();app.delegate=delegate;app.setActivationPolicy(.regular);app.run()
}
#else
print("PAIANativeLab requires macOS/AppKit; no host evidence was produced.")
#endif
