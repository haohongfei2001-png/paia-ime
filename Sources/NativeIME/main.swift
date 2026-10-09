#if os(macOS)
import AppKit
import InputMethodKit
import NativeHost
import EngineBridge

// Compilation-only InputMethodKit lifecycle skeleton. Never instantiate an IMKServer or register a service in this lab.
@objc(PAIAInputController) final class InputController: IMKInputController {}

@MainActor final class LabTextView: NSTextView {
    var dispatcher: HostDispatcher!
    let candidates=CandidatePanel()
    var makeSession:(()->HostDispatcher?)?
    func renew() {dispatcher?.invalidate();candidates.orderOut(nil);dispatcher=makeSession?()}
    override func resignFirstResponder()->Bool {dispatcher?.invalidate();candidates.orderOut(nil);return super.resignFirstResponder()}
    override func mouseDown(with event:NSEvent) {dispatcher?.invalidate();candidates.orderOut(nil);super.mouseDown(with:event)}
    override func keyDown(with event:NSEvent) {
        if dispatcher?.isCurrentTarget != true {renew()}
        guard let dispatcher=dispatcher else {super.keyDown(with:event);return}
        if event.modifierFlags.contains(.command) || event.modifierFlags.contains(.option) {
            dispatcher.invalidate();candidates.orderOut(nil);super.keyDown(with:event);return
        }
        let key:InputKey
        switch event.keyCode {
        case 36,76:key = .returnKey
        case 49:key = .space
        case 53:key = .escape
        case 51:key = .code(0xff08)
        case 117:key = .code(0xffff)
        case 123:key = .code(0xff51)
        case 124:key = .code(0xff53)
        case 125:key = .code(0xff54)
        case 126:key = .code(0xff52)
        case 115:key = .code(0xff50)
        case 119:key = .code(0xff57)
        case 116:key = .code(0xff55)
        case 121:key = .code(0xff56)
        case 48:key = .code(0xff09,modifiers:event.modifierFlags.contains(.shift) ? 1 : 0)
        default:
            guard let chars=event.characters,chars.unicodeScalars.count==1,let scalar=chars.unicodeScalars.first else {super.keyDown(with:event);return}
            if (48...57).contains(scalar.value) {key = .number(Int(scalar.value-48))}
            else {key = .code(Int32(scalar.value))}
        }
        do {
            let update=try dispatcher.session.process(key)
            _=dispatcher.apply(update);renderCandidates()
            if !update.handled {super.keyDown(with:event)}
        } catch {
            candidates.orderOut(nil);dispatcher.invalidate();NSSound.beep()
        }
    }
    func renderCandidates() {
        guard let s=dispatcher.session.snapshot,!s.rows.isEmpty,let screen=window?.screen else {candidates.orderOut(nil);return}
        let rect=firstRect(forCharacterRange:selectedRange(),actualRange:nil)
        candidates.show(s,below:rect,screen:screen.visibleFrame)
    }
}
@MainActor final class AppDelegate:NSObject,NSApplicationDelegate {
    var lab:LabEnvironment?,window:NSWindow?,view:LabTextView?
    func applicationDidFinishLaunching(_ notification:Notification) {
        do {
            let env=try LabEnvironment();lab=env
            let window=NSWindow(contentRect:NSRect(x:200,y:250,width:760,height:420),styleMask:[.titled,.closable,.resizable],backing:.buffered,defer:false)
            window.title="PAIA A1 · Synthetic AppKit host · Not a system input source"
            let scroll=NSScrollView(frame:window.contentView!.bounds);scroll.autoresizingMask=[.width,.height];scroll.hasVerticalScroller=true
            let view=LabTextView(frame:scroll.bounds);view.font = .systemFont(ofSize:22);view.isRichText=false;view.autoresizingMask=[.width,.height]
            view.makeSession={ [weak view] in
                guard let view=view,let session=try? env.runtime.makeSession() else{return nil}
                return HostDispatcher(client:view,session:session)
            }
            view.dispatcher=HostDispatcher(client:view,session:try env.runtime.makeSession())
            view.candidates.choose={ [weak view] ref in
                guard let view=view,view.dispatcher.isCurrentTarget else{return}
                do {_=view.dispatcher.apply(try view.dispatcher.session.select(ref));view.renderCandidates()} catch {view.candidates.orderOut(nil)}
            }
            scroll.documentView=view;window.contentView?.addSubview(scroll);self.window=window;self.view=view
            window.makeKeyAndOrderFront(nil);window.makeFirstResponder(view);NSApp.activate(ignoringOtherApps:true)
        } catch { fputs("A1 startup failed; verified fixture/library configuration is required.\n",stderr);NSApp.terminate(nil) }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender:NSApplication)->Bool {true}
    func applicationWillTerminate(_ notification:Notification) {view?.dispatcher.invalidate()}
}
MainActor.assumeIsolated {
    let app=NSApplication.shared
    let delegate=AppDelegate();app.delegate=delegate;app.setActivationPolicy(.regular);app.run()
}
#else
print("PAIANativeLab requires macOS/AppKit; no host evidence was produced.")
#endif
