#if os(macOS)
import AppKit
import InputMethodKit
import NativeHost
import EngineBridge

// Compilation-only InputMethodKit lifecycle skeleton. Never instantiate an IMKServer or register a service in this lab.
@objc(PAIAInputController) final class InputController: IMKInputController {}

@MainActor final class AppDelegate:NSObject,NSApplicationDelegate,NSWindowDelegate {
    var lab:LabEnvironment?,research:ResearchLabEnvironment?,window:NSWindow?,view:LabTextView?,controls:NativeLabController?
    func applicationDidFinishLaunching(_ notification:Notification) {
        do {
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
        } catch { fputs("A1 startup failed; verified fixture/library configuration is required.\n",stderr);NSApp.terminate(nil) }
    }
    func windowDidResignKey(_ notification:Notification) {view?.dispatcher?.invalidate();view?.candidates.orderOut(nil)}
    func applicationDidResignActive(_ notification:Notification) {view?.dispatcher?.invalidate();view?.candidates.orderOut(nil)}
    func applicationShouldTerminateAfterLastWindowClosed(_ sender:NSApplication)->Bool {true}
    func applicationWillTerminate(_ notification:Notification) {view?.dispatcher?.invalidate()}
}
MainActor.assumeIsolated {
    let app=NSApplication.shared
    let delegate=AppDelegate();app.delegate=delegate;app.setActivationPolicy(.regular);app.run()
}
#else
print("PAIANativeLab requires macOS/AppKit; no host evidence was produced.")
#endif
