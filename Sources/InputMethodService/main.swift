#if os(macOS)
import AppKit
import InputMethodKit
import IMKHost
import EngineBridge

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
              NSClassFromString("PAIAInputMethodController") != nil else{throw EngineError.closed}
        let environment=try LabEnvironment()
        defer{InputMethodRuntime.makeSession=nil;_ = environment.runtime.close()}
        InputMethodRuntime.makeSession={try? environment.runtime.makeSession()}
        if CommandLine.arguments.contains("--preflight") {
            let session=try environment.runtime.makeSession();let initial=try session.refresh();session.end()
            guard initial.commit==nil,initial.snapshot?.rawASCII.isEmpty==true else{throw EngineError.closed}
            print("IMK_BUNDLE_PREFLIGHT compiled controller, plist and real engine verified; server not started; input source not registered or installed.")
        } else {
            let app=NSApplication.shared,delegate=InputMethodDelegate();app.delegate=delegate
            app.setActivationPolicy(.prohibited);app.run()
        }
    } catch {fputs("Input method verified-resource preflight failed.\n",stderr);exit(1)}
}
#else
print("PAIAInputMethod requires macOS/InputMethodKit. No input source was started.")
#endif
