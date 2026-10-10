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
    let preflight=CommandLine.arguments.contains("--preflight")
    var phase="metadata"
    do {
        _=InputMethodController.self
        guard Bundle.main.object(forInfoDictionaryKey:"InputMethodServerControllerClass") as? String == "PAIAInputMethodController",
              NSClassFromString("PAIAInputMethodController") != nil,
              Bundle.main.object(forInfoDictionaryKey:"LSUIElement") as? Bool == true,
              Bundle.main.object(forInfoDictionaryKey:"LSBackgroundOnly") as? Bool != true else{throw EngineError.closed}
        // Candidate and explicit recovery panels need an agent that can show UI.
        // Prohibited/LSBackgroundOnly cannot supply that application contract.
        phase="accessory-policy"
        let app=NSApplication.shared
        let before=app.activationPolicy()
        // LSUIElement may already establish accessory. A redundant request can
        // return false even though the required effective policy is unchanged.
        let accepted=before == .accessory || app.setActivationPolicy(.accessory),after=app.activationPolicy()
        if preflight{print("IMK_PREFLIGHT_POLICY before=\(before.rawValue) accepted=\(accepted) after=\(after.rawValue)")}
        guard accepted,after == .accessory else{throw EngineError.closed}
        phase="engine-startup"
        let environment=try IMKServiceEnvironment()
        defer{InputMethodRuntime.preferences?.close();InputMethodRuntime.preferences=nil;InputMethodRuntime.workspace=nil;environment.close()}
        InputMethodRuntime.workspace=environment.workspace
        InputMethodRuntime.preferences=IMKPreferencesController(workspace:environment.workspace)
        if preflight {
            phase="engine-candidates"
            let session=try environment.makeSession(environment.workspace.configuration);defer{session.end()}
            let initial=try session.refresh()
            guard initial.commit==nil,initial.snapshot?.rawASCII.isEmpty==true else{throw EngineError.closed}
            for c in "nihao"{_ = try session.process(.text(String(c)))}
            guard let snapshot=session.snapshot,snapshot.rows.first?.text=="你好",let screen=NSScreen.main else{throw EngineError.closed}
            phase="candidate-window"
            let panel=CandidatePanel();defer{panel.orderOut(nil)}
            let frame=screen.visibleFrame,anchor=NSRect(x:frame.minX+40,y:frame.maxY-60,width:1,height:22)
            panel.show(snapshot,below:anchor,screen:frame,notice:"Authored preflight; service not started")
            panel.displayIfNeeded()
            print("IMK_PREFLIGHT_PANEL visible=\(panel.isVisible) key=\(panel.isKeyWindow) number=\(panel.windowNumber) rows=\(snapshot.rows.count)")
            guard panel.isVisible,!panel.isKeyWindow,panel.windowNumber>0,let view=panel.contentView,
                  let bitmap=view.bitmapImageRepForCachingDisplay(in:view.bounds) else{throw EngineError.closed}
            phase="native-content-capture"
            view.cacheDisplay(in:view.bounds,to:bitmap)
            guard let data=bitmap.representation(using:.png,properties:[:]) else{throw EngineError.closed}
            let encoded=Array(data.base64EncodedString()),chunk=1800
            for start in stride(from:0,to:encoded.count,by:chunk){
                print("PAIA_IMK_PREFLIGHT_IMAGE_\(start/chunk):\(String(encoded[start..<min(start+chunk,encoded.count)]))")
            }
            phase="candidate-hide"
            panel.orderOut(nil);guard !panel.isVisible else{throw EngineError.closed}
            print("IMK_UI_PREFLIGHT accessory=true; actual non-key candidate panel shown, captured and hidden; authored fixture only.")
            print("IMK_BUNDLE_PREFLIGHT compiled controller, agent plist and real engine verified; server not started; input source not registered or installed.")
        } else {
            let delegate=InputMethodDelegate();app.delegate=delegate
            withExtendedLifetime(delegate){app.run()}
        }
    } catch {if preflight{fputs("IMK_PREFLIGHT_FAILURE phase=\(phase)\n",stderr)}
        fputs("Input method verified-resource preflight failed.\n",stderr);exit(1)}
}
#else
print("PAIAInputMethod requires macOS/InputMethodKit. No input source was started.")
#endif
