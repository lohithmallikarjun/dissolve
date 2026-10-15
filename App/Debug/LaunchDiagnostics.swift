#if os(macOS) && DEBUG
import AppKit

/// CI diagnostics: logs the windows AppKit knows about shortly after launch.
final class LaunchDiagnostics: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        print("Dissolve: didFinishLaunching, windows=\(NSApp.windows.count)")
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            for window in NSApp.windows {
                print("Dissolve: window \(type(of: window)) title=\(window.title) visible=\(window.isVisible) frame=\(window.frame)")
            }
            print("Dissolve: total windows=\(NSApp.windows.count)")
        }
    }
}
#endif
