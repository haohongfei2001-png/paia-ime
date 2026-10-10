#if os(macOS)
import AppKit
import InputMethodKit
import IMKHost
import EngineBridge
import NativeHost

@MainActor final class InputMethodDelegate:NSObject,NSApplicationDelegate {
    var server:IMKServer?
    func applicationDidFinishLaunching(_ notification:Notification) {
        guard let id=Bundle.main.bundleIdentifier,
              let name=Bundle.main.object(forInfoDictionaryKey:"InputMethodConnectionName") as? String else{NSApp.terminate(nil);return}
        // This branch publishes an IMK service connection. CI only runs --preflight,
        // which returns before NSApplication.run and never constructs this server.
        server=IMKServer(name:name,bundleIdentifier:id)
        if server==nil{fputs("IMK service initialization failed.\n",stderr);NSApp.terminate(nil)}
    }
}
MainActor.assumeIsolated {
    do {
        _=InputMethodController.self
        guard Bundle.main.object(forInfoDictionaryKey:"InputMethodServerControllerClass") as? String == "PAIAInputMethodController",
              NSClassFromString("PAIAInputMethodController") != nil,
              Bundle.main.object(forInfoDictionaryKey:"LSUIElement") as? Bool == true,
              Bundle.main.object(forInfoDictionaryKey:"LSBackgroundOnly") as? Bool != true else{throw EngineError.closed}
        // Candidate and explicit recovery panels need an agent that can show UI.
        // Prohibited/LSBackgroundOnly cannot supply that application contract.
        let app=NSApplication.shared
        guard app.setActivationPolicy(.accessory),app.activationPolicy() == .accessory else{throw EngineError.closed}
        let environment=try LabEnvironment()
        defer{InputMethodRuntime.makeSession=nil;_ = environment.runtime.close()}
        InputMethodRuntime.makeSession={try? environment.runtime.makeSession()}
        if CommandLine.arguments.contains("--preflight") {
            let session=try environment.runtime.makeSession();defer{session.end()}
            let initial=try session.refresh()
            guard initial.commit==nil,initial.snapshot?.rawASCII.isEmpty==true else{throw EngineError.closed}
            for c in "nihao"{_ = try session.process(.text(String(c)))}
            guard let snapshot=session.snapshot,snapshot.rows.first?.text=="你好",let screen=NSScreen.main else{throw EngineError.closed}
            let panel=CandidatePanel();defer{panel.orderOut(nil)}
            let frame=screen.visibleFrame,anchor=NSRect(x:frame.minX+40,y:frame.maxY-60,width:1,height:22)
            panel.show(snapshot,below:anchor,screen:frame,notice:"Authored preflight; service not started")
            panel.displayIfNeeded()
            guard panel.isVisible,!panel.isKeyWindow,panel.windowNumber>0,let view=panel.contentView,
                  let bitmap=view.bitmapImageRepForCachingDisplay(in:view.bounds) else{throw EngineError.closed}
            view.cacheDisplay(in:view.bounds,to:bitmap)
            guard let data=bitmap.representation(using:.png,properties:[:]) else{throw EngineError.closed}
            let encoded=Array(data.base64EncodedString()),chunk=1800
            for start in stride(from:0,to:encoded.count,by:chunk){
                print("PAIA_IMK_PREFLIGHT_IMAGE_\(start/chunk):\(String(encoded[start..<min(start+chunk,encoded.count)]))")
            }
            panel.orderOut(nil);guard !panel.isVisible else{throw EngineError.closed}
            print("IMK_UI_PREFLIGHT accessory=true; actual non-key candidate panel shown, captured and hidden; authored fixture only.")
            print("IMK_BUNDLE_PREFLIGHT compiled controller, agent plist and real engine verified; server not started; input source not registered or installed.")
        } else {
            let delegate=InputMethodDelegate();app.delegate=delegate
            withExtendedLifetime(delegate){app.run()}
        }
    } catch {fputs("Input method verified-resource preflight failed.\n",stderr);exit(1)}
}
#else
print("PAIAInputMethod requires macOS/InputMethodKit. No input source was started.")
#endif
